//
//  FaceUnlockCoordinator.swift
//  facekey
//
//  Connects face recognition to the actual unlock path. Off by default; user opts in after validating accuracy in Face Lab.
//
//  Known limitation: LivenessAnalyzer defeats a photo but not a replayed video (real non-rigid motion looks live) — a successful spoof types the real macOS password.
//

import Foundation
import CoreGraphics
import AppKit
import Observation
import os

private let log = Logger(subsystem: "com.fparrav.facekey", category: "unlock")

@Observable
@MainActor
final class FaceUnlockCoordinator {
    private enum TriggerSource: String {
        case lockEvent
        case screenParameters
    }

    private enum ScanTrigger: String {
        case wake, lock, space, hover, autoRetry
    }

    private let pocController: POCController
    let lockMonitor = LockMonitor()
    let camera = CameraManager()
    let pipeline = FaceRecognitionPipeline()

    /// Persisted via FacekeySettings. Setting to false cancels any in-flight scan and disarms the overlay immediately.
    var isEnabled: Bool {
        didSet {
            FacekeySettings.shared.isFaceUnlockEnabled = isEnabled
            if !isEnabled { disarmOverlay() }
        }
    }

    /// Kept independent from Face Lab's own `threshold` so tuning the debug tool never silently changes the real unlock gate.
    var matchThreshold: Float {
        didSet { FacekeySettings.shared.matchThreshold = matchThreshold }
    }
    /// Shares its setting with NotchOverlayController's scanning timeout, so the background loop stops in step with the UI collapsing.
    private var scanWindowDuration: TimeInterval {
        TimeInterval(FacekeySettings.shared.faceDetectionSeconds)
    }
    /// The owner usually keeps looking away from the camera for a few seconds
    /// after the Mac wakes. Require a sustained 4 s non-match before giving
    /// the failure animation.
    private let wrongFaceGraceDuration: Duration = .seconds(4)

    private(set) var statusMessage = String(localized: "Idle")
    private(set) var lastOutcome: String?

    private var hasArmedForCurrentLock = false
    /// One-shot per lock session — an auto-retry that could itself auto-retry would loop the camera for the whole lock session.
    private var hasAutoRetriedForCurrentLock = false
    private var lastDisplayIDs: Set<UInt32> = []
    /// Whether the latest scan window ever selected a face; an empty wake scan starts the cooldown.
    private var scanSawFace = false
    private var scanTask: Task<Void, Never>?
    /// Bumped by every `startScanCycle()`; a cycle bails once superseded (see `runScanCycle(generation:)`).
    private var scanGeneration = 0
    /// When the last scan cycle was armed — collapses a single wake into a single arm (see `.wake` branch of `evaluateTrigger`).
    private var lastArmedAt: ContinuousClock.Instant?
    /// One lid-open fires several wake signals within a few hundred ms of each other; anything in this window counts as the same wake.
    private let rearmDebounce: Duration = .seconds(2)
    /// After an automatic scan finds nobody, further wake signals stay quiet this long — a shared monitor or KVM keeps waking the display with nobody at the Mac.
    private let wakeScanCooldown: Duration = .seconds(600)
    private var wakeScanCooldownUntil: ContinuousClock.Instant?
    /// When Facekey last typed the password itself, so a later unlock within seconds is known to be its own and is not verified again.
    private var lastOwnInjectionAt: ContinuousClock.Instant?
    /// An unlock this soon after Facekey typed the password is Facekey's own.
    private let ownUnlockWindow: Duration = .seconds(10)
    /// The post-unlock verification, if one is running. Separate from `scanTask`/`scanGeneration` so a lock-screen scan and a verification never cancel each other.
    private var verificationTask: Task<Void, Never>?
    private var verificationGeneration = 0
    /// Scan cycles currently inside `runScanCycle`, superseded ones included; they own the camera while running.
    private var activeScanCycles = 0
    /// After a verification locks the screen, further verifications pause so an owner who isn't recognised isn't locked out on every Watch unlock.
    private var verificationSuppressedUntil: ContinuousClock.Instant?
    private let verificationSuppression: Duration = .seconds(120)
    /// `LockMonitor.eventCount` of the last unlock event a verification was considered for, so one unlock is evaluated once.
    private var lastVerifiedEventCount = -1
    /// Held separately from `scanTask` since it's scheduled from inside the scan task it follows — reusing `scanTask` would self-cancel it.
    private var autoRetryTask: Task<Void, Never>?
    /// Gap between headless auto-retries, just to keep the camera from restarting in a tight loop.
    private let headlessRetryDelay: Duration = .seconds(1)

    /// When off, no notch/pill presence at all — every overlay call in this file is conditioned on this rather than just skipping the video.
    private var showsUI: Bool { FacekeySettings.shared.showUnlockAnimation }

    /// Reads the space key on the lock screen for the "On space" trigger; only runs while locked + opted in.
    private let spaceKeyMonitor = SpaceKeyMonitor()

    /// Token for the `didChangeScreenParametersNotification` observer registered in `init()`; kept for symmetry with `LockMonitor`'s observer bookkeeping (removed automatically by AppKit at process exit, so never explicitly removed).
    private var screenParametersObserver: NSObjectProtocol?

    init(pocController: POCController) {
        self.pocController = pocController
        self.isEnabled = FacekeySettings.shared.isFaceUnlockEnabled
        self.matchThreshold = FacekeySettings.shared.matchThreshold
        spaceKeyMonitor.onSpaceKeyDown = { [weak self] in self?.handleSpaceKeyPress() }
        observeLockAndWakeEvents()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard LockMonitor.isScreenActuallyLocked() else { return }
            self?.evaluateTrigger(source: .screenParameters)
        }
    }

    /// Re-subscribes on every change — `withObservationTracking` only fires once per registration.
    private func observeLockAndWakeEvents() {
        withObservationTracking {
            _ = lockMonitor.isScreenLocked
            _ = lockMonitor.wakeEventCount
            _ = lockMonitor.isSleeping
            // Also tracked so screensaver-stop and display-only wakes still wake this up.
            _ = lockMonitor.eventCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeLockAndWakeEvents()
                // Brief settle delay: CGSession's reported state can lag the true state right after wake.
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.evaluateTrigger(source: .lockEvent)
            }
        }
    }

    private func evaluateTrigger(source: TriggerSource) {
        let displayIDs = Set(NSScreen.screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value })
        let displaysChanged = displayIDs != lastDisplayIDs
        lastDisplayIDs = displayIDs
        log.notice("trigger source=\(source.rawValue, privacy: .public) lastEvent=\(String(describing: self.lockMonitor.lastEvent), privacy: .public) displays=\(displayIDs.count) displaysChanged=\(displaysChanged) armed=\(self.hasArmedForCurrentLock)")
        guard LockMonitor.isScreenActuallyLocked() else {
            hasArmedForCurrentLock = false
            hasAutoRetriedForCurrentLock = false
            wakeScanCooldownUntil = nil
            disarmOverlay()
            if lockMonitor.isSleeping {
                cancelVerification(reason: "sleeping")
            } else if source == .lockEvent {
                startVerificationIfNeeded()
            }
            return
        }
        cancelVerification(reason: "screen locked")
        // A new lock is a new session; an earlier wake cooldown no longer applies. Screen-parameter re-evaluations reuse a stale lastEvent, so they must not clear it.
        if source == .lockEvent, lockMonitor.lastEvent == .screenLocked { wakeScanCooldownUntil = nil }
        guard !lockMonitor.isSleeping else { log.notice("trigger decision=skip reason=sleeping"); return }

        // `.wake` (sleep, display sleep, or screensaver stopping) is an explicit "let me back in," so clear the one-shot guard.
        // `isWithinRecentArmBurst` keeps the several wake signals from one lid-open from each re-arming and fighting over the camera.
        if lockMonitor.lastEvent == .wake, !isWithinRecentArmBurst {
            hasArmedForCurrentLock = false
        }

        // Runs before the hasArmedForCurrentLock guard — the space monitor's lifetime is tied to "locked + opted in," not to whether a scan already ran.
        updateSpaceMonitor()

        guard isEnabled, !hasArmedForCurrentLock else { log.notice("trigger decision=skip reason=disabled or already armed"); return }
        guard let signal = requiredTrigger(for: lockMonitor.lastEvent) else { log.notice("trigger decision=skip reason=no trigger signal"); return }
        // A pinned display that isn't connected bails entirely rather than showing up elsewhere; "Main display" (nil) always resolves.
        guard NotchGeometry.preferredScreen() != nil else { log.notice("trigger decision=skip reason=no preferred screen"); return }

        guard FacekeySettings.shared.isFaceUnlockEnabled(for: DisplayContext.current()) else {
            disarmOverlay()
            log.notice("trigger decision=skip reason=face unlock off for this display")
            return
        }
        guard SecureCredentialManager.isSessionUnlocked else {
            statusMessage = String(localized: "Face unlock is on, but the session is locked — authenticate once from Password settings first.")
            log.notice("trigger decision=skip reason=session locked")
            return
        }
        guard SecureCredentialManager.hasStoredPassword() else {
            statusMessage = String(localized: "Face unlock is on, but no password is stored yet.")
            log.notice("trigger decision=skip reason=no stored password")
            return
        }

        // A deselected trigger means "don't auto-scan for this signal," not "do nothing" — the user can still opt in by hand.
        let cooldownActive = signal == .onWake && (wakeScanCooldownUntil.map { ContinuousClock.now < $0 } ?? false)
        if cooldownActive { log.notice("trigger decision=skip reason=wake cooldown") }
        let shouldAutoScan = FacekeySettings.shared.unlockTriggers.contains(signal) && !cooldownActive

        // Headless has nothing to arm/hover, so if this signal isn't selected there's nothing to do — and hasArmedForCurrentLock
        // must stay false, or a later selected signal could never fire (nothing else calls arm() to reset it).
        guard showsUI || shouldAutoScan else { log.notice("trigger decision=skip reason=trigger not selected"); return }

        log.notice("trigger decision=arm autoScan=\(shouldAutoScan)")
        hasArmedForCurrentLock = true
        lastArmedAt = .now
        let scanTrigger: ScanTrigger = (signal == .onLock) ? .lock : .wake
        Task { [weak self] in
            // arm() only shows a small closed notch silhouette, so this only needs a brief buffer past the login window's entrance.
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.arm(autoScan: shouldAutoScan, trigger: scanTrigger)
        }
    }

    /// Whether the last arm was recent enough to be part of the same wake burst rather than a new one.
    private var isWithinRecentArmBurst: Bool {
        guard let lastArmedAt else { return false }
        return ContinuousClock.now - lastArmedAt < rearmDebounce
    }

    /// nil for signals that shouldn't arm anything — including a nil `lastEvent`, or the first observation would fire regardless of user selection.
    private func requiredTrigger(for event: LockEventKind?) -> UnlockTrigger? {
        switch event {
        case .wake: return .onWake
        case .screenLocked: return .onLock
        case .screenUnlocked, .willSleep, nil: return nil
        }
    }

    private func disarmOverlay() {
        scanTask?.cancel()
        scanTask = nil
        // Bumping makes any cycle still suspended at `await camera.start()` inert, rather than resuming and re-showing the overlay.
        scanGeneration &+= 1
        autoRetryTask?.cancel()
        autoRetryTask = nil
        // A running verification owns the camera; it stops it itself.
        if verificationTask == nil { camera.stop() }
        NotchOverlayController.shared.disarm()
        // Covers isEnabled being switched off directly, keeping "disarmed" and "not listening for space" in lockstep.
        spaceKeyMonitor.stop()
    }

    /// Idempotent and safe to call on every lock/wake event. Deliberately does not prompt for Input Monitoring — a missing grant just means "don't listen."
    private func updateSpaceMonitor() {
        let shouldListen = isEnabled
            && FacekeySettings.shared.unlockTriggers.contains(.onSpace)
            && LockMonitor.isScreenActuallyLocked()
            && SpaceKeyMonitor.hasInputMonitoringAccess()
        if shouldListen {
            spaceKeyMonitor.start()
        } else {
            spaceKeyMonitor.stop()
        }
    }

    /// Runs the same gate chain as `evaluateTrigger`, then starts a scan. Independent of `LockMonitor` events, so doesn't touch `hasArmedForCurrentLock`.
    private func handleSpaceKeyPress() {
        guard isEnabled,
              FacekeySettings.shared.unlockTriggers.contains(.onSpace),
              LockMonitor.isScreenActuallyLocked(),
              NotchGeometry.preferredScreen() != nil,
              SecureCredentialManager.isSessionUnlocked,
              SecureCredentialManager.hasStoredPassword()
        else { return }

        // Already looking — swallows auto-repeat/double-presses and lets "On wake"/"On lock" override "On space" with no special-casing.
        guard NotchOverlayController.shared.phase != .scanning else { return }

        guard showsUI else {
            // Headless: no overlay, just scan.
            startScanCycle(trigger: .space)
            return
        }
        if NotchOverlayController.shared.isArmed {
            // Closed pill/notch already up — expand and scan, like a hover retry.
            startScanCycle(trigger: .space)
        } else {
            Task { [weak self] in await self?.arm(autoScan: true, trigger: .space) }
        }
    }

    /// Either way the overlay still arms — a deselected trigger only skips the automatic scan, leaving hover-to-start available.
    private func arm(autoScan: Bool, trigger: ScanTrigger) async {
        guard LockMonitor.isScreenActuallyLocked() else { return }
        guard showsUI else {
            // Headless: evaluateTrigger() already guaranteed autoScan is true here, so this is just "start scanning."
            startScanCycle(trigger: trigger)
            return
        }
        NotchOverlayController.shared.arm { [weak self] in
            self?.startScanCycle(trigger: .hover)
        }
        if autoScan {
            startScanCycle(trigger: trigger)
        }
    }

    /// Called on arm, and again whenever the overlay hover-activates.
    private func startScanCycle(trigger: ScanTrigger) {
        // A manual trigger always wins over the wake cooldown.
        if trigger == .hover || trigger == .space { wakeScanCooldownUntil = nil }
        scanTask?.cancel()
        scanGeneration &+= 1
        let generation = scanGeneration
        scanTask = Task { [weak self] in
            await self?.runScanCycle(generation: generation, trigger: trigger)
        }
    }

    /// `generation` is what makes overlapping cycles safe: `Task.cancel()` is cooperative, so a superseded cycle still runs to the
    /// end of this function, and its global side effects (`camera.stop()` etc.) could otherwise land on the newer cycle instead
    /// of itself. This was a real bug — a superseded `camera.stop()` queued behind the newer cycle's `startRunning()` made the
    /// camera visibly switch on then die mid-warm-up, leaving the surviving cycle polling a dead session and never unlocking.
    private func runScanCycle(generation: Int, trigger: ScanTrigger) async {
        activeScanCycles += 1
        defer { activeScanCycles -= 1 }
        guard LockMonitor.isScreenActuallyLocked() else {
            log.notice("scan #\(generation) skipped: screen not locked")
            return
        }
        // The active camera profile can change between scans (display plugged or unplugged), so resolve its width per scan.
        FacekeySettings.shared.refreshPipelineMinimumFaceWidth()
        log.notice("scan #\(generation) start (ui=\(self.showsUI), window=\(self.scanWindowDuration, privacy: .public)s, threshold=\(self.matchThreshold, privacy: .public), trigger=\(trigger.rawValue, privacy: .public))")

        await camera.start()
        guard generation == scanGeneration else { return }

        if let error = camera.errorMessage {
            log.error("scan #\(generation) camera error: \(error, privacy: .public)")
            statusMessage = error
            camera.stop()
            return
        }

        let showsUI = self.showsUI
        if showsUI {
            NotchOverlayController.shared.beginScanning()
        }
        statusMessage = String(localized: "Looking for your face…")

        let outcome = await observeScanWindow(
            deadline: Date().addingTimeInterval(scanWindowDuration),
            requireOverlayScanning: showsUI
        )

        // A newer cycle now owns the camera and overlay — leave both alone, and leave the auto-retry one-shot unspent.
        guard generation == scanGeneration else {
            log.notice("scan #\(generation) superseded")
            return
        }
        log.notice("scan #\(generation) outcome: \(String(describing: outcome), privacy: .public) \(self.lastOutcome ?? "", privacy: .public)")

        camera.stop()

        if outcome == .noResolution, !scanSawFace, trigger == .wake || trigger == .autoRetry, LockMonitor.isScreenActuallyLocked() {
            wakeScanCooldownUntil = .now + wakeScanCooldown
            log.notice("wake cooldown started (\(trigger.rawValue, privacy: .public)): no face seen")
        }

        switch outcome {
        case .matched:
            // The unlock already happened inside observeScanWindow — this only decides whether anything is shown about it.
            if showsUI {
                NotchOverlayController.shared.finish(success: true)
            }
        case .consistentlyWrongFace:
            statusMessage = String(localized: "Face not recognized.")
            if showsUI {
                NotchOverlayController.shared.finish(success: false)
                statusMessage = String(localized: "Face not recognized — hover the notch to try again.")
                scheduleAutoRetryIfEnabled(after: NotchOverlayController.shared.failureHoldDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        case .spoofSuspected:
            statusMessage = String(localized: "Couldn't confirm a live face.")
            if showsUI {
                NotchOverlayController.shared.finish(success: false)
                statusMessage = String(localized: "Couldn't confirm a live face — hover the notch to try again.")
                scheduleAutoRetryIfEnabled(after: NotchOverlayController.shared.failureHoldDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        case .noResolution:
            statusMessage = String(localized: "No face detected.")
            if showsUI {
                // No explicit collapse call: NotchOverlayController's own scanning timeout fires on the same mark and collapses itself.
                statusMessage = String(localized: "No face detected — hover the notch to try again.")
                scheduleAutoRetryIfEnabled(after: NotchOverlayController.shared.collapseAnimationDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        }
    }

    /// `delay` waits out whatever the overlay is still showing so the retry doesn't start underneath the previous outcome.
    private func scheduleAutoRetryIfEnabled(after delay: Duration) {
        guard FacekeySettings.shared.autoRetryOnce, !hasAutoRetriedForCurrentLock else {
            log.notice("auto-retry not scheduled (enabled=\(FacekeySettings.shared.autoRetryOnce), alreadyUsed=\(self.hasAutoRetriedForCurrentLock))")
            return
        }
        log.notice("auto-retry scheduled")
        hasAutoRetriedForCurrentLock = true
        autoRetryTask?.cancel()
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            // Re-check rather than trust the delay: the user may have unlocked by password or retried manually while this waited.
            guard LockMonitor.isScreenActuallyLocked(), self.isEnabled else { return }
            if self.showsUI {
                // `delay` only matches the overlay's hold, not the collapse animation that follows it, so the phase is
                // still `.failure`/`.collapsing` when this wakes. Wait for it to settle instead of bailing (that spent the one-shot for nothing).
                let settleDeadline = ContinuousClock.now + .seconds(3)
                while NotchOverlayController.shared.phase != .closed {
                    guard ContinuousClock.now < settleDeadline, !Task.isCancelled else {
                        log.notice("auto-retry aborted: overlay never settled")
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard LockMonitor.isScreenActuallyLocked(), self.isEnabled else { return }
            }
            log.notice("auto-retry firing")
            self.startScanCycle(trigger: .autoRetry)
        }
    }

    private enum ScanOutcome {
        case matched
        case consistentlyWrongFace
        /// A deny cue (glare, device rectangle) fired — actively rejected as a spoof regardless of match. Same failure path as `.consistentlyWrongFace`.
        case spoofSuspected
        case noResolution
    }

    /// Recognition and liveness run concurrently and each latches when it succeeds, so unlock fires the moment the second lands;
    /// liveness never fails the scan by staying undecided, it just keeps scanning until `deadline`.
    /// `requireOverlayScanning` bails early once the overlay's own timeout collapses the UI — only applied when there is an
    /// overlay, since headlessly `phase` never becomes `.scanning` at all.
    private func observeScanWindow(deadline: Date, requireOverlayScanning: Bool) async -> ScanOutcome {
        let livenessEnabled = FacekeySettings.shared.livenessChecksEnabled
        let observedGeneration = scanGeneration
        scanSawFace = false
        let liveness = LivenessAnalyzer()
        liveness.modeProvider = { FacekeySettings.shared.livenessMode }
        /// Starts its warm-up clock here, so the dark first frames while the camera auto-exposes are skipped.
        var tracker = FaceMatchTracker()
        /// Set by the first consecutive non-match. A gap in face detection or
        /// a valid match clears it, so only a sustained wrong face resolves the scan.
        var wrongFaceStartedAt: ContinuousClock.Instant?

        /// Cleared the moment a detected face fails to match, so a latched match can't be handed to whoever steps in next.
        var readyMatch: ScoredIdentity?
        /// Turning liveness off in Settings makes this half permanently ready.
        var livenessConfirmed = !livenessEnabled
        /// Last frame's selected face, passed back so `selectDominantFace` stays on the same person instead of flip-flopping.
        var lastFaceBoundingBox: CGRect?
        /// Counts frames with a selected face, so the face width is logged once per scan instead of per frame.
        var faceWidthSamples = 0
        /// Cheap way to detect "no new camera frame yet" vs. "fresh frame" — without it a repeat frame would corrupt the liveness motion signal.
        var lastProcessedFrameID: UInt64?

        while Date() < deadline, !Task.isCancelled,
              !requireOverlayScanning || NotchOverlayController.shared.phase == .scanning {
            guard LockMonitor.isScreenActuallyLocked() else { return .noResolution }

            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                // 20ms keeps the liveness window's sample count high while staying close to the camera's native ~33ms cadence.
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastProcessedFrameID = frame.id

            let pipeline = self.pipeline
            let previousBoundingBox = lastFaceBoundingBox
            let outcome = await Task.detached(priority: .userInitiated) { () -> (FaceRecognitionResult, LivenessFrame)? in
                guard let result = try? pipeline.recognize(in: frame.image, preferNear: previousBoundingBox) else { return nil }
                let faceCrop = CameraManager.renderCrop(from: frame, imageRect: result.face.boundingBox)
                return (result, LivenessFeatureExtractor.extract(from: result, frame: frame.image, faceCrop: faceCrop))
            }.value

            guard let (result, livenessFrame) = outcome else {
                wrongFaceStartedAt = nil
                tracker.reset()
                lastFaceBoundingBox = nil
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastFaceBoundingBox = result.face.normalizedBoundingBox
            faceWidthSamples += 1
            // A superseded scan must not mark the newer scan as having seen a face.
            if observedGeneration == scanGeneration { scanSawFace = true }
            if faceWidthSamples == 5 {
                log.notice("scan face width=\(result.face.normalizedBoundingBox.width, privacy: .public) (min=\(FaceRecognitionPipeline.minimumProminentFaceWidth, privacy: .public)) frameSimilarity=\(pipeline.score(result.embedding, against: FaceEnrollmentStore.shared.activeIdentities).first?.centroidSimilarity ?? 0, privacy: .public)")
            }

            // Continuity, per-frame floor, warm-up and averaging live in the tracker, which `activeIdentities` feeds:
            // someone switched off on the Your Face page stays enrolled but must not unlock.
            let verdict = tracker.observe(
                result,
                previousBoundingBox: previousBoundingBox,
                pipeline: pipeline,
                activeIdentities: FaceEnrollmentStore.shared.activeIdentities,
                threshold: matchThreshold
            )
            let frameSimilarity = tracker.lastFrameSimilarity

            // Fed regardless of match, so liveness stays a genuinely independent gate rather than one starved by recognition confidence.
            var confirmingCue: LivenessCue?
            if livenessEnabled {
                let snapshot = liveness.observe(livenessFrame)
                switch snapshot.decision {
                case .denied:
                    // Overrides everything, including a match and any confirmation that already happened.
                    lastOutcome = snapshot.decision.denialReason
                    let glare = livenessFrame.glare
                    func box(_ r: CGRect?) -> String {
                        guard let r else { return "none" }
                        return "x=\(Int(r.minX)) y=\(Int(r.minY)) w=\(Int(r.width)) h=\(Int(r.height))"
                    }
                    let rectArea = (livenessFrame.deviceRectangle?.width ?? 0) * (livenessFrame.deviceRectangle?.height ?? 0)
                    let faceArea = (livenessFrame.faceBox?.width ?? 0) * (livenessFrame.faceBox?.height ?? 0)
                    log.notice("device rect: \(box(livenessFrame.deviceRectangle), privacy: .public) face: \(box(livenessFrame.faceBox), privacy: .public) image: \(Int(livenessFrame.imageSize?.width ?? 0))x\(Int(livenessFrame.imageSize?.height ?? 0)) rectToFaceArea=\(faceArea > 0 ? Double(rectArea / faceArea) : -1, privacy: .public)")
                    log.notice("liveness denied: \(self.lastOutcome ?? "?", privacy: .public) (frameSimilarity=\(frameSimilarity, privacy: .public), glareLevel=\(LivenessCues.glossGlare(livenessFrame).level, privacy: .public), specularFraction=\(glare?.specularFraction ?? -1, privacy: .public), cluster=\(glare?.specularClusterRatio ?? -1, privacy: .public), cropWidth=\(Double(glare?.cropPixelWidth ?? -1), privacy: .public), deviceOverlap=\(livenessFrame.deviceOverlapFraction ?? -1, privacy: .public))")
                    return .spoofSuspected
                case .confirmed(let cue):
                    livenessConfirmed = true
                    confirmingCue = cue
                case .pending:
                    break
                }
            }

            // Not enough samples yet — keep scanning (liveness above keeps running; wrongFaceStartedAt/readyMatch are deliberately untouched).
            // A frame below the per-frame floor is a confident non-match, so it falls through to the wrong-face handling.
            var matched: ScoredIdentity?
            switch verdict {
            case .undecided:
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            case .matched(let identity):
                matched = identity
            case .notMatched:
                break
            }

            if let matched {
                wrongFaceStartedAt = nil
                readyMatch = matched
            } else {
                readyMatch = nil
                if wrongFaceStartedAt == nil {
                    wrongFaceStartedAt = .now
                }
                if ContinuousClock.now - wrongFaceStartedAt! >= wrongFaceGraceDuration {
                    log.notice("wrong face for 4s (frameSimilarity=\(frameSimilarity, privacy: .public), threshold=\(self.matchThreshold, privacy: .public), buffer=\(tracker.bufferedCount))")
                    return .consistentlyWrongFace
                }
            }

            if let readyMatch, livenessConfirmed {
                statusMessage = String(localized: "Recognized — unlocking…")
                log.notice("matched, injecting password (similarity=\(readyMatch.centroidSimilarity, privacy: .public))")
                let livenessNote = livenessEnabled
                    ? (confirmingCue.map { "live via \($0.title)" } ?? "liveness clear")
                    : "liveness off"
                lastOutcome = "Matched \(readyMatch.identity.name) at \(String(format: "%.3f", readyMatch.centroidSimilarity)), \(livenessNote)."
                lastOwnInjectionAt = .now
                log.notice("own unlock: recording injection time before typing the password")
                await pocController.injectStoredPassword(requireAuthoritativeLock: true)
                return .matched
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return .noResolution
    }

    // MARK: - Post-unlock verification

    /// Called when the screen was found unlocked after a `.screenUnlocked` event. Facekey's own unlocks, a disabled setting, a pause after
    /// a re-lock and having nobody enrolled all skip the check; the rest start a short face scan.
    private func startVerificationIfNeeded() {
        guard lockMonitor.lastEvent == .screenUnlocked, lockMonitor.eventCount != lastVerifiedEventCount else { return }
        lastVerifiedEventCount = lockMonitor.eventCount
        guard FacekeySettings.shared.verifyAfterExternalUnlock else {
            log.notice("verify skip: setting off")
            return
        }
        if let injected = lastOwnInjectionAt, ContinuousClock.now - injected < ownUnlockWindow {
            log.notice("verify skip: own unlock")
            return
        }
        if let until = verificationSuppressedUntil, ContinuousClock.now < until {
            log.notice("verify skip: paused after a re-lock")
            return
        }
        guard !FaceEnrollmentStore.shared.activeIdentities.isEmpty else {
            log.notice("verify skip: no enabled identities")
            return
        }
        cancelVerification(reason: "superseded")
        verificationGeneration &+= 1
        let generation = verificationGeneration
        log.notice("verify #\(generation) armed after external unlock")
        verificationTask = Task { [weak self] in
            await self?.runVerification(generation: generation)
        }
    }

    /// No-op when none is running. Bumping the generation makes a verification still suspended at `await camera.start()` inert.
    private func cancelVerification(reason: String) {
        guard let task = verificationTask else { return }
        log.notice("verify #\(self.verificationGeneration) cancelled: \(reason, privacy: .public)")
        task.cancel()
        verificationTask = nil
        verificationGeneration &+= 1
        camera.stop()
    }

    /// Releases the camera once a verification is over, unless it was already superseded or cancelled.
    private func finishVerification(generation: Int) {
        guard generation == verificationGeneration else { return }
        verificationTask = nil
        camera.stop()
    }

    private func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }

    /// Runs `PostUnlockVerification` over live frames: a match anywhere ends it quietly, a sustained unrecognised face locks the
    /// screen again, and an empty window changes nothing. No liveness and no password: a spoofed owner only avoids a re-lock.
    private func runVerification(generation: Int) async {
        FacekeySettings.shared.refreshPipelineMinimumFaceWidth()
        await camera.start()
        guard generation == verificationGeneration else {
            // `start()` only suspends while the permission prompt is up. If this verification was cancelled meanwhile, its
            // `camera.stop()` ran first and the start queued after it, so the camera is on with no owner: release it unless a
            // newer verification or a running lock-screen scan has taken over.
            if verificationTask == nil, activeScanCycles == 0 {
                log.notice("verify #\(generation) superseded while starting: releasing the camera")
                camera.stop()
            }
            return
        }
        if let error = camera.errorMessage {
            log.error("verify #\(generation) camera error: \(error, privacy: .public)")
            finishVerification(generation: generation)
            return
        }

        let startedAt = ContinuousClock.now
        var firstFrameAt: ContinuousClock.Instant?
        var tracker = FaceMatchTracker()
        var decision = PostUnlockVerification()
        var lastFaceBoundingBox: CGRect?
        var lastProcessedFrameID: UInt64?
        var outcome: PostUnlockVerification.Outcome?
        var abortReason: String?

        while outcome == nil, abortReason == nil {
            guard !Task.isCancelled, generation == verificationGeneration else { return }
            guard FacekeySettings.shared.verifyAfterExternalUnlock else { abortReason = "setting turned off"; break }
            guard !LockMonitor.isScreenActuallyLocked(), !lockMonitor.isSleeping else { abortReason = "locked or sleeping"; break }

            let now = ContinuousClock.now
            if let first = firstFrameAt {
                if seconds(now - first) > PostUnlockVerification.window {
                    outcome = decision.finish(at: seconds(now - first))
                    break
                }
            } else if seconds(now - startedAt) > PostUnlockVerification.window + 2 {
                abortReason = "no camera frames"
                break
            }

            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastProcessedFrameID = frame.id
            let first = firstFrameAt ?? ContinuousClock.now
            firstFrameAt = first

            let pipeline = self.pipeline
            let previousBoundingBox = lastFaceBoundingBox
            let result = await Task.detached(priority: .userInitiated) {
                try? pipeline.recognize(in: frame.image, preferNear: previousBoundingBox)
            }.value
            guard generation == verificationGeneration else { return }
            // Recognition suspended this task; the setting or the lock state may have changed meanwhile and must veto a re-lock.
            guard FacekeySettings.shared.verifyAfterExternalUnlock, !LockMonitor.isScreenActuallyLocked(), !lockMonitor.isSleeping else {
                abortReason = "setting turned off, locked or sleeping"
                break
            }

            let t = seconds(ContinuousClock.now - first)
            let observation: PostUnlockVerification.Observation?
            if let result {
                lastFaceBoundingBox = result.face.normalizedBoundingBox
                switch tracker.observe(
                    result,
                    previousBoundingBox: previousBoundingBox,
                    pipeline: pipeline,
                    activeIdentities: FaceEnrollmentStore.shared.activeIdentities,
                    threshold: matchThreshold
                ) {
                case .matched: observation = .matched
                case .notMatched: observation = .unrecognised
                case .undecided: observation = nil
                }
            } else {
                tracker.reset()
                lastFaceBoundingBox = nil
                observation = .noFace
            }
            if let observation { outcome = decision.observe(observation, at: t) }
            if outcome == nil { try? await Task.sleep(nanoseconds: 20_000_000) }
        }

        guard generation == verificationGeneration else { return }
        if let abortReason {
            log.notice("verify #\(generation) aborted: \(abortReason, privacy: .public)")
            finishVerification(generation: generation)
            return
        }
        guard let outcome else { finishVerification(generation: generation); return }

        switch outcome {
        case .verified:
            log.notice("verify #\(generation) outcome: verified, a recognised face is at the screen")
            finishVerification(generation: generation)
        case .nobody:
            log.notice("verify #\(generation) outcome: nobody in view, leaving the Mac unlocked")
            finishVerification(generation: generation)
        case .stranger:
            log.notice("verify #\(generation) outcome: unrecognised face for \(PostUnlockVerification.grace, privacy: .public)s, locking the screen")
            finishVerification(generation: generation)
            let locked = await ScreenLocker.lock()
            // Pause only once the Mac really re-locked: if the lock failed the stranger is still in, so the next unlock must be checked again.
            if locked { verificationSuppressedUntil = .now + verificationSuppression }
            log.notice("verify #\(generation) re-lock locked=\(locked, privacy: .public)")
        }
    }
}

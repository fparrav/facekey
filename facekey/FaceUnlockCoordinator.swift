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

    private(set) var statusMessage = "Idle"
    private(set) var lastOutcome: String?

    private var hasArmedForCurrentLock = false
    /// One-shot per lock session — an auto-retry that could itself auto-retry would loop the camera for the whole lock session.
    private var hasAutoRetriedForCurrentLock = false
    private var scanTask: Task<Void, Never>?
    /// Bumped by every `startScanCycle()`; a cycle bails once superseded (see `runScanCycle(generation:)`).
    private var scanGeneration = 0
    /// When the last scan cycle was armed — collapses a single wake into a single arm (see `.wake` branch of `evaluateTrigger`).
    private var lastArmedAt: ContinuousClock.Instant?
    /// One lid-open fires several wake signals within a few hundred ms of each other; anything in this window counts as the same wake.
    private let rearmDebounce: Duration = .seconds(2)
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
            self?.evaluateTrigger()
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
                self?.evaluateTrigger()
            }
        }
    }

    private func evaluateTrigger() {
        log.debug("evaluateTrigger lastEvent=\(String(describing: self.lockMonitor.lastEvent), privacy: .public) armed=\(self.hasArmedForCurrentLock)")
        guard LockMonitor.isScreenActuallyLocked() else {
            hasArmedForCurrentLock = false
            hasAutoRetriedForCurrentLock = false
            disarmOverlay()
            return
        }
        guard !lockMonitor.isSleeping else { return }

        // `.wake` (sleep, display sleep, or screensaver stopping) is an explicit "let me back in," so clear the one-shot guard.
        // `isWithinRecentArmBurst` keeps the several wake signals from one lid-open from each re-arming and fighting over the camera.
        if lockMonitor.lastEvent == .wake, !isWithinRecentArmBurst {
            hasArmedForCurrentLock = false
        }

        // Runs before the hasArmedForCurrentLock guard — the space monitor's lifetime is tied to "locked + opted in," not to whether a scan already ran.
        updateSpaceMonitor()

        guard isEnabled, !hasArmedForCurrentLock else { return }
        guard let signal = requiredTrigger(for: lockMonitor.lastEvent) else { return }
        // A pinned display that isn't connected bails entirely rather than showing up elsewhere; "Main display" (nil) always resolves.
        guard NotchGeometry.preferredScreen() != nil else { return }

        guard FacekeySettings.shared.isFaceUnlockEnabled(for: DisplayContext.current()) else {
            disarmOverlay()
            return
        }
        guard SecureCredentialManager.isSessionUnlocked else {
            statusMessage = "Face unlock is on, but the session is locked — authenticate once from Password settings first."
            return
        }
        guard SecureCredentialManager.hasStoredPassword() else {
            statusMessage = "Face unlock is on, but no password is stored yet."
            return
        }

        // A deselected trigger means "don't auto-scan for this signal," not "do nothing" — the user can still opt in by hand.
        let shouldAutoScan = FacekeySettings.shared.unlockTriggers.contains(signal)

        // Headless has nothing to arm/hover, so if this signal isn't selected there's nothing to do — and hasArmedForCurrentLock
        // must stay false, or a later selected signal could never fire (nothing else calls arm() to reset it).
        guard showsUI || shouldAutoScan else { return }

        hasArmedForCurrentLock = true
        lastArmedAt = .now
        Task { [weak self] in
            // arm() only shows a small closed notch silhouette, so this only needs a brief buffer past the login window's entrance.
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.arm(autoScan: shouldAutoScan)
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
        camera.stop()
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
            startScanCycle()
            return
        }
        if NotchOverlayController.shared.isArmed {
            // Closed pill/notch already up — expand and scan, like a hover retry.
            startScanCycle()
        } else {
            Task { [weak self] in await self?.arm(autoScan: true) }
        }
    }

    /// Either way the overlay still arms — a deselected trigger only skips the automatic scan, leaving hover-to-start available.
    private func arm(autoScan: Bool) async {
        guard LockMonitor.isScreenActuallyLocked() else { return }
        guard showsUI else {
            // Headless: evaluateTrigger() already guaranteed autoScan is true here, so this is just "start scanning."
            startScanCycle()
            return
        }
        NotchOverlayController.shared.arm { [weak self] in
            self?.startScanCycle()
        }
        if autoScan {
            startScanCycle()
        }
    }

    /// Called on arm, and again whenever the overlay hover-activates.
    private func startScanCycle() {
        scanTask?.cancel()
        scanGeneration &+= 1
        let generation = scanGeneration
        scanTask = Task { [weak self] in
            await self?.runScanCycle(generation: generation)
        }
    }

    /// `generation` is what makes overlapping cycles safe: `Task.cancel()` is cooperative, so a superseded cycle still runs to the
    /// end of this function, and its global side effects (`camera.stop()` etc.) could otherwise land on the newer cycle instead
    /// of itself. This was a real bug — a superseded `camera.stop()` queued behind the newer cycle's `startRunning()` made the
    /// camera visibly switch on then die mid-warm-up, leaving the surviving cycle polling a dead session and never unlocking.
    private func runScanCycle(generation: Int) async {
        guard LockMonitor.isScreenActuallyLocked() else {
            log.notice("scan #\(generation) skipped: screen not locked")
            return
        }
        log.notice("scan #\(generation) start (ui=\(self.showsUI), window=\(self.scanWindowDuration, privacy: .public)s, threshold=\(self.matchThreshold, privacy: .public))")

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
        statusMessage = "Looking for your face…"

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

        switch outcome {
        case .matched:
            // The unlock already happened inside observeScanWindow — this only decides whether anything is shown about it.
            if showsUI {
                NotchOverlayController.shared.finish(success: true)
            }
        case .consistentlyWrongFace:
            statusMessage = "Face not recognized."
            if showsUI {
                NotchOverlayController.shared.finish(success: false)
                statusMessage = "Face not recognized — hover the notch to try again."
                scheduleAutoRetryIfEnabled(after: NotchOverlayController.shared.failureHoldDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        case .spoofSuspected:
            statusMessage = "Couldn't confirm a live face."
            if showsUI {
                NotchOverlayController.shared.finish(success: false)
                statusMessage = "Couldn't confirm a live face — hover the notch to try again."
                scheduleAutoRetryIfEnabled(after: NotchOverlayController.shared.failureHoldDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        case .noResolution:
            statusMessage = "No face detected."
            if showsUI {
                // No explicit collapse call: NotchOverlayController's own scanning timeout fires on the same mark and collapses itself.
                statusMessage = "No face detected — hover the notch to try again."
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
            self.startScanCycle()
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
        let liveness = LivenessAnalyzer()
        liveness.modeProvider = { FacekeySettings.shared.livenessMode }
        /// Early frames are dark while the camera auto-exposes, so skip them from the embedding buffer.
        let scanStartedAt = ContinuousClock.now
        let warmUpDuration: Duration = .milliseconds(300)
        /// Set by the first consecutive non-match. A gap in face detection or
        /// a valid match clears it, so only a sustained wrong face resolves the scan.
        var wrongFaceStartedAt: ContinuousClock.Instant?

        /// Cleared the moment a detected face fails to match, so a latched match can't be handed to whoever steps in next.
        var readyMatch: ScoredIdentity?
        /// Turning liveness off in Settings makes this half permanently ready.
        var livenessConfirmed = !livenessEnabled
        /// Last frame's selected face, passed back so `selectDominantFace` stays on the same person instead of flip-flopping.
        var lastFaceBoundingBox: CGRect?
        /// Cheap way to detect "no new camera frame yet" vs. "fresh frame" — without it a repeat frame would corrupt the liveness motion signal.
        var lastProcessedFrameID: UInt64?
        /// Recent face embeddings, averaged before scoring so per-frame noise doesn't flip the match decision.
        var embeddingBuffer: [[Float]] = []
        let maxBufferedEmbeddings = 5
        let minBufferedEmbeddings = 3
        let perFrameFloorMargin: Float = 0.08

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
                embeddingBuffer.removeAll()
                lastFaceBoundingBox = nil
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastFaceBoundingBox = result.face.normalizedBoundingBox

            // Same tolerance as `FaceRecognitionPipeline.continuityDistanceTolerance`: center drift at or beyond this in
            // normalized coordinates means the tracked face is a different person, so the running average must not blend them.
            let continuityDistanceTolerance: CGFloat = 0.3
            if let previous = previousBoundingBox {
                let previousCenter = CGPoint(x: previous.midX, y: previous.midY)
                let center = CGPoint(x: result.face.normalizedBoundingBox.midX, y: result.face.normalizedBoundingBox.midY)
                if hypot(center.x - previousCenter.x, center.y - previousCenter.y) >= continuityDistanceTolerance {
                    embeddingBuffer.removeAll()
                }
            }
            // Each frame must clear a floor on its own: averaging alone would let a few frames of the owner lift a
            // stranger who steps in front of the camera over the threshold. A frame below the floor drops the whole buffer.
            // `activeIdentities`, not `identities`: someone switched off on the Your Face page stays enrolled but must not unlock.
            let activeIdentities = FaceEnrollmentStore.shared.activeIdentities
            let frameSimilarity = pipeline.score(result.embedding, against: activeIdentities).first?.centroidSimilarity ?? 0
            let frameBelowFloor = frameSimilarity < matchThreshold - perFrameFloorMargin
            if frameBelowFloor {
                embeddingBuffer.removeAll()
            } else if ContinuousClock.now - scanStartedAt >= warmUpDuration {
                embeddingBuffer.append(result.embedding)
                if embeddingBuffer.count > maxBufferedEmbeddings {
                    embeddingBuffer.removeFirst()
                }
            }

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
            if embeddingBuffer.count < minBufferedEmbeddings && !frameBelowFloor {
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            var matched: ScoredIdentity?
            if !frameBelowFloor {
                guard let smoothed = FaceRecognitionPipeline.averagedEmbedding(embeddingBuffer) else {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    continue
                }
                let scored = pipeline.score(smoothed, against: activeIdentities)
                matched = pipeline.bestMatch(in: scored, threshold: matchThreshold)
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
                    log.notice("wrong face for 4s (frameSimilarity=\(frameSimilarity, privacy: .public), threshold=\(self.matchThreshold, privacy: .public), buffer=\(embeddingBuffer.count))")
                    return .consistentlyWrongFace
                }
            }

            if let readyMatch, livenessConfirmed {
                statusMessage = "Recognized — unlocking…"
                log.notice("matched, injecting password (similarity=\(readyMatch.centroidSimilarity, privacy: .public))")
                let livenessNote = livenessEnabled
                    ? (confirmingCue.map { "live via \($0.title)" } ?? "liveness clear")
                    : "liveness off"
                lastOutcome = "Matched \(readyMatch.identity.name) at \(String(format: "%.3f", readyMatch.centroidSimilarity)), \(livenessNote)."
                await pocController.injectStoredPassword(requireAuthoritativeLock: true)
                return .matched
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return .noResolution
    }
}

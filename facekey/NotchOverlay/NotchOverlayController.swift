//
//  NotchOverlayController.swift
//  facekey
//
//  The only file other code should touch to show the notch overlay.
//
//  Interaction is hover-driven, not click-driven: a non-activating panel
//  otherwise needs a first click just to gain focus before a second click
//  registers — hover avoids that "have to double-click" bug entirely.
//

import AppKit
import SwiftUI
import Observation
import os

private let log = Logger(subsystem: "com.fparrav.facekey", category: "overlay")

@Observable
@MainActor
final class NotchOverlayController {
    /// One overlay window for the whole app — sharing one instance guarantees
    /// the triggers never run concurrently, rather than leaving that incidental.
    static let shared = NotchOverlayController()

    enum Phase: Equatable {
        /// While armed, the window stays on-screen here (hover-reactive); otherwise ordered out.
        case closed
        /// Expanded, showing the idle still image — actively looking for a face.
        case scanning
        /// Success animation playing, then auto-collapses.
        case success
        /// Failure animation playing/held; collapses after a hold unless
        /// the user hovers first to retry.
        case failure
        case collapsing
        /// Hosting the multi-step onboarding flow, driven by the hosted
        /// OnboardingController rather than this controller's own machinery.
        case onboarding
        /// Asking the user to approve a `sudo` request (or whether an app may use Facekey for it).
        /// Interactive but never key, so it can't take focus from the terminal.
        case sudoRequest
    }

    /// Kept as one enum (rather than two independent optionals) so exactly one is ever active.
    enum Content: Equatable {
        case scan(ScanMedia)
        case onboarding(OnboardingController)
        case sudo(SudoOverlayPrompt)

        static func == (lhs: Content, rhs: Content) -> Bool {
            switch (lhs, rhs) {
            case (.scan(let a), .scan(let b)): return a == b
            case (.onboarding(let a), .onboarding(let b)): return a === b
            case (.sudo(let a), .sudo(let b)): return a == b
            default: return false
            }
        }
    }

    private(set) var phase: Phase = .closed
    private(set) var content: Content = .scan(.idle)
    /// The state whose one-line message the scan panel shows under the video; nil shows no text.
    private(set) var statusState: NotchStatusState?
    /// Read-only convenience for the scan-mode view/callers — `.idle` while
    /// onboarding owns the panel.
    var media: ScanMedia {
        if case .scan(let media) = content { return media }
        return .idle
    }
    private(set) var geometry: NotchGeometry = .forMainScreen()
    /// Read by the view for the hover-driven size/shadow bump — irrelevant
    /// to the phase state machine itself.
    private(set) var isArmed = false

    /// Pill style only: whether the pill is parked on screen at rest vs. off-screen.
    /// Deliberately separate from `isArmed` — it lags it by a frame on the way in
    /// (making the pill slide into place) and leads it on the way out.
    private(set) var isPillDocked = false

    /// Snapshotted from `FacekeySettings` when a cycle begins rather than read live,
    /// so a settings change mid-attempt can't resize the panel or change how it resolves.
    private(set) var activeUnlockStyle: UnlockAnimationStyle = .original

    /// What a hover-driven activation should do — set by `arm()` (persists
    /// across scan cycles) or by one-shot `present(onRetry:)` (single use).
    private var onActivate: (() -> Void)?

    /// Answer for the sudo prompt on screen; taken (set to nil) by the first click so a
    /// prompt resolves at most once.
    private var onSudoChoice: ((SudoOverlayChoice, String) -> Void)?

    private let windowController = NotchWindowController()
    private var resolveTask: Task<Void, Never>?
    private var scanTimeoutTask: Task<Void, Never>?

    /// Guards `primeWindowIfNeeded` so the extra render pass only happens on the first show.
    private var hasPrimedWindow = false

    /// Matches the success asset duration (~1.22s) plus a short beat to read the final frame.
    private let successHoldDuration: Duration = .milliseconds(1_700)
    /// Non-private so FaceUnlockCoordinator's auto-retry can wait this out too.
    let failureHoldDuration: Duration = .seconds(5)
    /// Reads the same setting as `FaceUnlockCoordinator.scanWindowDuration` so
    /// the two separate timers expire together.
    private var scanTimeoutDuration: Duration {
        .seconds(FacekeySettings.shared.faceDetectionSeconds)
    }
    /// Long enough for the closing spring to fully settle before the window is
    /// hidden/left closed — collapsing state too early made the window visibly pop away.
    let collapseAnimationDuration: Duration = .milliseconds(700)

    private init() {
        windowController.contentView = NSHostingView(rootView: NotchOverlayView(controller: self))
        // A display connecting/disconnecting mid-flow can flip notch vs. pill style.
        windowController.onScreenParametersChanged = { [weak self] in
            guard let self else { return }
            self.geometry = self.windowController.currentGeometry
        }
        windowController.onLeftMouseDown = { [weak self] point, panel, source in
            self?.handleSudoMouseDown(at: point, panel: panel, clickSource: source)
        }
    }

    // MARK: - Armed mode (FaceUnlockCoordinator)

    /// Arms the overlay for the lock-screen flow: shows the window and keeps it
    /// up until `disarm()`. `onActivate` restarts scanning on hover.
    func arm(onActivate: @escaping () -> Void) {
        cancelPendingSudoPrompt()
        isArmed = true
        self.onActivate = onActivate
        geometry = windowController.currentGeometry
        phase = .closed
        content = .scan(.idle)
        statusState = nil
        isPillDocked = false
        windowController.show()
        hasPrimedWindow = true // already shown+rendered while closed, same effect as primeWindowIfNeeded
        updateInteractivity()

        guard geometry.style == .pill else {
            // The notch silhouette has nowhere to travel from — it's on top of hardware already there.
            isPillDocked = true
            return
        }
        // Render one real frame with the pill still off-screen, so flipping the
        // flag next runloop animates it down instead of appearing already docked.
        windowController.displaySynchronously()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isArmed else { return }
            self.isPillDocked = true
        }
    }

    /// Truly hides the window. Only call once the lock-screen attempt is
    /// completely done — while armed, resolving an attempt goes back to `.closed`, not this.
    ///
    /// If a success/collapse sequence is already resolving, let it finish
    /// naturally: setting `isArmed = false` is enough, since the already-scheduled
    /// `collapse()` checks `isArmed` once its hold expires and hides for real then.
    func disarm() {
        cancelPendingSudoPrompt()
        isArmed = false
        onActivate = nil
        // Undocked before the guard: if a success collapse is already in flight, this
        // turns it into a full slide-off-screen exit rather than a shrink to a resting pill.
        isPillDocked = false
        guard phase != .success, phase != .collapsing else { return }
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        // Re-measured here, not just trusted from `arm()` — `arm()` typically
        // fires right around wake/unlock, when AppKit may not have finished
        // laying out the menu bar yet, so `auxiliaryTopLeftArea`/`RightArea`
        // can read back momentarily wrong. Refreshing right before settling
        // to `.closed` (the shape most directly compared against the real
        // notch) self-corrects instead of baking in a bad first reading.
        geometry = windowController.currentGeometry
        phase = .closed
        content = .scan(.idle)
        windowController.setInteractive(false)

        guard geometry.style == .pill, windowController.isVisible else {
            windowController.hide()
            return
        }
        // The pill is visible at rest, so hiding the window right now would blink it
        // away instead of playing the slide-up (visibility check above skips hidden windows).
        Task { [weak self] in
            try? await Task.sleep(for: self?.collapseAnimationDuration ?? .milliseconds(700))
            guard let self, !self.isArmed, self.phase == .closed else { return }
            self.windowController.hide()
        }
    }

    /// Shows the idle still; auto-collapses silently (no failure animation) after
    /// `scanTimeoutDuration` if nothing resolves it.
    func beginScanning() {
        cancelPendingSudoPrompt()
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel()
        geometry = windowController.currentGeometry
        activeUnlockStyle = FacekeySettings.shared.effectiveUnlockAnimationStyle
        content = .scan(.idle)
        statusState = .scanning
        phase = .scanning
        updateInteractivity()

        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: self?.scanTimeoutDuration ?? .seconds(5))
            guard let self, !Task.isCancelled, self.phase == .scanning else { return }
            await self.collapse()
        }
    }

    // MARK: - Window priming (first show only)

    /// On the very first show, `present()`/`presentOnboarding()` would otherwise render
    /// already-expanded with no prior "closed" frame for SwiftUI to animate away from.
    /// This runs one real closed-state show+render pass first, only on that first call.
    private func primeWindowIfNeeded(_ completion: @escaping () -> Void) {
        guard !hasPrimedWindow else {
            completion()
            return
        }
        hasPrimedWindow = true
        content = .scan(.idle)
        phase = .closed
        windowController.show()
        windowController.displaySynchronously()
        DispatchQueue.main.async(execute: completion)
    }

    // MARK: - One-shot mode (onboarding, Face Lab preview)

    /// Shows the overlay in its scanning state. Safe to call again while already visible.
    /// `onRetry` runs on hover after a failed attempt; pass nil to just collapse on hover.
    ///
    /// - Parameter styleOverride: forces `.minimal`/`.original` regardless of the saved
    ///   preference, for the Animation section's live preview.
    func present(styleOverride: UnlockAnimationStyle? = nil, onRetry: (() -> Void)? = nil) {
        cancelPendingSudoPrompt()
        isArmed = false
        onActivate = onRetry
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        geometry = windowController.currentGeometry
        activeUnlockStyle = styleOverride ?? FacekeySettings.shared.effectiveUnlockAnimationStyle
        primeWindowIfNeeded { [weak self] in
            guard let self else { return }
            content = .scan(.idle)
            // The Animation section's preview forces a style and has nothing to announce.
            statusState = styleOverride == nil ? .scanning : nil
            phase = .scanning
            windowController.show()
            updateInteractivity()
        }
    }

    // MARK: - Onboarding mode (OnboardingController)

    /// Hands the panel to the onboarding flow — this object only owns visibility and
    /// interactivity while `.onboarding` is active; sizing/content is driven by `controller`.
    func presentOnboarding(_ controller: OnboardingController) {
        cancelPendingSudoPrompt()
        isArmed = false
        onActivate = nil
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        geometry = windowController.currentGeometry
        primeWindowIfNeeded { [weak self] in
            guard let self else { return }
            content = .onboarding(controller)
            statusState = nil
            phase = .onboarding
            windowController.show()
            updateInteractivity()
        }
    }

    /// Gracefully shrinks the onboarding panel away and hides the window; guarded by
    /// re-checking `content` so a concurrently-started scan cycle can't be interrupted.
    func dismissOnboarding() {
        guard case .onboarding = content else { return }
        // Drop key/interactivity now, not inside the Task: first-run completion opens
        // Settings this same turn, and a still-key overlay would leave it inactive.
        phase = .collapsing
        updateInteractivity()
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.collapseAnimationDuration)
            guard case .onboarding = self.content else { return }
            self.content = .scan(.idle)
            self.phase = .closed
            self.windowController.hide()
        }
    }

    // MARK: - Sudo approval mode (SudoOverlayPresenter)

    /// Shows the sudo prompt, or swaps the content when one is already up (the first-use
    /// question is followed by the confirmation without closing in between). `onChoice`
    /// fires once, from a mouse-down on one of the two buttons, with who produced the click.
    /// Returns false, showing nothing, when onboarding owns the panel.
    @discardableResult
    func presentSudo(_ prompt: SudoOverlayPrompt, onChoice: @escaping (SudoOverlayChoice, String) -> Void) -> Bool {
        guard phase != .onboarding else { return false }
        isArmed = false
        onActivate = nil
        onSudoChoice = onChoice
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        geometry = windowController.currentGeometry
        primeWindowIfNeeded { [weak self] in
            guard let self, self.onSudoChoice != nil else { return } // closed while priming
            content = .sudo(prompt)
            statusState = nil
            phase = .sudoRequest
            windowController.show()
            updateInteractivity()
        }
        return true
    }

    /// After Accept: the prompt gives way to the scan panel with the approval line while the face
    /// scan runs. The phase stays `.sudoRequest`, so `dismissSudo()` still closes it.
    func showSudoScanning() {
        guard phase == .sudoRequest else { return }
        content = .scan(.idle)
        statusState = .sudoApproval
    }

    /// Drops the pending answer and shrinks the prompt away; a no-op when no sudo prompt is up.
    func dismissSudo() {
        onSudoChoice = nil
        guard phase == .sudoRequest else { return }
        Task { [weak self] in await self?.collapse() }
    }

    /// Another flow is taking the panel: answer the waiting prompt as cancelled so its
    /// caller never hangs on a prompt that is no longer on screen.
    private func cancelPendingSudoPrompt() {
        guard let onSudoChoice else { return }
        self.onSudoChoice = nil
        onSudoChoice(.cancel, "none")
    }

    private func handleSudoMouseDown(at point: CGPoint, panel: CGRect?, clickSource: String) {
        guard phase == .sudoRequest, case .sudo(let prompt) = content,
              let onSudoChoice, let panel,
              let choice = SudoOverlayMetrics.choice(at: point, panel: panel, kind: prompt.kind)
        else { return }
        self.onSudoChoice = nil
        onSudoChoice(choice, clickSource)
    }

    // MARK: - Resolving (shared by both modes)

    /// Resolves the current attempt. Success plays its animation and then
    /// collapses on its own; failure plays its animation and holds until
    /// either the hold expires or the user hovers to retry.
    func finish(success: Bool) {
        resolveTask?.cancel()
        scanTimeoutTask?.cancel()

        // Unlock Animation → None just skips the success/failure video; phase and
        // retry behavior are unaffected. Reads the cycle's captured style, not live settings.
        let shouldAnimate = activeUnlockStyle != .none
        content = shouldAnimate ? .scan(success ? .success : .failure) : .scan(.idle)
        statusState = success ? .success : .failure
        phase = success ? .success : .failure
        updateInteractivity()

        let hold = shouldAnimate ? (success ? successHoldDuration : failureHoldDuration) : Duration.milliseconds(400)
        resolveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled else { return }
            await self.collapse()
        }
    }

    /// The camera could not be opened: resolves like a failed scan (same hold, hover retry still
    /// available, no password typed) with the amber "Camera unavailable" line instead of the
    /// failure animation.
    func showCameraUnavailable() {
        resolveTask?.cancel()
        scanTimeoutTask?.cancel()
        geometry = windowController.currentGeometry
        content = .scan(.idle)
        statusState = .cameraUnavailable
        phase = .failure
        updateInteractivity()

        resolveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.failureHoldDuration)
            guard !Task.isCancelled else { return }
            await self.collapse()
        }
    }

    /// Hover-driven activation: wakes from a closed/armed state, or retries from a held
    /// failure frame. No-op during scanning/success/collapsing.
    func activate() {
        log.notice("activate phase=\(String(describing: self.phase), privacy: .public) retryOnHover=\(FacekeySettings.shared.retryOnHover) armed=\(self.isArmed) hasHandler=\(self.onActivate != nil)")
        // Gated here rather than in `updateInteractivity()` so the cosmetic hover bump
        // stays unaffected — only the retry itself is removed.
        guard FacekeySettings.shared.retryOnHover else { return }
        switch phase {
        case .closed, .failure:
            guard let onActivate else {
                if phase == .failure { Task { await collapse() } }
                return
            }
            resolveTask?.cancel(); resolveTask = nil
            if !isArmed {
                // Captures its own style here; the armed path doesn't need to since
                // `onActivate()` routes through `beginScanning()`, which captures.
                activeUnlockStyle = FacekeySettings.shared.effectiveUnlockAnimationStyle
                content = .scan(.idle)
                statusState = .scanning
                phase = .scanning
                updateInteractivity()
            }
            onActivate()
        case .scanning, .success, .collapsing, .onboarding, .sudoRequest:
            break
        }
    }

    /// Collapses gracefully: animates shut, then either leaves the window
    /// at rest (closed, still on-screen, hover-reactive) if armed, or
    /// orders it out entirely if not.
    func collapse() async {
        guard phase != .closed, phase != .collapsing else { return }
        // Capture the display's real closed notch dimensions before changing phase.
        // The phase change starts the SwiftUI closing animation; measuring afterward
        // would animate toward stale geometry, then expose the real (smaller) notch
        // when the window is hidden.
        geometry = windowController.currentGeometry
        phase = .collapsing
        updateInteractivity()
        try? await Task.sleep(for: collapseAnimationDuration)
        guard phase == .collapsing else { return }

        content = .scan(.idle)
        statusState = nil
        if isArmed {
            phase = .closed
            updateInteractivity()
        } else {
            phase = .closed
            windowController.hide()
        }
    }

    /// Tears the overlay down without any resolve animation. Deliberately a no-op while
    /// success/collapsing is in flight — interrupting that made the window vanish abruptly.
    func dismissImmediately() {
        cancelPendingSudoPrompt()
        guard phase != .success, phase != .collapsing else { return }
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        phase = .closed
        content = .scan(.idle)
        statusState = nil
        isPillDocked = false
        windowController.setInteractive(false)
        windowController.hide()
    }

    private func updateInteractivity() {
        // Click-through otherwise, so the overlay never intercepts anything it doesn't
        // need to. Onboarding additionally needs key so its text field can receive keystrokes.
        // The sudo prompt takes clicks but never focus (`canBecomeKey: false`).
        windowController.setInteractive(
            isArmed || phase == .failure || phase == .onboarding || phase == .sudoRequest,
            key: phase == .onboarding,
            canBecomeKey: phase != .sudoRequest
        )
    }

    /// Called by `NotchOverlayView` whenever the visible panel's own frame
    /// changes (step change, expand/collapse, hover bump, …) — see
    /// `NotchWindowController.updateMousePassthrough()`.
    func updateInteractiveContentRect(_ rect: CGRect?) {
        windowController.setInteractiveContentRect(rect)
    }
}

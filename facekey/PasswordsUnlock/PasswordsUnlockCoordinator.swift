//
//  PasswordsUnlockCoordinator.swift
//  facekey
//
//  Decides one unlock of the Passwords app: gates in order, then the "Unlock Passwords"
//  confirmation, a click-started face scan, a last-moment focus check and, only then, the
//  read and typing of the stored Mac password. Anything but a completed typing leaves
//  Passwords locked. Never logs the password, and holds it only inside the typing step,
//  wiped on every way out.
//

import Foundation
import os

private let log = Logger(subsystem: "com.fparrav.facekey", category: "passwords-unlock")

/// Thrown by a `KeystrokeTyping` when `shouldContinue` said stop; nothing more was posted.
struct KeystrokeTypingCancelled: Error {}

@MainActor
final class PasswordsUnlockCoordinator {
    private let session: SudoSessionState
    private let setup: PasswordsUnlockSetupProviding
    private let overlay: PasswordsUnlockOverlayPresenting
    private let scanner: SudoFaceScanning
    private let focus: PasswordsFocusChecking
    /// The focus checkers for the browser surfaces; a surface that is not listed is declined.
    private let browserFocus: [PasswordsSurface: PasswordsFocusChecking]
    private let credentials: PasswordsCredentialReading
    private let typer: KeystrokeTyping
    private let clock: SudoClock

    private var isBusy = false
    /// Set by the flow timer; every wait afterwards ends the flow as timed out.
    private var requestTimedOut = false
    /// Set when the lock is no longer seen while a flow runs (the user left Passwords).
    private var lockLost = false
    /// The surface the running flow serves; events from the other surface do not disturb it.
    private var activeSurface: PasswordsSurface?
    /// Surfaces with an attempt since their lock was last seen to end, so one lock gets one attempt.
    private var attemptedSurfaces: Set<PasswordsSurface> = []
    private var lastAttemptEnd: Date?
    /// Set when Passwords is seen unlocked while a flow runs: the typed password was accepted.
    private var unlockedDuringFlow = false
    private var scanTask: Task<SudoScanResult, Never>?

    /// After pressing "use password", the field is polled this often for up to `fieldWaitPolls` times (about 3 s).
    private nonisolated static let fieldWaitInterval: Duration = .milliseconds(100)
    private nonisolated static let fieldWaitPolls = 30

    init(session: SudoSessionState,
         setup: PasswordsUnlockSetupProviding,
         overlay: PasswordsUnlockOverlayPresenting,
         scanner: SudoFaceScanning,
         focus: PasswordsFocusChecking,
         browserFocus: [PasswordsSurface: PasswordsFocusChecking] = [:],
         credentials: PasswordsCredentialReading,
         typer: KeystrokeTyping,
         clock: SudoClock) {
        self.session = session
        self.setup = setup
        self.overlay = overlay
        self.scanner = scanner
        self.focus = focus
        self.browserFocus = browserFocus
        self.credentials = credentials
        self.typer = typer
        self.clock = clock
    }

    /// Feed every state the watcher reports. Returns the outcome when a locked state ran or
    /// declined a flow, and nil for the states that only update bookkeeping.
    @discardableResult
    func lockStateChanged(_ state: PasswordsLockState, surface: PasswordsSurface = .app) async -> PasswordsUnlockOutcome? {
        guard state == .locked || state == .lockedChoice else {
            // The lock is gone (unlocked, hidden or in the background): the next lock is a new one.
            attemptedSurfaces.remove(surface)
            if state == .unlocked {
                // The password was accepted, so the cool-down meant for a rejected one has nothing to guard.
                if isBusy, activeSurface == surface { unlockedDuringFlow = true } else if !isBusy { lastAttemptEnd = nil }
            }
            if isBusy, activeSurface == surface {
                lockLost = true
                overlay.close() // resolves a prompt still waiting for a click
                scanTask?.cancel()
            }
            return nil
        }
        return await run(surface)
    }

    private func run(_ surface: PasswordsSurface) async -> PasswordsUnlockOutcome {
        if !setup.isUnlockEnabled { return decline(.setupDisabled) }
        if surface != .app, !setup.isBrowserUnlockEnabled || browserFocus[surface] == nil { return decline(.setupDisabled) }
        if session.isScreenLocked { return decline(.screenLocked) }
        if !session.isSessionUnlocked { return decline(.sessionLocked) }
        if !focus.isAccessibilityTrusted { return decline(.accessibilityMissing) }
        // A second lock event must not touch the state of the flow in flight.
        if isBusy { return decline(.busy) }
        if session.isLockScreenScanArming { return decline(.cameraBusy) }
        if attemptedSurfaces.contains(surface) { return decline(.alreadyTried) }
        if let last = lastAttemptEnd, clock.now.timeIntervalSince(last) < PasswordsUnlockTimeouts.cooldown {
            return decline(.coolingDown)
        }

        isBusy = true
        activeSurface = surface
        attemptedSurfaces.insert(surface)
        lockLost = false
        requestTimedOut = false
        unlockedDuringFlow = false
        session.setSudoRequestActive(true)
        let flowTimer = startTimer(PasswordsUnlockTimeouts.flow) { [weak self] in
            guard let self else { return }
            requestTimedOut = true
            overlay.close()
            scanTask?.cancel()
        }
        defer {
            flowTimer.cancel()
            scanTask = nil
            isBusy = false
            activeSurface = nil
            session.setSudoRequestActive(false)
            overlay.close()
        }

        if lockLost { return finish(.focusLost) }
        let confirmation = await askUser { await overlay.confirm() }
        if confirmation.timedOut { return finish(.timedOut) }
        if lockLost { return finish(.focusLost) }
        switch confirmation.value {
        case .cancelled: return finish(.cancelled)
        case .timedOut: return finish(.timedOut)
        case .accepted: break
        }

        if requestTimedOut { return finish(.timedOut) }
        // Its own task so the flow timer or a lost lock can cancel a scan that is still looking;
        // the scanner releases the camera when cancelled.
        let task = Task { await scanner.scan() }
        scanTask = task
        let scan = await task.value
        scanTask = nil
        if requestTimedOut { return finish(.timedOut) }
        if lockLost { return finish(.focusLost) }
        guard scan.matched else { return finish(.notMatched) }

        // The screen or the session may have locked during the confirmation and the scan.
        if session.isScreenLocked { return decline(.screenLocked) }
        if !session.isSessionUnlocked { return decline(.sessionLocked) }

        return finish(await readAndType(surface))
    }

    /// Re-checks focus immediately before reading the password, then reads and types it in one
    /// step off the main actor so the plaintext never crosses an actor. The bytes are wiped on
    /// every way out. Typing stops between batches if focus leaves Passwords.
    private func readAndType(_ surface: PasswordsSurface) async -> PasswordsUnlockOutcome {
        let focus = browserFocus[surface] ?? self.focus
        let credentials = self.credentials
        let typer = self.typer
        let polls = Self.fieldWaitPolls
        let interval = Self.fieldWaitInterval
        return await Task.detached(priority: .userInitiated) { () -> PasswordsUnlockOutcome in
            if !focus.isPasswordsLockedAndFocused() {
                // Touch ID or Apple Watch is on offer: ask for the password field, then wait for it to take focus.
                guard focus.isPasswordsAtUsePasswordChoice(), focus.pressUsePassword() else { return .focusLost }
                var fieldReady = false
                for _ in 0..<polls {
                    if Task.isCancelled { return .focusLost }
                    if focus.isPasswordsLockedAndFocused() { fieldReady = true; break }
                    try? await Task.sleep(for: interval)
                }
                guard fieldReady else { return .focusLost }
            }
            let secret: SecretBytes
            do {
                secret = try credentials.readPassword()
            } catch {
                return .credentialUnavailable
            }
            defer { secret.wipe() }
            do {
                try typer.typeAndReturn(secret) { !Task.isCancelled && focus.isPasswordsLockedAndFocused() }
                return .typed
            } catch is KeystrokeTypingCancelled {
                return .focusLost
            } catch {
                return .typingFailed
            }
        }.value
    }

    // MARK: - Timers

    private final class Expiry {
        var fired = false
    }

    /// Cancelled with `cancel()`; `onFire` runs only if the full duration passes.
    private func startTimer(_ duration: Duration, onFire: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { [clock] in
            do { try await clock.sleep(for: duration) } catch { return }
            onFire()
        }
    }

    /// Runs the prompt under the Accept timeout. On expiry the overlay is closed, which resolves the
    /// waiting prompt, and `timedOut` tells the caller that was why. The flow timer counts too.
    private func askUser<T>(_ prompt: () async -> T) async -> (value: T, timedOut: Bool) {
        let expiry = Expiry()
        let timer = startTimer(PasswordsUnlockTimeouts.accept) { [weak self] in
            expiry.fired = true
            self?.overlay.close()
        }
        let value = await prompt()
        timer.cancel()
        return (value, expiry.fired || requestTimedOut)
    }

    // MARK: - Answer

    private func decline(_ reason: PasswordsUnlockDeclineReason) -> PasswordsUnlockOutcome {
        log.notice("passwords unlock ignored: \(String(describing: reason), privacy: .public) (\(self.setup.setupName, privacy: .public))")
        return .declined(reason)
    }

    private func finish(_ outcome: PasswordsUnlockOutcome) -> PasswordsUnlockOutcome {
        // Only a typed password can feed Passwords' lockout counter, so only that starts the cool-down.
        // A cancel, a timeout or a face that did not match leaves the next lock free to be offered at once.
        // Passwords already seen unlocked means it took the password and there is nothing to throttle.
        if outcome == .typed || outcome == .typingFailed, !unlockedDuringFlow { lastAttemptEnd = clock.now }
        log.notice("passwords unlock ended: \(String(describing: outcome), privacy: .public)")
        return outcome
    }
}

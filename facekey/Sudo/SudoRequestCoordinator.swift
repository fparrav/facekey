//
//  SudoRequestCoordinator.swift
//  facekey
//
//  Decides one sudo approval request: gates in order, then overlay, Accept and
//  face scan. Anything but a completed approval answers `.ignore` so sudo falls
//  through to its next authentication method. Never logs app names or commands.
//

import Foundation
import os

private let log = Logger(subsystem: "com.fparrav.facekey", category: "sudo")

@MainActor
final class SudoRequestCoordinator {
    private let session: SudoSessionState
    private let setup: SudoSetupProviding
    private let overlay: SudoOverlayPresenting
    private let scanner: SudoFaceScanning
    private let policy: SudoPolicyStoring
    private let audit: SudoAuditWriting
    private let clock: SudoClock
    private let resolveIdentity: ([Int32]) -> SudoAppIdentity?
    private let storesExecutableOnly: () -> Bool
    private var isBusy = false
    /// Set by the request timer; every wait afterwards ends the request as timed out.
    private var requestTimedOut = false
    private var scanTask: Task<SudoScanResult, Never>?

    init(session: SudoSessionState,
         setup: SudoSetupProviding,
         overlay: SudoOverlayPresenting,
         scanner: SudoFaceScanning,
         policy: SudoPolicyStoring,
         audit: SudoAuditWriting,
         clock: SudoClock,
         resolveIdentity: @escaping ([Int32]) -> SudoAppIdentity?,
         storesExecutableOnly: @escaping () -> Bool) {
        self.session = session
        self.setup = setup
        self.overlay = overlay
        self.scanner = scanner
        self.policy = policy
        self.audit = audit
        self.clock = clock
        self.resolveIdentity = resolveIdentity
        self.storesExecutableOnly = storesExecutableOnly
    }

    func handle(_ request: SudoRequest) async -> SudoDecision {
        log.notice("sudo request received")
        let storedCommand = SudoCommandText.display(argv: request.argv, executableOnly: storesExecutableOnly())
        if session.isScreenLocked { return decline(.screenLocked, storedCommand) }
        if !session.isSessionUnlocked { return decline(.sessionLocked, storedCommand) }
        if !setup.isApprovalEnabled { return decline(.setupDisabled, storedCommand) }
        // A second request must not touch the state of the one in flight.
        if isBusy { return decline(.busy, storedCommand) }

        isBusy = true
        if session.isLockScreenScanArming {
            // This request never took the camera or showed the overlay, so it releases neither.
            isBusy = false
            return decline(.lockScreenScanArming, storedCommand)
        }
        session.setSudoRequestActive(true)
        requestTimedOut = false
        let requestTimer = startTimer(SudoTimeouts.request) { [weak self] in
            guard let self else { return }
            requestTimedOut = true
            overlay.close() // resolves a prompt still waiting for a click
            scanTask?.cancel()
        }
        defer {
            requestTimer.cancel()
            isBusy = false
            session.setSudoRequestActive(false)
            overlay.close()
        }

        guard let identity = resolveIdentity(request.ancestorPIDs) else {
            return decline(.unknownIdentity, storedCommand)
        }
        let context = Context(appName: identity.displayName, command: storedCommand)

        switch await resolvePolicy(for: identity, context: context) {
        case .proceed: break
        case .decline(let reason): return decline(reason, storedCommand, appName: identity.displayName)
        case .dismissed: return finish(.cancelled, context)
        case .timedOut: return finish(.timedOut, context)
        }

        let shown = SudoCommandText.display(argv: request.argv, executableOnly: false)
        let overlayRequest = SudoOverlayRequest(appName: identity.displayName, command: shown, isUnsigned: identity.kind == .unsigned)
        let clickSource: String?
        // The request timer may have fired while an earlier step ran; never open a prompt after it.
        if requestTimedOut { return finish(.timedOut, context) }
        let confirmation = await askUser { await overlay.confirm(overlayRequest) }
        if confirmation.timedOut { return finish(.timedOut, context) }
        switch confirmation.value {
        case .cancelled: return finish(.cancelled, context)
        case .timedOut: return finish(.timedOut, context)
        case .accepted(let source): clickSource = source
        }

        if requestTimedOut { return finish(.timedOut, context) }
        // Its own task so the request timer can cancel a scan that is still looking; the scanner
        // releases the camera when cancelled.
        let task = Task { await scanner.scan() }
        scanTask = task
        let scan = await task.value
        scanTask = nil
        if requestTimedOut { return finish(.timedOut, context) }
        guard scan.matched else { return finish(.notMatched, context, scan: scan, clickSource: clickSource) }
        // The screen or session may have locked during the confirmation and scan.
        if session.isScreenLocked || !session.isSessionUnlocked {
            return decline(session.isScreenLocked ? .screenLocked : .sessionLocked, storedCommand, appName: identity.displayName)
        }
        record(.approved, context, scan: scan, clickSource: clickSource)
        return .approve
    }

    // MARK: - Policy

    private enum PolicyResult {
        case proceed
        case decline(SudoDeclineReason)
        case dismissed
        case timedOut
    }

    private func resolvePolicy(for identity: SudoAppIdentity, context: Context) async -> PolicyResult {
        var entries: [String: SudoAppState]
        do {
            entries = try policy.load()
        } catch SudoPolicyStoreError.sessionLocked {
            return .decline(.sessionLocked)
        } catch {
            return .decline(.policyUnavailable)
        }
        switch SudoAppPolicy.decision(for: identity, entries: entries) {
        case .proceed:
            return .proceed
        case .decline:
            return .decline(.policyBlocked)
        case .askToAllow:
            if requestTimedOut { return .timedOut }
            let answer = await askUser { await overlay.askFirstUse(appName: identity.displayName, isUnsigned: identity.kind == .unsigned) }
            if answer.timedOut { return .timedOut }
            let choice = answer.value
            guard choice != .dismissed else { return .dismissed }
            entries[identity.key] = choice == .allow ? .allowed : .blocked
            do {
                try policy.save(entries)
            } catch {
                return .decline(.policyUnavailable)
            }
            return choice == .allow ? .proceed : .decline(.policyBlocked)
        }
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

    /// Runs a prompt under the Accept timeout. On expiry the overlay is closed, which resolves the
    /// waiting prompt, and `timedOut` tells the caller that was why. The request timer counts too.
    private func askUser<T>(_ prompt: () async -> T) async -> (value: T, timedOut: Bool) {
        let expiry = Expiry()
        let timer = startTimer(SudoTimeouts.accept) { [weak self] in
            expiry.fired = true
            self?.overlay.close()
        }
        let value = await prompt()
        timer.cancel()
        return (value, expiry.fired || requestTimedOut)
    }

    // MARK: - Answer and audit

    private struct Context {
        var appName: String
        var command: String
    }

    private func decline(_ reason: SudoDeclineReason, _ command: String, appName: String = "unknown") -> SudoDecision {
        log.notice("sudo request ignored: \(String(describing: reason), privacy: .public) (\(self.setup.setupName, privacy: .public))")
        if let outcome = reason.auditOutcome {
            record(outcome, Context(appName: appName, command: command))
        }
        return .ignore
    }

    private func finish(_ outcome: SudoAuditOutcome, _ context: Context, scan: SudoScanResult? = nil, clickSource: String? = nil) -> SudoDecision {
        log.notice("sudo request ended: \(String(describing: outcome), privacy: .public)")
        record(outcome, context, scan: scan, clickSource: clickSource)
        return .ignore
    }

    /// An audit failure never changes the answer.
    private func record(_ outcome: SudoAuditOutcome, _ context: Context, scan: SudoScanResult? = nil, clickSource: String? = nil) {
        let entry = SudoAuditEntry(
            time: clock.now,
            appName: context.appName,
            displaySetup: setup.setupName,
            outcome: outcome,
            similarity: scan?.similarity,
            liveness: scan?.liveness,
            command: context.command,
            clickSource: clickSource
        )
        try? audit.append(entry)
    }
}

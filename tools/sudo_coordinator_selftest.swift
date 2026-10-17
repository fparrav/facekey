//
//  sudo_coordinator_selftest.swift
//  facekey (tools)
//
//  Offline self-test for SudoRequestCoordinator with fakes: the gate order
//  (screen lock, session lock, setup, busy, lock-screen arming) declines
//  before any overlay or scan, an unknown identity and a stored or failing
//  policy decline early, the first-use question stores its answer, the full
//  approve path records a complete audit entry, a lock during the scan can
//  never approve, an audit failure never changes the answer, and
//  storesExecutableOnly only affects the stored command, and both time limits
//  (Accept and the whole request) end a waiting request as timed out.
//  This project has no test target, so this compiles as a standalone script against the real files:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/sudo_coordinator_selftest facekey/Sudo/SudoRequest.swift facekey/Sudo/SudoCommandText.swift facekey/Sudo/SudoAuditEntry.swift facekey/Sudo/SudoAuditLog.swift facekey/Sudo/SudoPolicyStore.swift facekey/Sudo/SudoAppPolicy.swift facekey/Sudo/SudoAppIdentity.swift facekey/Sudo/SudoCoordinatorTypes.swift facekey/Sudo/SudoTimeouts.swift facekey/Sudo/SudoRequestCoordinator.swift tools/sudo_coordinator_selftest.swift && /private/tmp/sudo_coordinator_selftest
//
//  Prints PASS/FAIL per check; exits 0 when every check passes, 1 otherwise.
//

import Foundation

var failures = 0

func check(_ cond: Bool, _ name: String) {
    if cond {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}

/// One own error type, reused by the policy and audit fakes as "some failure".
struct SelfTestError: Error {}

let identity = SudoAppIdentity(
    kind: .signed,
    identifier: "com.example.term",
    teamID: "TEAM123456",
    displayName: "Term"
)

let baseRequest = SudoRequest(
    nonce: "n1",
    ancestorPIDs: [10, 20],
    argv: ["sudo", "launchctl", "list"],
    uid: 501
)

/// Fake lock and session facts; records every setSudoRequestActive call.
@MainActor
final class FakeSession: SudoSessionState {
    var isScreenLocked = false
    var isSessionUnlocked = true
    var isLockScreenScanArming = false
    var activeHistory: [Bool] = []

    func setSudoRequestActive(_ active: Bool) {
        activeHistory.append(active)
    }
}

@MainActor
final class FakeSetup: SudoSetupProviding {
    var setupName = "built-in"
    var isApprovalEnabled = true
}

@MainActor
final class FakeOverlay: SudoOverlayPresenting {
    var firstUseCalls = 0
    var confirmCalls = 0
    var closeCalls = 0
    var lastRequest: SudoOverlayRequest?
    var firstUseAnswer: SudoFirstUseChoice = .allow
    var confirmAnswer: SudoOverlayResult = .accepted(clickSource: "pid=0 stateID=1")
    /// Gate mode: when enabled, confirm() suspends on a stored continuation
    /// until the test resumes it, so a second request can be answered while
    /// the first still waits for the user.
    var gateEnabled = false
    private var gate: CheckedContinuation<SudoOverlayResult, Never>?
    /// Same as `gateEnabled`, for the first-use question.
    var firstUseGateEnabled = false
    private var firstUseGate: CheckedContinuation<SudoFirstUseChoice, Never>?

    func askFirstUse(appName: String, isUnsigned: Bool) async -> SudoFirstUseChoice {
        firstUseCalls += 1
        guard firstUseGateEnabled else { return firstUseAnswer }
        return await withCheckedContinuation { continuation in
            firstUseGate = continuation
        }
    }

    func confirm(_ request: SudoOverlayRequest) async -> SudoOverlayResult {
        confirmCalls += 1
        lastRequest = request
        guard gateEnabled else { return confirmAnswer }
        return await withCheckedContinuation { continuation in
            gate = continuation
        }
    }

    /// Resumes the gated confirm with the given result.
    func release(_ result: SudoOverlayResult) {
        gate?.resume(returning: result)
        gate = nil
    }

    /// Like the live presenter, closing resolves any prompt still waiting.
    func close() {
        closeCalls += 1
        release(.cancelled)
        firstUseGate?.resume(returning: .dismissed)
        firstUseGate = nil
    }
}

@MainActor
final class FakeScanner: SudoFaceScanning {
    var scanCalls = 0
    var answer: SudoScanResult = SudoScanResult(matched: true, similarity: 0.9, liveness: 0.8)
    /// Runs right before the answer is returned.
    var onScan: (@MainActor () -> Void)?
    /// When enabled, scan() keeps "looking" until its task is cancelled, then reports no match.
    var scansUntilCancelled = false
    var wasCancelled = false

    func scan() async -> SudoScanResult {
        scanCalls += 1
        if scansUntilCancelled {
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000) }
            wasCancelled = true
            return SudoScanResult(matched: false, similarity: nil, liveness: nil)
        }
        onScan?()
        return answer
    }
}

final class FakePolicy: SudoPolicyStoring {
    var entries: [String: SudoAppState] = [:]
    var loadError: Error?
    var saveError: Error?
    var saveCalls = 0

    func load() throws -> [String: SudoAppState] {
        if let loadError { throw loadError }
        return entries
    }

    func save(_ newEntries: [String: SudoAppState]) throws {
        saveCalls += 1
        if let saveError { throw saveError }
        entries = newEntries
    }
}

final class FakeAudit: SudoAuditWriting {
    var entries: [SudoAuditEntry] = []
    var failAppend = false

    func append(_ entry: SudoAuditEntry) throws {
        if failAppend { throw SelfTestError() }
        entries.append(entry)
    }
}

/// Sleeps until the test fires them, so a timeout happens exactly when the case says.
@MainActor
final class FakeClock: SudoClock {
    let now = Date(timeIntervalSince1970: 1_000_000)
    private var sleepers: [UUID: (duration: Duration, continuation: CheckedContinuation<Void, Error>)] = [:]

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler(operation: { () async throws -> Void in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    sleepers[id] = (duration, continuation)
                }
            }
        }, onCancel: {
            Task { @MainActor in self.cancel(id) }
        })
    }

    private func cancel(_ id: UUID) {
        sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }

    func sleeperCount(for duration: Duration) -> Int {
        sleepers.values.filter { $0.duration == duration }.count
    }

    var pendingSleepers: Int { sleepers.count }

    /// Wakes every sleeper that asked for exactly this duration, as if that much time passed.
    func fire(_ duration: Duration) {
        for (id, sleeper) in sleepers where sleeper.duration == duration {
            sleepers.removeValue(forKey: id)
            sleeper.continuation.resume()
        }
    }
}

/// A fresh coordinator with fresh fakes for one case.
struct Rig {
    let coordinator: SudoRequestCoordinator
    let session: FakeSession
    let setup: FakeSetup
    let overlay: FakeOverlay
    let scanner: FakeScanner
    let policy: FakePolicy
    let audit: FakeAudit
    let clock: FakeClock
}

@MainActor
func make(
    resolveIdentity: (([Int32]) -> SudoAppIdentity?)? = nil,
    storesExecutableOnly: @escaping () -> Bool = { false }
) -> Rig {
    let session = FakeSession()
    let setup = FakeSetup()
    let overlay = FakeOverlay()
    let scanner = FakeScanner()
    let policy = FakePolicy()
    let audit = FakeAudit()
    let clock = FakeClock()
    let coordinator = SudoRequestCoordinator(
        session: session,
        setup: setup,
        overlay: overlay,
        scanner: scanner,
        policy: policy,
        audit: audit,
        clock: clock,
        resolveIdentity: resolveIdentity ?? { _ in identity },
        storesExecutableOnly: storesExecutableOnly
    )
    return Rig(
        coordinator: coordinator,
        session: session,
        setup: setup,
        overlay: overlay,
        scanner: scanner,
        policy: policy,
        audit: audit,
        clock: clock
    )
}

/// Yields until `condition` holds, so a case can fire a timer only once the request is waiting on it.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async {
    var spins = 0
    while !condition(), spins < 100_000 {
        await Task.yield()
        spins += 1
    }
}

@main
enum SudoCoordinatorSelfTest {
    @MainActor
    static func main() async {
        let secondRequest = SudoRequest(
            nonce: "n2",
            ancestorPIDs: [10, 20],
            argv: ["sudo", "launchctl", "list"],
            uid: 501
        )

        // MARK: - 1. A locked screen declines before any overlay or scan

        do {
            let rig = make()
            rig.session.isScreenLocked = true
            let answer = await rig.coordinator.handle(baseRequest)
            check(answer == .ignore, "a locked screen is ignored")
            check(
                rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .declinedLocked,
                "a locked screen records exactly one declinedLocked audit entry"
            )
            check(
                rig.overlay.confirmCalls == 0 && rig.scanner.scanCalls == 0,
                "a locked screen shows no overlay and runs no scan"
            )
        }

        // MARK: - 2. A locked session declines before any overlay or scan

        do {
            let rig = make()
            rig.session.isSessionUnlocked = false
            let answer = await rig.coordinator.handle(baseRequest)
            check(answer == .ignore, "a locked session is ignored")
            check(
                rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .declinedLocked,
                "a locked session records exactly one declinedLocked audit entry"
            )
            check(
                rig.overlay.confirmCalls == 0 && rig.scanner.scanCalls == 0,
                "a locked session shows no overlay and runs no scan"
            )
        }

        // MARK: - 3. A setup with approval off declines silently

        do {
            let rig = make()
            rig.setup.isApprovalEnabled = false
            let answer = await rig.coordinator.handle(baseRequest)
            check(answer == .ignore, "a disabled setup is ignored")
            check(rig.audit.entries.isEmpty, "a disabled setup records no audit entry")
            check(
                rig.overlay.confirmCalls == 0 && rig.overlay.firstUseCalls == 0 && rig.scanner.scanCalls == 0,
                "a disabled setup shows no overlay and runs no scan"
            )
        }

        // MARK: - 4. A second request is declined busy while the first waits for the user

        do {
            let rig = make()
            rig.overlay.gateEnabled = true
            let first = Task { await rig.coordinator.handle(baseRequest) }
            for _ in 0..<50 where rig.overlay.confirmCalls < 1 {
                await Task.yield()
            }
            check(rig.overlay.confirmCalls == 1, "the in-flight request reaches the confirmation")
            let secondAnswer = await rig.coordinator.handle(secondRequest)
            check(
                secondAnswer == .ignore
                    && rig.audit.entries.isEmpty
                    && rig.overlay.closeCalls == 0
                    && rig.session.activeHistory == [true],
                "a busy coordinator ignores the second request without audit, close or history change"
            )
            rig.overlay.release(.cancelled)
            let firstAnswer = await first.value
            check(
                firstAnswer == .ignore
                    && rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .cancelled
                    && rig.session.activeHistory == [true, false]
                    && rig.overlay.closeCalls == 1,
                "releasing the gate cancels the first request and settles its history"
            )
        }

        // MARK: - 5. A lock-screen scan arming refuses the camera

        do {
            let rig = make()
            rig.session.isLockScreenScanArming = true
            let answer = await rig.coordinator.handle(baseRequest)
            check(answer == .ignore, "a request while the lock-screen scan is arming is ignored")
            check(
                rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .declinedLocked,
                "an arming lock-screen scan records exactly one declinedLocked audit entry"
            )
            check(
                rig.session.activeHistory.isEmpty
                    && rig.overlay.closeCalls == 0
                    && rig.scanner.scanCalls == 0,
                "an arming lock-screen scan never sets the camera flag or closes the overlay"
            )
        }

        // MARK: - 6. An unknown requester is declined

        do {
            let rig = make(resolveIdentity: { _ in nil })
            let answer = await rig.coordinator.handle(baseRequest)
            check(answer == .ignore, "an unknown requester is ignored")
            check(
                rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .declinedUnknown,
                "an unknown requester records exactly one declinedUnknown audit entry"
            )
            check(
                rig.overlay.confirmCalls == 0 && rig.overlay.firstUseCalls == 0,
                "an unknown requester shows no overlay"
            )
        }

        // MARK: - 7. A stored blocked policy is declined

        do {
            let rig = make()
            rig.policy.entries[identity.key] = .blocked
            let answer = await rig.coordinator.handle(baseRequest)
            check(answer == .ignore, "a blocked app is ignored")
            check(
                rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .declinedPolicy,
                "a blocked app records exactly one declinedPolicy audit entry"
            )
            check(
                rig.overlay.confirmCalls == 0 && rig.overlay.firstUseCalls == 0,
                "a blocked app shows no overlay"
            )
        }

        // MARK: - 8. The first-use question

        do {
            let rig = make()
            rig.overlay.firstUseAnswer = .allow
            let answer = await rig.coordinator.handle(baseRequest)
            check(answer == .approve, "a first-use allow approves")
            check(
                rig.policy.entries[identity.key] == .allowed && rig.overlay.firstUseCalls == 1,
                "a first-use allow stores an allowed entry after one first-use question"
            )
        }

        do {
            let rig = make()
            rig.overlay.firstUseAnswer = .block
            let answer = await rig.coordinator.handle(baseRequest)
            check(
                answer == .ignore && rig.policy.entries[identity.key] == .blocked,
                "a first-use block stores a blocked entry and ignores"
            )
            check(
                rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .declinedPolicy,
                "a first-use block records exactly one declinedPolicy audit entry"
            )
        }

        do {
            let rig = make()
            rig.overlay.firstUseAnswer = .dismissed
            let answer = await rig.coordinator.handle(baseRequest)
            check(
                answer == .ignore
                    && rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .cancelled
                    && rig.policy.saveCalls == 0,
                "a first-use dismissal ignores, audits cancelled and stores nothing"
            )
        }

        // MARK: - 9. Policy store failures

        do {
            let rig = make()
            rig.policy.loadError = SudoPolicyStoreError.sessionLocked
            let answer = await rig.coordinator.handle(baseRequest)
            check(
                answer == .ignore
                    && rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .declinedLocked,
                "a session-locked policy store ignores and audits declinedLocked"
            )
        }

        do {
            let rig = make()
            rig.policy.loadError = SelfTestError()
            let answer = await rig.coordinator.handle(baseRequest)
            check(
                answer == .ignore
                    && rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .declinedPolicy,
                "any other policy load failure ignores and audits declinedPolicy"
            )
        }

        do {
            let rig = make()
            rig.overlay.firstUseAnswer = .allow
            rig.policy.saveError = SelfTestError()
            let answer = await rig.coordinator.handle(baseRequest)
            check(
                answer == .ignore
                    && rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .declinedPolicy
                    && rig.policy.entries[identity.key] == nil,
                "a first-use save failure ignores, audits declinedPolicy and stores nothing"
            )
        }

        // MARK: - 10. Confirmation outcomes

        do {
            let rig = make()
            rig.policy.entries[identity.key] = .allowed
            rig.overlay.confirmAnswer = .cancelled
            let answer = await rig.coordinator.handle(baseRequest)
            check(
                answer == .ignore
                    && rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .cancelled
                    && rig.scanner.scanCalls == 0,
                "a cancelled confirmation ignores, audits cancelled and runs no scan"
            )
        }

        do {
            let rig = make()
            rig.policy.entries[identity.key] = .allowed
            rig.overlay.confirmAnswer = .timedOut
            let answer = await rig.coordinator.handle(baseRequest)
            check(
                answer == .ignore
                    && rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .timedOut
                    && rig.scanner.scanCalls == 0,
                "a timed-out confirmation ignores, audits timedOut and runs no scan"
            )
        }

        // MARK: - 11. An accepted confirmation with no face match

        do {
            let rig = make()
            rig.policy.entries[identity.key] = .allowed
            rig.scanner.answer = SudoScanResult(matched: false, similarity: 0.3, liveness: 0.8)
            let answer = await rig.coordinator.handle(baseRequest)
            check(
                answer == .ignore
                    && rig.audit.entries.count == 1
                    && rig.audit.entries[0].outcome == .notMatched
                    && rig.audit.entries[0].similarity == 0.3
                    && rig.audit.entries[0].clickSource == "pid=0 stateID=1",
                "a no-match scan ignores and audits notMatched with the similarity and click source"
            )
        }

        // MARK: - 12. The full approve path

        do {
            let rig = make()
            rig.policy.entries[identity.key] = .allowed
            let answer = await rig.coordinator.handle(baseRequest)
            let entry = rig.audit.entries.first
            check(answer == .approve, "an allowed app approves")
            check(
                entry?.outcome == .approved
                    && entry?.appName == "Term"
                    && entry?.displaySetup == "built-in"
                    && entry?.command == "sudo launchctl list"
                    && entry?.similarity == 0.9
                    && entry?.liveness == 0.8
                    && entry?.clickSource == "pid=0 stateID=1",
                "the approval audit entry carries the app, setup, command, scan and click source"
            )
            check(
                rig.session.activeHistory == [true, false]
                    && rig.overlay.closeCalls == 1
                    && rig.scanner.scanCalls == 1
                    && rig.policy.saveCalls == 0,
                "the approval path releases the camera flag, closes the overlay, scans once and saves nothing"
            )
        }

        // MARK: - 13. The screen locks during the scan

        do {
            let rig = make()
            rig.policy.entries[identity.key] = .allowed
            rig.scanner.onScan = { rig.session.isScreenLocked = true }
            let answer = await rig.coordinator.handle(baseRequest)
            check(
                answer == .ignore
                    && rig.audit.entries.count == 1
                    && rig.audit.entries[0].outcome == .declinedLocked,
                "a screen that locks during the scan ignores and audits declinedLocked, never approved"
            )
        }

        // MARK: - 14. An audit failure never changes the answer

        do {
            let rig = make()
            rig.policy.entries[identity.key] = .allowed
            rig.audit.failAppend = true
            let answer = await rig.coordinator.handle(baseRequest)
            check(answer == .approve, "a failing audit still approves")
        }

        // MARK: - 15. storesExecutableOnly

        do {
            let rig = make(storesExecutableOnly: { true })
            rig.policy.entries[identity.key] = .allowed
            let answer = await rig.coordinator.handle(baseRequest)
            check(
                answer == .approve
                    && rig.audit.entries[0].command == "sudo"
                    && rig.overlay.lastRequest?.command == "sudo launchctl list",
                "storesExecutableOnly stores only the executable but keeps the full text in the overlay"
            )
        }

        // MARK: - 16. Time limits

        do {
            // Accept timeout while the confirmation waits for a click.
            let rig = make()
            rig.policy.entries[identity.key] = .allowed
            rig.overlay.gateEnabled = true
            let request = Task { await rig.coordinator.handle(baseRequest) }
            await waitUntil { rig.overlay.confirmCalls == 1 && rig.clock.sleeperCount(for: SudoTimeouts.accept) == 1 }
            rig.clock.fire(SudoTimeouts.accept)
            let answer = await request.value
            check(
                answer == .ignore
                    && rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .timedOut
                    && rig.scanner.scanCalls == 0 && rig.overlay.closeCalls >= 1
                    && rig.session.activeHistory == [true, false],
                "the Accept timeout closes the overlay, ignores and audits timedOut without scanning"
            )
            check(rig.clock.pendingSleepers == 0, "no timer outlives a request that timed out on Accept")
        }

        do {
            // Accept timeout while the first-use question waits.
            let rig = make()
            rig.overlay.firstUseGateEnabled = true
            let request = Task { await rig.coordinator.handle(baseRequest) }
            await waitUntil { rig.overlay.firstUseCalls == 1 && rig.clock.sleeperCount(for: SudoTimeouts.accept) == 1 }
            rig.clock.fire(SudoTimeouts.accept)
            let answer = await request.value
            check(
                answer == .ignore
                    && rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .timedOut
                    && rig.policy.saveCalls == 0 && rig.overlay.confirmCalls == 0,
                "a first-use question that times out stores nothing, ignores and audits timedOut"
            )
        }

        do {
            // Request time limit while the confirmation waits for a click.
            let rig = make()
            rig.policy.entries[identity.key] = .allowed
            rig.overlay.gateEnabled = true
            let request = Task { await rig.coordinator.handle(baseRequest) }
            await waitUntil { rig.overlay.confirmCalls == 1 && rig.clock.sleeperCount(for: SudoTimeouts.request) == 1 }
            rig.clock.fire(SudoTimeouts.request)
            let answer = await request.value
            check(
                answer == .ignore
                    && rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .timedOut
                    && rig.scanner.scanCalls == 0,
                "the request time limit also ends a request waiting for a click as timedOut"
            )
        }

        do {
            // Request time limit during the face scan: the scan is cancelled and cannot approve.
            let rig = make()
            rig.policy.entries[identity.key] = .allowed
            rig.scanner.scansUntilCancelled = true
            let request = Task { await rig.coordinator.handle(baseRequest) }
            await waitUntil { rig.scanner.scanCalls == 1 && rig.clock.sleeperCount(for: SudoTimeouts.request) == 1 }
            rig.clock.fire(SudoTimeouts.request)
            let answer = await request.value
            check(
                answer == .ignore
                    && rig.audit.entries.count == 1 && rig.audit.entries[0].outcome == .timedOut
                    && rig.scanner.wasCancelled,
                "the request time limit cancels a running scan, ignores and audits timedOut"
            )
            check(
                rig.session.activeHistory == [true, false] && rig.overlay.closeCalls >= 1 && rig.clock.pendingSleepers == 0,
                "a scan timeout releases the camera flag, closes the overlay and leaves no timer behind"
            )
        }

        do {
            // A request that finishes in time leaves no timer behind and is unaffected by them.
            let rig = make()
            rig.policy.entries[identity.key] = .allowed
            let answer = await rig.coordinator.handle(baseRequest)
            // Cancelling a timer reaches the fake clock one hop later.
            await waitUntil { rig.clock.pendingSleepers == 0 }
            check(
                answer == .approve && rig.clock.pendingSleepers == 0,
                "an approval inside both limits leaves no timer behind"
            )
        }

        if failures == 0 {
            print("All sudo coordinator self-tests passed.")
        } else {
            print("\(failures) sudo coordinator check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

//
//  passwords_unlock_coordinator_selftest.swift
//  facekey (tools)
//
//  Offline self-test for PasswordsUnlockCoordinator with fakes: every gate (setup off, screen lock,
//  session lock, Accessibility, camera busy, a flow already running) declines with no overlay, scan
//  or password read; Cancel, the Accept timeout and a non-matching or non-live scan type nothing;
//  focus lost during the confirmation, during the scan or while typing stops before the password is
//  read or between batches; the password buffer is wiped on every exit path; and a lock gets one
//  attempt, with a cool-down before the next.
//  This project has no test target, so this compiles as a standalone script against the real files:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/passwords_unlock_coordinator_selftest facekey/Sudo/SudoRequest.swift facekey/Sudo/SudoCommandText.swift facekey/Sudo/SudoAuditEntry.swift facekey/Sudo/SudoAuditLog.swift facekey/Sudo/SudoPolicyStore.swift facekey/Sudo/SudoAppPolicy.swift facekey/Sudo/SudoAppIdentity.swift facekey/Sudo/SudoCoordinatorTypes.swift facekey/Sudo/SudoTimeouts.swift facekey/PasswordsUnlock/PasswordsLockWatching.swift facekey/PasswordsUnlock/PasswordsUnlockTypes.swift facekey/PasswordsUnlock/PasswordsUnlockCoordinator.swift tools/passwords_unlock_coordinator_selftest.swift && /private/tmp/passwords_unlock_coordinator_selftest
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

struct SelfTestError: Error {}

/// A throwaway value; never a real password.
let testPassword = "hunter2-test"

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
final class FakeSetup: PasswordsUnlockSetupProviding {
    var setupName = "built-in"
    var isUnlockEnabled = true
}

@MainActor
final class FakeOverlay: PasswordsUnlockOverlayPresenting {
    var confirmCalls = 0
    var closeCalls = 0
    var confirmAnswer: SudoOverlayResult = .accepted(clickSource: "pid=0 stateID=1")
    /// When enabled, confirm() suspends until the test resumes it or close() resolves it as cancelled.
    var gateEnabled = false
    private var gate: CheckedContinuation<SudoOverlayResult, Never>?

    func confirm() async -> SudoOverlayResult {
        confirmCalls += 1
        guard gateEnabled else { return confirmAnswer }
        return await withCheckedContinuation { continuation in
            gate = continuation
        }
    }

    func release(_ result: SudoOverlayResult) {
        gate?.resume(returning: result)
        gate = nil
    }

    func close() {
        closeCalls += 1
        release(.cancelled)
    }
}

@MainActor
final class FakeScanner: SudoFaceScanning {
    var scanCalls = 0
    var answer = SudoScanResult(matched: true, similarity: 0.9, liveness: 0.8)
    var onScan: (@MainActor () -> Void)?

    func scan() async -> SudoScanResult {
        scanCalls += 1
        onScan?()
        return answer
    }
}

final class FakeFocus: PasswordsFocusChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var locked = true
    private var trusted = true
    private var checks = 0
    private var choice = false
    private var presses = 0
    private var pressSucceeds = true
    private var fieldAppears = true

    /// Touch ID / Apple Watch is offered with a "use password" button and no field yet.
    var atChoice: Bool {
        get { lock.withLock { choice } }
        set { lock.withLock { choice = newValue } }
    }
    var pressCalls: Int { lock.withLock { presses } }
    var pressWorks: Bool {
        get { lock.withLock { pressSucceeds } }
        set { lock.withLock { pressSucceeds = newValue } }
    }
    /// Whether pressing the button makes the field take focus.
    var fieldAppearsOnPress: Bool {
        get { lock.withLock { fieldAppears } }
        set { lock.withLock { fieldAppears = newValue } }
    }

    var isAccessibilityTrusted: Bool {
        get { lock.withLock { trusted } }
        set { lock.withLock { trusted = newValue } }
    }

    var lockedAndFocused: Bool {
        get { lock.withLock { locked } }
        set { lock.withLock { locked = newValue } }
    }

    var checkCount: Int { lock.withLock { checks } }

    func isPasswordsLockedAndFocused() -> Bool {
        lock.withLock {
            checks += 1
            return locked
        }
    }

    func isPasswordsAtUsePasswordChoice() -> Bool {
        lock.withLock { choice && !locked }
    }

    func pressUsePassword() -> Bool {
        lock.withLock {
            presses += 1
            guard pressSucceeds, choice else { return false }
            if fieldAppears { choice = false; locked = true }
            return true
        }
    }
}

final class FakeCredentials: PasswordsCredentialReading, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    private var secrets: [SecretBytes] = []
    var failure: Error?

    var readCalls: Int { lock.withLock { reads } }
    var lastSecret: SecretBytes? { lock.withLock { secrets.last } }

    func readPassword() throws -> SecretBytes {
        try lock.withLock {
            reads += 1
            if let failure { throw failure }
            let secret = SecretBytes(copying: Data(testPassword.utf8))
            secrets.append(secret)
            return secret
        }
    }
}

final class FakeTyper: KeystrokeTyping, @unchecked Sendable {
    private let lock = NSLock()
    private var batches = 0
    private var calls = 0
    private var seen: Data?
    /// How many batches a full typing takes.
    let totalBatches = 4
    var failure: Error?
    /// Runs after each posted batch, to move focus mid-typing.
    var afterBatch: (@Sendable (Int) -> Void)?

    var typeCalls: Int { lock.withLock { calls } }
    var postedBatches: Int { lock.withLock { batches } }
    var typedBytes: Data? { lock.withLock { seen } }

    func typeAndReturn(_ password: SecretBytes, shouldContinue: @Sendable () -> Bool) throws {
        lock.withLock {
            calls += 1
            seen = password.makeData()
        }
        if let failure { throw failure }
        for index in 0..<totalBatches {
            guard shouldContinue() else { throw KeystrokeTypingCancelled() }
            lock.withLock { batches += 1 }
            afterBatch?(index)
        }
        guard shouldContinue() else { throw KeystrokeTypingCancelled() }
    }
}

/// Sleeps until the test fires them, so a timeout happens exactly when the case says.
@MainActor
final class FakeClock: SudoClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
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

    func fire(_ duration: Duration) {
        for (id, sleeper) in sleepers where sleeper.duration == duration {
            sleepers.removeValue(forKey: id)
            sleeper.continuation.resume()
        }
    }
}

struct Rig {
    let coordinator: PasswordsUnlockCoordinator
    let session: FakeSession
    let setup: FakeSetup
    let overlay: FakeOverlay
    let scanner: FakeScanner
    let focus: FakeFocus
    let credentials: FakeCredentials
    let typer: FakeTyper
    let clock: FakeClock
}

@MainActor
func make() -> Rig {
    let session = FakeSession()
    let setup = FakeSetup()
    let overlay = FakeOverlay()
    let scanner = FakeScanner()
    let focus = FakeFocus()
    let credentials = FakeCredentials()
    let typer = FakeTyper()
    let clock = FakeClock()
    let coordinator = PasswordsUnlockCoordinator(
        session: session,
        setup: setup,
        overlay: overlay,
        scanner: scanner,
        focus: focus,
        credentials: credentials,
        typer: typer,
        clock: clock
    )
    return Rig(coordinator: coordinator, session: session, setup: setup, overlay: overlay, scanner: scanner,
               focus: focus, credentials: credentials, typer: typer, clock: clock)
}

/// Yields until `condition` holds, so a case can act only once the flow is waiting on something.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async {
    var spins = 0
    while !condition(), spins < 100_000 {
        await Task.yield()
        spins += 1
    }
}

/// Nothing was shown, scanned, read or typed.
@MainActor
func untouched(_ rig: Rig) -> Bool {
    rig.overlay.confirmCalls == 0 && rig.scanner.scanCalls == 0 && rig.credentials.readCalls == 0 && rig.typer.typeCalls == 0
}

@MainActor
func expectDecline(_ name: String, _ reason: PasswordsUnlockDeclineReason, configure: (Rig) -> Void) async {
    let rig = make()
    configure(rig)
    let outcome = await rig.coordinator.lockStateChanged(.locked)
    check(outcome == .declined(reason), "\(name) declines as \(reason)")
    check(untouched(rig), "\(name) shows no overlay, scans nothing, reads nothing and types nothing")
    check(rig.session.activeHistory.isEmpty, "\(name) never takes the camera")
}

@main
enum PasswordsUnlockCoordinatorSelfTest {
    @MainActor
    static func main() async {
        // MARK: Gates

        await expectDecline("setup off", .setupDisabled) { $0.setup.isUnlockEnabled = false }
        await expectDecline("screen locked", .screenLocked) { $0.session.isScreenLocked = true }
        await expectDecline("session locked", .sessionLocked) { $0.session.isSessionUnlocked = false }
        await expectDecline("Accessibility missing", .accessibilityMissing) { $0.focus.isAccessibilityTrusted = false }
        await expectDecline("camera busy", .cameraBusy) { $0.session.isLockScreenScanArming = true }

        do {
            let rig = make()
            check(await rig.coordinator.lockStateChanged(.unlocked) == nil, "an unlocked state starts nothing")
            check(await rig.coordinator.lockStateChanged(.unknown) == nil, "an unknown state starts nothing")
            check(untouched(rig), "non-locked states touch nothing")
        }

        do {
            let rig = make()
            rig.overlay.gateEnabled = true
            let first = Task { await rig.coordinator.lockStateChanged(.locked) }
            await waitUntil { rig.overlay.confirmCalls == 1 }
            let second = await rig.coordinator.lockStateChanged(.locked)
            check(second == .declined(.busy), "a second lock event during a flow declines as busy")
            check(rig.overlay.confirmCalls == 1, "the busy decline opens no second overlay")
            rig.overlay.release(.cancelled)
            check(await first.value == .cancelled, "the first flow still ends on its own answer")
        }

        // MARK: Happy path

        do {
            let rig = make()
            let outcome = await rig.coordinator.lockStateChanged(.locked)
            check(outcome == .typed, "Accept then match then focus types the password")
            check(rig.typer.typedBytes == Data(testPassword.utf8), "the typed bytes are the stored password")
            check(rig.typer.postedBatches == rig.typer.totalBatches, "every batch was posted")
            check(rig.credentials.lastSecret?.isWiped == true, "the password buffer is wiped after typing")
            check(rig.session.activeHistory == [true, false], "the camera is taken for the flow and released")
            check(rig.overlay.confirmCalls == 1 && rig.scanner.scanCalls == 1, "one confirmation and one scan")
        }

        // MARK: Cancel, timeout, no match

        do {
            let rig = make()
            rig.overlay.confirmAnswer = .cancelled
            check(await rig.coordinator.lockStateChanged(.locked) == .cancelled, "Cancel ends the flow")
            check(rig.scanner.scanCalls == 0 && rig.credentials.readCalls == 0 && rig.typer.typeCalls == 0, "Cancel scans, reads and types nothing")
        }

        do {
            let rig = make()
            rig.overlay.gateEnabled = true
            let flow = Task { await rig.coordinator.lockStateChanged(.locked) }
            await waitUntil { rig.clock.sleeperCount(for: PasswordsUnlockTimeouts.accept) >= 1 }
            rig.clock.fire(PasswordsUnlockTimeouts.accept)
            check(await flow.value == .timedOut, "an unanswered Accept ends as timed out")
            check(rig.scanner.scanCalls == 0 && rig.credentials.readCalls == 0 && rig.typer.typeCalls == 0, "the timeout scans, reads and types nothing")
            check(rig.overlay.closeCalls >= 1, "the timeout closes the overlay")
        }

        do {
            let rig = make()
            rig.scanner.answer = SudoScanResult(matched: false, similarity: 0.2, liveness: 0.8)
            check(await rig.coordinator.lockStateChanged(.locked) == .notMatched, "no match ends the flow")
            check(rig.credentials.readCalls == 0 && rig.typer.typeCalls == 0, "no match reads and types nothing")
        }

        do {
            let rig = make()
            rig.scanner.answer = SudoScanResult(matched: false, similarity: 0.9, liveness: 0)
            check(await rig.coordinator.lockStateChanged(.locked) == .notMatched, "a liveness denial ends the flow")
            check(rig.credentials.readCalls == 0 && rig.typer.typeCalls == 0, "a liveness denial reads and types nothing")
        }

        // MARK: Focus

        do {
            let rig = make()
            rig.overlay.gateEnabled = true
            let flow = Task { await rig.coordinator.lockStateChanged(.locked) }
            await waitUntil { rig.overlay.confirmCalls == 1 }
            check(await rig.coordinator.lockStateChanged(.unknown) == nil, "leaving Passwords during the confirmation is only bookkeeping")
            check(await flow.value == .focusLost, "leaving Passwords during the confirmation ends the flow")
            check(rig.scanner.scanCalls == 0 && rig.credentials.readCalls == 0, "no scan and no read after leaving during the confirmation")
        }

        do {
            let rig = make()
            rig.scanner.onScan = { rig.focus.lockedAndFocused = false }
            check(await rig.coordinator.lockStateChanged(.locked) == .focusLost, "focus moving during the scan ends the flow")
            check(rig.credentials.readCalls == 0, "the password was not read when focus moved before reading")
            check(rig.typer.typeCalls == 0, "nothing was typed when focus moved before reading")
        }

        do {
            let rig = make()
            rig.typer.afterBatch = { index in if index == 1 { rig.focus.lockedAndFocused = false } }
            check(await rig.coordinator.lockStateChanged(.locked) == .focusLost, "focus moving while typing ends the flow")
            check(rig.typer.postedBatches == 2, "no batch is posted after focus left")
            check(rig.credentials.lastSecret?.isWiped == true, "the buffer is wiped when typing is cut short")
        }

        // MARK: Touch ID / Apple Watch screen

        do {
            let rig = make()
            rig.focus.lockedAndFocused = false
            rig.focus.atChoice = true
            check(await rig.coordinator.lockStateChanged(.lockedChoice) == .typed, "the choice screen runs the flow and types once the field is up")
            check(rig.focus.pressCalls == 1, "the use-password button is pressed once")
            check(rig.credentials.readCalls == 1 && rig.typer.typeCalls == 1, "the password is read and typed after the button")
            check(rig.credentials.lastSecret?.isWiped == true, "the buffer is wiped after typing from the choice screen")
        }

        do {
            let rig = make()
            rig.scanner.answer = SudoScanResult(matched: false, similarity: 0.1, liveness: 1)
            rig.focus.lockedAndFocused = false
            rig.focus.atChoice = true
            check(await rig.coordinator.lockStateChanged(.lockedChoice) == .notMatched, "a wrong face on the choice screen ends the flow")
            check(rig.focus.pressCalls == 0, "the button is not pressed without a face match")
        }

        do {
            let rig = make()
            rig.focus.lockedAndFocused = false
            rig.focus.atChoice = true
            rig.focus.pressWorks = false
            check(await rig.coordinator.lockStateChanged(.lockedChoice) == .focusLost, "a button that cannot be pressed ends the flow")
            check(rig.credentials.readCalls == 0 && rig.typer.typeCalls == 0, "nothing is read or typed when the button fails")
        }

        do {
            let rig = make()
            rig.focus.lockedAndFocused = false
            rig.focus.atChoice = true
            rig.focus.fieldAppearsOnPress = false
            check(await rig.coordinator.lockStateChanged(.lockedChoice) == .focusLost, "a field that never appears ends the flow")
            check(rig.credentials.readCalls == 0 && rig.typer.typeCalls == 0, "nothing is read or typed when the field never appears")
        }

        do {
            let rig = make()
            rig.focus.lockedAndFocused = false
            check(await rig.coordinator.lockStateChanged(.lockedChoice) == .focusLost, "neither field nor button at the end ends the flow")
            check(rig.focus.pressCalls == 0, "nothing is pressed when the button is not there")
        }

        do {
            let rig = make()
            rig.focus.lockedAndFocused = false
            rig.focus.atChoice = true
            check(await rig.coordinator.lockStateChanged(.lockedChoice) == .typed, "the choice screen is one attempt")
            check(await rig.coordinator.lockStateChanged(.locked) == .declined(.alreadyTried), "the field appearing afterwards is the same lock, not a new attempt")
        }

        do {
            let rig = make()
            rig.scanner.onScan = { rig.session.isScreenLocked = true }
            check(await rig.coordinator.lockStateChanged(.locked) == .declined(.screenLocked), "a screen lock during the scan declines")
            check(rig.credentials.readCalls == 0 && rig.typer.typeCalls == 0, "a screen lock during the scan reads and types nothing")
        }

        // MARK: Failures wipe the buffer

        do {
            let rig = make()
            rig.credentials.failure = SelfTestError()
            check(await rig.coordinator.lockStateChanged(.locked) == .credentialUnavailable, "a missing password ends the flow")
            check(rig.typer.typeCalls == 0, "a missing password types nothing")
        }

        do {
            let rig = make()
            rig.typer.failure = SelfTestError()
            check(await rig.coordinator.lockStateChanged(.locked) == .typingFailed, "a typing failure ends the flow")
            check(rig.credentials.lastSecret?.isWiped == true, "the buffer is wiped after a typing failure")
        }

        do {
            let secret = SecretBytes(copying: Data(testPassword.utf8))
            check(secret.makeData() == Data(testPassword.utf8), "a secret returns its bytes before the wipe")
            secret.wipe()
            check(secret.isWiped && secret.makeData().isEmpty, "a wiped secret returns nothing")
            secret.wipe()
            check(secret.isWiped, "wiping twice is safe")
        }

        // MARK: One attempt per lock, cool-down

        do {
            let rig = make()
            check(await rig.coordinator.lockStateChanged(.locked) == .typed, "the first lock is attempted")
            check(await rig.coordinator.lockStateChanged(.locked) == .declined(.alreadyTried), "the same lock is not retried")
            check(rig.credentials.readCalls == 1 && rig.typer.typeCalls == 1, "no second read or typing for the same lock")

            _ = await rig.coordinator.lockStateChanged(.unknown)
            check(await rig.coordinator.lockStateChanged(.locked) == .declined(.coolingDown), "a lock seen again inside the cool-down after typing is refused")

            rig.clock.now = rig.clock.now.addingTimeInterval(PasswordsUnlockTimeouts.cooldown + 1)
            _ = await rig.coordinator.lockStateChanged(.unknown)
            check(await rig.coordinator.lockStateChanged(.locked) == .typed, "a lock seen again after the cool-down is attempted")
            check(rig.credentials.readCalls == 2, "the second attempt reads the password once")
        }

        do {
            let rig = make()
            rig.overlay.confirmAnswer = .cancelled
            _ = await rig.coordinator.lockStateChanged(.locked)
            check(await rig.coordinator.lockStateChanged(.locked) == .declined(.alreadyTried), "a cancelled lock is not offered again until it is seen again")
            check(rig.overlay.confirmCalls == 1, "a cancelled lock opens the overlay once")
        }

        do {
            let rig = make()
            check(await rig.coordinator.lockStateChanged(.locked) == .typed, "the first lock types")
            _ = await rig.coordinator.lockStateChanged(.unlocked)
            _ = await rig.coordinator.lockStateChanged(.unknown)
            check(await rig.coordinator.lockStateChanged(.locked) == .typed, "after Passwords unlocked, locking it again is offered at once")
            check(rig.credentials.readCalls == 2, "each accepted unlock reads the password once")
        }

        do {
            let rig = make()
            check(await rig.coordinator.lockStateChanged(.locked) == .typed, "a typed password that is rejected")
            _ = await rig.coordinator.lockStateChanged(.unknown)
            check(await rig.coordinator.lockStateChanged(.locked) == .declined(.coolingDown), "stays under the cool-down when Passwords never unlocked")
        }

        do {
            let rig = make()
            rig.overlay.confirmAnswer = .cancelled
            check(await rig.coordinator.lockStateChanged(.locked) == .cancelled, "the first overlay is cancelled")
            _ = await rig.coordinator.lockStateChanged(.unknown)
            rig.overlay.confirmAnswer = .accepted(clickSource: "pid=0 stateID=1")
            check(await rig.coordinator.lockStateChanged(.locked) == .typed, "after a cancel, leaving and coming back offers the overlay at once, with no cool-down")
        }

        do {
            let rig = make()
            rig.scanner.answer = SudoScanResult(matched: false, similarity: 0.1, liveness: 1)
            check(await rig.coordinator.lockStateChanged(.locked) == .notMatched, "a face that does not match ends the flow")
            _ = await rig.coordinator.lockStateChanged(.unknown)
            rig.scanner.answer = SudoScanResult(matched: true, similarity: 0.9, liveness: 1)
            check(await rig.coordinator.lockStateChanged(.locked) == .typed, "after a non-match, leaving and coming back is offered at once, with no cool-down")
        }

        if failures == 0 {
            print("All passwords unlock coordinator self-tests passed.")
            exit(0)
        } else {
            print("\(failures) check(s) failed.")
            exit(1)
        }
    }
}

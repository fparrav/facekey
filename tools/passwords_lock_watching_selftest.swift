//
//  passwords_lock_watching_selftest.swift
//  facekey (tools)
//
//  Offline self-test for the Passwords lock-watching seam: the classifier maps fake
//  accessibility snapshots to locked, unlocked and unknown exactly as the spike
//  requires, and the tracker emits only on state changes (nothing for a first
//  unknown read).
//  This project has no test target, so this compiles as a standalone script against the real files:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/passwords_lock_watching_selftest facekey/PasswordsUnlock/PasswordsLockWatching.swift tools/passwords_lock_watching_selftest.swift && /private/tmp/passwords_lock_watching_selftest
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

/// A `PasswordsAXReading` whose snapshot the test sets directly.
/// A class, so the tracker's copy of the existential sees the test's mutations.
final class FakeAXReader: PasswordsAXReading {
    var state: PasswordsAXState?

    init(state: PasswordsAXState?) {
        self.state = state
    }

    func read() -> PasswordsAXState? {
        state
    }
}

func axState(frontmost: Bool = true, windows: Int = 1, focused: String? = nil, splitGroup: Bool = false, useButton: Bool = false) -> PasswordsAXState {
    PasswordsAXState(isFrontmost: frontmost, windowCount: windows, focusedSubrole: focused, hasSplitGroup: splitGroup, hasUsePasswordButton: useButton)
}

@main
enum PasswordsLockWatchingSelfTest {
    static func main() {
        // MARK: - 1. The classifier

        check(
            PasswordsLockClassifier.state(for: axState(focused: "AXSecureTextField")) == .locked,
            "frontmost + focused secure field + no split group is locked"
        )
        check(
            PasswordsLockClassifier.state(for: axState(focused: "AXSearchField", splitGroup: true)) == .unlocked,
            "frontmost + split group + search-field focus is unlocked"
        )
        check(
            PasswordsLockClassifier.state(for: axState(focused: nil, splitGroup: true)) == .unlocked,
            "frontmost + split group + focus elsewhere is unlocked"
        )
        check(
            PasswordsLockClassifier.state(for: axState(useButton: true)) == .lockedChoice,
            "frontmost + one plain button + no field + no split group is the Touch ID / Apple Watch choice"
        )
        check(
            PasswordsLockClassifier.state(for: axState(focused: "AXSecureTextField", useButton: true)) == .locked,
            "a focused secure field wins over a leftover button"
        )
        check(
            PasswordsLockClassifier.state(for: axState(focused: "AXSearchField", splitGroup: true, useButton: true)) == .unlocked,
            "a split group is unlocked even with a button"
        )
        check(
            PasswordsLockClassifier.state(for: axState(frontmost: false, useButton: true)) == .unknown,
            "the choice screen in the background is unknown"
        )
        check(
            PasswordsLockClassifier.state(for: axState(windows: 0, useButton: true)) == .unknown,
            "the choice screen without a window is unknown"
        )
        check(
            PasswordsLockClassifier.state(for: axState()) == .unknown,
            "no field, no split group and no button is unknown"
        )
        check(
            PasswordsLockClassifier.state(for: axState(frontmost: false, focused: "AXSecureTextField")) == .unknown,
            "not frontmost with a secure-field focus is unknown"
        )
        check(
            PasswordsLockClassifier.state(for: axState(frontmost: false, focused: "AXSearchField", splitGroup: true)) == .unknown,
            "not frontmost with a split group is unknown"
        )
        check(
            PasswordsLockClassifier.state(for: axState(windows: 0, focused: "AXSecureTextField")) == .unknown,
            "no window is unknown"
        )
        check(
            PasswordsLockClassifier.state(for: axState(windows: 0, splitGroup: true)) == .unknown,
            "no window with a split group is unknown"
        )
        check(
            PasswordsLockClassifier.state(for: axState(focused: "AXSecureTextField", splitGroup: true)) == .unknown,
            "a secure field inside a split group is ambiguous, so unknown"
        )
        check(
            PasswordsLockClassifier.state(for: nil) == .unknown,
            "an unreadable app is unknown"
        )

        // MARK: - 2. The tracker emits only on state changes

        let reader = FakeAXReader(state: nil)
        var events: [PasswordsLockState] = []
        let tracker = PasswordsLockTracker(reader: reader) { events.append($0) }

        reader.state = axState(focused: "AXSecureTextField") // locked
        tracker.refresh()
        reader.state = axState(focused: "AXSecureTextField") // locked again
        tracker.refresh()
        check(events == [.locked], "locked then locked again emits once")

        reader.state = axState(focused: "AXSearchField", splitGroup: true) // unlocked
        tracker.refresh()
        check(events == [.locked, .unlocked], "then unlocked emits")

        reader.state = axState(frontmost: false, focused: "AXSecureTextField") // not frontmost
        tracker.refresh()
        check(events == [.locked, .unlocked, .unknown], "then not frontmost emits unknown")

        // MARK: - 3. The tracker is quiet when the first read is unknown

        let quietReader = FakeAXReader(state: nil)
        var quietEvents: [PasswordsLockState] = []
        let quietTracker = PasswordsLockTracker(reader: quietReader) { quietEvents.append($0) }
        quietTracker.refresh()
        check(quietEvents.isEmpty, "the tracker emits nothing when the first read is unknown")

        // MARK: - 4. One stray unknown does not end a lock

        do {
            let r = FakeAXReader(state: axState(focused: "AXSecureTextField"))
            var ev: [PasswordsLockState] = []
            let t = PasswordsLockTracker(reader: r) { ev.append($0) }
            t.refresh()
            r.state = axState(focused: nil) // between the choice screen and the field
            t.refresh()
            check(ev == [.locked], "one unknown read right after a lock is held back")
            r.state = axState(focused: "AXSecureTextField")
            t.refresh()
            check(ev == [.locked], "the lock coming back after one unknown emits nothing")
            r.state = axState(focused: nil)
            t.refresh()
            t.refresh()
            check(ev == [.locked, .unknown], "two unknown reads in a row end the lock")
        }

        do {
            let r = FakeAXReader(state: axState(useButton: true))
            var ev: [PasswordsLockState] = []
            let t = PasswordsLockTracker(reader: r) { ev.append($0) }
            t.refresh()
            r.state = axState(frontmost: false, useButton: true)
            t.refresh(force: true)
            check(ev == [.lockedChoice, .unknown], "leaving the front ends the lock at once")
        }

        do {
            let r = FakeAXReader(state: axState(useButton: true))
            var ev: [PasswordsLockState] = []
            let t = PasswordsLockTracker(reader: r) { ev.append($0) }
            t.refresh()
            r.state = axState(focused: "AXSecureTextField")
            t.refresh()
            check(ev == [.lockedChoice, .locked], "the choice screen turning into the field is reported")
            r.state = axState(focused: "AXSearchField", splitGroup: true)
            t.refresh()
            check(ev == [.lockedChoice, .locked, .unlocked], "unlocking is reported at once")
        }

        if failures == 0 {
            print("All passwords lock-watching self-tests passed.")
        } else {
            print("\(failures) passwords lock-watching check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

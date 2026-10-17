//
//  sudo_policy_selftest.swift
//  facekey (tools)
//
//  Offline self-test for SudoAppPolicy: an allowed entry proceeds, a blocked
//  entry declines, no entry asks the user, and a copy signed differently (other
//  team id, other identifier, other cdhash) never inherits a stored entry.
//  This project has no test target, so this compiles as a standalone script against the real files:
//
//      /usr/bin/swiftc -O -parse-as-library -o /tmp/sudo_policy_selftest facekey/Sudo/SudoAppIdentity.swift facekey/Sudo/SudoAppPolicy.swift tools/sudo_policy_selftest.swift && /tmp/sudo_policy_selftest
//
//  Prints PASS/FAIL per check; exits 0 when every check passes, 1 otherwise.
//

import AppKit
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

@main
enum SudoPolicySelfTest {
    static func main() {
        // MARK: - 1. Signed app with an allowed entry proceeds

        let signed = SudoAppIdentity(kind: .signed, identifier: "com.example.term", teamID: "TEAM123456", displayName: "Term")
        check(SudoAppPolicy.decision(for: signed, entries: [signed.key: .allowed]) == .proceed, "signed app with an allowed entry proceeds")

        // MARK: - 2. A blocked entry declines outright

        check(SudoAppPolicy.decision(for: signed, entries: [signed.key: .blocked]) == .decline, "signed app with a blocked entry declines")

        // MARK: - 3. No stored entry asks the user

        check(SudoAppPolicy.decision(for: signed, entries: [:]) == .askToAllow, "signed app with no entry asks to allow")

        // MARK: - 4. A copy with a different team id does not inherit the entry

        let otherTeam = SudoAppIdentity(kind: .signed, identifier: "com.example.term", teamID: "OTHERTEAM1", displayName: "Term")
        let allowed: [String: SudoAppState] = [signed.key: .allowed]
        check(SudoAppPolicy.decision(for: otherTeam, entries: allowed) == .askToAllow, "copy with a different team id does not inherit the allowed entry")
        check(otherTeam.key != signed.key, "a different team id yields a different key")

        // MARK: - 5. A copy with a different identifier does not inherit the entry

        let otherID = SudoAppIdentity(kind: .signed, identifier: "com.example.other", teamID: "TEAM123456", displayName: "Term")
        check(SudoAppPolicy.decision(for: otherID, entries: allowed) == .askToAllow, "copy with a different identifier does not inherit the allowed entry")

        // MARK: - 6. Unsigned apps key on the code directory hash

        let unsigned = SudoAppIdentity(kind: .unsigned, identifier: "abc123deadbeef", teamID: nil, displayName: "Term")
        let unsignedAllowed: [String: SudoAppState] = [unsigned.key: .allowed]
        check(SudoAppPolicy.decision(for: unsigned, entries: unsignedAllowed) == .proceed, "unsigned app with an allowed entry proceeds")
        let rehashed = SudoAppIdentity(kind: .unsigned, identifier: "ffff0000", teamID: nil, displayName: "Term")
        check(SudoAppPolicy.decision(for: rehashed, entries: unsignedAllowed) == .askToAllow, "unsigned app with a different cdhash does not inherit the allowed entry")

        // MARK: - 7. A blocked entry never proceeds or asks

        let cases: [(SudoAppIdentity, String)] = [
            (signed, "original signed app"),
            (otherTeam, "copy with a different team id"),
            (otherID, "copy with a different identifier"),
            (unsigned, "unsigned app"),
            (rehashed, "unsigned app with a different cdhash"),
        ]
        for (identity, label) in cases {
            let blocked: [String: SudoAppState] = [identity.key: .blocked]
            check(SudoAppPolicy.decision(for: identity, entries: blocked) == .decline, "blocked entry declines for the \(label)")
        }

        // MARK: - 8. A blocked entry is scoped to its own key

        let blockedSigned: [String: SudoAppState] = [signed.key: .blocked]
        for (identity, label) in cases where identity.key != signed.key {
            check(SudoAppPolicy.decision(for: identity, entries: blockedSigned) == .askToAllow, "blocked entry for the original app does not affect the \(label)")
        }

        if failures == 0 {
            print("All sudo policy self-tests passed.")
        } else {
            print("\(failures) sudo policy check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

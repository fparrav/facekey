//
//  post_unlock_verification_selftest.swift
//  facekey (tools)
//
//  Offline self-test for PostUnlockVerification (window, grace, reset on
//  noFace, out-of-window ignores, finish fallback). This project has no test
//  target, so this compiles as a standalone script against the real file:
//
//      swiftc -O -parse-as-library -o /tmp/post_unlock_verification_selftest \
//        facekey/PostUnlockVerification.swift \
//        tools/post_unlock_verification_selftest.swift \
//      && /tmp/post_unlock_verification_selftest
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

@main
enum PostUnlockVerificationSelfTest {
    static func main() {
        // MARK: - Match verifies

        var v = PostUnlockVerification()
        check(v.observe(.matched, at: 0.5) == .verified, "a match at 0.5s verifies immediately")

        // MARK: - Stranger after grace

        v = PostUnlockVerification()
        check(v.observe(.unrecognised, at: 0) == nil, "unrecognised at 0 returns nil (grace not elapsed)")
        check(v.observe(.unrecognised, at: 1) == nil, "unrecognised at 1 returns nil (grace not elapsed)")
        check(v.observe(.unrecognised, at: 2) == nil, "unrecognised at 2 returns nil (grace not elapsed)")
        check(v.observe(.unrecognised, at: 3) == .stranger, "unrecognised at 3 returns .stranger (grace elapsed)")

        // MARK: - Match after some unrecognised frames

        v = PostUnlockVerification()
        check(v.observe(.unrecognised, at: 0) == nil, "unrecognised at 0 returns nil")
        check(v.observe(.unrecognised, at: 2) == nil, "unrecognised at 2 returns nil (grace not elapsed)")
        check(v.observe(.matched, at: 2.1) == .verified, "a match at 2.1 verifies despite earlier unrecognised frames")

        // MARK: - noFace resets the unrecognised timer

        v = PostUnlockVerification()
        check(v.observe(.unrecognised, at: 0) == nil, "unrecognised at 0 returns nil")
        check(v.observe(.noFace, at: 1.5) == nil, "noFace at 1.5 returns nil and resets the timer")
        check(v.observe(.unrecognised, at: 2) == nil, "unrecognised at 2 returns nil (timer restarted, since 2)")
        check(v.observe(.unrecognised, at: 4.9) == nil, "unrecognised at 4.9 returns nil (2.9s since reset, grace not elapsed)")
        check(v.observe(.unrecognised, at: 5.0) == .stranger, "unrecognised at 5.0 returns .stranger (3s since the 2s reset)")

        // MARK: - Finish when grace never elapses

        v = PostUnlockVerification()
        check(v.observe(.unrecognised, at: 0) == nil, "unrecognised at 0 returns nil")
        check(v.observe(.unrecognised, at: 2.9) == nil, "unrecognised at 2.9 returns nil (grace not elapsed)")
        check(v.finish(at: 6) == .nobody, "finish at 6 without an outcome is .nobody")

        // MARK: - Finish after only noFace frames

        v = PostUnlockVerification()
        let noFaceTicks: [TimeInterval] = [0, 1, 2, 3, 4, 5, 6]
        for t in noFaceTicks {
            check(v.observe(.noFace, at: t) == nil, "noFace at \(t) returns nil")
        }
        check(v.finish(at: 6) == .nobody, "finish at 6 after only noFace frames is .nobody")

        // MARK: - Out-of-window ignores

        v = PostUnlockVerification()
        check(v.observe(.matched, at: 6.5) == nil, "a match at 6.5s outside the window is ignored")
        check(v.observe(.unrecognised, at: 6.5) == nil, "an unrecognised face at 6.5s outside the window is ignored")

        // MARK: - Constants

        check(PostUnlockVerification.window == 6, "window is 6 seconds")
        check(PostUnlockVerification.grace == 3, "grace is 3 seconds")

        // MARK: - Out-of-window unrecognised does not alter state

        v = PostUnlockVerification()
        check(v.observe(.unrecognised, at: 3.5) == nil, "unrecognised at 3.5 returns nil (grace not elapsed)")
        check(v.observe(.unrecognised, at: 7) == nil, "an unrecognised face at 7s outside the window is ignored (state untouched)")
        check(v.finish(at: 7) == .nobody, "finish at 7 after an out-of-window unrecognised is .nobody")

        if failures == 0 {
            print("All post-unlock verification self-tests passed.")
        } else {
            print("\(failures) post-unlock verification check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

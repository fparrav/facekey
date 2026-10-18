//
//  notch_status_message_selftest.swift
//  facekey (tools)
//
//  Offline self-test for the notch status text in facekey/NotchOverlay/NotchStatusMessage.swift:
//  the key and tone of each of the five states, and the hover hint on the failure text.
//  This project has no test target, so this compiles as a standalone script against the real file:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/notch_status_message_selftest facekey/NotchOverlay/NotchStatusMessage.swift tools/notch_status_message_selftest.swift && /private/tmp/notch_status_message_selftest
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

func message(_ state: NotchStatusState, hover: Bool = false) -> NotchStatusMessage {
    NotchStatusMessage.for(state: state, hoverRetryEnabled: hover)
}

@main
enum NotchStatusMessageSelfTest {
    static func main() {
        check(message(.scanning).key == "Looking for your face…", "scanning text")
        check(message(.scanning).tone == .accent, "scanning is accent")
        check(message(.success).key == "Mac unlocked", "success text")
        check(message(.success).tone == .accent, "success is accent")
        check(message(.cameraUnavailable).key == "Camera unavailable", "camera unavailable text")
        check(message(.cameraUnavailable).tone == .warning, "camera unavailable is warning")
        check(message(.sudoApproval).key == "Approve sudo with your face", "sudo approval text")
        check(message(.sudoApproval).tone == .accent, "sudo approval is accent")

        check(message(.failure, hover: true).key == "Face not recognized. Hover to retry.", "failure with hover retry carries the hint")
        check(message(.failure, hover: false).key == "Face not recognized.", "failure without hover retry has no hint")
        check(message(.failure, hover: true).tone == .failure, "failure with hover retry is failure tone")
        check(message(.failure, hover: false).tone == .failure, "failure without hover retry is failure tone")

        for state in [NotchStatusState.scanning, .success, .cameraUnavailable, .sudoApproval] {
            check(message(state, hover: true) == message(state, hover: false), "\(state) ignores hover retry")
        }

        if failures > 0 {
            print("\(failures) check(s) failed")
            exit(1)
        }
        print("All checks passed")
    }
}

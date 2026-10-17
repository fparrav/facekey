//
//  sudo_command_text_selftest.swift
//  facekey (tools)
//
//  Offline self-test for SudoCommandText: empty argv, joining, executableOnly,
//  head+tail clipping, and escaping of control/format/direction characters.
//  This project has no test target, so this compiles as a standalone script against the real file:
//
//      /usr/bin/swiftc -O -parse-as-library -o /tmp/sudo_command_text_selftest \
//        facekey/Sudo/SudoCommandText.swift \
//        tools/sudo_command_text_selftest.swift \
//      && /tmp/sudo_command_text_selftest
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
enum SudoCommandTextSelfTest {
    static func main() {
        // MARK: - 1. Empty argv

        check(SudoCommandText.display(argv: [], executableOnly: false) == "", "empty argv with executableOnly false returns empty")
        check(SudoCommandText.display(argv: [], executableOnly: true) == "", "empty argv with executableOnly true returns empty")

        // MARK: - 2. Short argv joins unchanged

        check(SudoCommandText.display(argv: ["ls", "-la"], executableOnly: false) == "ls -la", "short argv joins with a space and is not clipped")

        // MARK: - 3. executableOnly keeps argv[0] alone

        let onlyExe = SudoCommandText.display(argv: ["tool", "--token=abc"], executableOnly: true)
        check(onlyExe == "tool", "executableOnly returns argv[0] alone")
        check(!onlyExe.contains("abc"), "executableOnly hides the rest of argv")
        check(
            SudoCommandText.display(argv: ["tool", "--token=abc"], executableOnly: false).contains("--token=abc"),
            "full argv keeps every argument"
        )

        // MARK: - 4. Over-long argv clips to maxLength

        let long = SudoCommandText.display(argv: ["echo", String(repeating: "a", count: 300)], executableOnly: false)
        check(long.count == 120, "over-long argv clips to exactly maxLength characters")
        check(long.contains("…"), "clipped text contains the ellipsis")

        // MARK: - 5. Clipping keeps the tail visible

        let tail = SudoCommandText.display(argv: ["cmd", String(repeating: "x", count: 300), "FINAL-ARG"], executableOnly: false)
        check(tail.count == 120, "clipping a long command still yields maxLength characters")
        check(tail.hasSuffix("FINAL-ARG"), "clipping keeps the last argument visible")

        // MARK: - 6. Newline and bidi override are escaped

        let bidi = SudoCommandText.display(argv: ["echo", "a\nb\u{202E}c"], executableOnly: false)
        check(!bidi.contains("\n"), "newline is not present raw")
        check(!bidi.contains("\u{202E}"), "bidi override is not present raw")
        check(bidi.contains("\\u{000A}"), "newline renders as the literal \\u{000A}")
        check(bidi.contains("\\u{202E}"), "bidi override renders as the literal \\u{202E}")

        // MARK: - 7. Tab and zero-width space are escaped

        let zw = SudoCommandText.display(argv: ["echo", "a\tb\u{200B}c"], executableOnly: false)
        check(!zw.contains("\t"), "tab is not present raw")
        check(!zw.contains("\u{200B}"), "zero-width space is not present raw")
        check(zw.contains("\\u{0009}"), "tab renders as the literal \\u{0009}")
        check(zw.contains("\\u{200B}"), "zero-width space renders as the literal \\u{200B}")

        // MARK: - 8. executableOnly clips an over-long argv[0]

        let longExe = SudoCommandText.display(argv: [String(repeating: "z", count: 300)], executableOnly: true)
        check(longExe.count == 120, "executableOnly clips an over-long argv[0] to maxLength")

        if failures == 0 {
            print("All sudo command text self-tests passed.")
        } else {
            print("\(failures) sudo command text check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

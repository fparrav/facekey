//
//  accent_choice_selftest.swift
//  facekey (tools)
//
//  Offline self-test for the settings accent picker in facekey/Settings/AccentChoice.swift:
//  the five hex values, the green default, the round trip through storedValue,
//  the dark ink on a bright accent, and the case count.
//  This project has no test target, so this compiles as a standalone script against the real file:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/accent_choice_selftest facekey/Settings/AccentChoice.swift tools/accent_choice_selftest.swift && /private/tmp/accent_choice_selftest
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
enum AccentChoiceSelfTest {
    static func main() {
        // MARK: - Hex values

        check(AccentChoice.green.hex == "#34D399", "green is #34D399")
        check(AccentChoice.lime.hex == "#7DDC5A", "lime is #7DDC5A")
        check(AccentChoice.mint.hex == "#5EEAD4", "mint is #5EEAD4")
        check(AccentChoice.blue.hex == "#3499FF", "blue is #3499FF")
        check(AccentChoice.amber.hex == "#F5B73B", "amber is #F5B73B")

        // MARK: - Default

        check(AccentChoice.defaultChoice == .green, "the default accent is green")

        // MARK: - Stored value round trip

        check(AccentChoice(storedValue: nil) == .green, "no stored value falls back to green")
        check(AccentChoice(storedValue: "nonsense") == .green, "an unknown stored value falls back to green")
        for choice in AccentChoice.allCases {
            check(AccentChoice(storedValue: choice.rawValue) == choice, "\(choice.rawValue) round-trips through storedValue")
        }

        // MARK: - Ink and case count

        check(AccentChoice.inkHex == "#0C1410", "ink on a bright accent is #0C1410")
        check(AccentChoice.allCases.count == 5, "there are exactly five accents")

        if failures == 0 {
            print("All accent choice self-tests passed.")
        } else {
            print("\(failures) accent choice check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

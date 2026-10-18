//
//  settings_page_selftest.swift
//  facekey (tools)
//
//  Offline self-test for the Settings page list in facekey/Settings/SettingsPage.swift:
//  the order of the five pages, the Face Lab hidden or shown, and Summary as the default page.
//  This project has no test target, so this compiles as a standalone script against the real file:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/settings_page_selftest facekey/Settings/SettingsPage.swift tools/settings_page_selftest.swift && /private/tmp/settings_page_selftest
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
enum SettingsPageSelfTest {
    static func main() {
        let hidden = SettingsPage.visiblePages(includingLab: false)
        let shown = SettingsPage.visiblePages(includingLab: true)

        check(hidden == [.summary, .access, .security, .devices, .app], "the five pages come in sidebar order")
        check(!hidden.contains(.faceLab), "Face Lab is hidden by default")
        check(shown == [.summary, .access, .security, .devices, .app, .faceLab], "Face Lab comes last when shown")
        check(SettingsPage.defaultPage == .summary, "Summary is the default page")
        check(hidden.first == SettingsPage.defaultPage, "the default page is the first one in the sidebar")
        check(Set(SettingsPage.allCases.map(\.id)).count == SettingsPage.allCases.count, "page ids are unique")
        check(Set(SettingsPage.allCases.map(\.symbolName)).count == SettingsPage.allCases.count, "page symbols are unique")
        check(SettingsPage.allCases.allSatisfy { $0.tileHex.hasPrefix("#") && $0.tileHex.count == 7 }, "tile colours are #RRGGBB")

        if failures > 0 {
            print("\(failures) check(s) failed")
            exit(1)
        }
        print("All checks passed")
    }
}

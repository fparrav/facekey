//
//  sudo_settings_selftest.swift
//  facekey (tools)
//
//  Offline self-test for SudoApprovalSettings on a throwaway UserDefaults suite: every
//  display setup and the command-storage flag default off, one setup never turns on
//  another, and values persist across a new struct over the same suite.
//  This project has no test target, so this compiles as a standalone script against the real files:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/sudo_settings_selftest facekey/Sudo/SudoApprovalSettings.swift facekey/NotchOverlay/DisplayContext.swift tools/sudo_settings_selftest.swift && /private/tmp/sudo_settings_selftest
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

/// `DisplayContext.swift` reads this from `NotchGeometry.swift`, which is not part of this build.
extension NSScreen {
    var isBuiltIn: Bool { true }
}

@main
enum SudoSettingsSelfTest {
    static func main() {
        let suite = "sudo_settings_selftest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            print("FAIL: could not create a throwaway UserDefaults suite")
            exit(1)
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let contexts: [(DisplayContext, String)] = [
            (.builtInOnly, "built-in only"),
            (.builtInAndExternal, "built-in and external"),
            (.externalOnly, "external only"),
        ]
        let settings = SudoApprovalSettings(defaults: defaults)

        // MARK: - 1. Everything defaults off

        for (context, label) in contexts {
            check(!settings.isEnabled(for: context), "\(label) defaults off")
        }
        check(!settings.storesExecutableOnly, "storesExecutableOnly defaults off")

        // MARK: - 2. Turning one setup on leaves the others off

        for (target, targetLabel) in contexts {
            settings.setEnabled(true, for: target)
            for (other, otherLabel) in contexts where other != target {
                check(!settings.isEnabled(for: other), "enabling \(targetLabel) leaves \(otherLabel) off")
            }
            check(settings.isEnabled(for: target), "\(targetLabel) reads back on")
            settings.setEnabled(false, for: target)
        }

        // MARK: - 3. Values persist across a new instance

        settings.setEnabled(true, for: .builtInAndExternal)
        settings.storesExecutableOnly = true
        let reloaded = SudoApprovalSettings(defaults: defaults)
        check(reloaded.isEnabled(for: .builtInAndExternal), "an enabled setup persists in a new instance")
        check(!reloaded.isEnabled(for: .builtInOnly) && !reloaded.isEnabled(for: .externalOnly), "the other setups stay off in a new instance")
        check(reloaded.storesExecutableOnly, "storesExecutableOnly persists in a new instance")

        reloaded.setEnabled(false, for: .builtInAndExternal)
        reloaded.storesExecutableOnly = false
        check(!SudoApprovalSettings(defaults: defaults).isEnabled(for: .builtInAndExternal), "turning a setup off persists")
        check(!SudoApprovalSettings(defaults: defaults).storesExecutableOnly, "turning storesExecutableOnly off persists")

        if failures == 0 {
            print("All sudo settings self-tests passed.")
        } else {
            print("\(failures) sudo settings check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

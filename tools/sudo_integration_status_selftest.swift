//
//  sudo_integration_status_selftest.swift
//  facekey (tools)
//
//  Offline self-test for SudoIntegrationStatus over scratch trees: nothing installed, a
//  current install, a module with no sudo_local entry, an entry with an old or missing
//  module, and an entry whose block is incomplete or points elsewhere.
//  This project has no test target, so this compiles as a standalone script against the real file:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/sudo_integration_status_selftest facekey/Sudo/SudoIntegrationStatus.swift tools/sudo_integration_status_selftest.swift && /private/tmp/sudo_integration_status_selftest
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

let bundled = "abc123"

/// A scratch root with the module and/or a sudo_local made from `sudoLocal`.
func makeRoot(module: Bool, sudoLocal: String?) -> String {
    let root = NSTemporaryDirectory() + "sudo_integration_selftest_\(UUID().uuidString)"
    let fm = FileManager.default
    try? fm.createDirectory(atPath: root + "/usr/local/lib/pam", withIntermediateDirectories: true)
    try? fm.createDirectory(atPath: root + "/etc/pam.d", withIntermediateDirectories: true)
    if module {
        fm.createFile(atPath: root + SudoIntegrationStatus.modulePath, contents: Data("module".utf8))
    }
    if let sudoLocal {
        fm.createFile(atPath: root + SudoIntegrationStatus.sudoLocalPath, contents: Data(sudoLocal.utf8))
    }
    return root
}

func block(version: String?, path: String = SudoIntegrationStatus.modulePath) -> String {
    var lines = ["# sudo_local", "# BEGIN facekey"]
    if let version { lines.append("# facekey-version: \(version)") }
    lines += ["auth       sufficient     \(path)", "# END facekey", "auth       sufficient     pam_tid.so", ""]
    return lines.joined(separator: "\n")
}

@main
enum SudoIntegrationStatusSelfTest {
    static func main() {
        var roots: [String] = []
        func state(module: Bool, sudoLocal: String?) -> SudoIntegrationState {
            let root = makeRoot(module: module, sudoLocal: sudoLocal)
            roots.append(root)
            return SudoIntegrationStatus.evaluate(root: root, bundledVersion: bundled)
        }
        defer { roots.forEach { try? FileManager.default.removeItem(atPath: $0) } }

        check(state(module: false, sudoLocal: nil) == .notInstalled, "no module and no sudo_local is not installed")
        check(state(module: false, sudoLocal: "auth       sufficient     pam_tid.so\n") == .notInstalled, "no module and a sudo_local without the block is not installed")
        check(state(module: true, sudoLocal: block(version: bundled)) == .installed, "module plus a current entry is installed")
        check(state(module: true, sudoLocal: nil) == .missingEntry, "module with no sudo_local is a missing entry")
        check(state(module: true, sudoLocal: "auth       sufficient     pam_tid.so\n") == .missingEntry, "module with a sudo_local that lost the block is a missing entry")
        check(state(module: true, sudoLocal: block(version: "old")) == .outdatedModule, "an entry recording another version is outdated")
        check(state(module: true, sudoLocal: block(version: nil)) == .outdatedModule, "an entry with no recorded version is outdated")
        check(state(module: false, sudoLocal: block(version: bundled)) == .outdatedModule, "an entry whose module file is gone is outdated")
        check(state(module: true, sudoLocal: block(version: bundled, path: "/somewhere/else.so")) == .missingEntry, "a block pointing at another module is not our entry")
        check(state(module: true, sudoLocal: block(version: bundled, path: "/tmp" + SudoIntegrationStatus.modulePath)) == .missingEntry, "a path that only ends like ours is not our entry")
        check(state(module: true, sudoLocal: "# BEGIN facekey\n# facekey-version: \(bundled)\nauth       sufficient     \(SudoIntegrationStatus.modulePath)\n") == .missingEntry, "a block with no closing marker is not an entry")

        if failures == 0 {
            print("All sudo integration status self-tests passed.")
        } else {
            print("\(failures) sudo integration status check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

//
//  sudo_audit_list_selftest.swift
//  facekey (tools)
//
//  Offline self-test for SudoAuditListModel with a fixed audit key: entries come back
//  newest first, clear empties the history, and clear is refused while the session is locked.
//  This project has no test target, so this compiles as a standalone script against the real files:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/sudo_audit_list_selftest facekey/Sudo/SudoAuditEntry.swift facekey/Sudo/SudoAuditLog.swift facekey/Sudo/SudoAuditListModel.swift tools/sudo_audit_list_selftest.swift && /private/tmp/sudo_audit_list_selftest
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

struct FixedKey: SudoAuditKeyProviding {
    func auditKey() -> Data? { Data(repeating: 7, count: 32) }
}

@main
enum SudoAuditListSelfTest {
    static func main() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = SudoAuditLog(fileURL: directory.appendingPathComponent("audit.enc"), keys: FixedKey())
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var unlocked = true
        let model = SudoAuditListModel(log: log, isSessionUnlocked: { unlocked })

        check((try? model.entries())?.isEmpty == true, "an empty history lists no entries")

        for (index, command) in ["first", "second", "third"].enumerated() {
            try? log.append(SudoAuditEntry(time: Date(timeIntervalSince1970: Double(index)), appName: "Ghostty",
                                           displaySetup: "Built-in display", outcome: .approved, command: command))
        }
        check((try? model.entries())?.map(\.command) == ["third", "second", "first"], "entries come back newest first")

        unlocked = false
        var refused = false
        do { try model.clear() } catch SudoAuditListError.sessionLocked { refused = true } catch {}
        check(refused, "clear is refused while the session is locked")
        check((try? model.entries())?.count == 3, "a refused clear leaves the history intact")

        unlocked = true
        check((try? model.clear()) != nil, "clear works while the session is unlocked")
        check((try? model.entries())?.isEmpty == true, "the history is empty after clearing")
        check((try? model.clear()) != nil, "clearing an empty history is a no-op")

        print(failures == 0 ? "All sudo audit list self-tests passed." : "\(failures) check(s) FAILED.")
        exit(failures == 0 ? 0 : 1)
    }
}

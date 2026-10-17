//
//  sudo_app_list_selftest.swift
//  facekey (tools)
//
//  Offline self-test for SudoAppListModel with a fake session cipher: stored policy
//  keys become rows sorted by name, a change is saved and read back, removing drops a
//  row, keys this app did not write are skipped, and a locked session refuses every edit.
//  This project has no test target, so this compiles as a standalone script against the real files:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/sudo_app_list_selftest facekey/Sudo/SudoAppIdentity.swift facekey/Sudo/SudoAppPolicy.swift facekey/Sudo/SudoPolicyStore.swift facekey/Sudo/SudoAppListModel.swift tools/sudo_app_list_selftest.swift && /private/tmp/sudo_app_list_selftest
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

/// XOR with 0x5A, so the stored file is never clear-text JSON.
final class FakeCipher: SudoSessionCipher {
    var isSessionUnlocked = true
    func encrypt(_ data: Data) throws -> Data { Data(data.map { $0 ^ 0x5A }) }
    func decrypt(_ data: Data) throws -> Data { Data(data.map { $0 ^ 0x5A }) }
}

func fails(_ error: SudoPolicyStoreError, _ body: () throws -> Void) -> Bool {
    do { try body(); return false } catch let caught as SudoPolicyStoreError { return caught == error } catch { return false }
}

@main
enum SudoAppListSelfTest {
    static func main() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cipher = FakeCipher()
        let store = SudoPolicyStore(fileURL: directory.appendingPathComponent("policy.enc"), cipher: cipher)
        let model = SudoAppListModel(store: store)

        let ghostty = "signed|com.mitchellh.ghostty|TEAM1"
        let terminal = "signed|com.apple.Terminal|-"
        let script = "unsigned|0123456789abcdef0123456789abcdef01234567|-"

        check((try? model.entries())?.isEmpty == true, "a missing policy file lists no rows")

        try? store.save([ghostty: .allowed, terminal: .blocked, script: .allowed, "garbage": .allowed, "other|x|-": .blocked])
        let rows = (try? model.entries()) ?? []
        check(rows.map(\.key) == [script, terminal, ghostty], "rows are sorted by name and keys this app did not write are skipped")
        check(rows[1].state == .blocked && rows[1].teamID == nil, "a row carries its state and a missing team id")
        check(rows[0].title == "0123456789ab" && rows[0].kind == .unsigned, "an unsigned app is shown by a shortened code hash")
        check(rows[2].teamID == "TEAM1", "a signed row keeps its team id")

        check((try? model.setState(.blocked, forKey: ghostty)) != nil, "a state change saves")
        check((try? store.load())?[ghostty] == .blocked, "the change is read back from the store")

        check((try? model.remove(key: terminal)) != nil, "removing a row saves")
        check((try? store.load())?[terminal] == nil, "the removed row is gone from the store")
        check((try? model.remove(key: "signed|not.there|-")) != nil, "removing a row that is not stored does nothing")

        cipher.isSessionUnlocked = false
        check(model.isLocked, "the model reports a locked session")
        check(fails(.sessionLocked) { _ = try model.entries() }, "a locked session refuses to list")
        check(fails(.sessionLocked) { try model.setState(.allowed, forKey: ghostty) }, "a locked session refuses a state change")
        check(fails(.sessionLocked) { try model.remove(key: ghostty) }, "a locked session refuses a removal")

        cipher.isSessionUnlocked = true
        check((try? store.load())?[ghostty] == .blocked, "refused edits left the stored policy untouched")

        print(failures == 0 ? "All sudo app list self-tests passed." : "\(failures) check(s) FAILED.")
        exit(failures == 0 ? 0 : 1)
    }
}

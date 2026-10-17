//
//  sudo_audit_selftest.swift
//  facekey (tools)
//
//  Offline self-test for SudoAuditLog with a fake key provider: append and
//  read work without a Facekey session, entries survive a recreated object,
//  a missing or short key refuses to write, the file on disk is never
//  clear-text JSON, a wrong key fails to decrypt, and the entry cap evicts
//  the oldest entries.
//  This project has no test target, so this compiles as a standalone script against the real files:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/sudo_audit_selftest facekey/Sudo/SudoAuditEntry.swift facekey/Sudo/SudoAuditLog.swift tools/sudo_audit_selftest.swift && /private/tmp/sudo_audit_selftest
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

/// Fake key provider with a mutable key; defaults to 32 bytes of 0x42.
final class FakeKeys: SudoAuditKeyProviding {
    var key: Data? = Data(repeating: 0x42, count: 32)

    func auditKey() -> Data? {
        key
    }
}

func containsSubstring(_ haystack: Data, _ needle: Data) -> Bool {
    guard needle.count > 0, needle.count <= haystack.count else { return false }
    for index in 0...(haystack.count - needle.count) where haystack.subdata(in: index..<index + needle.count) == needle {
        return true
    }
    return false
}

func entry(_ command: String) -> SudoAuditEntry {
    SudoAuditEntry(appName: "com.example.Terminal", displaySetup: "built-in", outcome: .approved, command: command)
}

@main
enum SudoAuditLogSelfTest {
    static func main() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = tempDir.appendingPathComponent("audit.bin")
        let keys = FakeKeys()
        let goodKey = Data(repeating: 0x42, count: 32)
        let log = SudoAuditLog(fileURL: fileURL, keys: keys)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        // MARK: - 1. append works with only the fake key provider, no Facekey session

        do {
            try log.append(entry("one"))
            let entries = try log.entriesNewestFirst()
            check(entries.count == 1, "append works without a Facekey session and the entry reads back")
        } catch {
            check(false, "append works without a Facekey session and the entry reads back")
        }

        // MARK: - 2. entriesNewestFirst orders by insertion, newest first

        do {
            try log.append(entry("two"))
            try log.append(entry("three"))
            let commands = try log.entriesNewestFirst().map(\.command)
            check(commands == ["three", "two", "one"], "entriesNewestFirst returns commands newest first")
        } catch {
            check(false, "entriesNewestFirst returns commands newest first")
        }

        // MARK: - 3. Entries survive recreating the object

        do {
            let fresh = SudoAuditLog(fileURL: fileURL, keys: keys)
            let recreated = try fresh.entriesNewestFirst()
            let original = try log.entriesNewestFirst()
            check(recreated == original, "entries survive recreating the object")
        } catch {
            check(false, "entries survive recreating the object")
        }

        // MARK: - 4. A nil key refuses to append and read, without touching the file

        let bytesBefore = (try? Data(contentsOf: fileURL)) ?? Data()
        keys.key = nil
        var appendNoKey = false
        do {
            try log.append(entry("nope"))
        } catch SudoAuditLogError.noKey {
            appendNoKey = true
        } catch {}
        var readNoKey = false
        do {
            _ = try log.entriesNewestFirst()
        } catch SudoAuditLogError.noKey {
            readNoKey = true
        } catch {}
        let bytesAfter = (try? Data(contentsOf: fileURL)) ?? Data()
        keys.key = goodKey
        check(appendNoKey && readNoKey && bytesBefore == bytesAfter, "nil key throws noKey on append and read and leaves the file untouched")

        // MARK: - 5. A key that is not 32 bytes counts as no key

        keys.key = Data(repeating: 0x77, count: 16)
        var shortNoKey = false
        do {
            try log.append(entry("short"))
        } catch SudoAuditLogError.noKey {
            shortNoKey = true
        } catch {}
        keys.key = goodKey
        check(shortNoKey, "a 16-byte key is treated as no key")

        // MARK: - 6. The file on disk is not clear-text JSON

        let secret = (try? Data(contentsOf: fileURL)) ?? Data()
        var parsesAsJSON = false
        do {
            _ = try JSONSerialization.jsonObject(with: secret)
            parsesAsJSON = true
        } catch {
            parsesAsJSON = false
        }
        check(!secret.isEmpty && !parsesAsJSON
            && !containsSubstring(secret, Data("three".utf8))
            && !containsSubstring(secret, Data("appName".utf8)), "audit file on disk is not clear-text JSON and contains no entry fields")

        // MARK: - 7. A different 32-byte key fails to decrypt, without reporting noKey

        keys.key = Data(repeating: 0x99, count: 32)
        var wrongKeyDecryptError = false
        do {
            _ = try log.entriesNewestFirst()
        } catch SudoAuditLogError.noKey {
            wrongKeyDecryptError = false
        } catch {
            wrongKeyDecryptError = true
        }
        keys.key = goodKey
        check(wrongKeyDecryptError, "a different 32-byte key throws a decrypt error, not noKey")

        // MARK: - 8. clear() empties the log and is a no-op on a missing file

        var cleared = false
        do {
            try log.clear()
            let entries = try log.entriesNewestFirst()
            let fileGone = !FileManager.default.fileExists(atPath: fileURL.path)
            try log.clear()
            cleared = entries.isEmpty && fileGone
        } catch {
            cleared = false
        }
        check(cleared, "clear() leaves an empty log, removes the file, and does not throw on a missing file")

        // MARK: - 9. The entry cap evicts the oldest entries

        do {
            for index in 0...SudoAuditLog.maxEntries {
                try log.append(entry("e\(index)"))
            }
            let entries = try log.entriesNewestFirst()
            check(entries.count == SudoAuditLog.maxEntries
                && entries.first?.command == "e\(SudoAuditLog.maxEntries)"
                && !entries.contains { $0.command == "e0" }, "beyond maxEntries the oldest entries are evicted, newest first")
        } catch {
            check(false, "beyond maxEntries the oldest entries are evicted, newest first")
        }

        if failures == 0 {
            print("All sudo audit log self-tests passed.")
        } else {
            print("\(failures) sudo audit log check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

//
//  sudo_policy_store_selftest.swift
//  facekey (tools)
//
//  Offline self-test for SudoPolicyStore with a fake session cipher: an unlocked
//  session saves and loads the policy, a locked session refuses both, the file on
//  disk is never clear-text JSON, and a corrupt file surfaces a cipher error.
//  This project has no test target, so this compiles as a standalone script against the real files:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/sudo_policy_store_selftest facekey/Sudo/SudoAppIdentity.swift facekey/Sudo/SudoAppPolicy.swift facekey/Sudo/SudoPolicyStore.swift tools/sudo_policy_store_selftest.swift && /private/tmp/sudo_policy_store_selftest
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

/// XOR with 0x5A plus an "FKEY" prefix, so the stored file is never clear-text JSON.
final class FakeCipher: SudoSessionCipher {
    var isSessionUnlocked = true

    static let prefix = Data("FKEY".utf8)

    func encrypt(_ data: Data) throws -> Data {
        Self.prefix + Data(data.map { $0 ^ 0x5A })
    }

    enum FakeCipherError: Error, Equatable { case badPrefix }

    func decrypt(_ data: Data) throws -> Data {
        guard data.count > Self.prefix.count, data.prefix(Self.prefix.count) == Self.prefix else {
            throw FakeCipherError.badPrefix
        }
        return Data(data.dropFirst(Self.prefix.count).map { $0 ^ 0x5A })
    }
}

func containsSubstring(_ haystack: Data, _ needle: Data) -> Bool {
    guard needle.count > 0, needle.count <= haystack.count else { return false }
    for index in 0...(haystack.count - needle.count) where haystack.subdata(in: index..<index + needle.count) == needle {
        return true
    }
    return false
}

@main
enum SudoPolicyStoreSelfTest {
    static func main() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = tempDir.appendingPathComponent("policy.json")

        let cipher = FakeCipher()
        let store = SudoPolicyStore(fileURL: fileURL, cipher: cipher)
        let entries: [String: SudoAppState] = ["com.example.one": .allowed, "com.example.two": .blocked]

        defer { try? FileManager.default.removeItem(at: tempDir) }

        // MARK: - 1. An unlocked session saves and loads the same policy

        do {
            try store.save(entries)
            check(try store.load() == entries, "unlocked session saves and loads the same policy")
        } catch {
            check(false, "unlocked session saves and loads the same policy")
        }

        // MARK: - 2. A missing file loads as an empty policy

        let missingStore = SudoPolicyStore(fileURL: tempDir.appendingPathComponent("missing.json"), cipher: cipher)
        do {
            check(try missingStore.load() == [:], "loading a missing file with an unlocked session returns an empty policy")
        } catch {
            check(false, "loading a missing file with an unlocked session returns an empty policy")
        }

        // MARK: - 3. A locked session refuses to load, even when the file exists

        cipher.isSessionUnlocked = false
        do {
            _ = try store.load()
            check(false, "locked session load throws sessionLocked even when the file exists")
        } catch SudoPolicyStoreError.sessionLocked {
            check(true, "locked session load throws sessionLocked even when the file exists")
        } catch {
            check(false, "locked session load throws sessionLocked even when the file exists")
        }

        // MARK: - 4. A locked session refuses to save and writes nothing

        let freshURL = tempDir.appendingPathComponent("fresh.json")
        let freshStore = SudoPolicyStore(fileURL: freshURL, cipher: cipher)
        var lockedSaveThrew = false
        do {
            _ = try freshStore.save(entries)
        } catch SudoPolicyStoreError.sessionLocked {
            lockedSaveThrew = true
        } catch {
            lockedSaveThrew = false
        }
        check(lockedSaveThrew && !FileManager.default.fileExists(atPath: freshURL.path), "locked session save throws sessionLocked and writes no file")

        // MARK: - 5. The file on disk is not clear-text JSON

        cipher.isSessionUnlocked = true
        let secret = (try? Data(contentsOf: fileURL)) ?? Data()
        var parsesAsJSON = false
        do {
            _ = try JSONSerialization.jsonObject(with: secret)
            parsesAsJSON = true
        } catch {
            parsesAsJSON = false
        }
        check(!secret.isEmpty && !parsesAsJSON && !containsSubstring(secret, Data("allowed".utf8)), "saved file on disk is not clear-text JSON and does not contain \"allowed\"")

        // MARK: - 6. A corrupt file without the prefix surfaces a cipher error, not sessionLocked

        let corruptURL = tempDir.appendingPathComponent("corrupt.json")
        try? Data([0x01, 0x02, 0x03]).write(to: corruptURL)
        let corruptStore = SudoPolicyStore(fileURL: corruptURL, cipher: cipher)
        do {
            _ = try corruptStore.load()
            check(false, "corrupt file without the FKEY prefix makes load() throw an error that is not sessionLocked")
        } catch SudoPolicyStoreError.sessionLocked {
            check(false, "corrupt file without the FKEY prefix makes load() throw an error that is not sessionLocked")
        } catch {
            check(true, "corrupt file without the FKEY prefix makes load() throw an error that is not sessionLocked")
        }

        if failures == 0 {
            print("All sudo policy store self-tests passed.")
        } else {
            print("\(failures) sudo policy store check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

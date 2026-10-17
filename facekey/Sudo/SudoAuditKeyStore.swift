//
//  SudoAuditKeyStore.swift
//  facekey
//
//  Keychain-backed audit key: created on first use, readable only while unlocked.
//

import Foundation
import Security

/// Audit key in the Keychain, available while the Mac is unlocked; created on first use.
struct SudoAuditKeyStore: SudoAuditKeyProviding {
    static let account = "sudoAuditKey"

    func auditKey() -> Data? {
        do {
            let data = try KeychainManager.read(account: Self.account)
            guard data.count == 32 else { return nil }
            return data
        } catch KeychainError.itemNotFound {
            return createNewKey()
        } catch {
            // Locked Mac or other read failure: never overwrite the stored key.
            return nil
        }
    }

    private func createNewKey() -> Data? {
        var key = Data(count: 32)
        let generated = key.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base.assumingMemoryBound(to: UInt8.self)) == errSecSuccess
        }
        guard generated else { return nil }
        // Add-only: `KeychainManager.save` would update in place and let a concurrent first use replace the key.
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainManager.service,
            kSecAttrAccount as String: Self.account,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ] as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { return nil }
        // Re-read: a duplicate means another first use won, so return the stored key.
        guard let stored = try? KeychainManager.read(account: Self.account), stored.count == 32 else { return nil }
        return stored
    }
}

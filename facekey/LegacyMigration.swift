//
//  LegacyMigration.swift
//  facekey
//
//  One-time carry-over of data created under the former "glance" name (bundle id `com.jonathan.glance`): the Touch ID-gated
//  session key and password blob in the keychain, the encrypted face store, and preferences. Legacy data is copied, never
//  moved or deleted, so a failed or interrupted run loses nothing. If the legacy keychain items can't be read (e.g. they were
//  written by a differently signed build), nothing changes and the app starts as a fresh install.
//

import Foundation
import LocalAuthentication
import OSLog

enum LegacyMigration {
    private static let log = Logger(subsystem: "com.fparrav.facekey", category: "migration")

    private static let legacyService = "com.jonathan.glance"
    private static let legacyDirectoryName = "glance"
    private static let currentDirectoryName = "facekey"

    // Keychain accounts owned by `SecureCredentialManager` (private there); the on-disk file by `SecureFaceStore`.
    private static let sessionKeyAccount = "sessionKey"
    private static let passwordBlobAccount = "encryptedPassword"
    private static let preferencesMigratedKey = "legacyPreferencesMigrated"

    /// Runs before anything reads the store (from `applicationWillFinishLaunching`). Blocking: may show one Touch ID prompt
    /// when legacy keychain data exists. Never throws — every failure is logged and leaves legacy data intact.
    static func runIfNeeded() {
        migratePreferences()
        migrateSecureData()
    }

    // MARK: - Preferences

    private static func migratePreferences() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: preferencesMigratedKey) else { return }
        defer { defaults.set(true, forKey: preferencesMigratedKey) }
        guard let legacy = defaults.persistentDomain(forName: legacyService) else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        log.info("Migrated \(legacy.count) preference keys from the legacy domain")
    }

    // MARK: - Keychain + encrypted store

    private static func migrateSecureData() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let legacyDirectory = appSupport.appendingPathComponent(legacyDirectoryName, isDirectory: true)
        let currentDirectory = appSupport.appendingPathComponent(currentDirectoryName, isDirectory: true)

        guard fileManager.fileExists(atPath: legacyDirectory.path) || KeychainManager.exists(account: sessionKeyAccount, service: legacyService) else { return }
        // A session key already under the new service means this build owns the data (or a previous run finished).
        guard !KeychainManager.exists(account: sessionKeyAccount) else { return }
        guard KeychainManager.exists(account: sessionKeyAccount, service: legacyService) else {
            // Face store without its key is unreadable ciphertext; leave it alone and start fresh.
            return
        }

        do {
            let context = LAContext()
            context.localizedReason = "Carry your existing face unlock setup over to Facekey"
            let key = try KeychainManager.read(account: sessionKeyAccount, service: legacyService, context: context)
            let access = try KeychainManager.makeUserPresenceAccessControl()
            try KeychainManager.save(account: sessionKeyAccount, data: key, accessControl: access)

            if KeychainManager.exists(account: passwordBlobAccount, service: legacyService),
               !KeychainManager.exists(account: passwordBlobAccount),
               let blob = try? KeychainManager.read(account: passwordBlobAccount, service: legacyService) {
                try KeychainManager.save(account: passwordBlobAccount, data: blob)
            }

            try copyMissingItems(from: legacyDirectory, to: currentDirectory)
            log.info("Migrated legacy keychain items and face store")
        } catch {
            log.error("Legacy migration skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Copies each entry of `source` that doesn't exist in `destination`, creating `destination` if needed. A missing
    /// `source` is a no-op. Existing destination entries are never overwritten.
    static func copyMissingItems(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fileManager.contentsOfDirectory(atPath: source.path) {
            let target = destination.appendingPathComponent(item)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            try fileManager.copyItem(at: source.appendingPathComponent(item), to: target)
        }
    }
}

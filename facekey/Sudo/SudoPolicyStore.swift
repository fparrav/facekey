//
//  SudoPolicyStore.swift
//  facekey
//
//  Loads and saves the stored per-app sudo policy as encrypted JSON,
//  keyed by the session cipher so it can be tested without Keychain.
//

import Foundation

/// Seam over the session-bound encryption so stores can be tested without Keychain.
protocol SudoSessionCipher {
    var isSessionUnlocked: Bool { get }
    func encrypt(_ data: Data) throws -> Data
    func decrypt(_ data: Data) throws -> Data
}

enum SudoPolicyStoreError: Error, Equatable { case sessionLocked }

struct SudoPolicyStore {
    let fileURL: URL
    let cipher: SudoSessionCipher

    init(fileURL: URL, cipher: SudoSessionCipher) {
        self.fileURL = fileURL
        self.cipher = cipher
    }

    /// Missing file loads as an empty policy.
    func load() throws -> [String: SudoAppState] {
        guard cipher.isSessionUnlocked else { throw SudoPolicyStoreError.sessionLocked }
        let secret: Data
        do {
            secret = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return [:]
        }
        let clear = try cipher.decrypt(secret)
        return try JSONDecoder().decode([String: SudoAppState].self, from: clear)
    }

    func save(_ entries: [String: SudoAppState]) throws {
        guard cipher.isSessionUnlocked else { throw SudoPolicyStoreError.sessionLocked }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let clear = try encoder.encode(entries)
        let secret = try cipher.encrypt(clear)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try secret.write(to: fileURL, options: .atomic)
    }
}

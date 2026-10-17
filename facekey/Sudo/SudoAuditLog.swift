//
//  SudoAuditLog.swift
//  facekey
//
//  Encrypted store of sudo approval audit entries: one AES-GCM-sealed
//  JSON blob on disk, never plaintext.
//

import Foundation
import CryptoKit

/// Supplies the audit key bytes (32 bytes), or nil when no key is available.
protocol SudoAuditKeyProviding {
    func auditKey() -> Data?
}

enum SudoAuditLogError: Error, Equatable { case noKey }

struct SudoAuditLog {
    static let maxEntries = 500

    let fileURL: URL
    let keys: SudoAuditKeyProviding

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(fileURL: URL, keys: SudoAuditKeyProviding) {
        self.fileURL = fileURL
        self.keys = keys
    }

    /// A key that is not exactly 32 bytes counts as no key.
    private var key: SymmetricKey? {
        guard let data = keys.auditKey(), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    func append(_ entry: SudoAuditEntry) throws {
        guard let key = key else { throw SudoAuditLogError.noKey }
        var entries = try readEntries(key: key)
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        try write(entries, key: key)
    }

    func entriesNewestFirst() throws -> [SudoAuditEntry] {
        guard let key = key else { throw SudoAuditLogError.noKey }
        return Array(try readEntries(key: key).reversed())
    }

    /// Removes the file if present; a missing file is a no-op, no key needed.
    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    /// A missing file reads as an empty log; other read, decrypt, or
    /// decode errors propagate.
    private func readEntries(key: SymmetricKey) throws -> [SudoAuditEntry] {
        let secret: Data
        do {
            secret = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        let box = try AES.GCM.SealedBox(combined: secret)
        let clear = try AES.GCM.open(box, using: key)
        return try Self.decoder.decode([SudoAuditEntry].self, from: clear)
    }

    private func write(_ entries: [SudoAuditEntry], key: SymmetricKey) throws {
        let clear = try Self.encoder.encode(entries)
        let box = try AES.GCM.seal(clear, using: key)
        // Non-nil after a successful seal; noKey is the only reported case.
        guard let blob = box.combined else { throw SudoAuditLogError.noKey }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try blob.write(to: fileURL, options: .atomic)
    }
}

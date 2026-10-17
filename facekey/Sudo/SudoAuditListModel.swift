//
//  SudoAuditListModel.swift
//  facekey
//
//  The audit history the Settings page shows: entries newest first, and a clear
//  that only works while the session is unlocked. Foundation only.
//

import Foundation

enum SudoAuditListError: Error, Equatable { case sessionLocked }

struct SudoAuditListModel {
    let log: SudoAuditLog
    let isSessionUnlocked: () -> Bool

    func entries() throws -> [SudoAuditEntry] {
        try log.entriesNewestFirst()
    }

    func clear() throws {
        guard isSessionUnlocked() else { throw SudoAuditListError.sessionLocked }
        try log.clear()
    }
}

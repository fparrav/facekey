//
//  SudoAuditEntry.swift
//  facekey
//
//  Audit record for a sudo approval request: who asked, how the match went,
//  and how it ended. Never log appName or command via os_log or print;
//  they are user-visible text only. Foundation only.
//

import Foundation

enum SudoAuditOutcome: String, Codable, CaseIterable {
    /// Approved after the user tapped Accept and the face matched.
    case approved
    /// Cancelled by the user.
    case cancelled
    /// The approval window ran out of time.
    case timedOut
    /// Face did not match the enrolled one.
    case notMatched
    /// Rejected by policy (app blocked).
    case declinedPolicy
    /// Rejected because the session is locked.
    case declinedLocked
    /// Rejected because the requester is unknown.
    case declinedUnknown
}

/// Do not write appName or command to os_log or print; they belong in the
/// audit store only.
struct SudoAuditEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var time: Date
    var appName: String
    var displaySetup: String
    var outcome: SudoAuditOutcome
    var similarity: Float?
    var liveness: Float?
    /// Already shortened by whoever creates the entry.
    var command: String
    var clickSource: String?

    init(id: UUID = UUID(),
         time: Date = Date(),
         appName: String,
         displaySetup: String,
         outcome: SudoAuditOutcome,
         similarity: Float? = nil,
         liveness: Float? = nil,
         command: String,
         clickSource: String? = nil) {
        self.id = id
        self.time = time
        self.appName = appName
        self.displaySetup = displaySetup
        self.outcome = outcome
        self.similarity = similarity
        self.liveness = liveness
        self.command = command
        self.clickSource = clickSource
    }
}

//
//  SudoAppPolicy.swift
//  facekey
//
//  Maps a resolved app identity to a sudo decision using the stored
//  per-app state; unknown apps default to asking the user.
//

import Foundation

enum SudoAppState: String, Codable { case allowed, blocked }

enum SudoPolicyDecision: Equatable {
    /// Stored entry says allowed: continue without prompting.
    case proceed
    /// Stored entry says blocked: refuse outright.
    case decline
    /// No stored entry: ask the user.
    case askToAllow
}

enum SudoAppPolicy {
    /// The key includes kind, identifier and team id, so a copy of the app
    /// signed differently does not inherit the stored entry.
    static func decision(for identity: SudoAppIdentity, entries: [String: SudoAppState]) -> SudoPolicyDecision {
        switch entries[identity.key] {
        case .allowed: return .proceed
        case .blocked: return .decline
        case nil: return .askToAllow
        }
    }
}

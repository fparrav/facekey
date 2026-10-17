//
//  SudoAppListModel.swift
//  facekey
//
//  The per-app sudo allow/block list the Settings page shows: reads the stored
//  policy as rows and edits it, refusing every change while the session is locked.
//  Foundation only.
//

import Foundation

struct SudoAppListEntry: Identifiable, Equatable {
    let key: String
    let kind: SudoAppIdentity.Kind
    let identifier: String
    let teamID: String?
    var state: SudoAppState

    var id: String { key }

    /// A signed app is named by its bundle identifier; an unsigned one only has a code hash, so it is shortened.
    var title: String {
        switch kind {
        case .signed: return identifier
        case .unsigned: return String(identifier.prefix(12))
        }
    }

    /// Parses a policy key (`kind|identifier|team`); nil when it is not one this app wrote.
    init?(key: String, state: SudoAppState) {
        let parts = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let kind = SudoAppIdentity.Kind(rawValue: parts[0]), !parts[1].isEmpty else { return nil }
        self.key = key
        self.kind = kind
        self.identifier = parts[1]
        self.teamID = parts[2] == "-" ? nil : parts[2]
        self.state = state
    }
}

struct SudoAppListModel {
    let store: SudoPolicyStore

    var isLocked: Bool { !store.cipher.isSessionUnlocked }

    /// Rows sorted by name; stored keys that do not parse are left out.
    func entries() throws -> [SudoAppListEntry] {
        try store.load()
            .compactMap { SudoAppListEntry(key: $0.key, state: $0.value) }
            .sorted { lhs, rhs in
                let order = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                return order == .orderedSame ? lhs.key < rhs.key : order == .orderedAscending
            }
    }

    func setState(_ state: SudoAppState, forKey key: String) throws {
        var stored = try store.load()
        stored[key] = state
        try store.save(stored)
    }

    func remove(key: String) throws {
        var stored = try store.load()
        guard stored.removeValue(forKey: key) != nil else { return }
        try store.save(stored)
    }
}

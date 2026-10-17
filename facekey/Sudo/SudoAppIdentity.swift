//
//  SudoAppIdentity.swift
//  facekey
//
//  Resolves the identity of the GUI app asking for sudo approval from a
//  process chain: finds the first regular app, then reads its signing code
//  to classify it as signed (identifier + team id) or unsigned (cdhash).
//

import Foundation
import AppKit
import Security

struct SudoAppIdentity: Codable, Hashable {
    enum Kind: String, Codable { case signed, unsigned }
    var kind: Kind
    var identifier: String   // signing identifier when signed, hex code directory hash when unsigned
    var teamID: String?
    var displayName: String
    /// Stable policy key: kind, identifier and team id.
    var key: String { "\(kind.rawValue)|\(identifier)|\(teamID ?? "-")" }
}

enum SudoAppIdentityResolver {
    /// `pids` are ordered nearest parent first. Returns the identity of the first pid that is a regular GUI app, or nil.
    static func identity(forChain pids: [Int32]) -> SudoAppIdentity? {
        for pid in pids {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular else { continue }
            return identity(for: app, pid: pid)
        }
        return nil
    }

    /// Signed when the running code is valid under "anchor apple generic" and has
    /// an identifier; otherwise unsigned keyed by cdhash; nil when no cdhash is
    /// available.
    private static func identity(for app: NSRunningApplication, pid: Int32) -> SudoAppIdentity? {
        let info = signingInfo(pid: pid)
        // Apple's own apps have no team id; they still anchor to Apple, so only valid + identifier is required.
        let signed = (info?.valid ?? false) && (info?.identifier != nil)
        let identifier = signed ? info?.identifier : info?.cdhash
        guard let identifier else { return nil }
        return SudoAppIdentity(
            kind: signed ? .signed : .unsigned,
            identifier: identifier,
            teamID: signed ? info?.teamID : nil,
            displayName: app.localizedName ?? identifier
        )
    }

    /// Reads identifier, team id and cdhash from the static code; the running code
    /// is validated against it above.
    private static func signingInfo(pid: Int32) -> (identifier: String?, teamID: String?, cdhash: String?, valid: Bool)? {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code) == errSecSuccess,
              let code else { return nil }

        // Checked on the running code, so a binary replaced on disk after launch fails here.
        var requirement: SecRequirement?
        SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement)
        let valid = requirement != nil
            && SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return (nil, nil, nil, valid) }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info else { return (nil, nil, nil, valid) }

        let dict = info as NSDictionary
        let identifier = dict[kSecCodeInfoIdentifier as String] as? String
        let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let cdhash = (dict[kSecCodeInfoUnique as String] as? Data).map(hex)
        return (identifier, teamID, cdhash, valid)
    }

    /// Lowercase hex of a code directory hash.
    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

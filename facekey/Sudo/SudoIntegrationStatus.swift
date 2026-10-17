//
//  SudoIntegrationStatus.swift
//  facekey
//
//  What is installed for sudo approval, read from the two files the installer writes:
//  the PAM module and the marked block in sudo_local. Foundation only.
//

import Foundation

enum SudoIntegrationState: Equatable {
    /// Neither the module nor the sudo_local entry is there.
    case notInstalled
    /// Module and entry are there and the module is the bundled version.
    case installed
    /// The module is there but sudo_local has no entry (a macOS update can drop it).
    case missingEntry
    /// The entry is there but the module is missing or is not the bundled version.
    case outdatedModule
}

enum SudoIntegrationStatus {
    static let modulePath = "/usr/local/lib/pam/pam_facekey.so"
    static let sudoLocalPath = "/etc/pam.d/sudo_local"

    private static let beginMarker = "# BEGIN facekey"
    private static let endMarker = "# END facekey"
    private static let versionPrefix = "# facekey-version: "

    private struct Entry {
        let version: String?
    }

    /// `root` prefixes both paths (empty for the real system); `bundledVersion` is what the
    /// installer would write as the block's version for the module shipped in the app.
    static func evaluate(root: String = "", bundledVersion: String) -> SudoIntegrationState {
        let moduleExists = FileManager.default.fileExists(atPath: root + modulePath)
        guard let block = entryBlock(in: root + sudoLocalPath) else {
            return moduleExists ? .missingEntry : .notInstalled
        }
        guard moduleExists, block.version == bundledVersion else { return .outdatedModule }
        return .installed
    }

    /// The first complete marked block that points at the module, with the version it records.
    private static func entryBlock(in path: String) -> Entry? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var inBlock = false
        var version: String?
        var pointsAtModule = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line == beginMarker {
                inBlock = true
                version = nil
                pointsAtModule = false
            } else if line == endMarker, inBlock {
                if pointsAtModule { return Entry(version: version) }
                inBlock = false
            } else if inBlock {
                if line.hasPrefix(versionPrefix) {
                    version = String(line.dropFirst(versionPrefix.count))
                } else {
                    let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                    if fields.count == 3, fields[0] == "auth", fields[2] == modulePath { pointsAtModule = true }
                }
            }
        }
        return nil
    }
}

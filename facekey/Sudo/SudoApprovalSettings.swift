//
//  SudoApprovalSettings.swift
//  facekey
//
//  Per-display-setup on/off for sudo approval, plus the audit-command
//  storage flag. Everything defaults to off.
//

import Foundation

/// Per-display-setup on/off for sudo approval, plus the audit-command storage flag. Everything defaults to off.
struct SudoApprovalSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isEnabled(for context: DisplayContext) -> Bool {
        defaults.bool(forKey: key(for: context))
    }

    func setEnabled(_ enabled: Bool, for context: DisplayContext) {
        defaults.set(enabled, forKey: key(for: context))
    }

    var storesExecutableOnly: Bool {
        get { defaults.bool(forKey: "sudoApproval.storesExecutableOnly") }
        nonmutating set { defaults.set(newValue, forKey: "sudoApproval.storesExecutableOnly") }
    }

    private func key(for context: DisplayContext) -> String {
        switch context {
        case .builtInOnly: return "sudoApproval.enabled.builtInOnly"
        case .builtInAndExternal: return "sudoApproval.enabled.builtInAndExternal"
        case .externalOnly: return "sudoApproval.enabled.externalOnly"
        }
    }
}

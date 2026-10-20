//
//  PasswordsUnlockSettings.swift
//  facekey
//
//  Per-display-setup on/off for unlocking Passwords. Everything defaults to off.
//

import Foundation

/// Per-display-setup on/off for unlocking Passwords. Everything defaults to off.
struct PasswordsUnlockSettings {
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

    private func key(for context: DisplayContext) -> String {
        switch context {
        case .builtInOnly: return "passwordsUnlock.enabled.builtInOnly"
        case .builtInAndExternal: return "passwordsUnlock.enabled.builtInAndExternal"
        case .externalOnly: return "passwordsUnlock.enabled.externalOnly"
        }
    }
}

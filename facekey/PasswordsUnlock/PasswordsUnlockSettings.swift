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

    /// Whether the browser surfaces (the AutoFill popup and Safari's lock sheet) may be unlocked too. One switch for
    /// every display setup, off by default; it only takes effect where `isEnabled(for:)` is true for the current setup.
    /// The key keeps the name from when the popup was the only surface.
    var isBrowserEnabled: Bool {
        get { defaults.bool(forKey: Self.popupKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.popupKey) }
    }

    static let popupKey = "passwordsUnlock.autofillPopup.enabled"

    private func key(for context: DisplayContext) -> String {
        switch context {
        case .builtInOnly: return "passwordsUnlock.enabled.builtInOnly"
        case .builtInAndExternal: return "passwordsUnlock.enabled.builtInAndExternal"
        case .externalOnly: return "passwordsUnlock.enabled.externalOnly"
        }
    }
}

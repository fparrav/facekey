//
//  PasswordsUnlockLiveAdapters.swift
//  facekey
//
//  Live implementations of the small seams `PasswordsUnlockCoordinator` depends on: the
//  display setup, the Accessibility and focus facts, the stored Mac password and the
//  keystroke injector. None of them logs, and the password is only ever held in a
//  `SecretBytes` or in a `Data` copy that is zeroed right after use.
//

import Foundation

@MainActor
final class PasswordsUnlockLiveSetup: PasswordsUnlockSetupProviding {
    private let settings: PasswordsUnlockSettings

    init(settings: PasswordsUnlockSettings = PasswordsUnlockSettings()) {
        self.settings = settings
    }

    var setupName: String {
        switch DisplayContext.current() {
        case .builtInOnly: return "Built-in display"
        case .builtInAndExternal: return "Built-in and external displays"
        case .externalOnly: return "External display only"
        }
    }

    var isUnlockEnabled: Bool { settings.isEnabled(for: DisplayContext.current()) }

    var isBrowserUnlockEnabled: Bool { settings.isBrowserEnabled }
}

/// Reads Accessibility and the lock signal fresh every time, so the answer is the state at the
/// moment the password is about to be read or the next batch typed.
struct LivePasswordsFocusChecker: PasswordsFocusChecking {
    private let reader: LivePasswordsAXReader
    private let allowedFocusOwners: Set<String>?

    init(surface: PasswordsSurface = .app) {
        reader = LivePasswordsAXReader(surface: surface)
        allowedFocusOwners = surface.allowedFocusOwners
    }

    var isAccessibilityTrusted: Bool { KeystrokeInjector.isAccessibilityTrusted() }

    func isPasswordsLockedAndFocused() -> Bool {
        PasswordsLockClassifier.state(for: reader.read(), allowedFocusOwners: allowedFocusOwners) == .locked
    }

    func isPasswordsAtUsePasswordChoice() -> Bool {
        PasswordsLockClassifier.state(for: reader.read(), allowedFocusOwners: allowedFocusOwners) == .lockedChoice
    }

    func pressUsePassword() -> Bool {
        reader.pressUsePasswordButton()
    }
}

struct LivePasswordsCredentialReader: PasswordsCredentialReading {
    func readPassword() throws -> SecretBytes {
        var data = try SecureCredentialManager.readPassword()
        defer { data.resetBytes(in: 0..<data.count) }
        return SecretBytes(copying: data)
    }
}

struct LiveKeystrokeTyper: KeystrokeTyping {
    func typeAndReturn(_ password: SecretBytes, shouldContinue: @Sendable () -> Bool) throws {
        var data = password.makeData()
        defer { data.resetBytes(in: 0..<data.count) }
        do {
            try KeystrokeInjector.typeAndReturn(data, shouldContinue: shouldContinue)
        } catch KeystrokeError.cancelled {
            throw KeystrokeTypingCancelled()
        }
    }
}

//
//  SecuritySettingsPage.swift
//  facekey
//

import SwiftUI

struct SecuritySettingsPage: View {
    let environment: AppEnvironment

    @Bindable private var settings = FacekeySettings.shared
    @State private var statusMessage: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SudoSettingsPage(environment: environment)

            if environment.pocController.isSessionUnlocked {
                PostUnlockVerificationSection()
                SessionSecuritySection(
                    autoLockInterval: Binding(
                        get: { settings.autoLockInterval },
                        set: { settings.autoLockInterval = $0 }
                    ),
                    autoUnlockSession: Binding(
                        get: { settings.autoUnlockSession },
                        set: setAutoUnlock
                    )
                )

                if let statusMessage {
                    SettingsCaption(text: statusMessage)
                }
            } else {
                SettingsCaption(text: "Unlock the session to change these settings.")
            }
        }
    }

    /// Skips Touch ID by keeping the session key in the Keychain without the user-presence gate, so anything running as you can
    /// request it (macOS asks you to allow it). Turning it off puts the gate back.
    private func setAutoUnlock(_ enabled: Bool) {
        do {
            try SecureCredentialManager.setSessionKeyGated(!enabled)
            settings.autoUnlockSession = enabled
            statusMessage = enabled
                ? "Facekey will unlock itself at launch. Touch ID is no longer required."
                : "Touch ID is required again to unlock the session."
        } catch {
            statusMessage = "Couldn't change it: \(error.localizedDescription)"
        }
    }
}

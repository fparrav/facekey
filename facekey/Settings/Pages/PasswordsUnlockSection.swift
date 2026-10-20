//
//  PasswordsUnlockSection.swift
//  facekey
//
//  Unlocking Passwords: picks the display setups where Facekey answers,
//  states the risk next to the toggles, and flags missing Accessibility.
//

import SwiftUI

struct PasswordsUnlockSection: View {
    @State private var enabledBuiltInOnly = false
    @State private var enabledBuiltInAndExternal = false
    @State private var enabledExternalOnly = false
    @State private var accessibilityTrusted = false

    private let settings = PasswordsUnlockSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsSectionTitle(text: "Unlock Passwords")
            displayGroup
            SettingsCaption(text: "When Passwords is in front and locked, Facekey asks you to accept and checks your face before typing your Mac password. With this off for the current display setup, Passwords asks for Touch ID or your password as usual.")
            SettingsCaption(text: "Face match is weaker than Touch ID. Anyone who passes the face check and clicks Accept can open everything in the Passwords app. Facekey only types into Passwords, and only after you click Accept.")

            if !accessibilityTrusted {
                SettingsCaption(text: "Accessibility access is missing. Without it Facekey can not type into Passwords. Grant it in the Permissions section of the App page.")
            }
        }
        .onAppear(perform: reload)
    }

    // MARK: - Display setups

    private var displayGroup: some View {
        SettingsGroup {
            displayRow(title: "Built-in display", isOn: $enabledBuiltInOnly, context: .builtInOnly)
            SettingsGroupDivider()
            displayRow(title: "Built-in + external display", isOn: $enabledBuiltInAndExternal, context: .builtInAndExternal)
            SettingsGroupDivider()
            displayRow(title: "External display", isOn: $enabledExternalOnly, context: .externalOnly)
        }
    }

    private func displayRow(title: LocalizedStringKey, isOn: Binding<Bool>, context: DisplayContext) -> some View {
        SettingsRowContent(title: title) {
            FacekeyToggle(isOn: Binding(
                get: { isOn.wrappedValue },
                set: { newValue in
                    isOn.wrappedValue = newValue
                    settings.setEnabled(newValue, for: context)
                }
            ))
        }
    }

    private func reload() {
        enabledBuiltInOnly = settings.isEnabled(for: .builtInOnly)
        enabledBuiltInAndExternal = settings.isEnabled(for: .builtInAndExternal)
        enabledExternalOnly = settings.isEnabled(for: .externalOnly)
        accessibilityTrusted = KeystrokeInjector.isAccessibilityTrusted()
    }
}

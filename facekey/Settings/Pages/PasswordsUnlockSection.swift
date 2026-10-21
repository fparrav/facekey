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
    @State private var popupEnabled = false
    @State private var accessibilityTrusted = false

    private let settings = PasswordsUnlockSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsSectionTitle(text: "Unlock Passwords")
            displayGroup
            SettingsCaption(text: "When Passwords is in front and locked, Facekey asks you to accept and checks your face before typing your Mac password. With this off for the current display setup, Passwords asks for Touch ID or your password as usual.")
            SettingsCaption(text: "Face match is weaker than Touch ID. Anyone who passes the face check and clicks Accept can open everything in the Passwords app. Facekey only types into Passwords, and only after you click Accept.")

            popupGroup
            SettingsCaption(text: "Browsers ask for Passwords in two places: an AutoFill popup drawn by a system service, and a \"Passwords is locked\" sheet inside the Safari window. With this on, Facekey types your Mac password into the password field of either one after you accept and your face matches, only while it is showing and its field has the focus. A web page can make them appear, but it can not accept for you.")

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

    private var popupGroup: some View {
        SettingsGroup {
            SettingsRowContent(title: "Also unlock Passwords in the browser") {
                FacekeyToggle(isOn: Binding(
                    get: { popupEnabled },
                    set: { newValue in
                        popupEnabled = newValue
                        settings.isBrowserEnabled = newValue
                    }
                ))
            }
        }
        .opacity(anyDisplayEnabled ? 1 : 0.5)
        .disabled(!anyDisplayEnabled)
    }

    /// The popup switch only takes effect where Unlock Passwords is on, so it is dimmed while all three are off.
    private var anyDisplayEnabled: Bool {
        enabledBuiltInOnly || enabledBuiltInAndExternal || enabledExternalOnly
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
        popupEnabled = settings.isBrowserEnabled
        accessibilityTrusted = KeystrokeInjector.isAccessibilityTrusted()
    }
}

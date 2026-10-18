//
//  ActiveWhenSection.swift
//  facekey
//

import SwiftUI

struct ActiveWhenSection: View {
    @Bindable private var settings = FacekeySettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Active when")
            SettingsGroup {
                SettingsRowContent(title: "Built-in only") {
                    FacekeyToggle(isOn: $settings.isFaceUnlockEnabledBuiltInOnly)
                }
                SettingsGroupDivider()
                SettingsRowContent(title: "Built-in + external") {
                    FacekeyToggle(isOn: $settings.isFaceUnlockEnabledBuiltInAndExternal)
                }
                SettingsGroupDivider()
                SettingsRowContent(title: "External only") {
                    FacekeyToggle(isOn: $settings.isFaceUnlockEnabledExternalOnly)
                }
            }
        }
    }
}

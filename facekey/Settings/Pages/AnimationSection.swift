//
//  AnimationSection.swift
//  facekey
//

import SwiftUI

struct AnimationSection: View {
    @Bindable private var settings = FacekeySettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Animation")
            SettingsGroup {
                SettingsRowContent(title: "Show animation") {
                    FacekeyToggle(isOn: $settings.showUnlockAnimation)
                }
                SettingsGroupDivider()
                UnlockAnimationPicker(
                    selection: $settings.unlockAnimationStyle,
                    isEnabled: settings.showUnlockAnimation
                )
            }
        }
    }
}

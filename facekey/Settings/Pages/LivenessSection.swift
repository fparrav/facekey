import SwiftUI

struct LivenessSection: View {
    @Bindable private var settings = FacekeySettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Liveness")
            SettingsGroup {
                SettingsRowContent(
                    title: "Liveness detection",
                    subtitle: "Checks that you're a live person, not a photo. May increase unlock time.",
                    subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                ) {
                    FacekeyToggle(isOn: $settings.livenessChecksEnabled)
                }
                SettingsGroupDivider()
                LivenessModePicker(
                    selection: $settings.livenessMode,
                    isEnabled: settings.livenessChecksEnabled
                )
            }
        }
    }
}

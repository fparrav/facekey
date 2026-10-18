import SwiftUI

struct PostUnlockVerificationSection: View {
    @Bindable private var settings = FacekeySettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "After unlock")
            SettingsGroup {
                SettingsRowContent(
                    title: "Verify my face after other unlock methods",
                    subtitle: "Checks who is at the screen after the Mac was unlocked by something other than Facekey, such as an Apple Watch, and locks it again if an unknown face is seen. It runs after the unlock and cannot stop it.",
                    subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                ) {
                    FacekeyToggle(isOn: $settings.verifyAfterExternalUnlock)
                }
            }
        }
    }
}

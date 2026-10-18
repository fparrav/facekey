//
//  AppBehaviourSection.swift
//  facekey
//

import SwiftUI

struct AppBehaviourSection: View {
    @Bindable private var settings = FacekeySettings.shared
    @Binding var launchAtLoginEnabled: Bool
    @Binding var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsGroup {
                SettingsRowContent(title: "Launch at login") {
                    FacekeyToggle(isOn: Binding(
                        get: { launchAtLoginEnabled },
                        set: { newValue in
                            launchAtLoginEnabled = newValue
                            do {
                                try LaunchAtLogin.setEnabled(newValue)
                                launchAtLoginError = nil
                            } catch {
                                launchAtLoginEnabled = !newValue
                                launchAtLoginError = error.localizedDescription
                            }
                        }
                    ))
                }
                SettingsGroupDivider()
                SettingsRowContent(title: "Show in menu bar") {
                    FacekeyToggle(isOn: $settings.showsInMenuBar)
                }
            }
            if let launchAtLoginError {
                SettingsCaption(text: LocalizedStringKey.verbatim(launchAtLoginError))
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Behaviour")
                SettingsGroup {
                    SettingsRowContent(title: "Retry on notch hover") {
                        FacekeyToggle(isOn: $settings.retryOnHover)
                    }
                    SettingsGroupDivider()
                    SettingsRowContent(title: "Auto retry once after failure") {
                        FacekeyToggle(isOn: $settings.autoRetryOnce)
                    }
                    SettingsGroupDivider()
                    SettingsRowContent(title: "Haptic feedback") {
                        FacekeyToggle(isOn: $settings.hapticFeedbackEnabled)
                    }
                    SettingsGroupDivider()
                    SettingsSteppedSliderRowContent(
                        title: "Face detection duration",
                        valueLabel: "\(settings.faceDetectionSeconds)s",
                        index: Binding(
                            get: { Double(settings.faceDetectionSeconds - FacekeySettings.faceDetectionRange.lowerBound) },
                            set: { settings.faceDetectionSeconds = FacekeySettings.faceDetectionRange.lowerBound + Int($0.rounded()) }
                        ),
                        stopCount: FacekeySettings.faceDetectionRange.count
                    )
                }
            }
        }
    }
}

//
//  UnlockTriggerSection.swift
//  facekey
//

import SwiftUI

struct UnlockTriggerSection: View {
    @Bindable private var settings = FacekeySettings.shared
    @Bindable var coordinator: FaceUnlockCoordinator
    @Binding var inputMonitoring: SpaceKeyMonitor.InputMonitoringAccess

    private var needsInputMonitoring: Bool {
        settings.unlockTriggers.contains(.onSpace) && inputMonitoring != .granted
    }

    /// Dev-only: under Xcode the reading above is Xcode's permission, not
    /// Facekey's, so it's meaningless. See `SpaceKeyMonitor.isLaunchedByXcode`.
    private var hasInheritedXcodePermission: Bool {
        settings.unlockTriggers.contains(.onSpace) && SpaceKeyMonitor.isLaunchedByXcode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsGroup {
                SettingsRowContent(title: "Enable Face Unlock") {
                    FacekeyToggle(isOn: $coordinator.isEnabled)
                }
                SettingsGroupDivider()
                UnlockTriggerPicker(selection: $settings.unlockTriggers, isEnabled: coordinator.isEnabled)
            }
            if hasInheritedXcodePermission {
                SettingsCaption(text: "Running from Xcode — permission checks resolve against Xcode’s grants, not Facekey’s, so this reading is meaningless. Launch facekey.app on its own to see the real state.")
            } else if needsInputMonitoring {
                inputMonitoringNotice()
            }
        }
    }

    /// Shown while "On space" is selected but Input Monitoring isn't granted.
    private func inputMonitoringNotice() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsCaption(text: "“On space” reads the keyboard directly to see the space key on the lock screen, which needs Accessibility — the same permission Facekey uses to type your password. Switch Facekey on under Privacy & Security → Accessibility, then quit and reopen Facekey.")
            Button("Open Accessibility settings") {
                // Covers the rare install with no Accessibility grant at all.
                SpaceKeyMonitor.requestInputMonitoringAccess()
                openSystemSettings(pane: "Privacy_Accessibility")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    inputMonitoring = SpaceKeyMonitor.inputMonitoringAccess
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(FacekeyTheme.accent)
        }
    }

    private func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}

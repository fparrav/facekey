//
//  PermissionsSection.swift
//  facekey
//

import SwiftUI

struct PermissionsSection: View {
    @Binding var accessibilityGranted: Bool
    @Binding var cameraState: CameraPermissionState
    @Binding var hasPromptedAccessibility: Bool
    let refreshPermissions: () -> Void

    var body: some View {
        // System permissions the unlock flow depends on: Accessibility
        // lets Facekey type the password, Camera lets it see your face.
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Permissions")
            SettingsGroup {
                permissionRow(
                    title: "Accessibility",
                    isGranted: accessibilityGranted,
                    reason: String(localized: "Lets Facekey type your password on the lock screen."),
                    pendingNote: String(localized: "Without it Facekey recognizes you but can't unlock. If it was granted before, remove and re-add Facekey in System Settings."),
                    buttonTitle: hasPromptedAccessibility ? "Open Settings" : "Grant"
                ) {
                    if !hasPromptedAccessibility {
                        hasPromptedAccessibility = true
                        KeystrokeInjector.promptForAccessibility()
                    } else {
                        SystemPermissions.openPane("Privacy_Accessibility")
                    }
                    refreshPermissions()
                }
                SettingsGroupDivider()
                permissionRow(
                    title: "Camera",
                    isGranted: cameraState == .granted,
                    reason: String(localized: "Lets Facekey see your face to recognize you."),
                    pendingNote: cameraState == .denied ? String(localized: "Access was denied — enable it in System Settings.") : nil,
                    buttonTitle: cameraState == .notDetermined ? "Grant" : "Open Settings"
                ) {
                    Task {
                        await SystemPermissions.requestCamera()
                        refreshPermissions()
                    }
                }
            }
        }
    }

    /// One permission row. Granted shows a status mark instead of a disabled
    /// button (which was nearly invisible); both states share one trailing
    /// width so the controls line up across rows.
    private func permissionRow(
        title: LocalizedStringKey,
        isGranted: Bool,
        reason: String,
        pendingNote: String?,
        buttonTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        SettingsRowContent(title: title, subtitle: LocalizedStringKey.verbatim(isGranted ? reason : [reason, pendingNote].compactMap { $0 }.joined(separator: " ")), subtitleMaxWidth: 250) {
            Group {
                if isGranted {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(FacekeyTheme.statusGranted)
                        Text("Granted")
                            .foregroundStyle(SettingsMetrics.textSecondary)
                    }
                    .font(.system(size: 12, weight: .semibold))
                } else {
                    Button(action: action) {
                        Text(buttonTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FacekeyTheme.onAccent)
                            .frame(width: 112)
                            .padding(.vertical, 6)
                            .background(FacekeyTheme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 112, alignment: .trailing)
        }
    }
}

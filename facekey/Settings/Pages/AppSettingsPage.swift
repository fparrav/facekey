//
//  AppSettingsPage.swift
//  facekey
//

import AppKit
import SwiftUI

struct AppSettingsPage: View {
    let environment: AppEnvironment

    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    @State private var accessibilityGranted = SystemPermissions.accessibilityGranted
    @State private var cameraState = SystemPermissions.cameraState
    @State private var hasPromptedAccessibility = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            AboutIconSection(environment: environment)
            AboutUpdatesSection(updater: environment.updater)
            AccentPickerSection()
            AppBehaviourSection(
                launchAtLoginEnabled: $launchAtLoginEnabled,
                launchAtLoginError: $launchAtLoginError
            )
            AnimationSection()
            PermissionsSection(
                accessibilityGranted: $accessibilityGranted,
                cameraState: $cameraState,
                hasPromptedAccessibility: $hasPromptedAccessibility,
                refreshPermissions: refreshPermissions
            )
        }
        // The tccd database flips without an observable notification, so poll while visible.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                refreshPermissions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    /// Re-reads the system permission states; the Permissions block renders from these values.
    private func refreshPermissions() {
        accessibilityGranted = SystemPermissions.accessibilityGranted
        cameraState = SystemPermissions.cameraState
    }
}

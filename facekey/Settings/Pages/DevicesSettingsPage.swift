//
//  DevicesSettingsPage.swift
//  facekey
//

import AppKit
import SwiftUI

struct DevicesSettingsPage: View {
    let environment: AppEnvironment

    @State private var devices: [CameraDevice] = CameraDeviceCatalog.availableDevices()
    @State private var screens: [NSScreen] = NSScreen.screens
    @Bindable private var settings = FacekeySettings.shared

    var body: some View {
        SettingsSessionGate(pocController: environment.pocController) {
            VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
                DisplayOnSection(screens: $screens)
                ActiveWhenSection()
                CameraProfileSection(
                    devices: devices,
                    defaultCameraID: $settings.defaultCameraID,
                    builtInDisplayCameraID: $settings.builtInDisplayCameraID,
                    builtInAndExternalDisplayCameraID: $settings.builtInAndExternalDisplayCameraID,
                    externalDisplayCameraID: $settings.externalDisplayCameraID
                )
                DetectionProfileSection()
                CameraPreviewSection(
                    devices: devices,
                    isSessionUnlocked: environment.pocController.isSessionUnlocked,
                    defaultCameraID: settings.defaultCameraID,
                    builtInDisplayCameraID: settings.builtInDisplayCameraID,
                    externalDisplayCameraID: settings.externalDisplayCameraID
                )
            }
        }
        // Keep the refresh action hidden while the gate displays its locked prompt.
        .preference(
            key: HeaderTrailingActionKey.self,
            value: environment.pocController.isSessionUnlocked ? HeaderAction(perform: refreshDevices) : nil
        )
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }

    private func refreshDevices() {
        devices = CameraDeviceCatalog.availableDevices()
    }
}

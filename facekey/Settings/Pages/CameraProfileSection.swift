//
//  CameraProfileSection.swift
//  facekey
//

import SwiftUI

struct CameraProfileSection: View {
    let devices: [CameraDevice]
    @Binding var defaultCameraID: String?
    @Binding var builtInDisplayCameraID: String?
    @Binding var builtInAndExternalDisplayCameraID: String?
    @Binding var externalDisplayCameraID: String?

    var body: some View {
        SettingsGroup {
            cameraPicker(title: "Default", selection: $defaultCameraID)
            SettingsGroupDivider()
            cameraPicker(title: "Built-in display", selection: $builtInDisplayCameraID)
            SettingsGroupDivider()
            cameraPicker(title: "Built-in + external display", selection: $builtInAndExternalDisplayCameraID, emptyTitle: String(localized: "Same as built-in display"))
            SettingsGroupDivider()
            cameraPicker(title: "External display", selection: $externalDisplayCameraID)
        }
    }

    private func cameraPicker(title: LocalizedStringKey, selection: Binding<String?>, emptyTitle: String = String(localized: "System default")) -> some View {
        SettingsRowContent(title: title) {
            SettingsMenuPickerPill(label: LocalizedStringKey.verbatim(cameraLabel(for: selection.wrappedValue, emptyTitle: emptyTitle))) {
                Button(emptyTitle) { selection.wrappedValue = nil }
                ForEach(devices) { device in Button(device.name) { selection.wrappedValue = device.id } }
            }
        }
    }

    private func cameraLabel(for id: String?, emptyTitle: String) -> String {
        guard let id, let device = devices.first(where: { $0.id == id }) else { return emptyTitle }
        return device.name
    }
}

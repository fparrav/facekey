//
//  DisplayOnSection.swift
//  facekey
//

import SwiftUI

struct DisplayOnSection: View {
    @Bindable private var settings = FacekeySettings.shared
    @Binding var screens: [NSScreen]

    private var displayLabel: String {
        guard let targetID = settings.preferredDisplayID else { return String(localized: "Main display") }
        if let connected = screens.first(where: { $0.stableDisplayID == targetID }) {
            return connected.localizedName
        }
        // Picked, but not currently connected — say so rather than showing
        // a bare ID or falling back to another display's name.
        guard let name = settings.preferredDisplayName else { return String(localized: "Selected display (disconnected)") }
        return String(localized: "\(name) (disconnected)")
    }

    var body: some View {
        SettingsGroup {
            SettingsRowContent(title: "Display on") {
                SettingsMenuPickerPill(label: LocalizedStringKey.verbatim(displayLabel)) {
                    Button("Main display") {
                        settings.preferredDisplayID = nil
                        settings.preferredDisplayName = nil
                    }
                    ForEach(screens.compactMap(NamedScreen.init), id: \.id) { screen in
                        Button(screen.name) {
                            settings.preferredDisplayID = screen.id
                            settings.preferredDisplayName = screen.name
                        }
                    }
                }
            }
        }
    }

    /// A connected screen with its stable ID already unwrapped, so the
    /// picker's `ForEach` doesn't need to filter/force-unwrap inline.
    private struct NamedScreen {
        let id: String
        let name: String

        init?(_ screen: NSScreen) {
            guard let id = screen.stableDisplayID else { return nil }
            self.id = id
            self.name = screen.localizedName
        }
    }
}

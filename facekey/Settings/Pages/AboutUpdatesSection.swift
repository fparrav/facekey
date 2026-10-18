//
//  AboutUpdatesSection.swift
//  facekey
//

import SwiftUI
import AppKit

struct AboutUpdatesSection: View {
    @Bindable var updater: UpdaterController

    var body: some View {
        SettingsGroup {
            if updater.isConfigured {
                SettingsActionRowContent(
                    title: "Check for Updates",
                    buttonTitle: "Check",
                    isEnabled: updater.canCheckForUpdates
                ) {
                    updater.checkForUpdates()
                }

                SettingsGroupDivider()

                SettingsRowContent(title: "Automatically check for updates") {
                    FacekeyToggle(isOn: $updater.automaticallyChecksForUpdates)
                }

                SettingsGroupDivider()
            }

            SettingsActionRowContent(
                title: "Send Feedback",
                buttonTitle: "Send"
            ) {
                if let url = URL(string: "https://github.com/fparrav/facekey/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

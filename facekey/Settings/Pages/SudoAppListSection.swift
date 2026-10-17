//
//  SudoAppListSection.swift
//  facekey
//
//  The apps Facekey remembers for sudo: allow, block or forget each one.
//

import SwiftUI

struct SudoAppListSection: View {
    let model: SudoAppListModel

    @State private var entries: [SudoAppListEntry] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsSectionTitle(text: "Apps")
                .padding(.bottom, -4)

            if entries.isEmpty {
                SettingsCaption(text: "No apps yet. Facekey asks the first time an app uses sudo.")
            } else {
                SettingsGroup {
                    ForEach(entries) { entry in
                        if entry.id != entries.first?.id {
                            SettingsGroupDivider()
                        }
                        row(for: entry)
                    }
                }
            }

            if let errorMessage {
                SettingsCaption(text: LocalizedStringKey.verbatim(errorMessage))
            }
        }
        .onAppear(perform: reload)
    }

    private func row(for entry: SudoAppListEntry) -> some View {
        SettingsRowContent(
            title: LocalizedStringKey.verbatim(entry.title),
            subtitle: entry.teamID.map { LocalizedStringKey.verbatim($0) }
        ) {
            SettingsMenuPickerPill(label: entry.state == .allowed ? "Allowed" : "Blocked") {
                Button("Allowed") { change(entry) { try model.setState(.allowed, forKey: entry.key) } }
                Button("Blocked") { change(entry) { try model.setState(.blocked, forKey: entry.key) } }
                Divider()
                Button("Remove from list") { change(entry) { try model.remove(key: entry.key) } }
            }
        }
    }

    private func change(_ entry: SudoAppListEntry, _ edit: () throws -> Void) {
        do {
            try edit()
            errorMessage = nil
        } catch {
            errorMessage = sudoErrorMessage(error)
        }
        reload()
    }

    private func reload() {
        do {
            entries = try model.entries()
        } catch {
            entries = []
            errorMessage = sudoErrorMessage(error)
        }
    }
}

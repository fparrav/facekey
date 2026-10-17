//
//  SudoSettingsPage.swift
//  facekey
//
//  Sudo approval: installs or removes the integration, picks the display setups
//  where Facekey answers, and hosts the app list and the history.
//

import SwiftUI

struct SudoSettingsPage: View {
    let environment: AppEnvironment

    @State private var state = SudoIntegrationInstaller.currentState()
    @State private var isWorking = false
    @State private var installError: String?
    @State private var enabledBuiltInOnly = false
    @State private var enabledBuiltInAndExternal = false
    @State private var enabledExternalOnly = false

    private var settings: SudoApprovalSettings { environment.sudoApproval.settings }
    private var isSessionUnlocked: Bool { environment.pocController.isSessionUnlocked }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            integrationGroup

            if let installError {
                SettingsCaption(text: LocalizedStringKey.verbatim(installError))
            }

            SettingsSectionTitle(text: "Ask for approval on")
                .padding(.bottom, -4)
            displayGroup
            SettingsCaption(text: "When sudo needs a password, Facekey asks you to accept and checks your face. With this off for the current display setup, sudo asks for your password as usual.")

            if isSessionUnlocked {
                SudoAppListSection(
                    model: SudoAppListModel(store: environment.sudoApproval.policyStore)
                )
                SudoAuditSection(
                    model: SudoAuditListModel(
                        log: environment.sudoApproval.auditLog,
                        isSessionUnlocked: { environment.pocController.isSessionUnlocked }
                    ),
                    settings: settings
                )
            } else {
                SettingsCaption(text: "Unlock the session to see the app list and the history.")
            }
        }
        .onAppear(perform: reload)
    }

    // MARK: - Integration

    private var integrationGroup: some View {
        SettingsGroup {
            SettingsRowContent(title: "Sudo integration", subtitle: stateDescription) {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else if let title = primaryActionTitle {
                    SettingsPrimaryButton(title: title, compact: true) { run { try await SudoIntegrationInstaller.install() } }
                }
            }

            if state != .notInstalled {
                SettingsGroupDivider()

                SettingsActionRowContent(
                    title: "Remove integration",
                    buttonTitle: "Remove",
                    isDestructive: true,
                    isEnabled: !isWorking
                ) { run { try await SudoIntegrationInstaller.remove() } }
            }
        }
    }

    private var stateDescription: LocalizedStringKey {
        switch state {
        case .notInstalled: return "Not installed. Installing asks for your administrator password."
        case .installed: return "Installed"
        case .missingEntry: return "The sudo entry is missing, probably after a macOS update."
        case .outdatedModule: return "The installed module is out of date."
        }
    }

    private var primaryActionTitle: LocalizedStringKey? {
        switch state {
        case .notInstalled: return "Install"
        case .installed: return nil
        case .missingEntry: return "Repair"
        case .outdatedModule: return "Update"
        }
    }

    /// One administrator prompt per action; a cancelled prompt is not an error worth showing.
    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        installError = nil
        Task {
            do {
                try await action()
            } catch SudoIntegrationInstaller.Failure.cancelled {
            } catch {
                installError = sudoErrorMessage(error)
            }
            state = SudoIntegrationInstaller.currentState()
            isWorking = false
        }
    }

    // MARK: - Display setups

    private var displayGroup: some View {
        SettingsGroup {
            displayRow(title: "Built-in display", isOn: $enabledBuiltInOnly, context: .builtInOnly)
            SettingsGroupDivider()
            displayRow(title: "Built-in + external display", isOn: $enabledBuiltInAndExternal, context: .builtInAndExternal)
            SettingsGroupDivider()
            displayRow(title: "External display", isOn: $enabledExternalOnly, context: .externalOnly)
        }
    }

    private func displayRow(title: LocalizedStringKey, isOn: Binding<Bool>, context: DisplayContext) -> some View {
        SettingsRowContent(title: title) {
            FacekeyToggle(isOn: Binding(
                get: { isOn.wrappedValue },
                set: { newValue in
                    isOn.wrappedValue = newValue
                    settings.setEnabled(newValue, for: context)
                }
            ))
        }
    }

    private func reload() {
        state = SudoIntegrationInstaller.currentState()
        enabledBuiltInOnly = settings.isEnabled(for: .builtInOnly)
        enabledBuiltInAndExternal = settings.isEnabled(for: .builtInAndExternal)
        enabledExternalOnly = settings.isEnabled(for: .externalOnly)
    }
}

/// A sentence for the Settings sections: the installer's own text, or a localized one for the stores' errors.
func sudoErrorMessage(_ error: Error) -> String {
    if let described = (error as? LocalizedError)?.errorDescription { return described }
    if error is SudoPolicyStoreError || error is SudoAuditListError { return String(localized: "Session locked") }
    if error is SudoAuditLogError { return String(localized: "The history key is not available. Unlock your Mac and try again.") }
    return String(localized: "Something went wrong.")
}

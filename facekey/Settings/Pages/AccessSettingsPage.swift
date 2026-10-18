//
//  AccessSettingsPage.swift
//  facekey
//

import OSLog
import SwiftUI

struct AccessSettingsPage: View {
    let environment: AppEnvironment

    @Bindable private var settings = FacekeySettings.shared
    @State private var inputMonitoring = SpaceKeyMonitor.inputMonitoringAccess
    @State private var statusMessage: LocalizedStringKey?

    var body: some View {
        Group {
            if !environment.pocController.hasStoredPassword {
                noPasswordState
                    .onChange(of: NotchOverlayController.shared.phase) { _, newPhase in
                        guard newPhase == .closed else { return }
                        environment.pocController.refreshCredentialStatus()
                    }
            } else {
                SettingsSessionGate(pocController: environment.pocController) {
                    VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
                        FaceSection(environment: environment)
                        UnlockTriggerSection(
                            coordinator: environment.faceUnlockCoordinator,
                            inputMonitoring: $inputMonitoring
                        )
                        MatchConfidenceSection(coordinator: environment.faceUnlockCoordinator)
                        LivenessSection()
                        PasswordSection(
                            statusMessage: statusMessage,
                            changePassword: { OnboardingController.startPasswordOnly() },
                            removePassword: removePassword
                        )
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        inputMonitoring = SpaceKeyMonitor.inputMonitoringAccess
                    }
                    .onChange(of: settings.unlockTriggers) { oldValue, newValue in
                        SpaceKeyMonitor.log.info("unlockTriggers changed: old=\(String(describing: oldValue), privacy: .public) new=\(String(describing: newValue), privacy: .public) state=\(String(describing: inputMonitoring), privacy: .public)")
                        if newValue.contains(.onSpace), !oldValue.contains(.onSpace), inputMonitoring != .granted {
                            SpaceKeyMonitor.requestInputMonitoringAccess()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                inputMonitoring = SpaceKeyMonitor.inputMonitoringAccess
                            }
                        }
                    }
                }
            }
        }
        .onAppear { environment.pocController.refreshCredentialStatus() }
    }

    private var noPasswordState: some View {
        SettingsEmptyStateView(
            icon: "lock.fill",
            message: "Set up a password",
            buttonTitle: "Set password",
            caption: statusMessage,
            action: { OnboardingController.startPasswordOnly() }
        )
    }

    /// Face samples must be deleted before the password/session key —
    /// `deletePassword()` clears the cached session key, and deleting the
    /// face store requires an unlocked session.
    private func removePassword() {
        do {
            FaceEnrollmentStore.shared.deleteAll()
            try SecureCredentialManager.deletePassword()
            settings.autoUnlockSession = false
            environment.pocController.refreshCredentialStatus()
            statusMessage = "Password and face enrollment removed."
        } catch {
            statusMessage = "Couldn't remove: \(error.localizedDescription)"
        }
    }
}

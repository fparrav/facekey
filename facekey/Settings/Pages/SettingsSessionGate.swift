//
//  SettingsSessionGate.swift
//  facekey
//

import SwiftUI

/// Keeps Settings content mounted while requiring an unlocked session to use it.
struct SettingsSessionGate<Content: View>: View {
    @Bindable var pocController: POCController
    @ViewBuilder let content: () -> Content

    @State private var isUnlocking = false
    @State private var sessionError: String?

    private var isSessionUnlocked: Bool { pocController.isSessionUnlocked }

    var body: some View {
        ZStack(alignment: .top) {
            SettingsEmptyStateView(
                icon: "lock.fill",
                message: "Session locked",
                buttonTitle: isUnlocking ? "Authenticating…" : "Unlock session",
                isButtonEnabled: !isUnlocking,
                caption: sessionError.map { LocalizedStringKey.verbatim($0) },
                action: unlock
            )
            .opacity(isSessionUnlocked ? 0 : 1)
            .allowsHitTesting(!isSessionUnlocked)
            .accessibilityHidden(isSessionUnlocked)

            content()
                .opacity(isSessionUnlocked ? 1 : 0)
                .allowsHitTesting(isSessionUnlocked)
                .accessibilityHidden(!isSessionUnlocked)
        }
        .animation(SettingsMetrics.stateTransitionAnimation, value: isSessionUnlocked)
        .onAppear { pocController.refreshCredentialStatus() }
        // The password prompt runs in the notch, outside this view's hierarchy.
        .onChange(of: NotchOverlayController.shared.phase) { _, newPhase in
            guard newPhase == .closed else { return }
            pocController.refreshCredentialStatus()
        }
    }

    private func unlock() {
        isUnlocking = true
        sessionError = nil
        Task {
            await pocController.unlockSession()
            sessionError = pocController.sessionError
            isUnlocking = false
        }
    }
}

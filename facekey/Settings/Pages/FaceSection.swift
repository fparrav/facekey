//
//  FaceSection.swift
//  facekey
//

import SwiftUI

struct FaceSection: View {
    let environment: AppEnvironment

    @Bindable private var store = FaceEnrollmentStore.shared
    @State private var identityPendingDeletion: FaceIdentity?
    @State private var writeError: String?

    private enum StateKind {
        case unreadable
        case notEnrolled
        case enrolled
    }

    private var stateKind: StateKind {
        if store.loadFailure != nil { return .unreadable }
        return store.identities.isEmpty ? .notEnrolled : .enrolled
    }

    /// The enrollment flow runs in the notch, outside this view's hierarchy.
    private var enrollmentFlowIsRunning: Bool {
        NotchOverlayController.shared.phase == .onboarding
    }

    var body: some View {
        Group {
            switch stateKind {
            case .unreadable:
                unreadableState
            case .notEnrolled:
                notEnrolledState
            case .enrolled:
                IdentitiesSection(
                    environment: environment,
                    store: store,
                    enrollmentFlowIsRunning: enrollmentFlowIsRunning,
                    identityPendingDeletion: $identityPendingDeletion,
                    writeError: $writeError
                )
            }
        }
        .onAppear { store.reloadIfUnlocked() }
        .onChange(of: NotchOverlayController.shared.phase) { _, newPhase in
            guard newPhase == .closed else { return }
            store.reloadIfUnlocked()
        }
        .confirmationDialog(
            "Delete this enrolled face?",
            isPresented: Binding(
                get: { identityPendingDeletion != nil },
                set: { if !$0 { identityPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: identityPendingDeletion
        ) { identity in
            Button("Delete", role: .destructive) { delete(identity) }
            Button("Cancel", role: .cancel) { identityPendingDeletion = nil }
        } message: { identity in
            Text("\"\(identity.name)\" will stop being recognized until you enroll them again.")
        }
    }

    /// Session open but the encrypted store didn't decrypt. Deliberately
    /// offers no enroll or delete action, since a write here could replace faces.
    private var unreadableState: some View {
        VStack(spacing: SettingsMetrics.emptyStateSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: SettingsMetrics.emptyStateIconSize, weight: .regular))
                .foregroundStyle(SettingsMetrics.qualityFairColor)

            Text("Enrolled faces couldn't be read")
                .font(SettingsMetrics.rowFont)
                .foregroundStyle(SettingsMetrics.textSecondary)

            SettingsCaption(text: store.loadFailure.map { LocalizedStringKey.verbatim($0) } ?? "The stored data couldn't be decrypted with this session key.")
                .multilineTextAlignment(.center)

            SettingsCaption(text: "Nothing has been deleted, and Facekey will not overwrite it — enrolling is blocked until this resolves. Quit and reopen Facekey to retry. If it keeps failing, the session key no longer matches this data: remove the stored password on the Access page to clear both, then set up again.")
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.emptyStateMinHeight)
    }

    private var notEnrolledState: some View {
        SettingsEmptyStateView(
            icon: "faceid",
            message: "Face enrollment",
            buttonTitle: "Set up Face Unlock",
            isButtonEnabled: !enrollmentFlowIsRunning,
            action: { OnboardingController.startEnrollmentOnly() }
        )
    }

    private func delete(_ identity: FaceIdentity) {
        do {
            try store.delete(identity)
            writeError = nil
        } catch {
            writeError = error.localizedDescription
        }
        identityPendingDeletion = nil
    }
}

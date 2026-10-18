//
//  SummarySettingsPage.swift
//  facekey
//
//  The Summary page: one readiness card (mark, headline, "N of M" pill)
//  above one card of the five setup checks, each failing check pointing at
//  the page that fixes it. Readiness itself is the pure `SetupReadiness`
//  function; this view only renders it.
//

import AppKit
import SwiftUI

struct SummarySettingsPage: View {
    let environment: AppEnvironment
    let select: (SettingsPage) -> Void

    @Bindable private var store = FaceEnrollmentStore.shared

    /// Refreshed when the app regains focus, so granting a permission in
    /// System Settings updates the checks without a relaunch.
    @State private var accessibilityGranted = SystemPermissions.accessibilityGranted
    @State private var cameraPermission = Self.readinessPermission(from: SystemPermissions.cameraState)

    /// The same soft amber the notch's warning line uses — the tone for
    /// anything not yet ready.
    private static let warningColor = Color(red: 245 / 255, green: 183 / 255, blue: 59 / 255)

    private var readiness: SetupReadiness {
        SetupReadiness(
            enrolledCount: store.identities.count,
            hasPassword: environment.pocController.hasStoredPassword,
            liveness: livenessLevel,
            hasCameraForCurrentSetup: CameraDeviceCatalog.device(for: CameraProfile.current()) != nil,
            accessibilityGranted: accessibilityGranted,
            cameraPermission: cameraPermission
        )
    }

    private var livenessLevel: ReadinessLiveness {
        let settings = FacekeySettings.shared
        guard settings.livenessChecksEnabled else { return .off }
        return settings.livenessMode == .heavy ? .heavy : .light
    }

    var body: some View {
        Group {
            if environment.pocController.hasStoredPassword {
                // Enrolled faces are encrypted under the session key, so the
                // face check is only meaningful once the session is open.
                SettingsSessionGate(pocController: environment.pocController) {
                    content
                }
            } else {
                // Without a password the session can never unlock; the
                // checklist is exactly what the user needs to see.
                content
            }
        }
        .onAppear { refresh() }
        // The tccd database flips without an observable notification, so
        // re-read the states every time the app regains focus.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            readinessCard
            // A store that fails to decrypt looks like an empty one, so say
            // so instead of letting "No face enrolled yet." stand alone.
            if store.loadFailure != nil {
                SettingsCaption(text: "Enrolled faces couldn't be read")
            }
            checksCard
        }
    }

    // MARK: - Readiness card

    private var readinessCard: some View {
        SettingsGroup {
            HStack(spacing: 12) {
                FacekeyMark(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(readiness.isReady ? LocalizedStringKey("Ready to unlock") : LocalizedStringKey("Almost ready"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SettingsMetrics.textPrimary)
                    Text("\(readiness.passedCount) of \(readiness.total) checks passed")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsMetrics.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                readinessPill
            }
            .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
            .padding(.vertical, SettingsMetrics.optionCardVerticalPadding)
        }
    }

    private var readinessPill: some View {
        Text("\(readiness.passedCount) of \(readiness.total)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(FacekeyTheme.onAccent)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                Capsule().fill(readiness.isReady ? FacekeyTheme.accent : Self.warningColor)
            )
    }

    // MARK: - Checks card

    private var checksCard: some View {
        SettingsGroup {
            ForEach(Array(readiness.checks.enumerated()), id: \.element.id) { index, check in
                if index > 0 {
                    SettingsGroupDivider()
                }
                checkRow(check)
            }
        }
    }

    /// One check row in the same shape as `SettingsRowContent` (same insets
    /// and min height, wrapping subtitle), with a status glyph leading the
    /// title and — only when failing — the button that jumps to the fix.
    private func checkRow(_ check: SetupCheck) -> some View {
        HStack(spacing: 10) {
            Image(systemName: check.passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(check.passed ? FacekeyTheme.accent : Self.warningColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(check.titleKey))
                    .font(SettingsMetrics.rowFont)
                    .foregroundStyle(SettingsMetrics.textPrimary)
                Text(LocalizedStringKey(check.detailKey))
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsMetrics.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: SettingsMetrics.rowSubtitleMaxWidth, alignment: .leading)
            }
            Spacer(minLength: 8)
            if !check.passed {
                SettingsPrimaryButton(title: "Fix", compact: true) { select(check.targetPage) }
            }
        }
        .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
        .frame(minHeight: SettingsMetrics.rowHeight)
        .padding(.vertical, 10)
    }

    // MARK: - Data

    /// Re-reads the permission states and the stored-password flag; the
    /// enrolled count and liveness level are observable values that refresh
    /// on their own.
    private func refresh() {
        accessibilityGranted = SystemPermissions.accessibilityGranted
        cameraPermission = Self.readinessPermission(from: SystemPermissions.cameraState)
        environment.pocController.refreshCredentialStatus()
    }

    private static func readinessPermission(from state: CameraPermissionState) -> ReadinessPermission {
        switch state {
        case .granted: return .granted
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        }
    }
}

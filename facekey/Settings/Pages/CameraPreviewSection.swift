//
//  CameraPreviewSection.swift
//  facekey
//

import SwiftUI

struct CameraPreviewSection: View {
    let devices: [CameraDevice]
    let isSessionUnlocked: Bool
    let defaultCameraID: String?
    let builtInDisplayCameraID: String?
    let externalDisplayCameraID: String?
    @State private var previewCamera = CameraManager()
    @State private var isPreviewShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsSectionTitle(text: "Preview")
                .padding(.bottom, -4)
            previewArea
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius))
                .overlay(RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius).strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth))
            if isPreviewShown, let error = previewCamera.errorMessage {
                SettingsCaption(text: LocalizedStringKey.verbatim(error))
            }
        }
        .onChange(of: defaultCameraID) { restartPreview() }
        .onChange(of: builtInDisplayCameraID) { restartPreview() }
        .onChange(of: externalDisplayCameraID) { restartPreview() }
        .onChange(of: isSessionUnlocked) { _, unlocked in if !unlocked { hidePreview() } }
        .onDisappear { hidePreview() }
    }

    /// Live feed, or a placeholder until "Show preview" is tapped — opening
    /// this page alone should never request camera access.
    @ViewBuilder
    private var previewArea: some View {
        if isPreviewShown {
            CameraPreviewView(session: previewCamera.session, faces: [])
        } else {
            ZStack {
                SettingsMetrics.rowColor
                SettingsPrimaryButton(title: "Show preview", action: showPreview)
            }
        }
    }

    private func showPreview() {
        isPreviewShown = true
        Task { await previewCamera.start() }
    }

    private func hidePreview() {
        guard isPreviewShown else { return }
        previewCamera.stop()
        isPreviewShown = false
    }

    /// `CameraManager` only re-resolves its device on `start()`, so restart
    /// it to reflect a new pick. No-op while hidden — picking a camera must
    /// not be what quietly turns it on.
    private func restartPreview() {
        guard isPreviewShown else { return }
        previewCamera.stop()
        Task { await previewCamera.start() }
    }
}

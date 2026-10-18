//
//  DetectionProfileSection.swift
//  facekey
//

import AVFoundation
import SwiftUI

struct DetectionProfileSection: View {
    @Bindable private var settings = FacekeySettings.shared

    @State private var selectedProfile: CameraProfile = CameraProfile.current()
    @State private var calibrator: DistanceCalibrator?

    var body: some View {
        SettingsGroup {
            SettingsRowContent(title: "Camera profile") {
                SettingsMenuPickerPill(label: LocalizedStringKey.verbatim(selectedProfile.title)) {
                    ForEach(CameraProfile.allCases) { profile in
                        Button(profile.title) { selectedProfile = profile }
                    }
                }
            }
            SettingsGroupDivider()
            DetectionDistanceSection(
                profile: selectedProfile,
                calibrationSubtitle: calibrationSubtitle,
                onCalibrate: startCalibration
            )
        }
        .sheet(item: $calibrator) { calibrator in
            DistanceCalibrationSheet(
                calibrator: calibrator,
                onAccept: { threshold, cameraID in
                    settings.setMinimumFaceWidth(threshold, origin: .calibrated, cameraID: cameraID, for: calibrator.profile)
                    self.calibrator = nil
                },
                onCancel: { self.calibrator = nil }
            )
        }
    }

    /// Origin of the stored width, plus a warning when the calibrated camera
    /// no longer matches or no camera is usable.
    private var calibrationSubtitle: String {
        let label: String
        switch settings.detectionDistanceOrigin(for: selectedProfile) {
        case .manual:
            label = String(localized: "Manual.")
        case .calibrated:
            let currentID = CameraDeviceCatalog.device(for: selectedProfile)?.uniqueID
            if settings.calibratedCameraID(for: selectedProfile) != currentID {
                label = String(localized: "Camera changed, recalibrate.")
            } else {
                let name = CameraDeviceCatalog.availableDevices().first { $0.id == currentID }?.name ?? String(localized: "the profile camera")
                label = String(localized: "Calibrated with \(name).")
            }
        }
        if let reason = CameraDeviceCatalog.unusableReason(for: selectedProfile) {
            return label + " " + reason
        }
        return label
    }

    // MARK: - Actions

    private func startCalibration() {
        calibrator = DistanceCalibrator(profile: selectedProfile)
    }
}

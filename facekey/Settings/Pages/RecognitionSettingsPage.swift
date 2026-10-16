//
//  RecognitionSettingsPage.swift
//  facekey
//

import AVFoundation
import SwiftUI

struct RecognitionSettingsPage: View {
    @Bindable var coordinator: FaceUnlockCoordinator
    @Bindable var pocController: POCController
    @Bindable private var settings = FacekeySettings.shared

    @State private var isUnlocking = false
    @State private var sessionError: String?
    @State private var selectedProfile: CameraProfile = CameraProfile.current()
    @State private var calibrator: DistanceCalibrator?

    /// Read from `POCController`, not a local copy — same reasoning as
    /// `PasswordSettingsPage`.
    private var isSessionUnlocked: Bool { pocController.isSessionUnlocked }

    var body: some View {
        ZStack(alignment: .top) {
            lockedState
                .opacity(isSessionUnlocked ? 0 : 1)
                .allowsHitTesting(!isSessionUnlocked)
                .accessibilityHidden(isSessionUnlocked)

            unlockedState
                .opacity(isSessionUnlocked ? 1 : 0)
                .allowsHitTesting(isSessionUnlocked)
                .accessibilityHidden(!isSessionUnlocked)
        }
        .animation(SettingsMetrics.stateTransitionAnimation, value: isSessionUnlocked)
        .onAppear { pocController.refreshCredentialStatus() }
        // Password/name/enrollment flows run in the notch, outside this
        // window, so nothing else prompts a re-check once one closes.
        .onChange(of: NotchOverlayController.shared.phase) { _, newPhase in
            guard newPhase == .closed else { return }
            pocController.refreshCredentialStatus()
        }
    }

    // MARK: - Locked

    private var lockedState: some View {
        SettingsEmptyStateView(
            icon: "lock.fill",
            message: "Session locked",
            buttonTitle: isUnlocking ? "Authenticating…" : "Unlock session",
            isButtonEnabled: !isUnlocking,
            caption: sessionError.map { LocalizedStringKey.verbatim($0) },
            action: unlock
        )
    }

    // MARK: - Unlocked

    private var unlockedState: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup {
                SettingsOptionSliderRowContent(
                    title: "Match confidence",
                    stepLabels: MatchConfidenceLevel.allCases.map(\.title),
                    index: matchConfidenceIndex,
                    stopCount: MatchConfidenceLevel.allCases.count
                )

                SettingsGroupDivider()

                SettingsRowContent(title: "Camera profile") {
                    SettingsMenuPickerPill(label: LocalizedStringKey.verbatim(selectedProfile.title)) {
                        ForEach(CameraProfile.allCases) { profile in
                            Button(profile.title) { selectedProfile = profile }
                        }
                    }
                }
                SettingsGroupDivider()

                SettingsOptionSliderRowContent(
                    title: "Detection distance",
                    stepLabels: DetectionDistanceLevel.allCases.map(\.title),
                    index: detectionDistanceIndex,
                    stopCount: DetectionDistanceLevel.allCases.count
                )

                SettingsGroupDivider()

                SettingsActionRowContent(
                    title: "Calibrate distance",
                    subtitle: LocalizedStringKey.verbatim(calibrationSubtitle),
                    buttonTitle: "Calibrate",
                    isEnabled: CameraDeviceCatalog.unusableReason(for: selectedProfile) == nil,
                    action: startCalibration
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Liveness")
                SettingsGroup {
                    SettingsRowContent(
                        title: "Liveness detection",
                        subtitle: "Checks that you're a live person, not a photo. May increase unlock time.",
                        subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                    ) {
                        FacekeyToggle(isOn: $settings.livenessChecksEnabled)
                    }
                    SettingsGroupDivider()
                    LivenessModePicker(
                        selection: $settings.livenessMode,
                        isEnabled: settings.livenessChecksEnabled
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "After unlock")
                SettingsGroup {
                    SettingsRowContent(
                        title: "Verify my face after other unlock methods",
                        subtitle: "Checks who is at the screen after the Mac was unlocked by something other than Facekey, such as an Apple Watch, and locks it again if an unknown face is seen. It runs after the unlock and cannot stop it.",
                        subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                    ) {
                        FacekeyToggle(isOn: $settings.verifyAfterExternalUnlock)
                    }
                }
            }
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

    // MARK: - Match confidence

    /// Nearest of the three snap points to whatever's stored, in case the
    /// value doesn't land exactly on one of the stops.
    private var matchConfidenceLevel: MatchConfidenceLevel {
        .nearest(to: coordinator.matchThreshold)
    }

    private var matchConfidenceIndex: Binding<Double> {
        Binding(
            get: { matchConfidenceLevel.sliderIndex },
            set: { coordinator.matchThreshold = MatchConfidenceLevel.from(sliderIndex: $0).threshold }
        )
    }

    // MARK: - Detection distance

    private var detectionDistanceLevel: DetectionDistanceLevel {
        .nearest(to: settings.minimumFaceWidth(for: selectedProfile))
    }

    private var detectionDistanceIndex: Binding<Double> {
        Binding(
            get: { detectionDistanceLevel.sliderIndex },
            set: {
                settings.setMinimumFaceWidth(
                    DetectionDistanceLevel.from(sliderIndex: $0).minimumFaceWidth,
                    origin: .manual,
                    cameraID: nil,
                    for: selectedProfile
                )
            }
        )
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

/// The three selectable points on the "Match confidence" slider — named
/// rather than exposing the raw cosine-similarity threshold directly.
private enum MatchConfidenceLevel: Int, CaseIterable {
    case lessStrict, standard, moreStrict

    var title: String {
        switch self {
        case .lessStrict: return String(localized: "Less strict")
        case .standard: return String(localized: "Default")
        case .moreStrict: return String(localized: "More strict")
        }
    }

    var threshold: Float {
        switch self {
        case .lessStrict: return 0.58
        case .standard: return 0.63
        case .moreStrict: return 0.68
        }
    }

    /// Position in `allCases` — same role as `AutoLockInterval.sliderIndex`.
    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static func from(sliderIndex: Double) -> Self {
        let clamped = Int(sliderIndex.rounded())
        return allCases.indices.contains(clamped) ? allCases[clamped] : .standard
    }

    static func nearest(to threshold: Float) -> Self {
        allCases.min { abs($0.threshold - threshold) < abs($1.threshold - threshold) } ?? .standard
    }
}

/// The three selectable points on the "Detection distance" slider.
private enum DetectionDistanceLevel: Int, CaseIterable {
    /// Six stops (~10% distance apart) so a desk setup with a large monitor can land between the old Close/Default/Far. Stored
    /// widths from the previous three stops (0.23, 0.19, 0.15) are still exact stops here. Below ~0.13 the face reaches the
    /// embedder with too few pixels, so the slider stops there.
    case closest, close, standard, far, farther, farthest

    var title: String {
        switch self {
        case .closest: return String(localized: "Closest")
        case .close: return String(localized: "Close distance", defaultValue: "Close")
        case .standard: return String(localized: "Default distance", defaultValue: "Default")
        case .far: return String(localized: "Far")
        case .farther: return String(localized: "Farther")
        case .farthest: return String(localized: "Farthest")
        }
    }

    var minimumFaceWidth: Float {
        switch self {
        case .closest: return 0.23
        case .close: return 0.21
        case .standard: return 0.19
        case .far: return 0.17
        case .farther: return 0.15
        case .farthest: return 0.13
        }
    }

    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static func from(sliderIndex: Double) -> Self {
        let clamped = Int(sliderIndex.rounded())
        return allCases.indices.contains(clamped) ? allCases[clamped] : .standard
    }

    static func nearest(to width: Float) -> Self {
        allCases.min { abs($0.minimumFaceWidth - width) < abs($1.minimumFaceWidth - width) } ?? .standard
    }
}

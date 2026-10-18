import SwiftUI

struct DetectionDistanceSection: View {
    @Bindable private var settings = FacekeySettings.shared
    let profile: CameraProfile
    let calibrationSubtitle: String
    let onCalibrate: () -> Void

    private var detectionDistanceLevel: DetectionDistanceLevel {
        .nearest(to: settings.minimumFaceWidth(for: profile))
    }

    private var detectionDistanceIndex: Binding<Double> {
        Binding(
            get: { detectionDistanceLevel.sliderIndex },
            set: {
                settings.setMinimumFaceWidth(
                    DetectionDistanceLevel.from(sliderIndex: $0).minimumFaceWidth,
                    origin: .manual,
                    cameraID: nil,
                    for: profile
                )
            }
        )
    }

    var body: some View {
        Group {
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
                isEnabled: CameraDeviceCatalog.unusableReason(for: profile) == nil,
                action: onCalibrate
            )
        }
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

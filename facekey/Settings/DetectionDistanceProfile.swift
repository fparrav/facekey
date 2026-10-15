import Foundation

enum CameraProfile: String, CaseIterable, Identifiable, Sendable {
    case builtIn
    case external

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn:
            "Built-in display"
        case .external:
            "External display"
        }
    }

    static func current() -> CameraProfile {
        DisplayContext.current() == .externalOnly ? .external : .builtIn
    }
}

enum DetectionDistanceOrigin: String, Sendable {
    case manual
    case calibrated
}

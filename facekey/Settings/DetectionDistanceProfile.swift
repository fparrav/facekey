import Foundation

enum CameraProfile: String, CaseIterable, Identifiable, Sendable {
    case builtIn
    case builtInAndExternal
    case external

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn:
            "Built-in display"
        case .builtInAndExternal:
            "Built-in + external display"
        case .external:
            "External display"
        }
    }

    static func current() -> CameraProfile {
        switch DisplayContext.current() {
        case .builtInOnly: .builtIn
        case .builtInAndExternal: .builtInAndExternal
        case .externalOnly: .external
        }
    }
}

enum DetectionDistanceOrigin: String, Sendable {
    case manual
    case calibrated
}

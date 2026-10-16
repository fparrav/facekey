import Foundation

enum CameraProfile: String, CaseIterable, Identifiable, Sendable {
    case builtIn
    case builtInAndExternal
    case external

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn:
            String(localized: "Built-in display")
        case .builtInAndExternal:
            String(localized: "Built-in + external display")
        case .external:
            String(localized: "External display")
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

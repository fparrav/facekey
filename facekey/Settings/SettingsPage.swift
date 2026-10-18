import Foundation

enum SettingsPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case summary
    case access
    case security
    case devices
    case app
    case faceLab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: return String(localized: "Summary")
        case .access: return String(localized: "Access")
        case .security: return String(localized: "Security")
        case .devices: return String(localized: "Camera and displays")
        case .app: return String(localized: "App")
        case .faceLab: return String(localized: "Face Lab")
        }
    }

    var symbolName: String {
        switch self {
        case .summary: return "checkmark.shield.fill"
        case .access: return "faceid"
        case .security: return "lock.shield.fill"
        case .devices: return "camera.fill"
        case .app: return "gearshape.fill"
        case .faceLab: return "flask"
        }
    }

    var tileHex: String {
        switch self {
        case .summary: return "#34D399"
        case .access: return "#3499FF"
        case .security: return "#F5B73B"
        case .devices: return "#8E8E93"
        case .app: return "#8E8E93"
        case .faceLab: return "#BF5AF2"
        }
    }

    static let defaultPage: SettingsPage = .summary

    static func visiblePages(includingLab: Bool) -> [SettingsPage] {
        includingLab ? allCases : allCases.filter { $0 != .faceLab }
    }
}

import Foundation

enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case green
    case lime
    case mint
    case blue
    case amber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .green:
            String(localized: "Green")
        case .lime:
            String(localized: "Lime")
        case .mint:
            String(localized: "Mint")
        case .blue:
            String(localized: "Blue")
        case .amber:
            String(localized: "Amber")
        }
    }

    var hex: String {
        switch self {
        case .green:
            "#34D399"
        case .lime:
            "#7DDC5A"
        case .mint:
            "#5EEAD4"
        case .blue:
            "#3499FF"
        case .amber:
            "#F5B73B"
        }
    }

    static let defaultChoice: AccentChoice = .green

    /// Dark ink for text on a bright accent fill.
    static let inkHex = "#0C1410"

    var inkHex: String { Self.inkHex }

    init(storedValue: String?) {
        self = storedValue.flatMap { value in Self.allCases.first { $0.rawValue == value } } ?? .green
    }
}

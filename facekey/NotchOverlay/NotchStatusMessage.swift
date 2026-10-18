import Foundation

enum NotchStatusState: Sendable {
    case scanning
    case success
    case failure
    case cameraUnavailable
    case sudoApproval
}

enum NotchStatusTone: Equatable, Sendable {
    case accent
    case failure
    case warning
}

/// The small mark drawn beside the text; each one animates in its own way.
enum NotchStatusGlyph: Equatable, Sendable {
    /// An open arc turning: something is in progress.
    case spinner
    /// The ring closes and a check draws itself.
    case check
    /// The ring closes and a cross draws itself.
    case cross
    /// A ring with an exclamation mark, breathing.
    case alert
}

struct NotchStatusMessage: Equatable, Sendable {
    let key: String
    let tone: NotchStatusTone
    let glyph: NotchStatusGlyph

    static func `for`(state: NotchStatusState, hoverRetryEnabled: Bool) -> NotchStatusMessage {
        switch state {
        case .scanning:
            NotchStatusMessage(key: "Looking for your face…", tone: .accent, glyph: .spinner)
        case .success:
            NotchStatusMessage(key: "Mac unlocked", tone: .accent, glyph: .check)
        case .failure:
            NotchStatusMessage(
                key: hoverRetryEnabled ? "Face not recognized. Hover to retry." : "Face not recognized.",
                tone: .failure,
                glyph: .cross
            )
        case .cameraUnavailable:
            NotchStatusMessage(key: "Camera unavailable", tone: .warning, glyph: .alert)
        case .sudoApproval:
            NotchStatusMessage(key: "Approve sudo with your face", tone: .accent, glyph: .spinner)
        }
    }
}

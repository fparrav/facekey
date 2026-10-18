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

struct NotchStatusMessage: Equatable, Sendable {
    let key: String
    let tone: NotchStatusTone

    static func `for`(state: NotchStatusState, hoverRetryEnabled: Bool) -> NotchStatusMessage {
        switch state {
        case .scanning:
            NotchStatusMessage(key: "Looking for your face…", tone: .accent)
        case .success:
            NotchStatusMessage(key: "Mac unlocked", tone: .accent)
        case .failure:
            NotchStatusMessage(
                key: hoverRetryEnabled ? "Face not recognized. Hover to retry." : "Face not recognized.",
                tone: .failure
            )
        case .cameraUnavailable:
            NotchStatusMessage(key: "Camera unavailable", tone: .warning)
        case .sudoApproval:
            NotchStatusMessage(key: "Approve sudo with your face", tone: .accent)
        }
    }
}

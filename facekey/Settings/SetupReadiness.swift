import Foundation

enum ReadinessLiveness: Sendable {
    case off
    case light
    case heavy
}

enum ReadinessPermission: Sendable {
    case granted
    case notDetermined
    case denied
}

enum SetupCheckID: String, CaseIterable, Sendable {
    case face
    case password
    case liveness
    case camera
    case permissions
}

struct SetupCheck: Equatable, Identifiable, Sendable {
    let id: SetupCheckID
    let passed: Bool
    let titleKey: String
    let detailKey: String
    let targetPage: SettingsPage
}

struct SetupReadiness: Equatable, Sendable {
    let checks: [SetupCheck]

    init(
        enrolledCount: Int,
        hasPassword: Bool,
        liveness: ReadinessLiveness,
        hasCameraForCurrentSetup: Bool,
        accessibilityGranted: Bool,
        cameraPermission: ReadinessPermission
    ) {
        checks = [
            SetupCheck(
                id: .face,
                passed: enrolledCount > 0,
                titleKey: "Face enrolled",
                detailKey: enrolledCount > 0 ? "Your face is enrolled." : "No face enrolled yet.",
                targetPage: .access
            ),
            SetupCheck(
                id: .password,
                passed: hasPassword,
                titleKey: "Password stored",
                detailKey: hasPassword ? "Facekey can type your password." : "No password stored yet.",
                targetPage: .access
            ),
            SetupCheck(
                id: .liveness,
                passed: liveness != .off,
                titleKey: "Liveness checks",
                detailKey: liveness != .off ? "Liveness checks are on." : "Liveness checks are off.",
                targetPage: .access
            ),
            SetupCheck(
                id: .camera,
                passed: hasCameraForCurrentSetup,
                titleKey: "Camera for this display setup",
                detailKey: hasCameraForCurrentSetup
                    ? "A camera is set for this display setup."
                    : "No camera is set for this display setup.",
                targetPage: .devices
            ),
            SetupCheck(
                id: .permissions,
                passed: accessibilityGranted && cameraPermission == .granted,
                titleKey: "Permissions",
                detailKey: accessibilityGranted && cameraPermission == .granted
                    ? "Accessibility and Camera are granted."
                    : "Accessibility or Camera access is missing.",
                targetPage: .app
            )
        ]
    }

    var passedCount: Int { checks.filter(\.passed).count }
    var total: Int { checks.count }
    var isReady: Bool { passedCount == total }
}

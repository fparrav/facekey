//
//  SystemPermissions.swift
//  facekey
//
//  Reads system permission states without prompting and routes the user to the right Privacy & Security pane.
//

import AVFoundation
import AppKit

@MainActor
enum SystemPermissions {
    /// Camera access as the system reports it (no prompt).
    static var cameraState: CameraPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    /// Accessibility access (no prompt) — delegate to KeystrokeInjector.isAccessibilityTrusted().
    static var accessibilityGranted: Bool {
        return KeystrokeInjector.isAccessibilityTrusted()
    }

    /// Shows the system camera prompt when undetermined; otherwise opens the Camera pane.
    static func requestCamera() async {
        if cameraState == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        } else {
            openPane("Privacy_Camera")
        }
    }

    /// Opens a Privacy & Security pane, e.g. "Privacy_Accessibility" or "Privacy_Camera".
    static func openPane(_ pane: String) {
        // Modern settings extension (Ventura+); fall back to the legacy scheme on older systems.
        let modern = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)"
        let legacy = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        if let url = URL(string: modern), NSWorkspace.shared.open(url) {
            return
        }
        if let url = URL(string: legacy) {
            NSWorkspace.shared.open(url)
        }
    }
}

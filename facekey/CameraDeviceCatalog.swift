//
//  CameraDeviceCatalog.swift
//  facekey
//
//  Resolves the app's camera preference (flat default, or split by built-in vs. external display) into the device to open.
//

import AVFoundation

struct CameraDevice: Identifiable, Hashable {
    let id: String // AVCaptureDevice.uniqueID
    let name: String
}

enum CameraDeviceCatalog {
    static func availableDevices() -> [CameraDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// True if the currently-active screen is the Mac's built-in display
    /// (vs. an external monitor) — used to pick between the built-in/
    /// external camera overrides.
    static func isUsingBuiltInDisplay() -> Bool {
        DisplayContext.current() != .externalOnly
    }

    /// Display-specific override, then flat default, then the system default camera.
    static func device(for profile: CameraProfile) -> AVCaptureDevice? {
        let settings = FacekeySettings.shared
        let preferredID: String? = profile == .builtIn
            ? (settings.builtInDisplayCameraID ?? settings.defaultCameraID)
            : (settings.externalDisplayCameraID ?? settings.defaultCameraID)

        if let preferredID, let device = AVCaptureDevice(uniqueID: preferredID) {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }

    /// Human-readable reason the selected profile has no usable camera right now, or nil if it does.
    static func unusableReason(for profile: CameraProfile) -> String? {
        if profile == .builtIn, ClamshellState.isClosed() {
            return "The built-in camera is covered while the lid is closed."
        }
        let access = AVCaptureDevice.authorizationStatus(for: .video)
        if access == .denied || access == .restricted {
            return "Camera access is off for Facekey in System Settings > Privacy & Security > Camera."
        }
        if device(for: profile) == nil {
            return "No camera is available for this profile."
        }
        return nil
    }

    static func resolvedDevice() -> AVCaptureDevice? {
        device(for: isUsingBuiltInDisplay() ? .builtIn : .external)
    }
}

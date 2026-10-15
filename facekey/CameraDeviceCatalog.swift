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

    /// Display-specific override (including built-in + external), then flat default, then the system default camera.
    static func device(for profile: CameraProfile) -> AVCaptureDevice? {
        let settings = FacekeySettings.shared
        let chain: [String?]
        switch profile {
        case .builtIn:
            chain = [settings.builtInDisplayCameraID, settings.defaultCameraID]
        case .builtInAndExternal:
            chain = [settings.builtInAndExternalDisplayCameraID, settings.builtInDisplayCameraID, settings.defaultCameraID]
        case .external:
            chain = [settings.externalDisplayCameraID, settings.defaultCameraID]
        }

        // First saved ID that still resolves; a stale override must not skip the rest of the chain.
        if let device = chain.compactMap({ $0 }).lazy.compactMap({ AVCaptureDevice(uniqueID: $0) }).first {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }

    /// Human-readable reason the selected profile has no usable camera right now, or nil if it does.
    static func unusableReason(for profile: CameraProfile) -> String? {
        let selected = device(for: profile)
        if ClamshellState.isClosed(), selected?.deviceType == .builtInWideAngleCamera {
            return "The built-in camera is covered while the lid is closed."
        }
        let access = AVCaptureDevice.authorizationStatus(for: .video)
        if access == .denied || access == .restricted {
            return "Camera access is off for Facekey in System Settings > Privacy & Security > Camera."
        }
        if selected == nil {
            return "No camera is available for this profile."
        }
        return nil
    }

    static func resolvedDevice() -> AVCaptureDevice? {
        device(for: CameraProfile.current())
    }
}

//
//  DistanceCalibrator.swift
//  facekey
//
//  Measures the user's face width through one camera profile's camera and turns it into a detection-distance threshold.
//

@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import Observation

@Observable
@MainActor
final class DistanceCalibrator: Identifiable {
    enum State: Equatable {
        case starting
        /// No usable face yet; the message says why (no face, several faces, moving).
        case waiting(String)
        case ready(measuredWidth: Float)
        case failed(String)
    }

    let profile: CameraProfile
    let camera = CameraManager()
    private(set) var state: State = .starting
    private(set) var faces: [DetectedFace] = []
    /// Camera the measurement is made with; stored with the calibrated value.
    private(set) var cameraID: String?
    private(set) var cameraName: String?

    private var task: Task<Void, Never>?
    /// Set by `stop()` so a `start()` still waiting on the permission prompt doesn't turn the camera on afterwards.
    private var isStopped = false
    private var widths: [Float] = []
    private static let windowSize = 12
    private static let minimumSamples = 10

    init(profile: CameraProfile) {
        self.profile = profile
    }

    /// Threshold to store if the user accepts, nil until a stable measurement exists.
    var proposedThreshold: Float? {
        guard case .ready(let width) = state else { return nil }
        return DistanceCalibrationMath.threshold(fromMeasured: width)
    }

    func start() async {
        if let reason = CameraDeviceCatalog.unusableReason(for: profile) {
            state = .failed(reason)
            return
        }
        let device = CameraDeviceCatalog.device(for: profile)
        cameraID = device?.uniqueID
        cameraName = device?.localizedName
        camera.deviceIDOverride = cameraID
        await camera.start()
        if isStopped {
            camera.stop()
            return
        }
        if let error = camera.errorMessage {
            state = .failed(error)
            return
        }
        state = .waiting("Looking for your face…")
        beginMeasuring()
    }

    /// Discards a finished measurement and measures again.
    func retry() {
        guard case .ready = state else { return }
        widths.removeAll()
        state = .waiting("Looking for your face…")
        beginMeasuring()
    }

    func stop() {
        isStopped = true
        task?.cancel()
        task = nil
        camera.stop()
        faces = []
    }

    private func beginMeasuring() {
        task?.cancel()
        task = Task { [weak self] in
            var lastFrameID: UInt64?
            while !Task.isCancelled {
                guard let self else { return }
                if let frame = self.camera.currentFrame, frame.id != lastFrameID {
                    lastFrameID = frame.id
                    let image = frame.image
                    let detected = (try? await Task.detached(priority: .userInitiated) {
                        try FaceDetector.detectFaces(in: image)
                    }.value) ?? []
                    if Task.isCancelled { return }
                    if self.consume(detected) { return }
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    /// Returns true once a stable measurement is reached and the loop should end.
    private func consume(_ detected: [DetectedFace]) -> Bool {
        faces = detected
        guard detected.count == 1, let face = detected.first else {
            widths.removeAll()
            state = .waiting(detected.isEmpty ? "Looking for your face…" : "Only one person should be in view.")
            return false
        }
        widths.append(Float(face.normalizedBoundingBox.width))
        if widths.count > Self.windowSize { widths.removeFirst(widths.count - Self.windowSize) }

        guard widths.count >= Self.minimumSamples else {
            state = .waiting("Hold still…")
            return false
        }
        guard DistanceCalibrationMath.isStable(widths), let median = DistanceCalibrationMath.median(widths) else {
            state = .waiting("Hold still…")
            return false
        }
        state = .ready(measuredWidth: median)
        return true
    }
}

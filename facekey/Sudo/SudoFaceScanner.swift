//
//  SudoFaceScanner.swift
//  facekey
//
//  Live `SudoFaceScanning`: one face scan for a sudo approval, with the same matching,
//  threshold and liveness gate as the lock-screen unlock. It never types a password and
//  shows nothing; the camera is released on every way out.
//

import Foundation
import CoreGraphics

@MainActor
final class SudoFaceScanner: SudoFaceScanning {
    private let camera: CameraManager
    private let pipeline: FaceRecognitionPipeline
    private let matchThreshold: () -> Float

    /// A face that keeps failing to match for this long ends the scan early, as in the unlock path.
    private let wrongFaceGraceDuration: Duration = .seconds(4)

    init(camera: CameraManager, pipeline: FaceRecognitionPipeline, matchThreshold: @escaping () -> Float) {
        self.camera = camera
        self.pipeline = pipeline
        self.matchThreshold = matchThreshold
    }

    /// `liveness` in the result is 1 when a liveness cue confirmed a live face, 0 when one
    /// denied it, and nil when liveness checks are off.
    func scan() async -> SudoScanResult {
        // Declared before the await so a scan cancelled while the camera starts still stops it.
        defer { camera.stop() }
        FacekeySettings.shared.refreshPipelineMinimumFaceWidth()
        await camera.start()
        guard camera.errorMessage == nil else { return SudoScanResult(matched: false, similarity: nil, liveness: nil) }

        let threshold = matchThreshold()
        let livenessEnabled = FacekeySettings.shared.livenessChecksEnabled
        let deadline = Date().addingTimeInterval(TimeInterval(FacekeySettings.shared.faceDetectionSeconds))
        let liveness = LivenessAnalyzer()
        liveness.modeProvider = { FacekeySettings.shared.livenessMode }
        var tracker = FaceMatchTracker()
        var wrongFaceStartedAt: ContinuousClock.Instant?
        var readyMatch: ScoredIdentity?
        var livenessConfirmed = !livenessEnabled
        var lastFaceBoundingBox: CGRect?
        var lastProcessedFrameID: UInt64?
        var lastSimilarity: Float?

        while Date() < deadline, !Task.isCancelled {
            guard !LockMonitor.isScreenActuallyLocked() else { break }

            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastProcessedFrameID = frame.id

            let pipeline = self.pipeline
            let previousBoundingBox = lastFaceBoundingBox
            let outcome = await Task.detached(priority: .userInitiated) { () -> (FaceRecognitionResult, LivenessFrame)? in
                guard let result = try? pipeline.recognize(in: frame.image, preferNear: previousBoundingBox) else { return nil }
                let faceCrop = CameraManager.renderCrop(from: frame, imageRect: result.face.boundingBox)
                return (result, LivenessFeatureExtractor.extract(from: result, frame: frame.image, faceCrop: faceCrop))
            }.value

            guard let (result, livenessFrame) = outcome else {
                wrongFaceStartedAt = nil
                tracker.reset()
                lastFaceBoundingBox = nil
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastFaceBoundingBox = result.face.normalizedBoundingBox

            let verdict = tracker.observe(
                result,
                previousBoundingBox: previousBoundingBox,
                pipeline: pipeline,
                activeIdentities: FaceEnrollmentStore.shared.activeIdentities,
                threshold: threshold
            )
            lastSimilarity = tracker.lastFrameSimilarity

            if livenessEnabled {
                switch liveness.observe(livenessFrame).decision {
                case .denied:
                    // A denial overrides any match, as in the unlock path.
                    return SudoScanResult(matched: false, similarity: lastSimilarity, liveness: 0)
                case .confirmed:
                    livenessConfirmed = true
                case .pending:
                    break
                }
            }

            switch verdict {
            case .undecided:
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            case .matched(let identity):
                wrongFaceStartedAt = nil
                readyMatch = identity
            case .notMatched:
                // Cleared so a latched match is never handed to whoever steps in next.
                readyMatch = nil
                if wrongFaceStartedAt == nil { wrongFaceStartedAt = .now }
                if ContinuousClock.now - wrongFaceStartedAt! >= wrongFaceGraceDuration {
                    return SudoScanResult(matched: false, similarity: lastSimilarity, liveness: livenessEnabled ? (livenessConfirmed ? 1 : nil) : nil)
                }
            }

            if let readyMatch, livenessConfirmed {
                return SudoScanResult(matched: true, similarity: readyMatch.centroidSimilarity, liveness: livenessEnabled ? 1 : nil)
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return SudoScanResult(matched: false, similarity: lastSimilarity, liveness: livenessEnabled && livenessConfirmed ? 1 : nil)
    }
}

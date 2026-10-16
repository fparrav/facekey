//
//  FaceMatchTracker.swift
//  facekey
//
//  Per-frame matching state shared by the lock-screen scan and the post-unlock verification: warm-up skip, running embedding average, per-frame floor and the threshold check. Liveness, grace timers and what a match does stay with the caller.
//

import Foundation
import CoreGraphics

struct FaceMatchTracker {
    enum Verdict {
        /// Not enough consistent frames yet to decide either way.
        case undecided
        case matched(ScoredIdentity)
        case notMatched
    }

    /// Embedding of the latest frame scored against the best enabled identity, for logs.
    private(set) var lastFrameSimilarity: Float = 0
    var bufferedCount: Int { embeddingBuffer.count }

    /// Early frames are dark while the camera auto-exposes, so skip them from the embedding buffer.
    private let startedAt: ContinuousClock.Instant
    private let warmUpDuration: Duration = .milliseconds(300)
    /// Recent face embeddings, averaged before scoring so per-frame noise doesn't flip the match decision.
    private var embeddingBuffer: [[Float]] = []
    private let maxBufferedEmbeddings = 5
    private let minBufferedEmbeddings = 3
    private let perFrameFloorMargin: Float = 0.08
    /// Same tolerance as `FaceRecognitionPipeline.continuityDistanceTolerance`: center drift at or beyond this in
    /// normalized coordinates means the tracked face is a different person, so the running average must not blend them.
    private let continuityDistanceTolerance: CGFloat = 0.3

    init(startedAt: ContinuousClock.Instant = .now) {
        self.startedAt = startedAt
    }

    /// Call when no face was detected in a frame.
    mutating func reset() {
        embeddingBuffer.removeAll()
    }

    mutating func observe(
        _ result: FaceRecognitionResult,
        previousBoundingBox: CGRect?,
        pipeline: FaceRecognitionPipeline,
        activeIdentities: [FaceIdentity],
        threshold: Float
    ) -> Verdict {
        if let previous = previousBoundingBox {
            let previousCenter = CGPoint(x: previous.midX, y: previous.midY)
            let center = CGPoint(x: result.face.normalizedBoundingBox.midX, y: result.face.normalizedBoundingBox.midY)
            if hypot(center.x - previousCenter.x, center.y - previousCenter.y) >= continuityDistanceTolerance {
                embeddingBuffer.removeAll()
            }
        }
        // Each frame must clear a floor on its own: averaging alone would let a few frames of the owner lift a
        // stranger who steps in front of the camera over the threshold. A frame below the floor drops the whole buffer.
        // `activeIdentities`, not `identities`: someone switched off on the Your Face page stays enrolled but must not unlock.
        let frameSimilarity = pipeline.score(result.embedding, against: activeIdentities).first?.centroidSimilarity ?? 0
        lastFrameSimilarity = frameSimilarity
        let frameBelowFloor = frameSimilarity < threshold - perFrameFloorMargin
        if frameBelowFloor {
            embeddingBuffer.removeAll()
        } else if ContinuousClock.now - startedAt >= warmUpDuration {
            embeddingBuffer.append(result.embedding)
            if embeddingBuffer.count > maxBufferedEmbeddings {
                embeddingBuffer.removeFirst()
            }
        }

        // Not enough samples yet. A frame below the per-frame floor is a confident non-match instead.
        if embeddingBuffer.count < minBufferedEmbeddings && !frameBelowFloor {
            return .undecided
        }
        guard !frameBelowFloor else { return .notMatched }
        guard let smoothed = FaceRecognitionPipeline.averagedEmbedding(embeddingBuffer) else {
            return .undecided
        }
        let scored = pipeline.score(smoothed, against: activeIdentities)
        if let matched = pipeline.bestMatch(in: scored, threshold: threshold) {
            return .matched(matched)
        }
        return .notMatched
    }
}

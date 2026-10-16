//
//  PostUnlockVerification.swift
//  facekey
//
//  Time-bounded verification of the face that unlocked the Mac: matches verify, a persistent stranger is flagged, and a faceless window ends as nobody.
//

import Foundation

struct PostUnlockVerification {
    enum Observation { case matched, unrecognised, noFace }
    enum Outcome: Equatable { case verified, stranger, nobody }

    /// Longest a verification runs, in seconds from the first usable frame.
    static let window: TimeInterval = 6
    /// How long an unrecognised face must persist, with no match and no gap in detection, before it counts as a stranger.
    static let grace: TimeInterval = 3

    private var unrecognisedSince: TimeInterval?

    /// `t` is seconds since the first usable frame. Returns a final outcome as soon as one is known, otherwise nil.
    /// Callers pass a non-decreasing clock; out-of-order timestamps are not handled.
    mutating func observe(_ observation: Observation, at t: TimeInterval) -> Outcome? {
        guard t <= Self.window else { return nil }
        switch observation {
        case .matched:
            return .verified
        case .unrecognised:
            let since = unrecognisedSince ?? t
            unrecognisedSince = since
            return t - since >= Self.grace ? .stranger : nil
        case .noFace:
            unrecognisedSince = nil
            return nil
        }
    }

    /// Call when the window ends without `observe` having returned an outcome.
    func finish(at t: TimeInterval) -> Outcome { .nobody }
}

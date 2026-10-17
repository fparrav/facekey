//
//  SudoTimeouts.swift
//  facekey
//
//  Time limits for one sudo approval request. Foundation only.
//

import Foundation

enum SudoTimeouts {
    /// The whole request, from the frame arriving to the answer going back; it covers the
    /// first-use question, the confirmation and the face scan. The PAM module's own wait
    /// must be longer than this so the app always answers first.
    static let request: Duration = .seconds(45)
    /// How long one prompt waits for a click before the request is dropped.
    static let accept: Duration = .seconds(20)
}

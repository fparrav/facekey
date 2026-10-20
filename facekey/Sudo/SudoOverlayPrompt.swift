//
//  SudoOverlayPrompt.swift
//  facekey
//
//  What the notch overlay shows for a sudo request and how its click targets are
//  laid out. Pure data and geometry so the hit test can be checked standalone.
//  Foundation only.
//

import Foundation
import CoreGraphics

enum SudoOverlayChoice: Equatable {
    case cancel, accept
    case notNow, allow
}

struct SudoOverlayPrompt: Hashable {
    enum Kind: Hashable {
        /// Show app and command with Cancel and Accept.
        case confirm
        /// Ask whether the app may use Facekey for sudo, with Not now and Allow.
        case firstUse
        /// Ask whether Facekey may unlock Passwords, with Cancel and Accept.
        case unlockPasswords
    }

    var kind: Kind
    var appName: String
    /// Empty for the first-use question.
    var command: String
    /// True when the app has no stable signature and is matched by code hash.
    var isUnsigned: Bool
}

enum SudoOverlayMetrics {
    static let panelSize = CGSize(width: 380, height: 254)
    static let buttonRowHeight: CGFloat = 40
    static let bottomPadding: CGFloat = 18
    static let horizontalPadding: CGFloat = 28
    static let cornerRadius: CGFloat = 28

    /// The strip at the bottom of the panel holding the two buttons.
    static var buttonBandHeight: CGFloat { buttonRowHeight + bottomPadding }

    /// Maps a click to the choice under it, or nil when it misses the button band.
    /// `panel` and `point` share one top-down coordinate space; the left half of the
    /// band is the negative choice and the right half the positive one.
    static func choice(at point: CGPoint, panel: CGRect, kind: SudoOverlayPrompt.Kind) -> SudoOverlayChoice? {
        let band = CGRect(x: panel.minX, y: panel.maxY - buttonBandHeight, width: panel.width, height: buttonBandHeight)
        guard band.contains(point) else { return nil }
        let isRight = point.x >= panel.midX
        switch kind {
        case .confirm, .unlockPasswords: return isRight ? .accept : .cancel
        case .firstUse: return isRight ? .allow : .notNow
        }
    }
}

/// Describes who produced a mouse event from its CGEvent source fields. The spike showed a
/// hardware click carries pid 0 and state id 1; a posted `CGEvent` carries the poster's pid.
enum SudoClickSource {
    static func describe(pid: Int64, stateID: Int64) -> String {
        pid == 0 && stateID == 1 ? "hardware" : "synthetic pid=\(pid) stateID=\(stateID)"
    }

    /// True only for the description of a hardware click; "none", "unknown" and every synthetic one are not.
    static func isHardware(_ description: String) -> Bool {
        description == describe(pid: 0, stateID: 1)
    }
}

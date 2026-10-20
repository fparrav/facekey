//
//  PasswordsLockWatching.swift
//  facekey
//
//  The seam between the Passwords unlock flow and whatever detects the lock:
//  a read-only accessibility snapshot, a classifier that maps it to a lock
//  state, a tracker that reports only state changes, and the watching
//  protocol the live watcher (and the self-test fakes) conform to.
//  Foundation only.
//

import Foundation

/// What the Passwords app is doing, as far as the unlock flow cares.
/// `unknown` covers every case the flow must treat as "show nothing":
/// the app is not frontmost, has no window, shows an ambiguous tree,
/// or its accessibility state could not be read at all.
enum PasswordsLockState: Equatable {
    /// The lock screen with its password field focused.
    case locked
    /// The lock screen while it offers Touch ID or Apple Watch and a "use password" button, before the field exists.
    case lockedChoice
    case unlocked
    case unknown
}

/// One read-only snapshot of the Passwords app's accessibility state.
/// Only structural facts: no text field value is ever read or stored.
struct PasswordsAXState: Equatable {
    /// Whether Passwords is the frontmost app.
    var isFrontmost: Bool
    /// How many windows it has; the lock screen and the unlocked view are both a single window.
    var windowCount: Int
    /// The subrole of the app's focused UI element, e.g. "AXSecureTextField" or "AXSearchField".
    var focusedSubrole: String?
    /// Whether the first window contains a split group; the unlocked view has one, the lock screen does not.
    var hasSplitGroup: Bool
    /// Whether the first window holds exactly one plain button; on the lock screen that is the "use password" button
    /// shown while Touch ID or Apple Watch is offered. Identified by structure, never by its localized title.
    var hasUsePasswordButton: Bool = false
}

/// A read-only source of `PasswordsAXState`.
/// `nil` means the app or its accessibility tree could not be read
/// (the app is not running, or Accessibility is not trusted).
protocol PasswordsAXReading {
    func read() -> PasswordsAXState?
}

/// A watcher that reports Passwords lock-state changes.
protocol PasswordsLockWatching: AnyObject {
    /// Fires on the main thread whenever the lock state changes.
    var onChange: ((PasswordsLockState) -> Void)? { get set }
    func start()
    func stop()
}

/// Maps a snapshot to a lock state.
///
/// The rules come from the spike (design.md, "Spike findings"): the lock screen is a
/// small tree whose focused element is an `AXSecureTextField` and which has no split
/// group, while the unlocked view has a split group and focuses the search field.
/// While Touch ID or Apple Watch is offered there is no field yet, only a single "use password"
/// button and no split group: that is `lockedChoice`.
/// Anything else — including a `nil` snapshot — is `unknown`, and the flow shows nothing.
enum PasswordsLockClassifier {
    static func state(for ax: PasswordsAXState?) -> PasswordsLockState {
        guard let ax else { return .unknown }
        guard ax.isFrontmost else { return .unknown }
        guard ax.windowCount > 0 else { return .unknown }
        if ax.focusedSubrole == "AXSecureTextField", !ax.hasSplitGroup {
            return .locked
        }
        if ax.hasSplitGroup, ax.focusedSubrole != "AXSecureTextField" {
            return .unlocked
        }
        if !ax.hasSplitGroup, ax.hasUsePasswordButton, ax.focusedSubrole != "AXSecureTextField" {
            return .lockedChoice
        }
        return .unknown
    }
}

/// Reads through a `PasswordsAXReading`, classifies, and calls `onChange` only when
/// the state actually changed. The last state starts as `.unknown`, so a first read
/// that is already `unknown` emits nothing.
final class PasswordsLockTracker {
    private let reader: PasswordsAXReading
    /// The change callback. Settable so a live watcher can re-wire the forwarding
    /// after its own init completes (Swift forbids capturing self in a closure that
    /// is stored during init).
    var onChange: (PasswordsLockState) -> Void
    private var last: PasswordsLockState = .unknown
    /// Set when a lock was followed by one `unknown` read; a second one in a row confirms the lock is gone.
    private var pendingUnknown = false

    init(reader: PasswordsAXReading, onChange: @escaping (PasswordsLockState) -> Void) {
        self.reader = reader
        self.onChange = onChange
    }

    /// Reads once, classifies, and calls `onChange` only when the new state differs from the last reported one.
    ///
    /// Passwords passes through states the classifier cannot name when its lock screen changes from the
    /// Touch ID / Apple Watch screen to the password field. So one `unknown` read right after a lock is held
    /// back, and only a second one in a row ends the lock. `force` skips that wait, for a moment the caller
    /// knows is real (Passwords left the front).
    func refresh(force: Bool = false) {
        let state = PasswordsLockClassifier.state(for: reader.read())
        if state == .unknown, !force, last == .locked || last == .lockedChoice, !pendingUnknown {
            pendingUnknown = true
            return
        }
        pendingUnknown = false
        guard state != last else { return }
        last = state
        onChange(state)
    }
}

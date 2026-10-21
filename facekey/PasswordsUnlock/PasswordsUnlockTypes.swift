//
//  PasswordsUnlockTypes.swift
//  facekey
//
//  The seams PasswordsUnlockCoordinator depends on, so its decision flow can be
//  tested with fakes and wired to the live overlay, scanner and keystroke injector
//  later. It reuses the sudo seams for the session, the face scan, the clock and the
//  overlay answer. Foundation only.
//

import Foundation

/// A plaintext password held in memory the owner can wipe on demand. The bytes never
/// live in a `String`, and `wipe()` overwrites them in place so a test can observe it.
final class SecretBytes: @unchecked Sendable {
    private var storage: UnsafeMutableBufferPointer<UInt8>
    private(set) var isWiped = false

    let count: Int

    init(copying data: Data) {
        count = data.count
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: max(data.count, 1))
        buffer.initialize(repeating: 0)
        for (index, byte) in data.enumerated() { buffer[index] = byte }
        storage = buffer
    }

    /// A transient copy for an API that needs `Data`. The caller zeroes it with `resetBytes(in:)` after use.
    func makeData() -> Data {
        isWiped ? Data() : Data(storage.prefix(count))
    }

    func wipe() {
        guard !isWiped else { return }
        for index in 0..<storage.count { storage[index] = 0 }
        isWiped = true
    }

    deinit {
        wipe()
        storage.deallocate()
    }
}

/// Where a lock screen is drawn. Both are served by the same classifier, tracker and coordinator; only the
/// process read from and the owners a focused field may have differ.
enum PasswordsSurface: Equatable, Sendable {
    /// The Passwords app window.
    case app
    /// The AutoFill popup that a browser raises, drawn by the system AutoFill panel service. The panel service is
    /// the frontmost application while it shows, and its password field belongs to an XPC helper.
    case autofillPopup
    /// The "Passwords is locked" sheet Safari draws inside its own window when it needs a saved password (for example
    /// when a field is filled in from the list of other passwords). Safari is the frontmost app, so the lock is found
    /// through the focused element: it must sit inside a sheet that has the lock screen's layout.
    case browserSheet

    var bundleID: String {
        switch self {
        case .app: return "com.apple.Passwords"
        case .autofillPopup: return "com.apple.AutoFillPanelService"
        case .browserSheet: return "com.apple.Safari"
        }
    }

    /// Whether an Accessibility observer helps. The browser is in front most of the time and posts many
    /// notifications, so that surface relies on the one-second poll alone.
    var usesAXObserver: Bool { self != .browserSheet }

    /// Owners the focused secure field may have; nil means no owner check (the app's own field).
    var allowedFocusOwners: Set<String>? {
        switch self {
        case .app: return nil
        case .autofillPopup: return ["com.apple.AutoFillPanelService", "com.apple.SafariPlatformSupport.Helper"]
        // A page field is exposed through Safari too, so the owner proves little here; the sheet layout check does the work.
        case .browserSheet: return ["com.apple.Safari"]
        }
    }
}

/// Why the flow ended without typing, or how it ended.
enum PasswordsUnlockOutcome: Equatable {
    /// The password was typed and Return pressed. Whether Passwords accepted it is not known here.
    case typed
    case cancelled
    case timedOut
    case notMatched
    /// Passwords stopped being the frontmost locked app before the password was read or while it was typed.
    case focusLost
    case credentialUnavailable
    case typingFailed
    case declined(PasswordsUnlockDeclineReason)
}

/// Why a lock was ignored before any overlay or camera. None of these types anything.
enum PasswordsUnlockDeclineReason: Equatable {
    case setupDisabled
    case screenLocked
    case sessionLocked
    case accessibilityMissing
    /// A lock-screen scan or a sudo request owns the camera.
    case cameraBusy
    /// Another unlock flow is running.
    case busy
    /// This lock was already offered once (answered, cancelled, timed out or not matched).
    case alreadyTried
    /// A password was typed a moment ago and the cool-down has not passed.
    case coolingDown
}

/// The current display setup and whether Passwords unlock is on for it.
@MainActor
protocol PasswordsUnlockSetupProviding: AnyObject {
    var setupName: String { get }
    var isUnlockEnabled: Bool { get }
    /// Whether the browser surfaces (the AutoFill popup and Safari's lock sheet) may be unlocked too; only meaningful
    /// while `isUnlockEnabled` is true.
    var isBrowserUnlockEnabled: Bool { get }
}

/// Shows the "Unlock Passwords" confirmation. It must not take keyboard focus from Passwords.
/// `confirm()` resolves once the user (or `close()`) decides; only a hardware click is `.accepted`.
@MainActor
protocol PasswordsUnlockOverlayPresenting: AnyObject {
    func confirm() async -> SudoOverlayResult
    func close()
}

/// Live facts about Passwords and Accessibility, read at the moment they are needed.
/// Safe to call from any thread.
protocol PasswordsFocusChecking: Sendable {
    var isAccessibilityTrusted: Bool { get }
    /// True only while Passwords is frontmost and its unlock field is the focused element.
    func isPasswordsLockedAndFocused() -> Bool
    /// True while Passwords shows the lock screen with Touch ID or Apple Watch and a "use password" button, before the field exists.
    func isPasswordsAtUsePasswordChoice() -> Bool
    /// Presses that button so the password field appears. False if it was not there to press.
    func pressUsePassword() -> Bool
}

/// Reads the stored Mac password. Blocking; the caller wipes the returned bytes.
protocol PasswordsCredentialReading: Sendable {
    func readPassword() throws -> SecretBytes
}

/// Types the bytes into the focused field and presses Return. `shouldContinue` is asked
/// before each batch and before Return; once it answers false nothing more is posted and
/// the call throws. Blocking.
protocol KeystrokeTyping: Sendable {
    func typeAndReturn(_ password: SecretBytes, shouldContinue: @Sendable () -> Bool) throws
}

/// Time limits for one Passwords unlock; the same as a sudo approval, as the flow is the same.
enum PasswordsUnlockTimeouts {
    static let accept: Duration = SudoTimeouts.accept
    static let flow: Duration = SudoTimeouts.request
    /// After a password was typed, a new flow is refused for this long even if the lock is seen again.
    static let cooldown: TimeInterval = 10
}

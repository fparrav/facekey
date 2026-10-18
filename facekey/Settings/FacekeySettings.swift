//
//  FacekeySettings.swift
//  facekey
//
//  Backed directly by `UserDefaults.standard` — each property's `didSet`
//  writes through immediately, so there's no explicit "save" step.
//

import Foundation
import Observation

/// How long the Touch-ID-unlocked session may sit idle before it re-locks.
enum AutoLockInterval: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30
    case never = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .never: return String(localized: "Never")
        case .sevenDays: return String(localized: "7 days")
        case .fourteenDays: return String(localized: "14 days")
        case .thirtyDays: return String(localized: "30 days")
        }
    }

    /// `nil` means the session stays open until the app exits or the user
    /// explicitly locks it; the session key itself is never persisted in memory.
    var duration: TimeInterval? {
        self == .never ? nil : TimeInterval(rawValue) * 24 * 60 * 60
    }

    /// Position in `allCases`, used to drive the discrete 4-stop slider.
    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static func from(sliderIndex: Double) -> AutoLockInterval {
        let clamped = Int(sliderIndex.rounded())
        return allCases.indices.contains(clamped) ? allCases[clamped] : .thirtyDays
    }
}

/// Unlock success/failure animation style shown in the notch overlay.
enum UnlockAnimationStyle: String, CaseIterable, Identifiable {
    case none
    case minimal
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return String(localized: "None")
        case .minimal: return String(localized: "Minimal")
        case .original: return String(localized: "Original")
        }
    }

    /// The styles the picker offers; `.none` is still a valid stored value but is now produced by the "Show animation" toggle, not a tile.
    static let selectableCases: [UnlockAnimationStyle] = [.minimal, .original]
}

/// What can prompt Face Unlock. Multi-select; at least one is always kept
/// selected, since a Mac with none armed would never show the notch.
enum UnlockTrigger: String, CaseIterable, Identifiable {
    /// The display turned back on (see `LockEventKind.wake`).
    case onWake
    /// The screen just became locked, no wake involved.
    case onLock
    /// Pressing space on the lock screen starts a scan. The lock screen's
    /// Secure Event Input blocks normal event taps, so this is detected via
    /// IOKit HID instead (see `SpaceKeyMonitor`), requiring Input Monitoring.
    case onSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onWake: return String(localized: "On wake")
        case .onLock: return String(localized: "On lock")
        case .onSpace: return String(localized: "On space")
        }
    }

    var iconName: String {
        switch self {
        case .onWake: return "moon.fill"
        case .onLock: return "lock.laptopcomputer"
        case .onSpace: return "space"
        }
    }
}

@Observable
@MainActor
final class FacekeySettings {
    static let shared = FacekeySettings()

    private enum Key {
        static let isFaceUnlockEnabled = "FacekeySettings.isFaceUnlockEnabled"
        static let isFaceUnlockEnabledBuiltInOnly = "FacekeySettings.isFaceUnlockEnabledBuiltInOnly"
        static let isFaceUnlockEnabledBuiltInAndExternal = "FacekeySettings.isFaceUnlockEnabledBuiltInAndExternal"
        static let isFaceUnlockEnabledExternalOnly = "FacekeySettings.isFaceUnlockEnabledExternalOnly"
        static let matchThreshold = "FacekeySettings.matchThreshold"
        static let livenessChecksEnabled = "FacekeySettings.livenessChecksEnabled"
        static let livenessMode = "FacekeySettings.livenessMode"
        static let minimumFaceWidth = "FacekeySettings.minimumFaceWidth"
        static let minimumFaceWidthBuiltIn = "FacekeySettings.minimumFaceWidthBuiltIn"
        static let minimumFaceWidthExternal = "FacekeySettings.minimumFaceWidthExternal"
        static let minimumFaceWidthOriginBuiltIn = "FacekeySettings.minimumFaceWidthOriginBuiltIn"
        static let minimumFaceWidthOriginExternal = "FacekeySettings.minimumFaceWidthOriginExternal"
        static let calibratedCameraIDBuiltIn = "FacekeySettings.calibratedCameraIDBuiltIn"
        static let calibratedCameraIDExternal = "FacekeySettings.calibratedCameraIDExternal"
        static let minimumFaceWidthBuiltInAndExternal = "FacekeySettings.minimumFaceWidthBuiltInAndExternal"
        static let minimumFaceWidthOriginBuiltInAndExternal = "FacekeySettings.minimumFaceWidthOriginBuiltInAndExternal"
        static let calibratedCameraIDBuiltInAndExternal = "FacekeySettings.calibratedCameraIDBuiltInAndExternal"
        static let unlockAnimationStyle = "FacekeySettings.unlockAnimationStyle"
        static let showUnlockAnimation = "FacekeySettings.showUnlockAnimation"
        /// Legacy bool key — read once during migration, then ignored.
        static let playUnlockAnimation = "FacekeySettings.playUnlockAnimation"
        static let unlockTriggers = "FacekeySettings.unlockTriggers"
        static let retryOnHover = "FacekeySettings.retryOnHover"
        static let autoUnlockSession = "FacekeySettings.autoUnlockSession"
        static let faceDetectionSeconds = "FacekeySettings.faceDetectionSeconds"
        static let autoRetryOnce = "FacekeySettings.autoRetryOnce"
        static let verifyAfterExternalUnlock = "FacekeySettings.verifyAfterExternalUnlock"
        static let hapticFeedbackEnabled = "FacekeySettings.hapticFeedbackEnabled"
        static let showsInMenuBar = "FacekeySettings.showsInMenuBar"
        static let accentChoice = "FacekeySettings.accentChoice"
        static let preferredDisplayID = "FacekeySettings.preferredDisplayID"
        static let preferredDisplayName = "FacekeySettings.preferredDisplayName"
        static let autoLockIntervalDays = "FacekeySettings.autoLockIntervalDays"
        static let defaultCameraID = "FacekeySettings.defaultCameraID"
        static let builtInDisplayCameraID = "FacekeySettings.builtInDisplayCameraID"
        static let externalDisplayCameraID = "FacekeySettings.externalDisplayCameraID"
        static let builtInAndExternalDisplayCameraID = "FacekeySettings.builtInAndExternalDisplayCameraID"
        static let hasCompletedOnboarding = "FacekeySettings.hasCompletedOnboarding"
        static let onboardingResumeStep = "FacekeySettings.onboardingResumeStep"
        static let hasAcknowledgedSecurityNotice = "FacekeySettings.hasAcknowledgedSecurityNotice"
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// AppKit owns the actual status item. This callback keeps the persisted
    /// preference independent from that UI lifecycle.
    @ObservationIgnored private var menuBarVisibilityDidChange: ((Bool) -> Void)?

    var isFaceUnlockEnabled: Bool {
        didSet { defaults.set(isFaceUnlockEnabled, forKey: Key.isFaceUnlockEnabled) }
    }
    var isFaceUnlockEnabledBuiltInOnly: Bool {
        didSet { defaults.set(isFaceUnlockEnabledBuiltInOnly, forKey: Key.isFaceUnlockEnabledBuiltInOnly) }
    }
    var isFaceUnlockEnabledBuiltInAndExternal: Bool {
        didSet { defaults.set(isFaceUnlockEnabledBuiltInAndExternal, forKey: Key.isFaceUnlockEnabledBuiltInAndExternal) }
    }
    var isFaceUnlockEnabledExternalOnly: Bool {
        didSet { defaults.set(isFaceUnlockEnabledExternalOnly, forKey: Key.isFaceUnlockEnabledExternalOnly) }
    }

    func isFaceUnlockEnabled(for context: DisplayContext) -> Bool {
        switch context {
        case .builtInOnly: return isFaceUnlockEnabledBuiltInOnly
        case .builtInAndExternal: return isFaceUnlockEnabledBuiltInAndExternal
        case .externalOnly: return isFaceUnlockEnabledExternalOnly
        }
    }

    var matchThreshold: Float {
        didSet { defaults.set(matchThreshold, forKey: Key.matchThreshold) }
    }
    /// Master switch for liveness checking. Off means face recognition
    /// alone decides an unlock — a photo of the enrolled user would pass.
    var livenessChecksEnabled: Bool {
        didSet { defaults.set(livenessChecksEnabled, forKey: Key.livenessChecksEnabled) }
    }
    /// Light (deny-only) vs Heavy (deny plus a required proof of life) —
    /// see `LivenessMode`.
    var livenessMode: LivenessMode {
        didSet { defaults.set(livenessMode.rawValue, forKey: Key.livenessMode) }
    }
    /// The active camera profile's minimum face width (fraction of frame width).
    var activeMinimumFaceWidth: Float {
        minimumFaceWidth(for: CameraProfile.current())
    }
    var builtInMinimumFaceWidth: Float {
        didSet { defaults.set(builtInMinimumFaceWidth, forKey: Key.minimumFaceWidthBuiltIn) }
    }
    var externalMinimumFaceWidth: Float {
        didSet { defaults.set(externalMinimumFaceWidth, forKey: Key.minimumFaceWidthExternal) }
    }
    var builtInMinimumFaceWidthOrigin: DetectionDistanceOrigin {
        didSet { defaults.set(builtInMinimumFaceWidthOrigin.rawValue, forKey: Key.minimumFaceWidthOriginBuiltIn) }
    }
    var externalMinimumFaceWidthOrigin: DetectionDistanceOrigin {
        didSet { defaults.set(externalMinimumFaceWidthOrigin.rawValue, forKey: Key.minimumFaceWidthOriginExternal) }
    }
    var builtInCalibratedCameraID: String? {
        didSet { defaults.set(builtInCalibratedCameraID, forKey: Key.calibratedCameraIDBuiltIn) }
    }
    var externalCalibratedCameraID: String? {
        didSet { defaults.set(externalCalibratedCameraID, forKey: Key.calibratedCameraIDExternal) }
    }
    var builtInAndExternalMinimumFaceWidth: Float {
        didSet { defaults.set(builtInAndExternalMinimumFaceWidth, forKey: Key.minimumFaceWidthBuiltInAndExternal) }
    }
    var builtInAndExternalMinimumFaceWidthOrigin: DetectionDistanceOrigin {
        didSet { defaults.set(builtInAndExternalMinimumFaceWidthOrigin.rawValue, forKey: Key.minimumFaceWidthOriginBuiltInAndExternal) }
    }
    var builtInAndExternalCalibratedCameraID: String? {
        didSet { defaults.set(builtInAndExternalCalibratedCameraID, forKey: Key.calibratedCameraIDBuiltInAndExternal) }
    }
    /// The remembered choice (`.minimal`/`.original` only); `showUnlockAnimation`
    /// tracks on/off separately so toggling back on restores the prior pick.
    /// Read `effectiveUnlockAnimationStyle`, not this, to decide what to show.
    var unlockAnimationStyle: UnlockAnimationStyle {
        didSet { defaults.set(unlockAnimationStyle.rawValue, forKey: Key.unlockAnimationStyle) }
    }
    var showUnlockAnimation: Bool {
        didSet { defaults.set(showUnlockAnimation, forKey: Key.showUnlockAnimation) }
    }

    /// What the overlay should actually render — the pick, or `.none` when
    /// animations are switched off entirely.
    var effectiveUnlockAnimationStyle: UnlockAnimationStyle {
        showUnlockAnimation ? unlockAnimationStyle : .none
    }

    /// Which signals arm Face Unlock. Persisted as raw-value strings; the
    /// setter refuses to store an empty set (see `UnlockTrigger`).
    var unlockTriggers: Set<UnlockTrigger> {
        didSet {
            // Belt-and-braces behind the picker's own min-one rule. This
            // reassignment re-enters didSet once, then terminates since the
            // corrected value is never itself empty.
            if unlockTriggers.isEmpty {
                unlockTriggers = oldValue.isEmpty ? Set(UnlockTrigger.allCases) : oldValue
            }
            defaults.set(unlockTriggers.map(\.rawValue), forKey: Key.unlockTriggers)
        }
    }
    var retryOnHover: Bool {
        didSet { defaults.set(retryOnHover, forKey: Key.retryOnHover) }
    }
    /// The session key sits in the Keychain without the Touch ID gate and Facekey unlocks it at launch. Persisted only after
    /// `SecureCredentialManager.setSessionKeyGated` succeeds — the toggle in Password settings owns that rewrite.
    var autoUnlockSession: Bool {
        didSet { defaults.set(autoUnlockSession, forKey: Key.autoUnlockSession) }
    }
    /// How long each scan cycle looks for a face before giving up. Must stay
    /// equal to `FaceUnlockCoordinator.scanWindowDuration` and
    /// `NotchOverlayController.scanTimeoutDuration`.
    var faceDetectionSeconds: Int {
        didSet {
            // Only reassign when clamping actually changes the value —
            // unconditional reassignment would recurse infinitely, since the
            // slider only ever produces already-in-range values.
            let clamped = min(max(faceDetectionSeconds, Self.faceDetectionRange.lowerBound),
                               Self.faceDetectionRange.upperBound)
            guard clamped == faceDetectionSeconds else {
                faceDetectionSeconds = clamped
                return
            }
            defaults.set(faceDetectionSeconds, forKey: Key.faceDetectionSeconds)
        }
    }
    var autoRetryOnce: Bool {
        didSet { defaults.set(autoRetryOnce, forKey: Key.autoRetryOnce) }
    }
    var verifyAfterExternalUnlock: Bool {
        didSet { defaults.set(verifyAfterExternalUnlock, forKey: Key.verifyAfterExternalUnlock) }
    }
    /// Trackpad haptic on hovering the notch/pill and on a successful unlock —
    /// see `NotchOverlayView`'s hover handler and `.onChange(of: controller.phase)`.
    var hapticFeedbackEnabled: Bool {
        didSet { defaults.set(hapticFeedbackEnabled, forKey: Key.hapticFeedbackEnabled) }
    }
    /// Hiding the status item does not quit Facekey; a relaunch still routes
    /// through `AppDelegate.applicationShouldHandleReopen` to show Settings.
    var showsInMenuBar: Bool {
        didSet {
            defaults.set(showsInMenuBar, forKey: Key.showsInMenuBar)
            menuBarVisibilityDidChange?(showsInMenuBar)
        }
    }
    var accentChoice: AccentChoice {
        didSet { defaults.set(accentChoice.rawValue, forKey: Key.accentChoice) }
    }

    /// Bound once by `AppDelegate` after AppKit has finished launching. The
    /// initial call applies the stored preference as well as subsequent edits.
    func bindMenuBarVisibility(_ handler: @escaping (Bool) -> Void) {
        menuBarVisibilityDidChange = handler
        handler(showsInMenuBar)
    }

    static let faceDetectionRange = 3...10

    /// Which display Face Unlock shows on. `nil` means `NotchGeometry.preferredScreen()`'s
    /// default, re-evaluated live; a pinned display has deliberately no
    /// fallback if disconnected (see `FaceUnlockCoordinator.evaluateTrigger()`).
    var preferredDisplayID: String? {
        didSet { defaults.set(preferredDisplayID, forKey: Key.preferredDisplayID) }
    }
    /// The chosen display's name at pick time — cosmetic only, so the row can
    /// show something recognizable when that display is disconnected.
    var preferredDisplayName: String? {
        didSet { defaults.set(preferredDisplayName, forKey: Key.preferredDisplayName) }
    }
    /// Enforced by `SessionAutoLocker`, not here — this is only the stored
    /// preference.
    var autoLockInterval: AutoLockInterval {
        didSet { defaults.set(autoLockInterval.rawValue, forKey: Key.autoLockIntervalDays) }
    }
    /// Device `uniqueID`s, not device objects — devices can disconnect/
    /// reconnect between launches, but their unique ID is stable.
    var defaultCameraID: String? {
        didSet { defaults.set(defaultCameraID, forKey: Key.defaultCameraID) }
    }
    var builtInDisplayCameraID: String? {
        didSet { defaults.set(builtInDisplayCameraID, forKey: Key.builtInDisplayCameraID) }
    }
    var externalDisplayCameraID: String? {
        didSet { defaults.set(externalDisplayCameraID, forKey: Key.externalDisplayCameraID) }
    }
    var builtInAndExternalDisplayCameraID: String? {
        didSet { defaults.set(builtInAndExternalDisplayCameraID, forKey: Key.builtInAndExternalDisplayCameraID) }
    }

    /// Gates first-run onboarding — `AppDelegate` shows it instead of the
    /// Settings window until this is `true`. Set once, by `OnboardingController`
    /// on the true first-run flow reaching `.complete`.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }
    /// Where to resume first-run onboarding if the app quit mid-flow; `nil`
    /// starts fresh at `.intro`. Steps depending on in-memory capture state
    /// collapse to `.preSetup` before storing, since that state doesn't
    /// survive a relaunch — see `OnboardingStep.resumeTarget`.
    var onboardingResumeStep: OnboardingStep? {
        didSet { defaults.set(onboardingResumeStep?.rawValue, forKey: Key.onboardingResumeStep) }
    }
    /// Gates the one-time post-update notice for users who completed onboarding before the
    /// security-disclaimer step existed. Set alongside `hasCompletedOnboarding` for anyone
    /// finishing normal onboarding (which now includes that step), and separately by
    /// `OnboardingController.startPostUpdateNotice()` once the standalone catch-up notice is
    /// acknowledged. Defaults `false`, so an upgrading 1.0 install (where this key has never
    /// been written) correctly triggers the catch-up flow once.
    var hasAcknowledgedSecurityNotice: Bool {
        didSet { defaults.set(hasAcknowledgedSecurityNotice, forKey: Key.hasAcknowledgedSecurityNotice) }
    }

    private init() {
        // Enabled by default — onboarding already enrolled a face and set a
        // password specifically to use Face Unlock.
        isFaceUnlockEnabled = defaults.object(forKey: Key.isFaceUnlockEnabled) as? Bool ?? true
        isFaceUnlockEnabledBuiltInOnly = defaults.object(forKey: Key.isFaceUnlockEnabledBuiltInOnly) as? Bool ?? true
        isFaceUnlockEnabledBuiltInAndExternal = defaults.object(forKey: Key.isFaceUnlockEnabledBuiltInAndExternal) as? Bool ?? true
        isFaceUnlockEnabledExternalOnly = defaults.object(forKey: Key.isFaceUnlockEnabledExternalOnly) as? Bool ?? true
        // Matches the "Default" level (`MatchConfidenceLevel.standard`) — see RecognitionSettingsPage.swift.
        matchThreshold = defaults.object(forKey: Key.matchThreshold) as? Float ?? 0.63
        livenessChecksEnabled = defaults.object(forKey: Key.livenessChecksEnabled) as? Bool ?? true
        // Light by default — Heavy requires a blink/pose/depth signal a
        // still, non-blinking user may never produce, while Light still
        // catches the main attack (a photo on a phone screen).
        livenessMode = defaults.string(forKey: Key.livenessMode)
            .flatMap(LivenessMode.init(rawValue:)) ?? .light
        // Matches the "Default" level (`DetectionDistanceLevel.standard`) — see RecognitionSettingsPage.swift.
        // Migrates the legacy global width to both profiles until a per-profile value is saved.
        let legacyMinimumFaceWidth = defaults.object(forKey: Key.minimumFaceWidth) as? Float ?? 0.19
        // The built-in values load into locals first: `self` is not fully
        // initialized yet, so they cannot be read back for the defaults below.
        let builtInMinimumFaceWidth = defaults.object(forKey: Key.minimumFaceWidthBuiltIn) as? Float ?? legacyMinimumFaceWidth
        self.builtInMinimumFaceWidth = builtInMinimumFaceWidth
        externalMinimumFaceWidth = defaults.object(forKey: Key.minimumFaceWidthExternal) as? Float ?? legacyMinimumFaceWidth
        let builtInMinimumFaceWidthOrigin = defaults.string(forKey: Key.minimumFaceWidthOriginBuiltIn)
            .flatMap(DetectionDistanceOrigin.init(rawValue:)) ?? .manual
        self.builtInMinimumFaceWidthOrigin = builtInMinimumFaceWidthOrigin
        externalMinimumFaceWidthOrigin = defaults.string(forKey: Key.minimumFaceWidthOriginExternal)
            .flatMap(DetectionDistanceOrigin.init(rawValue:)) ?? .manual
        let builtInCalibratedCameraID = defaults.string(forKey: Key.calibratedCameraIDBuiltIn)
        self.builtInCalibratedCameraID = builtInCalibratedCameraID
        externalCalibratedCameraID = defaults.string(forKey: Key.calibratedCameraIDExternal)
        // `.builtInAndExternal` starts as a copy of the built-in profile until it gets its own values.
        builtInAndExternalMinimumFaceWidth = defaults.object(forKey: Key.minimumFaceWidthBuiltInAndExternal) as? Float ?? builtInMinimumFaceWidth
        builtInAndExternalMinimumFaceWidthOrigin = defaults.string(forKey: Key.minimumFaceWidthOriginBuiltInAndExternal)
            .flatMap(DetectionDistanceOrigin.init(rawValue:)) ?? builtInMinimumFaceWidthOrigin
        builtInAndExternalCalibratedCameraID = defaults.string(forKey: Key.calibratedCameraIDBuiltInAndExternal) ?? builtInCalibratedCameraID
        builtInAndExternalDisplayCameraID = defaults.string(forKey: Key.builtInAndExternalDisplayCameraID)

        // Resolve the stored style first, `.none` included, then split it
        // into the pick + the on/off flag the UI now works in.
        let storedStyle: UnlockAnimationStyle
        if let raw = defaults.string(forKey: Key.unlockAnimationStyle),
           let style = UnlockAnimationStyle(rawValue: raw) {
            storedStyle = style
        } else if let legacy = defaults.object(forKey: Key.playUnlockAnimation) as? Bool {
            // Migrate the oldest on/off toggle: off → none, on → original.
            storedStyle = legacy ? .original : .none
        } else {
            storedStyle = .original
        }
        // A stored `.none` becomes "off, remembering .original" so
        // switching back on has something to restore.
        unlockAnimationStyle = storedStyle == .none ? .original : storedStyle
        showUnlockAnimation = defaults.object(forKey: Key.showUnlockAnimation) as? Bool
            ?? (storedStyle != .none)

        // On wake/lock by default, not on space — `.onSpace` needs Input
        // Monitoring, which a fresh install shouldn't request unprompted.
        let storedTriggers = (defaults.array(forKey: Key.unlockTriggers) as? [String])?
            .compactMap { raw -> UnlockTrigger? in
                // "onActivity" was merged into "onWake"; keep old installs working.
                if raw == "onActivity" { return .onWake }
                return UnlockTrigger(rawValue: raw)
            }
        unlockTriggers = storedTriggers.map(Set.init).flatMap { $0.isEmpty ? nil : $0 }
            ?? [.onWake, .onLock]
        retryOnHover = defaults.object(forKey: Key.retryOnHover) as? Bool ?? true
        autoUnlockSession = defaults.object(forKey: Key.autoUnlockSession) as? Bool ?? false
        faceDetectionSeconds = (defaults.object(forKey: Key.faceDetectionSeconds) as? Int)
            .map { min(max($0, Self.faceDetectionRange.lowerBound), Self.faceDetectionRange.upperBound) }
            ?? 8
        autoRetryOnce = defaults.object(forKey: Key.autoRetryOnce) as? Bool ?? false
        verifyAfterExternalUnlock = defaults.object(forKey: Key.verifyAfterExternalUnlock) as? Bool ?? false
        hapticFeedbackEnabled = defaults.object(forKey: Key.hapticFeedbackEnabled) as? Bool ?? true
        // Keep the icon available for existing and new installs unless the
        // user explicitly opts into the background-only mode.
        showsInMenuBar = defaults.object(forKey: Key.showsInMenuBar) as? Bool ?? true
        accentChoice = AccentChoice(storedValue: defaults.string(forKey: Key.accentChoice))
        preferredDisplayID = defaults.string(forKey: Key.preferredDisplayID)
        preferredDisplayName = defaults.string(forKey: Key.preferredDisplayName)

        // Defaults to 30 days
        autoLockInterval = (defaults.object(forKey: Key.autoLockIntervalDays) as? Int)
            .flatMap(AutoLockInterval.init(rawValue:)) ?? .thirtyDays
        defaultCameraID = defaults.string(forKey: Key.defaultCameraID)
        builtInDisplayCameraID = defaults.string(forKey: Key.builtInDisplayCameraID)
        externalDisplayCameraID = defaults.string(forKey: Key.externalDisplayCameraID)

        hasCompletedOnboarding = defaults.object(forKey: Key.hasCompletedOnboarding) as? Bool ?? false
        onboardingResumeStep = defaults.string(forKey: Key.onboardingResumeStep)
            .flatMap(OnboardingStep.init(rawValue:))
        hasAcknowledgedSecurityNotice = defaults.object(forKey: Key.hasAcknowledgedSecurityNotice) as? Bool ?? false

        // Push into the nonisolated mirror immediately, or FaceRecognitionPipeline
        // would keep its own default until the slider is first touched.
        // `didSet` doesn't run inside `init`, so persist the migrated widths once; the legacy key then stops mattering.
        if defaults.object(forKey: Key.minimumFaceWidthBuiltIn) == nil {
            defaults.set(builtInMinimumFaceWidth, forKey: Key.minimumFaceWidthBuiltIn)
        }
        if defaults.object(forKey: Key.minimumFaceWidthExternal) == nil {
            defaults.set(externalMinimumFaceWidth, forKey: Key.minimumFaceWidthExternal)
        }
        if defaults.object(forKey: Key.minimumFaceWidthBuiltInAndExternal) == nil {
            defaults.set(builtInAndExternalMinimumFaceWidth, forKey: Key.minimumFaceWidthBuiltInAndExternal)
        }
        if defaults.object(forKey: Key.minimumFaceWidthOriginBuiltInAndExternal) == nil {
            defaults.set(builtInAndExternalMinimumFaceWidthOrigin.rawValue, forKey: Key.minimumFaceWidthOriginBuiltInAndExternal)
        }
        if defaults.object(forKey: Key.calibratedCameraIDBuiltInAndExternal) == nil {
            defaults.set(builtInAndExternalCalibratedCameraID, forKey: Key.calibratedCameraIDBuiltInAndExternal)
        }
        refreshPipelineMinimumFaceWidth()
    }

    /// Per-profile minimum face width (fraction of the video frame width).
    func minimumFaceWidth(for profile: CameraProfile) -> Float {
        switch profile {
        case .builtIn: builtInMinimumFaceWidth
        case .external: externalMinimumFaceWidth
        case .builtInAndExternal: builtInAndExternalMinimumFaceWidth
        }
    }

    /// Whether the per-profile distance was picked manually or came from calibration.
    func detectionDistanceOrigin(for profile: CameraProfile) -> DetectionDistanceOrigin {
        switch profile {
        case .builtIn: builtInMinimumFaceWidthOrigin
        case .external: externalMinimumFaceWidthOrigin
        case .builtInAndExternal: builtInAndExternalMinimumFaceWidthOrigin
        }
    }

    /// Camera the profile was calibrated with; `nil` unless the origin is `.calibrated`.
    func calibratedCameraID(for profile: CameraProfile) -> String? {
        switch profile {
        case .builtIn: builtInCalibratedCameraID
        case .external: externalCalibratedCameraID
        case .builtInAndExternal: builtInAndExternalCalibratedCameraID
        }
    }

    /// Pushes the active profile's width into the pipeline mirror, which is read
    /// from a background `nonisolated` context.
    func refreshPipelineMinimumFaceWidth() {
        FaceRecognitionPipeline.minimumProminentFaceWidth = activeMinimumFaceWidth
    }

    /// Sets width + origin + calibrated camera for one profile. The camera ID is
    /// only kept when the origin is `.calibrated`; otherwise it is dropped.
    func setMinimumFaceWidth(
        _ width: Float,
        origin: DetectionDistanceOrigin,
        cameraID: String?,
        for profile: CameraProfile
    ) {
        switch profile {
        case .builtIn:
            builtInMinimumFaceWidth = width
            builtInMinimumFaceWidthOrigin = origin
            builtInCalibratedCameraID = origin == .calibrated ? cameraID : nil
        case .external:
            externalMinimumFaceWidth = width
            externalMinimumFaceWidthOrigin = origin
            externalCalibratedCameraID = origin == .calibrated ? cameraID : nil
        case .builtInAndExternal:
            builtInAndExternalMinimumFaceWidth = width
            builtInAndExternalMinimumFaceWidthOrigin = origin
            builtInAndExternalCalibratedCameraID = origin == .calibrated ? cameraID : nil
        }
        if profile == CameraProfile.current() {
            refreshPipelineMinimumFaceWidth()
        }
    }
}

//
//  SudoCoordinatorTypes.swift
//  facekey
//
//  The seams SudoRequestCoordinator depends on, so its decision flow can be
//  tested with fakes and wired to the live overlay, scanner and stores later.
//  Foundation only.
//

import Foundation

/// Why a request was declined before or during the flow.
enum SudoDeclineReason: Equatable {
    case screenLocked
    case sessionLocked
    /// Approval is off for the current display setup; nothing is shown or audited.
    case setupDisabled
    /// Another request is in flight; nothing is audited.
    case busy
    /// A lock-screen face scan is arming, so the camera is not free.
    case lockScreenScanArming
    case unknownIdentity
    case policyBlocked
    /// The stored policy could not be read or written.
    case policyUnavailable

    /// Audit outcome for the decline, or nil when the decline is silent.
    var auditOutcome: SudoAuditOutcome? {
        switch self {
        case .setupDisabled, .busy: return nil
        case .screenLocked, .sessionLocked, .lockScreenScanArming: return .declinedLocked
        case .unknownIdentity: return .declinedUnknown
        case .policyBlocked, .policyUnavailable: return .declinedPolicy
        }
    }
}

/// What the overlay shows for a request.
struct SudoOverlayRequest: Equatable {
    var appName: String
    /// Already escaped and shortened.
    var command: String
    /// True when the app has no stable signature and is matched by code hash.
    var isUnsigned: Bool
}

/// The user's answer to the first-use question for an app.
enum SudoFirstUseChoice: Equatable {
    case allow
    case block
    case dismissed
}

/// How the confirmation ended; `clickSource` describes who produced the Accept click.
enum SudoOverlayResult: Equatable {
    case accepted(clickSource: String?)
    case cancelled
    case timedOut
}

/// Shows the confirmation UI; every call resolves once the user (or the time limit) decides.
@MainActor
protocol SudoOverlayPresenting: AnyObject {
    func askFirstUse(appName: String, isUnsigned: Bool) async -> SudoFirstUseChoice
    func confirm(_ request: SudoOverlayRequest) async -> SudoOverlayResult
    func close()
}

struct SudoScanResult: Equatable {
    var matched: Bool
    var similarity: Float?
    var liveness: Float?
}

/// Runs one face scan and reports whether an enabled identity matched.
@MainActor
protocol SudoFaceScanning: AnyObject {
    func scan() async -> SudoScanResult
}

/// Lock and session facts the coordinator gates on.
@MainActor
protocol SudoSessionState: AnyObject {
    var isScreenLocked: Bool { get }
    var isSessionUnlocked: Bool { get }
    /// True while the lock-screen path is arming or running a scan.
    var isLockScreenScanArming: Bool { get }
    /// Set while a sudo request owns the camera so the lock-screen path refuses to arm.
    func setSudoRequestActive(_ active: Bool)
}

/// The current display setup and whether sudo approval is on for it.
@MainActor
protocol SudoSetupProviding: AnyObject {
    var setupName: String { get }
    var isApprovalEnabled: Bool { get }
}

@MainActor
protocol SudoClock {
    var now: Date { get }
    /// Throws when the calling task is cancelled.
    func sleep(for duration: Duration) async throws
}

/// Stored per-app allow/block state.
protocol SudoPolicyStoring {
    func load() throws -> [String: SudoAppState]
    func save(_ entries: [String: SudoAppState]) throws
}

/// Where audit entries go; failures are never fatal to a request.
protocol SudoAuditWriting {
    func append(_ entry: SudoAuditEntry) throws
}

extension SudoPolicyStore: SudoPolicyStoring {}
extension SudoAuditLog: SudoAuditWriting {}

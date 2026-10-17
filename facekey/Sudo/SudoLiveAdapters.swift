//
//  SudoLiveAdapters.swift
//  facekey
//
//  Live implementations of the small seams `SudoRequestCoordinator` depends on:
//  lock and session facts, the current display setup, and the clock.
//

import Foundation

@MainActor
final class SudoLiveSession: SudoSessionState {
    private let faceUnlock: FaceUnlockCoordinator

    init(faceUnlock: FaceUnlockCoordinator) {
        self.faceUnlock = faceUnlock
    }

    var isScreenLocked: Bool { LockMonitor.isScreenActuallyLocked() }
    var isSessionUnlocked: Bool { SecureCredentialManager.isSessionUnlocked }
    /// Any lock-screen scan or post-unlock verification still owns the camera.
    var isLockScreenScanArming: Bool { faceUnlock.isUnlockPathBusy }

    func setSudoRequestActive(_ active: Bool) {
        faceUnlock.setSudoRequestActive(active)
    }
}

@MainActor
final class SudoLiveSetup: SudoSetupProviding {
    private let settings: SudoApprovalSettings

    init(settings: SudoApprovalSettings) {
        self.settings = settings
    }

    var setupName: String {
        switch DisplayContext.current() {
        case .builtInOnly: return "Built-in display"
        case .builtInAndExternal: return "Built-in and external displays"
        case .externalOnly: return "External display only"
        }
    }

    var isApprovalEnabled: Bool { settings.isEnabled(for: DisplayContext.current()) }
}

struct SudoLiveClock: SudoClock {
    var now: Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

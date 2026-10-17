//
//  SudoApprovalService.swift
//  facekey
//
//  Owns the sudo approval pieces for the app's lifetime: the stores, the coordinator
//  and the socket server the PAM module talks to.
//

import Foundation
import os

private let log = Logger(subsystem: "com.fparrav.facekey", category: "sudo")

@MainActor
final class SudoApprovalService {
    let settings = SudoApprovalSettings()
    let policyStore: SudoPolicyStore
    let auditLog: SudoAuditLog

    private let server: SudoSocketServer

    init(faceUnlock: FaceUnlockCoordinator) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // The server tightens this directory to 0700, so the socket gets one of its own.
        let directory = appSupport.appendingPathComponent("facekey/sudo", isDirectory: true)

        policyStore = SudoPolicyStore(fileURL: directory.appendingPathComponent("policy.enc"), cipher: SudoLiveSessionCipher())
        auditLog = SudoAuditLog(fileURL: directory.appendingPathComponent("audit.enc"), keys: SudoAuditKeyStore())

        let settings = settings
        let coordinator = SudoRequestCoordinator(
            session: SudoLiveSession(faceUnlock: faceUnlock),
            setup: SudoLiveSetup(settings: settings),
            overlay: SudoOverlayPresenter(),
            scanner: SudoFaceScanner(
                camera: faceUnlock.camera,
                pipeline: faceUnlock.pipeline,
                matchThreshold: { [weak faceUnlock] in faceUnlock?.matchThreshold ?? FacekeySettings.shared.matchThreshold }
            ),
            policy: policyStore,
            audit: auditLog,
            clock: SudoLiveClock(),
            resolveIdentity: { SudoAppIdentityResolver.identity(forChain: $0) },
            storesExecutableOnly: { settings.storesExecutableOnly }
        )
        server = SudoSocketServer(socketURL: directory.appendingPathComponent("approval.sock")) { request in
            await coordinator.handle(request)
        }
    }

    /// A failure only disables sudo approval: sudo then falls through to its next method.
    func start() {
        do {
            try server.start()
        } catch {
            log.error("sudo approval socket failed to start: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        server.stop()
    }
}

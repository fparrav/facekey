//
//  PasswordsUnlockService.swift
//  facekey
//
//  Owns the Passwords unlock pieces for the app's lifetime: the coordinator, and a lock
//  watcher that exists only while the feature is on for the current display setup. With the
//  feature off, nothing watches Passwords, shows an overlay or touches the camera.
//

import AppKit
import Foundation
import os

private let log = Logger(subsystem: "com.fparrav.facekey", category: "passwords-unlock")

@MainActor
final class PasswordsUnlockService {
    private let settings = PasswordsUnlockSettings()
    private let coordinator: PasswordsUnlockCoordinator
    /// A fresh watcher per enable, so a lock that is already showing is reported when the feature is turned on.
    private var watcher: LivePasswordsLockWatcher?
    private var observers: [NSObjectProtocol] = []

    init(faceUnlock: FaceUnlockCoordinator) {
        coordinator = PasswordsUnlockCoordinator(
            session: SudoLiveSession(faceUnlock: faceUnlock),
            setup: PasswordsUnlockLiveSetup(settings: settings),
            overlay: PasswordsUnlockOverlayPresenter(),
            scanner: SudoFaceScanner(
                camera: faceUnlock.camera,
                pipeline: faceUnlock.pipeline,
                matchThreshold: { [weak faceUnlock] in faceUnlock?.matchThreshold ?? FacekeySettings.shared.matchThreshold }
            ),
            focus: LivePasswordsFocusChecker(),
            credentials: LivePasswordsCredentialReader(),
            typer: LiveKeystrokeTyper(),
            clock: SudoLiveClock()
        )
    }

    /// Starts following the setting and the display setup. Safe to call once at launch.
    func start() {
        guard observers.isEmpty else { return }
        let onChange: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        observers = [
            NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main, using: onChange),
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: onChange),
        ]
        refresh()
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        stopWatching()
    }

    /// Starts or stops the watcher to match the setting for the current display setup.
    private func refresh() {
        let enabled = settings.isEnabled(for: DisplayContext.current())
        if enabled, watcher == nil {
            let watcher = LivePasswordsLockWatcher()
            watcher.onChange = { [weak self] state in
                guard let self else { return }
                log.notice("passwords lock state: \(String(describing: state), privacy: .public)")
                Task { await self.coordinator.lockStateChanged(state) }
            }
            self.watcher = watcher
            watcher.start()
        } else if !enabled, watcher != nil {
            stopWatching()
        }
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
        // A flow still waiting on the user ends: the lock is no longer being followed.
        Task { await coordinator.lockStateChanged(.unknown) }
    }
}

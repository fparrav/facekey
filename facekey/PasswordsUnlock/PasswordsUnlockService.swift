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
    /// One per browser surface; they exist only while the browser switch and Unlock Passwords are both on for the current setup.
    private var browserWatchers: [PasswordsSurface: LivePasswordsLockWatcher] = [:]
    private static let browserSurfaces: [PasswordsSurface] = [.autofillPopup, .browserSheet]
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
            browserFocus: Dictionary(uniqueKeysWithValues: Self.browserSurfaces.map { ($0, LivePasswordsFocusChecker(surface: $0)) }),
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

    /// Starts or stops the watchers to match the settings for the current display setup.
    private func refresh() {
        let enabled = settings.isEnabled(for: DisplayContext.current())
        if enabled, watcher == nil {
            watcher = makeWatcher(for: .app)
        } else if !enabled, watcher != nil {
            watcher?.stop()
            watcher = nil
            // A flow still waiting on the user ends: the lock is no longer being followed.
            Task { await coordinator.lockStateChanged(.unknown, surface: .app) }
        }
        let browserEnabled = enabled && settings.isBrowserEnabled
        for surface in Self.browserSurfaces {
            if browserEnabled, browserWatchers[surface] == nil {
                browserWatchers[surface] = makeWatcher(for: surface)
            } else if !browserEnabled, let existing = browserWatchers[surface] {
                existing.stop()
                browserWatchers[surface] = nil
                Task { await coordinator.lockStateChanged(.unknown, surface: surface) }
            }
        }
    }

    /// A fresh watcher per enable, started so a lock that is already showing is reported at once.
    private func makeWatcher(for surface: PasswordsSurface) -> LivePasswordsLockWatcher {
        let watcher = LivePasswordsLockWatcher(surface: surface)
        let label: String
        switch surface {
        case .app: label = "passwords"
        case .autofillPopup: label = "autofill popup"
        case .browserSheet: label = "browser sheet"
        }
        watcher.onChange = { [weak self] state in
            guard let self else { return }
            log.notice("\(label, privacy: .public) lock state: \(String(describing: state), privacy: .public)")
            Task { await self.coordinator.lockStateChanged(state, surface: surface) }
        }
        watcher.start()
        return watcher
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
        for watcher in browserWatchers.values { watcher.stop() }
        browserWatchers.removeAll()
        Task {
            await coordinator.lockStateChanged(.unknown, surface: .app)
            for surface in Self.browserSurfaces { await coordinator.lockStateChanged(.unknown, surface: surface) }
        }
    }
}

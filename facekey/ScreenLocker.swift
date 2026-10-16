//
//  ScreenLocker.swift
//  facekey
//
//  Locks the screen again by posting the system lock shortcut; used when a post-unlock verification sees an unrecognised face.
//

import Foundation
import ApplicationServices
import CoreGraphics
import os

private let log = Logger(subsystem: "com.fparrav.facekey", category: "unlock")

enum ScreenLocker {
    /// Posts Control-Command-Q (the default Lock Screen shortcut) through the HID tap, like `KeystrokeInjector`, then checks the
    /// authoritative lock state. Falls back to sleeping the display, which only locks when the user's "require password" delay
    /// is immediate. Returns whether the session ended up locked.
    static func lock() async -> Bool {
        guard KeystrokeInjector.isAccessibilityTrusted() else {
            log.error("relock failed: Accessibility not granted")
            return false
        }
        postLockShortcut()
        try? await Task.sleep(for: .seconds(1))
        if LockMonitor.isScreenActuallyLocked() {
            log.notice("relock ok: locked via Control-Command-Q")
            return true
        }
        log.notice("relock: shortcut did not lock, falling back to display sleep")
        await sleepDisplay()
        try? await Task.sleep(for: .seconds(1))
        let locked = LockMonitor.isScreenActuallyLocked()
        log.notice("relock fallback result: locked=\(locked, privacy: .public)")
        return locked
    }

    private static func postLockShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let qKey: CGKeyCode = 12
        let down = CGEvent(keyboardEventSource: source, virtualKey: qKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: qKey, keyDown: false)
        for event in [down, up] {
            event?.flags = [.maskControl, .maskCommand]
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Waits without blocking the caller (it runs on the main actor) and kills `pmset` if it hangs.
    private static func sleepDisplay() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                log.error("relock fallback failed to run pmset: \(error.localizedDescription, privacy: .public)")
                process.terminationHandler = nil
                continuation.resume()
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}

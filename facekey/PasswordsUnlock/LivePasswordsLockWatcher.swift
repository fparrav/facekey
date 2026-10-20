//
//  LivePasswordsLockWatcher.swift
//  facekey
//
//  Live implementation of `PasswordsLockWatching`: reports whether the Passwords app
//  (com.apple.Passwords) is frontmost and showing its lock screen.
//
//  NSWorkspace activation notifications decide when Passwords is in front. While it is,
//  an AXObserver on the app re-evaluates the structural signal from the spike
//  (focused `AXSecureTextField`, presence of a split group) on focus and window changes.
//  A one-second poll covers notifications Passwords does not send. The moment it stops being frontmost the observer and the poll are removed and one more read drops
//  the state back to `unknown`, so the watcher costs nothing in the background.
//
//  The watcher is strictly read-only: no AX actions, no attribute writes, no text field value
//  is ever read, and nothing here logs. The one action in this file, pressing the lock screen's
//  "use password" button, lives in the reader and is called only by the unlock flow after the
//  user accepted and the face matched. If Accessibility is not trusted, or the app is not
//  running, the reader returns nil and the state is `unknown`.
//

import AppKit
import ApplicationServices

/// Read-only accessibility snapshot of the Passwords app.
struct LivePasswordsAXReader: PasswordsAXReading {
    /// The Passwords app's bundle identifier.
    static let bundleID = "com.apple.Passwords"

    /// True when Passwords is the frontmost app.
    func isFrontmost() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        return frontmost.bundleIdentifier == Self.bundleID
    }

    /// A structural snapshot, or `nil` when the app is not running or Accessibility
    /// is not trusted. Never reads a text field's value.
    func read() -> PasswordsAXState? {
        guard AXIsProcessTrusted() else { return nil }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == Self.bundleID }) else {
            return nil
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var windowCount = 0
        var hasSplitGroup = false
        var hasUsePasswordButton = false
        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let windows = windowsValue as? [AXUIElement] {
            windowCount = windows.count
            if let firstWindow = windows.first {
                let scan = Self.scan(window: firstWindow)
                hasSplitGroup = scan.hasSplitGroup
                hasUsePasswordButton = scan.plainButtons.count == 1
            }
        }

        var focusedSubrole: String?
        if let focused = axElement(axApp, kAXFocusedUIElementAttribute) {
            focusedSubrole = axString(focused, kAXSubroleAttribute)
        }

        return PasswordsAXState(
            isFrontmost: isFrontmost(),
            windowCount: windowCount,
            focusedSubrole: focusedSubrole,
            hasSplitGroup: hasSplitGroup,
            hasUsePasswordButton: hasUsePasswordButton
        )
    }

    /// Presses the lock screen's "use password" button so the password field appears. The only action this
    /// type ever performs on Passwords; it needs Passwords frontmost, no split group and exactly one plain
    /// button in the first window, and it does not read or write any text field.
    func pressUsePasswordButton() -> Bool {
        guard AXIsProcessTrusted(), isFrontmost(),
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == Self.bundleID })
        else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let window = (windowsValue as? [AXUIElement])?.first else { return false }
        let scan = Self.scan(window: window)
        guard !scan.hasSplitGroup, scan.plainButtons.count == 1, let button = scan.plainButtons.first else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// Read one AX attribute as a string; nil when the element doesn't expose it.
    private func axString(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Read one AX attribute whose value is another element (e.g. the focused one).
    private func axElement(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let ref = value else { return nil }
        return unsafeBitCast(ref, to: AXUIElement.self)
    }

    /// Breadth-first walk of `window`'s descendants, bounded to `maxDepth` levels and `maxElements`
    /// visited elements so a pathological tree cannot slow a refresh. It reports whether an element with
    /// role "AXSplitGroup" exists (the unlocked view's split group sits near the top of the tree) and
    /// collects the plain buttons: role "AXButton" with no subrole, which excludes the window's close,
    /// minimize and zoom buttons. The walk stops at the first split group.
    private static func scan(window: AXUIElement, maxDepth: Int = 6, maxElements: Int = 400) -> (hasSplitGroup: Bool, plainButtons: [AXUIElement]) {
        var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
        var visited = 0
        var plainButtons: [AXUIElement] = []
        while let (element, depth) = queue.first {
            queue.removeFirst()
            guard visited < maxElements else { break }
            visited += 1
            guard depth <= maxDepth else { continue }
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String {
                if role == "AXSplitGroup" { return (true, []) }
                if role == "AXButton" {
                    var subroleValue: CFTypeRef?
                    let hasSubrole = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success
                    if !hasSubrole { plainButtons.append(element) }
                }
            }
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else { continue }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return (false, plainButtons)
    }
}

/// Watches the Passwords app and reports lock-state changes on the main thread.
@MainActor
final class LivePasswordsLockWatcher: PasswordsLockWatching {
    /// Fires on the main thread whenever the lock state changes.
    var onChange: ((PasswordsLockState) -> Void)?

    private let reader: LivePasswordsAXReader
    private let tracker: PasswordsLockTracker

    private var isRunning = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var axObserver: AXObserver?
    /// Re-reads the state while Passwords is frontmost. AX notifications from Passwords are not reliable
    /// enough on their own (a lock or a screen change can arrive without one), so this closes the gap.
    private var pollTimer: Timer?
    private static let pollInterval: TimeInterval = 1.0

    init(reader: LivePasswordsAXReader = LivePasswordsAXReader()) {
        self.reader = reader
        // The forwarding is wired after all stored properties are initialized: Swift
        // forbids capturing self in a closure that is stored during init.
        self.tracker = PasswordsLockTracker(reader: reader) { _ in }
        self.tracker.onChange = { [weak self] state in
            // The tracker is not actor-isolated; hop so `onChange` fires on the main thread.
            Task { @MainActor in
                self?.onChange?(state)
            }
        }
    }

    /// Idempotent. Installs the workspace observers, syncs the AX observer to the
    /// current frontmost app, and does one initial refresh.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        installWorkspaceObservers()
        syncAXObserver()
        tracker.refresh()
    }

    /// Removes the workspace observers and the AX observer. Idempotent.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopPolling()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        removeAXObserver()
    }

    deinit {
        // Always stopped before teardown (when the feature is disabled or the app quits),
        // so there is nothing to unwind here; `stop()` is the only place observers go.
    }

    // MARK: - Workspace observers

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let activate = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                self?.passwordsDidActivate(note)
            }
        }
        let deactivate = center.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                self?.passwordsDidDeactivate(note)
            }
        }
        workspaceObservers = [activate, deactivate]
    }

    private func passwordsDidActivate(_ note: Notification) {
        guard isRunning else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == LivePasswordsAXReader.bundleID else { return }
        installAXObserver()
        startPolling()
        tracker.refresh()
    }

    private func passwordsDidDeactivate(_ note: Notification) {
        guard isRunning else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == LivePasswordsAXReader.bundleID else { return }
        removeAXObserver()
        stopPolling()
        // One more read so the state falls back to `unknown` even if no AX
        // notification follows the deactivation. Leaving the front is real, so no wait.
        tracker.refresh(force: true)
    }

    // MARK: - AX observer

    /// Installs or removes the AX observer to match whether Passwords is frontmost.
    private func syncAXObserver() {
        if reader.isFrontmost() {
            installAXObserver()
            startPolling()
        } else {
            removeAXObserver()
            stopPolling()
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tracker.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Installs an AXObserver on the Passwords app, if it is running.
    /// The callback is a capture-less C function; `self` is threaded through the refcon,
    /// as in `SpaceKeyMonitor`. `passUnretained` is safe because `stop()` always removes
    /// the observer before the watcher goes away.
    private func installAXObserver() {
        guard axObserver == nil,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == LivePasswordsAXReader.bundleID })
        else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<LivePasswordsLockWatcher>.fromOpaque(refcon).takeUnretainedValue()
            // The observer is scheduled on the main run loop, so this lands on the main thread.
            Task { @MainActor in
                watcher.tracker.refresh()
            }
        }

        var observer: AXObserver?
        guard AXObserverCreate(app.processIdentifier, callback, &observer) == .success, let observer else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

        let element = AXUIElementCreateApplication(app.processIdentifier)
        let notifications = [
            kAXFocusedUIElementChangedNotification,
            kAXWindowCreatedNotification,
            kAXMainWindowChangedNotification,
            kAXUIElementDestroyedNotification,
        ]
        for name in notifications {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
        axObserver = observer
    }

    private func removeAXObserver() {
        guard let observer = axObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = nil
    }
}

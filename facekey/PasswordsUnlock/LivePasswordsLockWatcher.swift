//
//  LivePasswordsLockWatcher.swift
//  facekey
//
//  Live implementation of `PasswordsLockWatching`: reports whether a Passwords lock surface
//  (the Passwords app, or the AutoFill popup drawn by com.apple.AutoFillPanelService) is
//  frontmost and showing its lock screen.
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
    let surface: PasswordsSurface

    /// Accessibility calls to an unresponsive app wait six seconds by default, and these run on the main thread once a
    /// second, so they give up much sooner. A timed-out read comes back as missing data, which classifies as unknown.
    private static let messagingTimeout: Float = 0.5

    init(surface: PasswordsSurface = .app) {
        self.surface = surface
    }

    /// The bundle identifier of the process that draws the surface.
    var bundleID: String { surface.bundleID }

    /// True when the surface's process is the frontmost app.
    func isFrontmost() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        return frontmost.bundleIdentifier == bundleID
    }

    /// A structural snapshot, or `nil` when the app is not running or Accessibility
    /// is not trusted. Never reads a text field's value.
    func read() -> PasswordsAXState? {
        guard AXIsProcessTrusted() else { return nil }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            return nil
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, Self.messagingTimeout)
        if surface == .browserSheet { return readBrowserSheet(axApp) }

        var windowCount = 0
        var hasSplitGroup = false
        var hasUsePasswordButton = false
        var firstWindow: AXUIElement?
        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let windows = windowsValue as? [AXUIElement] {
            windowCount = windows.count
            if let window = windows.first {
                firstWindow = window
                let scan = Self.scan(window: window)
                hasSplitGroup = scan.hasSplitGroup
                hasUsePasswordButton = isUsePasswordChoice(scan)
            }
        }

        var focusedSubrole: String?
        var focusedOwner: String?
        if let focused = axElement(axApp, kAXFocusedUIElementAttribute) {
            focusedSubrole = axString(focused, kAXSubroleAttribute)
            // The structure above was read from the first window, so the focused element must belong to it: a secure
            // field in another window of the app must not make this window read as the lock screen. An element that
            // does not say which window it is in is accepted, since there is nothing to contradict. The popup's field
            // lives in a helper process and reports that process's window, so it is covered by the owner list instead.
            if surface == .app, let firstWindow, let focusedWindow = axElement(focused, kAXWindowAttribute), !CFEqual(firstWindow, focusedWindow) {
                focusedSubrole = nil
            }
            var pid: pid_t = 0
            if AXUIElementGetPid(focused, &pid) == .success {
                focusedOwner = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            }
        }

        return PasswordsAXState(
            isFrontmost: isFrontmost(),
            windowCount: windowCount,
            focusedSubrole: focusedSubrole,
            hasSplitGroup: hasSplitGroup,
            hasUsePasswordButton: hasUsePasswordButton,
            focusedOwner: focusedOwner
        )
    }

    /// Presses the lock screen's "use password" button so the password field appears. The only action this
    /// type ever performs on Passwords; it needs Passwords frontmost, no split group and exactly one plain
    /// button in the first window, and it does not read or write any text field.
    func pressUsePasswordButton() -> Bool {
        guard AXIsProcessTrusted(), isFrontmost(),
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })
        else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, Self.messagingTimeout)
        if surface == .browserSheet {
            guard let group = lockGroupInFocusedSheet(axApp), group.secureFields.isEmpty, group.plainButtons.count == 1,
                  let button = group.plainButtons.first else { return false }
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let window = (windowsValue as? [AXUIElement])?.first else { return false }
        let scan = Self.scan(window: window)
        guard !scan.hasSplitGroup, isUsePasswordChoice(scan), let button = scan.plainButtons.first else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    // MARK: - Safari's lock sheet

    /// What a lock screen's content group holds: the buttons without a subrole and the secure fields among its children.
    private struct LockGroup {
        var plainButtons: [AXUIElement] = []
        var secureFields: [AXUIElement] = []
    }

    /// The snapshot for Safari's lock sheet. Safari is frontmost all the time, so nothing counts unless the focused
    /// element sits inside a sheet whose content has the lock screen's layout (two images, two texts, and either one
    /// button or the secure field). A field in a web page has no sheet above it, so it reads as "no window".
    private func readBrowserSheet(_ axApp: AXUIElement) -> PasswordsAXState {
        var state = PasswordsAXState(isFrontmost: isFrontmost(), windowCount: 0, focusedSubrole: nil, hasSplitGroup: false)
        guard state.isFrontmost, let focused = axElement(axApp, kAXFocusedUIElementAttribute),
              let sheet = Self.outerSheet(containing: focused), let group = Self.lockGroup(in: sheet) else { return state }
        state.windowCount = 1
        state.hasUsePasswordButton = group.secureFields.isEmpty && group.plainButtons.count == 1
        if group.secureFields.contains(where: { CFEqual($0, focused) }) { state.focusedSubrole = "AXSecureTextField" }
        var pid: pid_t = 0
        if AXUIElementGetPid(focused, &pid) == .success {
            state.focusedOwner = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        return state
    }

    private func lockGroupInFocusedSheet(_ axApp: AXUIElement) -> LockGroup? {
        guard let focused = axElement(axApp, kAXFocusedUIElementAttribute),
              let sheet = Self.outerSheet(containing: focused) else { return nil }
        return Self.lockGroup(in: sheet)
    }

    /// The outermost `AXSheet` at or above `element` (the element itself counts), or nil when none is on the way up.
    private static func outerSheet(containing element: AXUIElement, maxLevels: Int = 12) -> AXUIElement? {
        var current: AXUIElement? = element
        var outermost: AXUIElement?
        var levels = 0
        while let candidate = current, levels < maxLevels {
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(candidate, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String {
                if role == "AXSheet" { outermost = candidate }
                if role == "AXWindow" || role == "AXApplication" { break }
            }
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(candidate, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parent = parentValue else { break }
            current = unsafeBitCast(parent, to: AXUIElement.self)
            levels += 1
        }
        return outermost
    }

    /// Breadth-first search below `sheet` for the element whose children include exactly two images and two static
    /// texts, which is the lock screen's content; returns the plain buttons and secure fields among those children.
    private static func lockGroup(in sheet: AXUIElement, maxDepth: Int = 8, maxElements: Int = 200) -> LockGroup? {
        var queue: [(element: AXUIElement, depth: Int)] = [(sheet, 0)]
        var visited = 0
        while let (element, depth) = queue.first {
            queue.removeFirst()
            guard visited < maxElements else { break }
            visited += 1
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else { continue }
            var images = 0, texts = 0
            var group = LockGroup()
            for child in children {
                var roleValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
                      let role = roleValue as? String else { continue }
                var subroleValue: CFTypeRef?
                let subrole = AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subroleValue) == .success
                    ? subroleValue as? String : nil
                switch role {
                case "AXImage": images += 1
                case "AXStaticText": texts += 1
                case "AXButton" where subrole == nil: group.plainButtons.append(child)
                case "AXTextField" where subrole == "AXSecureTextField": group.secureFields.append(child)
                default: break
                }
            }
            if images == 2, texts == 2 { return group }
            if depth < maxDepth { queue.append(contentsOf: children.map { ($0, depth + 1) }) }
        }
        return nil
    }

    /// Whether a scan looks like the Touch ID / Apple Watch lock screen. The app needs exactly one plain button.
    /// The popup is stricter, because other popups (a passkey sheet, a code prompt) can also hold one button: it
    /// must show the two images and two static texts the spike found, plus the single button. A mismatch
    /// reads as "not the lock screen", so an unexpected layout shows nothing.
    private func isUsePasswordChoice(_ scan: Scan) -> Bool {
        guard scan.plainButtons.count == 1 else { return false }
        switch surface {
        case .app: return true
        case .autofillPopup: return scan.imageCount == 2 && scan.staticTextCount == 2
        case .browserSheet: return false // read through the sheet, never through a window scan
        }
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
    private struct Scan {
        var hasSplitGroup = false
        var plainButtons: [AXUIElement] = []
        var imageCount = 0
        var staticTextCount = 0
    }

    private static func scan(window: AXUIElement, maxDepth: Int = 6, maxElements: Int = 400) -> Scan {
        var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
        var visited = 0
        var result = Scan()
        while let (element, depth) = queue.first {
            queue.removeFirst()
            guard visited < maxElements else { break }
            visited += 1
            guard depth <= maxDepth else { continue }
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String {
                if role == "AXSplitGroup" { return Scan(hasSplitGroup: true) }
                if role == "AXImage" { result.imageCount += 1 }
                if role == "AXStaticText" { result.staticTextCount += 1 }
                if role == "AXButton" {
                    var subroleValue: CFTypeRef?
                    let hasSubrole = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success
                    if !hasSubrole { result.plainButtons.append(element) }
                }
            }
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else { continue }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return result
    }
}

/// Watches one Passwords lock surface and reports lock-state changes on the main thread.
@MainActor
final class LivePasswordsLockWatcher: PasswordsLockWatching {
    /// Fires on the main thread whenever the lock state changes.
    var onChange: ((PasswordsLockState) -> Void)?

    private let reader: LivePasswordsAXReader
    private let tracker: PasswordsLockTracker
    private let surface: PasswordsSurface

    private var isRunning = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var axObserver: AXObserver?
    /// Re-reads the state while Passwords is frontmost. AX notifications from Passwords are not reliable
    /// enough on their own (a lock or a screen change can arrive without one), so this closes the gap.
    private var pollTimer: Timer?
    private static let pollInterval: TimeInterval = 1.0

    init(surface: PasswordsSurface = .app) {
        let reader = LivePasswordsAXReader(surface: surface)
        self.reader = reader
        self.surface = surface
        // The forwarding is wired after all stored properties are initialized: Swift
        // forbids capturing self in a closure that is stored during init.
        self.tracker = PasswordsLockTracker(reader: reader, allowedFocusOwners: surface.allowedFocusOwners) { _ in }
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
              app.bundleIdentifier == reader.bundleID else { return }
        installAXObserver()
        startPolling()
        tracker.refresh()
    }

    private func passwordsDidDeactivate(_ note: Notification) {
        guard isRunning else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == reader.bundleID else { return }
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
        guard axObserver == nil, surface.usesAXObserver,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == reader.bundleID })
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

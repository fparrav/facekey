//
//  NotchWindow.swift
//  facekey
//
//  Borderless, transparent, click-through panel. Created once and never resized —
//  all expansion/collapse is SwiftUI animating content inside this fixed window
//  (never call setFrame/setContentSize on it; only setFrameOrigin, to reposition).
//

import AppKit
import CoreGraphics

final class NotchWindow: NSPanel {
    /// Above regular, menu-bar, screen-saver, and assistive overlays. The
    /// shielding level is the highest public Core Graphics window tier;
    private static let overlayWindowLevel = NSWindow.Level(
        rawValue: Int(CGShieldingWindowLevel()) + 1
    )

    /// Whether the panel may become key. Tracked separately from
    /// `ignoresMouseEvents`, which `NotchWindowController` flips on and off as
    /// the cursor moves over/away from the visible panel
    var acceptsKey = false

    /// Sees every left mouse-down before AppKit routes it. The sudo prompt resolves its
    /// buttons here instead of through a control action, so an accessibility press or an
    /// AppleScript click, which send no mouse event, can never accept it.
    var onLeftMouseDown: ((NSEvent) -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        level = Self.overlayWindowLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // Decorative by default — clicks pass through until a failed attempt is
        // waiting to be tapped for retry (see NotchWindowController.setInteractive).
        ignoresMouseEvents = true
    }

    /// Must become key while interactive or the tap-to-retry gesture never receives
    /// the click; never becomes main, so it doesn't take over as the app's primary window.
    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onLeftMouseDown?(event) }
        super.sendEvent(event)
    }
}

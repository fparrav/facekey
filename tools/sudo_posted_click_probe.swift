//
//  sudo_posted_click_probe.swift
//  facekey (tools)
//
//  Manual check for the sudo overlay: posts a left click as a program would, on the Accept button
//  (top centre of the notch display, or of the main display without one, or at the given X Y). With the overlay open the
//  request must end as Cancel and sudo must ask for the password.
//
//      /usr/bin/swiftc -O -o build/post_click tools/sudo_posted_click_probe.swift && build/post_click [X Y]
//
import ApplicationServices
import CoreGraphics
import AppKit

// The overlay opens on the notch display when there is one, otherwise on the main display.
let target = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
let displayID = (target.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
let frame = CGDisplayBounds(displayID)
let x = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[1])! : frame.midX + 95
let y = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : frame.minY + 216
let point = CGPoint(x: x, y: y)
// Without Accessibility for the app running this, macOS drops posted events silently.
if !AXIsProcessTrusted() {
    print("Warning: this terminal does not have Accessibility, so macOS will ignore the click. Grant it in Privacy & Security → Accessibility and run again.")
}
// The overlay only takes clicks once the pointer has been over it, so the pointer moves first and rests there.
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.6)
for type in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}
print("display \(target.localizedName), posted click at \(point)")

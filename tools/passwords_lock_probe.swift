//
//  passwords_lock_probe.swift
//  facekey (tools)
//
//  Standalone, read-only probe for the Passwords app (com.apple.Passwords):
//  finds the running app and prints to stdout, without touching it,
//
//  - whether the process is the frontmost app,
//  - its windows (title, role, subrole, frame),
//  - a depth-limited tree of the AX hierarchy of the first window:
//    role, subrole, title, description, value kind, enabled, focused and
//    the AX actions of every element,
//  - the app's currently focused UI element.
//
//  It only reads: no AX actions, no attribute writes, no events, no
//  keystrokes, no network. The value of a secure text field is never
//  printed (only its kind).
//
//  Build and run:
//
//      swiftc -O tools/passwords_lock_probe.swift -o /tmp/passwords_lock_probe
//      /tmp/passwords_lock_probe [--depth N] [--delay S]   # default depth 8
//
//  Exit codes: 0 = tree printed, 1 = bad arguments, 2 = Passwords is not
//  running, 3 = Accessibility not granted (System Settings > Privacy &
//  Security > Accessibility).
//

import Foundation
import ApplicationServices
import AppKit

/// Read one AX attribute; nil when the element doesn't expose it or the
/// query fails. Read-only: this never performs actions or sets values.
func axAttribute(_ element: AXUIElement, _ name: String) -> Any? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func axString(_ element: AXUIElement, _ name: String) -> String? {
    axAttribute(element, name) as? String
}

/// An AX attribute whose value is another element (e.g. the focused one).
func axElement(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let ref = value else { return nil }
    return unsafeBitCast(ref, to: AXUIElement.self)
}

/// An AX attribute whose value is an AXValue (position and size).
func axValue(_ element: AXUIElement, _ name: String) -> AXValue? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let ref = value else { return nil }
    return unsafeBitCast(ref, to: AXValue.self)
}

/// The kind of an element's AX value. The value itself is never printed:
/// a secure text field only shows "secure (hidden)".
func valueKind(of element: AXUIElement) -> String {
    if (axString(element, kAXRoleAttribute) ?? "") == "AXTextField",
       (axString(element, kAXSubroleAttribute) ?? "") == "AXSecureTextField" {
        return "secure (hidden)"
    }
    guard let value = axAttribute(element, kAXValueAttribute) else { return "-" }
    if value is Bool { return "bool" }
    if value is Int { return "number" }
    if value is Double { return "number" }
    if value is String { return "string" }
    return "other"
}

/// The AX actions the element supports (e.g. AXPress, AXShowMenu).
func axActions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success, let names = names else { return [] }
    return (names as? [String]) ?? []
}

/// One line per element: role, subrole, title, description, value kind,
/// enabled, focused and the AX actions.
func describeElement(_ element: AXUIElement) -> String {
    let role = axString(element, kAXRoleAttribute) ?? "?"
    let subrole = axString(element, kAXSubroleAttribute) ?? "-"
    let title = axString(element, kAXTitleAttribute) ?? ""
    let description = axString(element, kAXDescriptionAttribute) ?? ""
    let enabled = (axAttribute(element, kAXEnabledAttribute) as? Bool) ?? false
    let focused = (axAttribute(element, kAXFocusedAttribute) as? Bool) ?? false
    let actions = axActions(element)
    return "role=\(role) subrole=\(subrole) title=\"\(title)\" description=\"\(description)\" value=\(valueKind(of: element)) enabled=\(enabled ? "yes" : "no") focused=\(focused ? "yes" : "no") actions=[\(actions.joined(separator: ", "))]"
}

/// The element's frame as "x, y, w, h"; "?" when it doesn't expose one.
func axFrame(_ element: AXUIElement) -> String {
    guard let position = axValue(element, kAXPositionAttribute),
          let size = axValue(element, kAXSizeAttribute)
    else { return "frame=?" }
    var point = CGPoint.zero
    var sizeOut = CGSize.zero
    AXValueGetValue(position, .cgPoint, &point)
    AXValueGetValue(size, .cgSize, &sizeOut)
    return "frame=(x=\(Int(point.x)), y=\(Int(point.y)), w=\(Int(sizeOut.width)), h=\(Int(sizeOut.height)))"
}

/// Prints the element, then its children, down to `maxDepth` levels below
/// the root (the root is depth 0).
func printTree(_ element: AXUIElement, depth: Int, maxDepth: Int) {
    print(String(repeating: "  ", count: depth) + describeElement(element))
    guard depth < maxDepth else { return }
    let children = (axAttribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    for child in children {
        printTree(child, depth: depth + 1, maxDepth: maxDepth)
    }
}

let bundleID = "com.apple.Passwords"
let defaultDepth = 8

let usage = """
    Usage: passwords_lock_probe [--depth N] [--delay SECONDS]

    Dumps the Accessibility (AX) hierarchy of the running Passwords app
    (com.apple.Passwords) without touching it. Read-only: it performs no
    AX actions, writes no attributes, posts no events and never prints
    the value of a secure text field.

    Options:
      --depth N   how many levels below the first window to dump (default 8)
      --delay S   wait S seconds before reading, to bring Passwords to the front
      --help      show this help and exit 0

    Exit codes:
      0  tree printed
      1  bad arguments
      2  Passwords is not running
      3  Accessibility not granted — enable it in System Settings >
         Privacy & Security > Accessibility for the terminal that runs
         this probe, then run again
    """

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") || args.contains("-h") {
    print(usage)
    exit(0)
}

var depth = defaultDepth
var delay = 0
var index = 0
while index < args.count {
    if args[index] == "--depth", index + 1 < args.count, let value = Int(args[index + 1]), value >= 0 {
        depth = value
        index += 2
    } else if args[index] == "--delay", index + 1 < args.count, let value = Int(args[index + 1]), value >= 0 {
        delay = value
        index += 2
    } else {
        print("Unknown argument: \(args[index])")
        print(usage)
        exit(1)
    }
}

guard AXIsProcessTrusted() else {
    print("Accessibility is not granted to this terminal. Enable it in System Settings > Privacy & Security > Accessibility and run again.")
    exit(3)
}

if delay > 0 {
    // Lets you bring Passwords to the front (locked or unlocked) before the dump.
    print("waiting \(delay)s: switch to Passwords now...")
    fflush(stdout)
    sleep(UInt32(delay))
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
    print("Passwords (\(bundleID)) is not running. Launch it and run again.")
    exit(2)
}

let axApp = AXUIElementCreateApplication(app.processIdentifier)

let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
print("app: \(bundleID) (pid \(app.processIdentifier), \(app.bundleURL?.path ?? "?"))")
print("frontmost: \(frontmost ? "yes" : "no")")

var windowsValue: CFTypeRef?
let windowsError = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue)
let windows = windowsError == .success ? (windowsValue as? [AXUIElement] ?? []) : []
print("windows: \(windows.count)")
for (i, window) in windows.enumerated() {
    print("window \(i): \(describeElement(window)) \(axFrame(window))")
}

if let focused = axElement(axApp, kAXFocusedUIElementAttribute) {
    print("focused element: \(describeElement(focused))")
} else {
    print("focused element: none")
}

print("depth: \(depth)")
guard !windows.isEmpty else {
    print("tree: none (the app has no windows)")
    exit(0)
}
print("tree of window 0 (depth \(depth)):")
printTree(windows[0], depth: 0, maxDepth: depth)
exit(0)

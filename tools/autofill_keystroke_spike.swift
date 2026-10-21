//
//  autofill_keystroke_spike.swift
//  facekey (tools)
//
//  Throwaway spike for the AutoFill popup unlock (task 1.2). It answers one question: do HID
//  keystrokes reach the popup's secure password field while the browser stays frontmost?
//
//  It waits (up to --seconds, default 60) until the system-wide focused element is a secure text field
//  owned by one of the allowlisted processes, then types the DUMMY text "facekey" (never the Mac
//  password) and does NOT press Return. You confirm by eye that seven dots appeared in the popup's
//  field. If the focused secure field is owned by anything else (a page field, another app), it types
//  nothing and says so.
//
//  It never reads a field's value. It prints only owner bundle ids, roles and subroles.
//
//  Build and run (from the user's Terminal, with Accessibility granted to that Terminal):
//
//      swiftc -O tools/autofill_keystroke_spike.swift -o /tmp/autofill_keystroke_spike
//      /tmp/autofill_keystroke_spike [--seconds N] [--no-type]
//
//  --no-type only reports what the check would decide, which is how to test the "page field is
//  rejected" half: click a login field in a web page and run it.
//
//  Exit codes: 0 = typed (or --no-type and the field was accepted), 1 = bad arguments,
//  2 = timed out, 3 = Accessibility not granted, 4 = focused secure field is not an allowed owner.
//

import AppKit
import ApplicationServices
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let allowedOwners: Set<String> = ["com.apple.AutoFillPanelService", "com.apple.SafariPlatformSupport.Helper"]

var seconds = 60
var shouldType = true
var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
    case "--seconds":
        guard let value = arguments.first, let parsed = Int(value) else { exit(1) }
        arguments.removeFirst()
        seconds = parsed
    case "--no-type":
        shouldType = false
    default:
        fputs("unknown argument \(argument)\n", stderr)
        exit(1)
    }
}

guard AXIsProcessTrusted() else {
    fputs("Accessibility is not granted to this terminal\n", stderr)
    exit(3)
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

/// Every place a focused element can be asked for: the system-wide element, the system's focused
/// application, the frontmost app and the AutoFill panel service itself. A popup drawn by a view service
/// may answer on some of these and not others, which is part of what this spike records.
func focusedCandidates() -> [(source: String, element: AXUIElement)] {
    var found: [(String, AXUIElement)] = []
    let system = AXUIElementCreateSystemWide()
    if let ref = attribute(system, kAXFocusedUIElementAttribute) {
        found.append(("system", unsafeBitCast(ref, to: AXUIElement.self)))
    }
    if let appRef = attribute(system, kAXFocusedApplicationAttribute) {
        let app = unsafeBitCast(appRef, to: AXUIElement.self)
        if let ref = attribute(app, kAXFocusedUIElementAttribute) {
            found.append(("focusedApp", unsafeBitCast(ref, to: AXUIElement.self)))
        }
    }
    if let front = NSWorkspace.shared.frontmostApplication {
        let app = AXUIElementCreateApplication(front.processIdentifier)
        if let ref = attribute(app, kAXFocusedUIElementAttribute) {
            found.append(("frontmost", unsafeBitCast(ref, to: AXUIElement.self)))
        }
    }
    for service in NSWorkspace.shared.runningApplications where service.bundleIdentifier == "com.apple.AutoFillPanelService" {
        let app = AXUIElementCreateApplication(service.processIdentifier)
        if let ref = attribute(app, kAXFocusedUIElementAttribute) {
            found.append(("panelService", unsafeBitCast(ref, to: AXUIElement.self)))
        }
    }
    return found
}

func ownerBundle(of element: AXUIElement) -> String {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "?"
}

/// The first candidate that is a secure text field, with its owner bundle id.
func focusedSecureField() -> (owner: String, subrole: String)? {
    for candidate in focusedCandidates() where attribute(candidate.element, kAXSubroleAttribute) as? String == "AXSecureTextField" {
        return (ownerBundle(of: candidate.element), "AXSecureTextField")
    }
    return nil
}

func post(_ character: UniChar, source: CGEventSource?) {
    var unit = character
    for keyDown in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
        event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
        event?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.01)
    }
}

/// One line naming the focused elements by source: owner, role and subrole only, never a value.
func focusSummary() -> String {
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
    let parts = focusedCandidates().map { candidate -> String in
        let role = attribute(candidate.element, kAXRoleAttribute) as? String ?? "-"
        let subrole = attribute(candidate.element, kAXSubroleAttribute) as? String ?? "-"
        return "\(candidate.source)[owner=\(ownerBundle(of: candidate.element)) role=\(role) subrole=\(subrole)]"
    }
    return "frontmost=\(front) " + (parts.isEmpty ? "focused=none" : parts.joined(separator: " "))
}

print("waiting up to \(seconds)s for a focused secure field; open the AutoFill popup now")
let deadline = Date().addingTimeInterval(TimeInterval(seconds))
var lastSummary = ""
while Date() < deadline {
    let summary = focusSummary()
    if summary != lastSummary {
        print("focus: \(summary)")
        lastSummary = summary
    }
    if let field = focusedSecureField() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        print("focused secure field owner=\(field.owner) frontmost=\(front)")
        guard allowedOwners.contains(field.owner) else {
            print("REJECTED: owner is not on the allowlist, nothing typed")
            exit(4)
        }
        guard shouldType else {
            print("ACCEPTED (--no-type): would type the dummy text")
            exit(0)
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for unit in "facekey".utf16 { post(unit, source: source) }
        print("typed 7 dummy characters, no Return. Look at the popup: do seven dots show in its field?")
        exit(0)
    }
    // Pump the run loop so NSWorkspace sees app switches; a bare sleep leaves frontmostApplication stale.
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
}
print("timed out, no focused secure field seen")
exit(2)

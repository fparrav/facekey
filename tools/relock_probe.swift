//
//  relock_probe.swift
//  facekey (tools)
//
//  Standalone probe: checks that posting Control-Command-Q through the HID
//  tap locks the screen on this macOS release. Needs Accessibility granted
//  to the terminal that runs it. It WILL lock your Mac.
//
//  Build and run:
//
//      swiftc -O -parse-as-library -o /tmp/relock_probe tools/relock_probe.swift && /tmp/relock_probe
//

import Foundation
import ApplicationServices
import CoreGraphics

@main
enum RelockProbe {
    static func main() {
        guard AXIsProcessTrusted() else {
            print("Accessibility is not granted to this terminal. Enable it in System Settings > Privacy & Security > Accessibility and run again.")
            exit(2)
        }
        print("Locking in 3 s with Control-Command-Q...")
        for n in stride(from: 3, to: 0, by: -1) {
            print("\(n)...")
            sleep(1)
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let qKey: CGKeyCode = 12
        let down = CGEvent(keyboardEventSource: source, virtualKey: qKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: qKey, keyDown: false)
        for event in [down, up] {
            event?.flags = [.maskControl, .maskCommand]
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        sleep(1)
        let dict = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = (dict?["CGSSessionScreenIsLocked"] as? Bool) ?? false
        print(locked ? "RESULT: locked" : "RESULT: NOT locked")
        exit(locked ? 0 : 1)
    }
}

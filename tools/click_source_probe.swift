//
//  click_source_probe.swift
//  facekey (tools)
//
//  Standalone probe: can the app tell a real hardware mouse click from a
//  click synthesized by another process (CGEvent / osascript) when the click
//  lands on a non-activating panel? It shows a small "Click Accept" panel
//  with an Accept button on a borderless, non-activating window and logs the
//  CGEvent source fields of every left mouse down, classifying each click as
//  hardware (source pid 0) or synthetic (non-zero pid).
//
//  Build and run:
//
//      swiftc -o /private/tmp/click_source_probe tools/click_source_probe.swift && /private/tmp/click_source_probe --seconds 120
//

import AppKit
import CoreGraphics

private let logURL = URL(fileURLWithPath: "/private/tmp/facekey-click-probe.log")

/// The panel never becomes key, so a plain button would ignore the very
/// first click; accepting first mouse makes it react to that one.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ProbePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        let size = NSSize(width: 260, height: 90)
        var frame = NSRect(origin: .zero, size: size)
        if let visible = NSScreen.main?.visibleFrame {
            frame.origin = CGPoint(x: visible.midX - size.width / 2,
                                   y: visible.midY - size.height / 2)
        }
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        self.level = .statusBar
        self.isOpaque = true
        self.backgroundColor = .windowBackgroundColor

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        let label = NSTextField(labelWithString: "Click Accept")
        label.frame = NSRect(x: 24, y: 35, width: 120, height: 20)
        let button = FirstMouseButton(frame: NSRect(x: 156, y: 29, width: 80, height: 32))
        button.title = "Accept"
        content.addSubview(label)
        content.addSubview(button)
        self.contentView = content
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            if let cg = event.cgEvent {
                // A source pid of 0 means the HID system produced the event
                // (hardware mouse); a non-zero pid means a process posted it.
                let pid = Int(cg.getIntegerValueField(.eventSourceUnixProcessID))
                let stateID = Int(cg.getIntegerValueField(.eventSourceStateID))
                let userData = Int(cg.getIntegerValueField(.eventSourceUserData))
                let verdict = pid == 0 ? "hardware" : "synthetic"
                emit("click pid=\(pid) stateID=\(stateID) userData=\(userData) verdict=\(verdict)")
            } else {
                emit("click cgEvent=nil verdict=unknown")
            }
        }
        super.sendEvent(event)
    }

    private func emit(_ line: String) {
        print(line)
        let bytes = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: bytes)
            try? handle.close()
        } else {
            try? bytes.write(to: logURL)
        }
    }
}

// Parse --seconds N (default 120); after N seconds the probe exits 0.
var seconds = 120.0
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--seconds"), flag + 1 < arguments.count,
   let value = Double(arguments[flag + 1]) {
    seconds = value
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let panel = ProbePanel()
panel.orderFrontRegardless()

print("click_source_probe: accepting clicks for \(seconds) seconds (log: \(logURL.path)).")

DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    exit(0)
}

app.run()

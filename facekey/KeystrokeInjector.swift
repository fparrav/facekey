//
//  KeystrokeInjector.swift
//  facekey
//
//  Synthesizes keystrokes via CGEvent, posted at the HID tap so they reach the lock screen's secure text field.
//

import Foundation
import ApplicationServices
import CoreGraphics

enum KeystrokeError: LocalizedError {
    case accessibilityNotGranted
    case eventCreationFailed
    /// `shouldContinue` said stop; nothing more was posted. Not shown to the user.
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return nil
        case .accessibilityNotGranted:
            return String(localized: "Accessibility permission required. Open System Settings → Privacy & Security → Accessibility and enable Facekey.")
        case .eventCreationFailed:
            return String(localized: "Couldn't create CGEvent for keystroke.")
        }
    }
}

enum KeystrokeInjector {
    /// Returns true if the app has Accessibility permission (no prompt).
    nonisolated static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Triggers the system prompt to grant Accessibility (deep links to System Settings).
    @discardableResult
    nonisolated static func promptForAccessibility() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Types the UTF-8 bytes into whatever has keyboard focus, then presses Return. Takes `Data` rather than `String` so the
    /// caller can hold the plaintext as a zero-able buffer; the UTF-16 form posted to the system lives in a buffer that is
    /// zeroed before this returns, and no `String` or array copy of the password is ever made. Blocking.
    nonisolated static func typeAndReturn(_ passwordBytes: Data) throws {
        try typeAndReturn(passwordBytes, shouldContinue: { true })
    }

    /// Same, but asks `shouldContinue` before the field is cleared, between text batches and before Return. Once it
    /// answers false nothing more is posted and this throws `KeystrokeError.cancelled`.
    nonisolated static func typeAndReturn(_ passwordBytes: Data, shouldContinue: () -> Bool) throws {
        guard isAccessibilityTrusted() else {
            throw KeystrokeError.accessibilityNotGranted
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard shouldContinue() else { throw KeystrokeError.cancelled }
        try withUTF16(passwordBytes) { utf16 in
            try clearFocusedField(source: source)
            try postUnicodeText(utf16, source: source, shouldContinue: shouldContinue)
        }
        guard shouldContinue() else { throw KeystrokeError.cancelled }
        try postReturn(source: source)
    }

    /// Transcodes UTF-8 bytes to UTF-16 in a buffer this function owns and zeroes before returning, so no immutable
    /// copy of the plaintext (a `String` or an `Array`, neither of which can be wiped) is ever created. Throws
    /// `eventCreationFailed` for bytes that are not valid UTF-8.
    nonisolated static func withUTF16<T>(_ utf8: Data, _ body: (UnsafeBufferPointer<UInt16>) throws -> T) throws -> T {
        // UTF-16 never needs more code units than UTF-8 has bytes.
        let capacity = max(utf8.count, 1)
        let buffer = UnsafeMutableBufferPointer<UInt16>.allocate(capacity: capacity)
        buffer.initialize(repeating: 0)
        defer {
            buffer.update(repeating: 0)
            buffer.deallocate()
        }
        var count = 0
        let hadError = transcode(utf8.makeIterator(), from: UTF8.self, to: UTF16.self, stoppingOnError: true) { unit in
            buffer[count] = unit
            count += 1
        }
        guard !hadError else { throw KeystrokeError.eventCreationFailed }
        return try body(UnsafeBufferPointer(rebasing: buffer[0..<count]))
    }

    /// Wipes anything already typed into the focused field (e.g. a stray keypress
    /// on the lock screen) so it isn't prepended to the password: ⌘→ to the end,
    /// then ⌘⌫ to delete back to the start. Both are positional keys, so this
    /// behaves the same on every keyboard layout — unlike ⌘A, whose "A" moves.
    private nonisolated static func clearFocusedField(source: CGEventSource?) throws {
        let rightArrow: CGKeyCode = 0x7C
        let delete: CGKeyCode = 0x33
        try postKey(rightArrow, flags: .maskCommand, source: source)
        try postKey(delete, flags: .maskCommand, source: source)
    }

    /// Posts a virtual key down/up, wrapped in a real ⌘ down/up when `flags`
    /// includes `.maskCommand` — some text fields ignore a bare flag without it.
    private nonisolated static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = [], source: CGEventSource?) throws {
        let command: CGKeyCode = 0x37
        let usesCommand = flags.contains(.maskCommand)
        if usesCommand {
            guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: true) else {
                throw KeystrokeError.eventCreationFailed
            }
            commandDown.flags = .maskCommand
            commandDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.012)
        }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw KeystrokeError.eventCreationFailed
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
        keyUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
        if usesCommand {
            guard let commandUp = CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: false) else {
                throw KeystrokeError.eventCreationFailed
            }
            commandUp.flags = []
            commandUp.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.012)
        }
    }

    /// Quartz reliably delivers only a small Unicode payload per keyboard event.
    /// Batching at this conservative limit avoids the undocumented truncation seen
    /// with longer payloads, while replacing one down/up pair per character with
    /// one pair per batch.
    nonisolated private static let maximumUnicodeBatchLength = 20
    nonisolated private static let unicodeEventInterval: TimeInterval = 0.004

    /// Posts the password in small UTF-16 batches. Splitting occurs only between
    /// surrogate pairs, so non-BMP password characters are never corrupted.
    private nonisolated static func postUnicodeText(_ buffer: UnsafeBufferPointer<UInt16>, source: CGEventSource?, shouldContinue: () -> Bool) throws {
        do {
            guard let base = buffer.baseAddress else { return }
            var start = 0

            while start < buffer.count {
                guard shouldContinue() else { throw KeystrokeError.cancelled }
                var end = min(start + maximumUnicodeBatchLength, buffer.count)
                // Do not split a high/low-surrogate pair across separate key events.
                if end < buffer.count,
                   (0xD800...0xDBFF).contains(buffer[end - 1]) {
                    end -= 1
                }
                try postUnicode(
                    base.advanced(by: start),
                    length: end - start,
                    source: source
                )
                start = end
            }
        }
    }

    /// Unicode injection bypasses keyboard-layout issues. The password is placed
    /// on a key-down event as a text batch; the matching key-up maintains normal
    /// secure-field event semantics.
    private nonisolated static func postUnicode(
        _ unicode: UnsafePointer<UInt16>,
        length: Int,
        source: CGEventSource?
    ) throws {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw KeystrokeError.eventCreationFailed
        }
        keyDown.keyboardSetUnicodeString(stringLength: length, unicodeString: unicode)
        keyUp.keyboardSetUnicodeString(stringLength: length, unicodeString: unicode)
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: unicodeEventInterval)
        keyUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: unicodeEventInterval)
    }

    /// Physical Return key (virtual key 0x24).
    private nonisolated static func postReturn(source: CGEventSource?) throws {
        let returnKey: CGKeyCode = 0x24
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false) else {
            throw KeystrokeError.eventCreationFailed
        }
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
        keyUp.post(tap: .cghidEventTap)
    }
}

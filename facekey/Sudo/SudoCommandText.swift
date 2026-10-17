//
//  SudoCommandText.swift
//  facekey
//
//  Renders the sudo command line for the approval prompt: escapes control and
//  direction characters so arguments can't forge the prompt, then clips long
//  text to a fixed length keeping both head and tail. Foundation only.
//

import Foundation

enum SudoCommandText {
    static let maxLength = 120

    static func display(argv: [String], executableOnly: Bool) -> String {
        guard !argv.isEmpty else { return "" }
        let escaped = argv.map(escape)
        let text = executableOnly ? escaped[0] : escaped.joined(separator: " ")
        return clip(text)
    }

    /// Replaces control/format/separator scalars with \u{XXXX} so they render literally.
    private static func escape(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                out += String(format: "\\u{%04X}", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Clips to maxLength keeping head and tail around an ellipsis.
    private static func clip(_ text: String) -> String {
        guard text.count > maxLength else { return text }
        let headCount = (maxLength - 1) / 2
        let head = text.prefix(headCount)
        let tailCount = maxLength - 1 - head.count
        let tail = text.suffix(tailCount)
        return String(head) + "…" + String(tail)
    }
}

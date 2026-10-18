import Foundation

/// The accent and the shades derived from it as plain RGB, so the maths can be
/// checked offline. `FacekeyTheme` wraps these in SwiftUI colours.
struct AccentRGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
}

enum AccentPalette {
    static func rgb(hex: String) -> AccentRGB {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(digits, radix: 16) ?? 0
        return AccentRGB(
            r: Double((value >> 16) & 0xFF) / 255,
            g: Double((value >> 8) & 0xFF) / 255,
            b: Double(value & 0xFF) / 255
        )
    }

    static func accent(_ choice: AccentChoice) -> AccentRGB { rgb(hex: choice.hex) }
    static func ink(_ choice: AccentChoice) -> AccentRGB { rgb(hex: choice.inkHex) }

    /// White at 0, the accent at 1.
    static func whiteToAccent(_ choice: AccentChoice, _ t: Double) -> AccentRGB {
        let t = min(max(t, 0), 1)
        let a = accent(choice)
        return AccentRGB(r: 1 + (a.r - 1) * t, g: 1 + (a.g - 1) * t, b: 1 + (a.b - 1) * t)
    }

    static func pale(_ choice: AccentChoice) -> AccentRGB { shade(choice, lightness: 0.91, saturation: 1.0) }
    static func bright(_ choice: AccentChoice) -> AccentRGB { shade(choice, lightness: 0.75, saturation: 1.0) }

    static func deep(_ choice: AccentChoice) -> AccentRGB {
        let hsl = hsl(accent(choice))
        return rgb(hue: hsl.h, saturation: 0.75 * hsl.s, lightness: max(hsl.l - 0.13, 0.2))
    }

    private static func shade(_ choice: AccentChoice, lightness: Double, saturation: Double) -> AccentRGB {
        rgb(hue: hsl(accent(choice)).h, saturation: saturation, lightness: lightness)
    }

    private static func hsl(_ c: AccentRGB) -> (h: Double, s: Double, l: Double) {
        let maximum = max(c.r, c.g, c.b), minimum = min(c.r, c.g, c.b)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        let hue: Double
        if maximum == c.r { hue = ((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6) / 6 }
        else if maximum == c.g { hue = ((c.b - c.r) / delta + 2) / 6 }
        else { hue = ((c.r - c.g) / delta + 4) / 6 }
        return (hue < 0 ? hue + 1 : hue, saturation, lightness)
    }

    private static func rgb(hue: Double, saturation: Double, lightness: Double) -> AccentRGB {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let x = chroma * (1 - abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - chroma / 2
        let components: (Double, Double, Double)
        switch Int(hue * 6) % 6 {
        case 0: components = (chroma, x, 0)
        case 1: components = (x, chroma, 0)
        case 2: components = (0, chroma, x)
        case 3: components = (0, x, chroma)
        case 4: components = (x, 0, chroma)
        default: components = (chroma, 0, x)
        }
        return AccentRGB(r: components.0 + m, g: components.1 + m, b: components.2 + m)
    }
}

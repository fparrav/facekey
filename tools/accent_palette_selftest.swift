//
//  accent_palette_selftest.swift
//  facekey (tools)
//
//  Offline self-test for facekey/Settings/AccentPalette.swift: switching the accent
//  changes the accent and every shade derived from it, switching back restores them,
//  the shades keep their lightness order, and white-to-accent reaches both ends.
//  This project has no test target, so this compiles as a standalone script against the real files:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/accent_palette_selftest facekey/Settings/AccentChoice.swift facekey/Settings/AccentPalette.swift tools/accent_palette_selftest.swift && /private/tmp/accent_palette_selftest
//
//  Prints PASS/FAIL per check; exits 0 when every check passes, 1 otherwise.
//

import Foundation

var failures = 0

func check(_ cond: Bool, _ name: String) {
    if cond {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}

func near(_ a: AccentRGB, _ b: AccentRGB) -> Bool {
    abs(a.r - b.r) < 1e-9 && abs(a.g - b.g) < 1e-9 && abs(a.b - b.b) < 1e-9
}

func lightness(_ c: AccentRGB) -> Double { (max(c.r, c.g, c.b) + min(c.r, c.g, c.b)) / 2 }

@main
enum AccentPaletteSelfTest {
    static func main() {
        let green = AccentChoice.green
        let amber = AccentChoice.amber

        check(AccentPalette.accent(green) != AccentPalette.accent(amber), "the accent differs between green and amber")
        check(AccentPalette.pale(green) != AccentPalette.pale(amber), "the pale shade follows the accent")
        check(AccentPalette.bright(green) != AccentPalette.bright(amber), "the bright shade follows the accent")
        check(AccentPalette.deep(green) != AccentPalette.deep(amber), "the deep shade follows the accent")

        let first = AccentPalette.accent(green)
        _ = AccentPalette.accent(amber)
        check(AccentPalette.accent(green) == first, "switching away and back restores the green accent")

        var distinct = Set<String>()
        for choice in AccentChoice.allCases {
            let a = AccentPalette.accent(choice)
            distinct.insert("\(a.r),\(a.g),\(a.b)")
        }
        check(distinct.count == AccentChoice.allCases.count, "every accent has its own colour")

        for choice in AccentChoice.allCases {
            let l = [AccentPalette.deep(choice), AccentPalette.accent(choice), AccentPalette.bright(choice), AccentPalette.pale(choice)].map(lightness)
            check(l[0] < l[1] && l[1] < l[2] && l[2] < l[3], "\(choice.rawValue): shades run deep < accent < bright < pale")
        }

        let g = AccentPalette.rgb(hex: "#34D399")
        check(abs(g.r - 0x34 / 255.0) < 1e-9 && abs(g.g - 0xD3 / 255.0) < 1e-9 && abs(g.b - 0x99 / 255.0) < 1e-9, "hex parsing reads #34D399")
        check(AccentPalette.whiteToAccent(green, 0) == AccentRGB(r: 1, g: 1, b: 1), "white-to-accent is white at 0")
        check(near(AccentPalette.whiteToAccent(green, 1), AccentPalette.accent(green)), "white-to-accent is the accent at 1")
        check(near(AccentPalette.whiteToAccent(green, 2), AccentPalette.accent(green)), "white-to-accent clamps above 1")
        check(AccentPalette.ink(green) == AccentPalette.rgb(hex: "#0C1410"), "the ink is #0C1410")

        if failures == 0 {
            print("All accent palette self-tests passed.")
            exit(0)
        }
        print("\(failures) accent palette self-test(s) failed.")
        exit(1)
    }
}

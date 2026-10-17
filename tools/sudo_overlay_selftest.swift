//
//  sudo_overlay_selftest.swift
//  facekey (tools)
//
//  Offline self-test for the sudo prompt's click targets and click-source label:
//  only the bottom button band answers, the left half is the negative choice and the
//  right half the positive one, and only pid 0 / state id 1 reads as hardware.
//  This project has no test target, so this compiles as a standalone script against the real file:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/sudo_overlay_selftest facekey/Sudo/SudoOverlayPrompt.swift tools/sudo_overlay_selftest.swift && /private/tmp/sudo_overlay_selftest
//
//  Prints PASS/FAIL per check; exits 0 when every check passes, 1 otherwise.
//

import Foundation
import CoreGraphics

var failures = 0

func check(_ cond: Bool, _ name: String) {
    if cond {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}

@main
enum SudoOverlaySelfTest {
    static func main() {
        let panel = CGRect(x: 100, y: 0, width: 340, height: 170)
        let bandTop = panel.maxY - SudoOverlayMetrics.buttonBandHeight
        let inBand = bandTop + SudoOverlayMetrics.buttonBandHeight / 2

        // MARK: - Confirm prompt

        check(SudoOverlayMetrics.choice(at: CGPoint(x: panel.minX + 20, y: inBand), panel: panel, kind: .confirm) == .cancel, "left half of the band cancels")
        check(SudoOverlayMetrics.choice(at: CGPoint(x: panel.maxX - 20, y: inBand), panel: panel, kind: .confirm) == .accept, "right half of the band accepts")
        check(SudoOverlayMetrics.choice(at: CGPoint(x: panel.midX, y: inBand), panel: panel, kind: .confirm) == .accept, "the exact middle falls on the right half")
        check(SudoOverlayMetrics.choice(at: CGPoint(x: panel.midX - 0.5, y: inBand), panel: panel, kind: .confirm) == .cancel, "just left of the middle cancels")

        // MARK: - Clicks outside the band

        check(SudoOverlayMetrics.choice(at: CGPoint(x: panel.maxX - 20, y: panel.minY + 20), panel: panel, kind: .confirm) == nil, "a click on the text area answers nothing")
        check(SudoOverlayMetrics.choice(at: CGPoint(x: panel.maxX - 20, y: bandTop - 1), panel: panel, kind: .confirm) == nil, "a click just above the band answers nothing")
        check(SudoOverlayMetrics.choice(at: CGPoint(x: panel.maxX + 5, y: inBand), panel: panel, kind: .confirm) == nil, "a click right of the panel answers nothing")
        check(SudoOverlayMetrics.choice(at: CGPoint(x: panel.minX - 5, y: inBand), panel: panel, kind: .confirm) == nil, "a click left of the panel answers nothing")
        check(SudoOverlayMetrics.choice(at: CGPoint(x: panel.maxX - 20, y: panel.maxY + 5), panel: panel, kind: .confirm) == nil, "a click below the panel answers nothing")

        // MARK: - First-use prompt

        check(SudoOverlayMetrics.choice(at: CGPoint(x: panel.minX + 20, y: inBand), panel: panel, kind: .firstUse) == .notNow, "first use: left half is Not now")
        check(SudoOverlayMetrics.choice(at: CGPoint(x: panel.maxX - 20, y: inBand), panel: panel, kind: .firstUse) == .allow, "first use: right half is Allow")

        // MARK: - Click source

        check(SudoClickSource.describe(pid: 0, stateID: 1) == "hardware", "pid 0 and state id 1 is a hardware click")
        check(SudoClickSource.describe(pid: 4242, stateID: 0) == "synthetic pid=4242 stateID=0", "a posted CGEvent reports the poster's pid")
        check(SudoClickSource.describe(pid: 0, stateID: 0) == "synthetic pid=0 stateID=0", "pid 0 with another state id is not hardware")
        check(SudoClickSource.describe(pid: -1, stateID: -1) == "synthetic pid=-1 stateID=-1", "a click with no CGEvent behind it is not hardware")
        check(SudoClickSource.isHardware("hardware"), "a hardware click description is hardware")
        check(!SudoClickSource.isHardware(SudoClickSource.describe(pid: 4242, stateID: 0)), "a posted click is not hardware")
        check(!SudoClickSource.isHardware("none") && !SudoClickSource.isHardware(""), "no click source is not hardware")

        if failures == 0 {
            print("All sudo overlay self-tests passed.")
        } else {
            print("\(failures) sudo overlay check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

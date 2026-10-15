//
//  distance_calibration_selftest.swift
//  facekey (tools)
//
//  Offline self-test for `DistanceCalibrationMath` (median, margin,
//  threshold clamping, sample stability). This project has no test
//  target, so this compiles as a standalone script against the real
//  file:
//
//      swiftc -O -parse-as-library -o /tmp/distance_calibration_selftest \
//        facekey/DistanceCalibrationMath.swift \
//        tools/distance_calibration_selftest.swift \
//      && /tmp/distance_calibration_selftest
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

/// Tolerance for "approximately equal" comparisons of Float values.
let tolerance: Float = 0.0001

/// True when `a` and `b` differ by no more than `tolerance`.
func approxEqual(_ a: Float, _ b: Float) -> Bool {
    abs(a - b) <= tolerance
}

@main
enum DistanceCalibrationSelfTest {
    static func main() {
        // MARK: - Median

        check(DistanceCalibrationMath.median([]) == nil, "median of an empty array is nil")
        check(DistanceCalibrationMath.median([0.3]) == 0.3, "median of a single value is that value")
        check(DistanceCalibrationMath.median([0.1, 0.3, 0.2]) == 0.2, "median of three values is the middle one (unsorted input)")
        let evenMedian = DistanceCalibrationMath.median([0.1, 0.2, 0.3, 0.4])
        check(evenMedian != nil && approxEqual(evenMedian!, 0.25), "median of four values is the average of the two central ones (~0.25)")

        // MARK: - Threshold (margin + clamp)

        let normal = DistanceCalibrationMath.threshold(fromMeasured: 0.24)
        check(approxEqual(normal, 0.192), "threshold(0.24) is the margin-scaled width (~0.192), unclamped")
        check(DistanceCalibrationMath.threshold(fromMeasured: 0.10) == 0.13, "threshold(0.10) clamps up to the lower bound 0.13")
        check(DistanceCalibrationMath.threshold(fromMeasured: 0.40) == 0.23, "threshold(0.40) clamps down to the upper bound 0.23")

        // MARK: - Stability

        check(DistanceCalibrationMath.isStable([]) == false, "isStable([]) is false (no samples, no stability)")
        check(DistanceCalibrationMath.isStable([0.24, 0.241, 0.239, 0.242]) == true, "isStable passes on tightly clustered samples")
        check(DistanceCalibrationMath.isStable([0.24, 0.30, 0.24]) == false, "isStable fails when one sample drifts beyond the tolerance")

        // MARK: - Result

        if failures == 0 {
            print("All distance calibration self-tests passed.")
        } else {
            print("\(failures) distance calibration check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

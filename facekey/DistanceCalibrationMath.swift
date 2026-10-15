import Foundation

/// Pure math for calibrating the unlock distance from a measured face width.
nonisolated enum DistanceCalibrationMath {
    /// Factor applied to the measured face width to derive the unlock threshold.
    static let margin: Float = 0.8

    /// Bounds for the calibrated threshold so results stay in a sensible range.
    static let thresholdRange: ClosedRange<Float> = 0.13...0.23

    /// Maximum relative deviation from the median for samples to count as stable.
    static let stabilityTolerance: Float = 0.05

    /// Returns the median of `values`, or `nil` if the array is empty.
    /// With an even count, averages the two central values.
    static func median(_ values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }

    /// Clamps the margin-scaled measured width into the calibrated threshold range.
    static func threshold(fromMeasured width: Float) -> Float {
        min(max(width * margin, thresholdRange.lowerBound), thresholdRange.upperBound)
    }

    /// True when `widths` is non-empty and every width lies within the relative
    /// stability tolerance of the median.
    static func isStable(_ widths: [Float]) -> Bool {
        guard let m = median(widths) else { return false }
        return widths.allSatisfy { abs($0 - m) <= m * stabilityTolerance }
    }
}

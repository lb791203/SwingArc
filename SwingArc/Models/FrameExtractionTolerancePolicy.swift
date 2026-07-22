import Foundation
import CoreMedia

enum FrameExtractionTolerancePolicy {
    static func halfFrameSeconds(sourceFrameRate: Double) -> Double? {
        guard sourceFrameRate.isFinite, sourceFrameRate > 0 else { return nil }
        return 0.5 / sourceFrameRate
    }

    static func halfFrameTime(sourceFrameRate: Double) -> CMTime? {
        guard let seconds = halfFrameSeconds(sourceFrameRate: sourceFrameRate) else {
            return nil
        }
        return CMTime(seconds: seconds, preferredTimescale: 60_000)
    }

    /// AVAssetImageGenerator seeks to a sample at or before the requested
    /// timestamp. Fractional/VFR metadata can place the nominal frame time
    /// just before its real presentation timestamp, selecting the prior
    /// frame. Asking for the interval center keeps the intended sample inside
    /// the bounded half-frame search window.
    static func decodeRequestTime(
        sourceFrameIndex: Int,
        sourceFrameRate: Double
    ) -> CMTime? {
        guard sourceFrameIndex >= 0,
              sourceFrameRate.isFinite,
              sourceFrameRate > 0 else {
            return nil
        }
        return CMTime(
            seconds: (Double(sourceFrameIndex) + 0.5) / sourceFrameRate,
            preferredTimescale: 60_000
        )
    }
}

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

    /// Integer CFR timelines use their exact source-frame timestamp. For
    /// fractional/VFR metadata, AVAssetImageGenerator can place a nominal
    /// frame time just before its real presentation timestamp and select the
    /// prior frame; asking for the interval center keeps the intended sample
    /// inside the bounded half-frame search window.
    static func decodeRequestTime(
        sourceFrameIndex: Int,
        sourceFrameRate: Double
    ) -> CMTime? {
        guard sourceFrameIndex >= 0,
              sourceFrameRate.isFinite,
              sourceFrameRate > 0 else {
            return nil
        }
        let roundedFrameRate = sourceFrameRate.rounded()
        if abs(sourceFrameRate - roundedFrameRate) < 0.001,
           roundedFrameRate <= Double(Int32.max) {
            return CMTime(
                value: CMTimeValue(sourceFrameIndex),
                timescale: CMTimeScale(roundedFrameRate)
            )
        }
        return CMTime(
            seconds: (Double(sourceFrameIndex) + 0.5) / sourceFrameRate,
            preferredTimescale: 60_000
        )
    }
}

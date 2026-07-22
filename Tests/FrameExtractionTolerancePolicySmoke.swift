import Foundation
import AVFoundation

@main
struct FrameExtractionTolerancePolicySmoke {
    static func main() {
        precondition(
            FrameExtractionTolerancePolicy.halfFrameSeconds(sourceFrameRate: 240)
                == 1.0 / 480.0
        )
        precondition(
            abs(
                FrameExtractionTolerancePolicy.halfFrameSeconds(sourceFrameRate: 239.9)!
                    - 1.0 / 479.8
            ) < 1e-12
        )
        precondition(
            FrameExtractionTolerancePolicy.halfFrameSeconds(sourceFrameRate: 0) == nil
        )
        precondition(
            FrameExtractionTolerancePolicy.halfFrameSeconds(sourceFrameRate: .nan) == nil
        )
        let centeredRequest = FrameExtractionTolerancePolicy.decodeRequestTime(
            sourceFrameIndex: 30,
            sourceFrameRate: 239.9
        )
        precondition(
            abs(centeredRequest!.seconds - 30.5 / 239.9) < 1.0 / 60_000.0,
            "VFR decoding must request the center of the estimated frame interval"
        )

        if CommandLine.arguments.count > 1 {
            let analyzer = try! String(
                contentsOfFile: CommandLine.arguments[1],
                encoding: .utf8
            )
            precondition(
                analyzer.contains("FrameExtractionTolerancePolicy.halfFrameTime"),
                "The analyzer must derive a bounded high-speed decode tolerance"
            )
            precondition(
                analyzer.components(separatedBy: "FrameExtractionTolerancePolicy.decodeRequestTime").count >= 3,
                "Both coarse and fine extraction must request the frame-interval center"
            )
            precondition(
                analyzer.contains("requestedTimeToleranceBefore = decodeTolerance") &&
                    analyzer.contains("requestedTimeToleranceAfter = decodeTolerance"),
                "Both generator tolerance directions must use the half-frame bound"
            )
        }

        if CommandLine.arguments.count > 2 {
            verifyHighSpeedAsset(at: URL(fileURLWithPath: CommandLine.arguments[2]))
        }
    }

    private static func verifyHighSpeedAsset(at url: URL) {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration.seconds
        let track = asset.tracks(withMediaType: .video).first!
        let sourceFrameRate = Double(track.nominalFrameRate)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let tolerance = FrameExtractionTolerancePolicy.halfFrameTime(
            sourceFrameRate: sourceFrameRate
        )!
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let maximumSourceFrameIndex = max(0, Int(ceil(duration * sourceFrameRate)) - 1)
        let sampleCount = Int(ceil(duration * 8))
        for index in 0...sampleCount {
            let seconds = min(duration, Double(index) / 8.0)
            let requestedSourceFrameIndex = min(
                maximumSourceFrameIndex,
                max(0, Int((seconds * sourceFrameRate).rounded()))
            )
            let requestedTime = FrameExtractionTolerancePolicy.decodeRequestTime(
                sourceFrameIndex: requestedSourceFrameIndex,
                sourceFrameRate: sourceFrameRate
            )!
            var actualTime = CMTime.invalid
            do {
                _ = try generator.copyCGImage(at: requestedTime, actualTime: &actualTime)
            } catch {
                preconditionFailure(
                    "decode failed at sample \(index), frame \(requestedSourceFrameIndex), " +
                        "time \(requestedTime.seconds): \(error)"
                )
            }
            let framePosition = actualTime.seconds * sourceFrameRate
            let distance = abs(framePosition - Double(requestedSourceFrameIndex))
            precondition(
                distance + 1e-9 < 0.5,
                "frame mismatch at sample \(index): requested \(requestedSourceFrameIndex), " +
                    "actual time \(actualTime.seconds), position \(framePosition), distance \(distance)"
            )
        }
    }
}

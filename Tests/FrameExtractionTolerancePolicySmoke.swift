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
        for sourceFrameRate in [29.9995, 30.0005] {
            let request = FrameExtractionTolerancePolicy.decodeRequestTime(
                sourceFrameIndex: 86,
                sourceFrameRate: sourceFrameRate
            )
            precondition(
                abs(request!.seconds - 86.5 / sourceFrameRate) < 1.0 / 60_000.0,
                "Non-integer rates must request the center of the estimated frame interval"
            )
        }
        for sourceFrameRate in [30.0, 60.0, 120.0, 240.0] {
            let sourceFrameIndex = 86
            let request = FrameExtractionTolerancePolicy.decodeRequestTime(
                sourceFrameIndex: sourceFrameIndex,
                sourceFrameRate: sourceFrameRate
            )
            precondition(
                request == CMTime(
                    value: CMTimeValue(sourceFrameIndex),
                    timescale: CMTimeScale(sourceFrameRate)
                ),
                "Integer CFR decoding must request the exact source-frame timestamp"
            )
        }

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
                "Both coarse and fine extraction must use exact integer-CFR or centered fractional requests"
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

        if CommandLine.arguments.count > 3 {
            let diagnostics = try! String(
                contentsOfFile: CommandLine.arguments[3],
                encoding: .utf8
            )
            precondition(
                diagnostics.contains(
                    "case .failed(.frameExtractionFailed), .cancelled:"
                ) &&
                    diagnostics.contains("case .completed, .failed:") &&
                    diagnostics.components(separatedBy: "exit(EXIT_FAILURE)").count >= 3,
                "The real-video diagnostic must fail only for frame extraction or cancellation"
            )
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

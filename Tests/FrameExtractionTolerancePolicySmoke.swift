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

        let variableTimeline = SourceFrameTimeline(presentationTimes: [
            CMTime(value: 0, timescale: 240),
            CMTime(value: 1, timescale: 240),
            CMTime(value: 2, timescale: 240),
            CMTime(value: 4, timescale: 240),
            CMTime(value: 5, timescale: 240)
        ])!
        precondition(variableTimeline.count == 5)
        precondition(variableTimeline.maximumSourceFrameIndex == 4)
        precondition(
            variableTimeline.presentationTime(sourceFrameIndex: 3)
                == CMTime(value: 4, timescale: 240)
        )
        precondition(
            variableTimeline.nearestSourceFrameIndex(at: 3.8 / 240.0) == 3
        )
        precondition(
            variableTimeline.nearestSourceFrameIndex(at: 3.0 / 240.0) == 3,
            "Exact midpoint ties must preserve Swift rounded() forward selection"
        )
        precondition(
            variableTimeline.matches(
                requestedSourceFrameIndex: 3,
                actualTime: CMTime(value: 4, timescale: 240)
            )
        )
        precondition(
            !variableTimeline.matches(
                requestedSourceFrameIndex: 2,
                actualTime: CMTime(value: 4, timescale: 240)
            )
        )
        precondition(
            FrameExtractionTolerancePolicy.decodeRequestTime(
                sourceFrameIndex: 3,
                sourceFrameTimeline: variableTimeline
            ) == CMTime(value: 4, timescale: 240)
        )
        let constantTimeline = SourceFrameTimeline(
            duration: 1,
            constantFrameRate: 30
        )!
        precondition(constantTimeline.count == 30)
        precondition(
            constantTimeline.presentationTime(sourceFrameIndex: 29)
                == CMTime(value: 29, timescale: 30)
        )

        // Regression: the persisted P8 time from a 30 fps clip used to be
        // truncated to 1459/600, which is before source frame 73 and makes
        // AVPlayer display frame 72.
        let persistedP8Time = 2.433333333333333
        let expectedP8Time = CMTime(value: 73, timescale: 30)
        let legacyP8Time = CMTime(
            seconds: persistedP8Time,
            preferredTimescale: 600
        )
        precondition(
            CMTimeCompare(legacyP8Time, expectedP8Time) < 0,
            "The fixture must reproduce the previous-frame seek bug"
        )
        let roundedP8Fallback = PlaybackSeekTimePolicy
            .roundedFallbackTime(
                seconds: persistedP8Time,
                timescale: 15_360
            )
        precondition(
            CMTimeCompare(roundedP8Fallback, expectedP8Time) == 0,
            "Legacy marker fallback must not land before source frame 73"
        )
        let exactVFRTime = CMTime(value: 37_376, timescale: 15_360)
        precondition(
            PlaybackSeekTimePolicy.targetTime(
                exactPresentationTime: exactVFRTime,
                fallbackSeconds: 1
            ) == exactVFRTime,
            "A persisted source frame must keep its exact presentation timestamp"
        )
        precondition(
            PlaybackSeekTimePolicy.targetTime(
                exactPresentationTime: nil,
                fallbackSeconds: persistedP8Time,
                fallbackTimescale: 15_360
            ) == roundedP8Fallback,
            "Legacy markers without a source frame must use the rounded fallback"
        )
        precondition(
            PlaybackSeekTimePolicy.roundedFallbackTime(seconds: .nan) == .zero
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
                "Both coarse and fine extraction must use exact integer-CFR or centered fractional requests"
            )
            precondition(
                analyzer.contains("requestedTimeToleranceBefore = decodeTolerance") &&
                    analyzer.contains("requestedTimeToleranceAfter = decodeTolerance"),
                "Both generator tolerance directions must use the half-frame bound"
            )
            precondition(
                analyzer.contains(
                    "ExactVideoFrameProvider.load(url: url).timeline"
                ),
                "VFR analysis must reuse the exact annotation source timeline"
            )
            precondition(
                !analyzer.contains(
                    "private static func sourceFrameTimeline("
                ),
                "The duplicated AVAssetReader timeline loader must be removed"
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
        let reader = try! AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
        reader.add(output)
        precondition(reader.startReading())
        var presentationTimes: [CMTime] = []
        while let sample = output.copyNextSampleBuffer() {
            presentationTimes.append(
                CMSampleBufferGetPresentationTimeStamp(sample)
            )
        }
        precondition(reader.status == .completed)
        let timeline = SourceFrameTimeline(
            presentationTimes: presentationTimes
        )!
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let tolerance = FrameExtractionTolerancePolicy.halfFrameTime(
            sourceFrameRate: timeline.averageFrameRate!
        )!
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let sampleCount = Int(ceil(duration * 8))
        for index in 0...sampleCount {
            let seconds = min(duration, Double(index) / 8.0)
            let requestedSourceFrameIndex = timeline
                .nearestSourceFrameIndex(at: seconds)!
            let requestedTime = FrameExtractionTolerancePolicy.decodeRequestTime(
                sourceFrameIndex: requestedSourceFrameIndex,
                sourceFrameTimeline: timeline
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
            precondition(
                timeline.matches(
                    requestedSourceFrameIndex: requestedSourceFrameIndex,
                    actualTime: actualTime
                ),
                "frame mismatch at sample \(index): requested \(requestedSourceFrameIndex), " +
                    "requested time \(requestedTime.seconds), actual time \(actualTime.seconds)"
            )
        }
    }
}

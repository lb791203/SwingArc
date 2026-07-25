import Foundation

@main
struct ManualPPointFeedbackDiagnostics {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: manual-p-feedback <video-path>\n", stderr)
            exit(EXIT_FAILURE)
        }
        let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let corrections: [(SwingStage, Int)] = [
            (.address, 9),
            (.takeaway, 24),
            (.leadArmParallelBackswing, 43),
            (.top, 95),
            (.leadArmParallelDownswing, 131),
            (.shaftParallelDownswing, 150),
            (.impact, 162),
            (.followThrough, 180)
        ]
        let gate = AnalysisRunGate()
        let runID = gate.begin()
        let outcome = SwingVideoAnalysisEngine().analyze(
            url: videoURL,
            view: .downTheLine,
            runID: runID,
            gate: gate,
            progress: { _ in }
        )
        guard case var .completed(output) = outcome else {
            preconditionFailure("Video analysis did not complete")
        }

        let provider = try ExactVideoFrameProvider.load(url: videoURL)
        let detector = VisionPoseDetector()
        var markers: [KeyframeMarker] = []
        for (stage, frameIndex) in corrections {
            let frame = try provider.frame(at: frameIndex)
            guard let pose = detector.detectPose(
                in: frame.image,
                orientation: .up
            ) else {
                preconditionFailure("No pose at frame \(frameIndex)")
            }
            let exactBody = SwingPoseObservationAdapter.frame(
                pose: pose,
                sourceFrameIndex: frameIndex,
                time: frame.presentationTime.seconds
            )
            let refined = ManualPPointAnalysisRefiner.merging(
                exactBodyFrame: exactBody,
                intoFrames: output.observationFrames,
                poseSamples: output.poseSamples
            )
            output = SwingVideoAnalysisOutput(
                view: output.view,
                result: output.result,
                poseSamples: refined.poseSamples,
                leadArm: output.leadArm,
                adaptiveWindow: output.adaptiveWindow,
                sourceFrameRate: output.sourceFrameRate,
                elapsedSeconds: output.elapsedSeconds,
                trackingDiagnostics: output.trackingDiagnostics,
                observationFrames: refined.frames
            )
            markers.append(
                KeyframeMarker(
                    time: frame.presentationTime.seconds,
                    stage: stage,
                    source: .manual,
                    sourceFrameIndex: frameIndex
                )
            )
        }

        guard let feedback = SwingFeedbackPipeline.make(
            output: output,
            manualMarkers: markers
        )?.feedback else {
            preconditionFailure("Feedback pipeline returned nil")
        }
        for card in feedback.cards {
            print(
                "\(card.category.title): \(card.status.rawValue) " +
                "confidence=\(String(format: "%.3f", card.evidenceConfidence))"
            )
        }
    }
}

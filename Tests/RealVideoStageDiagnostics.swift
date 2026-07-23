import Darwin
import AVFoundation
import Foundation

struct RealVideoStageDiagnostic: Encodable {
    let stage: String
    let sourceFrameIndex: Int?
    let time: Double?
    let confidence: Double
    let status: String
    let hasClubEvidence: Bool
    let hasBallEvidence: Bool
    let hasBallChangeEvidence: Bool
}

struct RealVideoStageDiagnosticReport: Encodable {
    let video: String
    let captureFrameRate: Double
    let sourceFrameRate: Double?
    let timelineInterpretation: String
    let motionBlurHandling: String
    let outcome: String
    let elapsedSeconds: Double?
    let adaptiveWindowStart: Double?
    let adaptiveWindowEnd: Double?
    let stages: [RealVideoStageDiagnostic]
    let observationFrameCount: Int
    let measuredLandmarkFrameCounts: [String: Int]
    let trackingDiagnostics: PrimaryGolferTrackingDiagnostics
}

@main
struct RealVideoStageDiagnostics {
    static func main() async throws {
        guard (2...4).contains(CommandLine.arguments.count) else {
            fputs(
                "usage: real-video-stage-diagnostics <video-path> [capture-fps] [--blocking-blur]\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        let usesBlockingBlur = CommandLine.arguments.contains("--blocking-blur")
        let valueArguments = CommandLine.arguments.dropFirst().filter {
            $0 != "--blocking-blur"
        }
        guard (1...2).contains(valueArguments.count) else {
            fputs("invalid diagnostic arguments\n", stderr)
            exit(EXIT_FAILURE)
        }
        let captureFrameRate: Double
        if valueArguments.count == 2 {
            guard let parsed = Double(valueArguments[1]),
                  parsed.isFinite,
                  parsed > 0 else {
                fputs("capture-fps must be a positive number\n", stderr)
                exit(EXIT_FAILURE)
            }
            captureFrameRate = parsed
        } else {
            captureFrameRate = 240
        }

        let videoURL = URL(fileURLWithPath: valueArguments[0])
        let asset = AVURLAsset(url: videoURL)
        let metadataSourceFrameRate: Double?
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let nominalFrameRate = try? await track.load(.nominalFrameRate) {
            metadataSourceFrameRate = Double(nominalFrameRate)
        } else {
            metadataSourceFrameRate = nil
        }
        let timelineInterpretation = (metadataSourceFrameRate ?? 0) > 120
            ? "unmodified high-frame-rate capture timeline"
            : "processed slow-motion playback timeline"
        let gate = AnalysisRunGate()
        let runID = gate.begin()
        let engine = usesBlockingBlur
            ? SwingVideoAnalysisEngine(motionBlurDisposition: .blocking)
            : SwingVideoAnalysisEngine()
        let outcome = engine.analyze(
            url: videoURL,
            runID: runID,
            gate: gate,
            progress: { _ in }
        )

        let report: RealVideoStageDiagnosticReport
        switch outcome {
        case let .completed(output):
            let stages = SwingStage.pStages.enumerated().map { index, stage in
                let detection = output.result.detections.first {
                    $0.stage == stage
                }
                return RealVideoStageDiagnostic(
                    stage: "P\(index + 1)",
                    sourceFrameIndex: detection?.sourceFrameIndex,
                    time: detection?.time,
                    confidence: detection?.confidence ?? 0,
                    status: detection?.status.rawValue ?? "unresolved",
                    hasClubEvidence: detection?.hasClubEvidence ?? false,
                    hasBallEvidence: detection?.hasBallEvidence ?? false,
                    hasBallChangeEvidence: detection?.hasBallChangeEvidence ?? false
                )
            }
            var measuredCounts: [String: Int] = [:]
            for landmark in SwingLandmark.allCases {
                measuredCounts[landmark.rawValue] = output.observationFrames.filter {
                    $0.landmarks[landmark]?.isMeasured == true
                }.count
            }
            report = RealVideoStageDiagnosticReport(
                video: videoURL.lastPathComponent,
                captureFrameRate: captureFrameRate,
                sourceFrameRate: output.sourceFrameRate,
                timelineInterpretation: timelineInterpretation,
                motionBlurHandling: usesBlockingBlur ? "blocking diagnostic" : "warning",
                outcome: "completed",
                elapsedSeconds: output.elapsedSeconds,
                adaptiveWindowStart: output.adaptiveWindow.startTime,
                adaptiveWindowEnd: output.adaptiveWindow.endTime,
                stages: stages,
                observationFrameCount: output.observationFrames.count,
                measuredLandmarkFrameCounts: measuredCounts,
                trackingDiagnostics: output.trackingDiagnostics
            )
        case let .failed(reason):
            report = RealVideoStageDiagnosticReport(
                video: videoURL.lastPathComponent,
                captureFrameRate: captureFrameRate,
                sourceFrameRate: metadataSourceFrameRate,
                timelineInterpretation: timelineInterpretation,
                motionBlurHandling: usesBlockingBlur ? "blocking diagnostic" : "warning",
                outcome: "failed: \(reason)",
                elapsedSeconds: nil,
                adaptiveWindowStart: nil,
                adaptiveWindowEnd: nil,
                stages: [],
                observationFrameCount: 0,
                measuredLandmarkFrameCounts: [:],
                trackingDiagnostics: engine.latestTrackingDiagnostics
            )
        case .cancelled:
            report = RealVideoStageDiagnosticReport(
                video: videoURL.lastPathComponent,
                captureFrameRate: captureFrameRate,
                sourceFrameRate: metadataSourceFrameRate,
                timelineInterpretation: timelineInterpretation,
                motionBlurHandling: usesBlockingBlur ? "blocking diagnostic" : "warning",
                outcome: "cancelled",
                elapsedSeconds: nil,
                adaptiveWindowStart: nil,
                adaptiveWindowEnd: nil,
                stages: [],
                observationFrameCount: 0,
                measuredLandmarkFrameCounts: [:],
                trackingDiagnostics: engine.latestTrackingDiagnostics
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data("\n".utf8))

        switch outcome {
        case .failed(.frameExtractionFailed), .cancelled:
            exit(EXIT_FAILURE)
        case .completed, .failed:
            break
        }
    }
}

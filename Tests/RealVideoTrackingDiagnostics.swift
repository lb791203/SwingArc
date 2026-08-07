import Foundation
import Darwin

struct TrackingDiagnosticReport: Encodable {
    let video: String
    let outcome: String
    let diagnostics: PrimaryGolferTrackingDiagnostics
    let elapsedSeconds: Double?
    let poseSampleCount: Int
    let observationFrameCount: Int
    let stages: [StageDiagnosticReport]
}

struct StageDiagnosticReport: Encodable {
    let stage: String
    let status: String
    let sourceFrameIndex: Int?
    let time: Double?
    let confidence: Double
}

@main
struct RealVideoTrackingDiagnostics {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: real-video-tracking-diagnostics <video-path>\n", stderr)
            exit(EXIT_FAILURE)
        }

        let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let gate = AnalysisRunGate()
        let runID = gate.begin()
        let engine = SwingVideoAnalysisEngine()
        let outcome = engine.analyze(
            url: videoURL,
            runID: runID,
            gate: gate,
            progress: { _ in }
        )

        let outcomeText: String
        let elapsedSeconds: Double?
        let poseSampleCount: Int
        let observationFrameCount: Int
        let stages: [StageDiagnosticReport]
        switch outcome {
        case let .completed(output):
            outcomeText = "completed"
            elapsedSeconds = output.elapsedSeconds
            poseSampleCount = output.poseSamples.count
            observationFrameCount = output.observationFrames.count
            stages = output.result.detections.map {
                StageDiagnosticReport(
                    stage: $0.stage.shortName,
                    status: $0.status.rawValue,
                    sourceFrameIndex: $0.sourceFrameIndex,
                    time: $0.time,
                    confidence: $0.confidence
                )
            }
        case let .failed(reason):
            outcomeText = "failed: \(reason)"
            elapsedSeconds = nil
            poseSampleCount = 0
            observationFrameCount = 0
            stages = []
        case .cancelled:
            outcomeText = "cancelled"
            elapsedSeconds = nil
            poseSampleCount = 0
            observationFrameCount = 0
            stages = []
        }

        let report = TrackingDiagnosticReport(
            video: videoURL.lastPathComponent,
            outcome: outcomeText,
            diagnostics: engine.latestTrackingDiagnostics,
            elapsedSeconds: elapsedSeconds,
            poseSampleCount: poseSampleCount,
            observationFrameCount: observationFrameCount,
            stages: stages
        )
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

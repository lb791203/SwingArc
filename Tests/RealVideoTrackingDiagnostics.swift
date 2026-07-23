import Foundation
import Darwin

struct TrackingDiagnosticReport: Encodable {
    let video: String
    let outcome: String
    let diagnostics: PrimaryGolferTrackingDiagnostics
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
        switch outcome {
        case .completed:
            outcomeText = "completed"
        case let .failed(reason):
            outcomeText = "failed: \(reason)"
        case .cancelled:
            outcomeText = "cancelled"
        }

        let report = TrackingDiagnosticReport(
            video: videoURL.lastPathComponent,
            outcome: outcomeText,
            diagnostics: engine.latestTrackingDiagnostics
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

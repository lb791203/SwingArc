import Foundation
import Darwin
import AVFoundation

struct RealVideoReport: Encodable {
    let video: String
    let sourceFrameRate: Double
    let adaptiveWindowStart: Double
    let adaptiveWindowEnd: Double
    let elapsedSeconds: Double
    let stages: [StageAcceptance]
}

@main
struct RealVideoP1P8Acceptance {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fputs("usage: real-video-p1p8 <video-path> <manifest-path>\n", stderr)
            exit(EXIT_FAILURE)
        }

        let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let manifest = try JSONDecoder().decode(
            GroundTruthManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let asset = AVURLAsset(url: videoURL)
        let assetFrameRate = Double(
            asset.tracks(withMediaType: .video).first?.nominalFrameRate ?? 0
        )
        do {
            try GroundTruthManifestValidator.validate(
                manifest,
                videoName: videoURL.lastPathComponent,
                sourceFrameRate: assetFrameRate,
                duration: asset.duration.seconds
            )
        } catch {
            fputs("manifest rejected: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
        let gate = AnalysisRunGate()
        let runID = gate.begin()
        let outcome = SwingVideoAnalysisEngine().analyze(
            url: videoURL,
            runID: runID,
            gate: gate,
            progress: { _ in }
        )

        switch outcome {
        case let .completed(output):
            let stages = RealVideoAcceptance.evaluate(
                manifest: manifest,
                result: output.result
            )
            let report = RealVideoReport(
                video: videoURL.lastPathComponent,
                sourceFrameRate: output.sourceFrameRate,
                adaptiveWindowStart: output.adaptiveWindow.startTime,
                adaptiveWindowEnd: output.adaptiveWindow.endTime,
                elapsedSeconds: output.elapsedSeconds,
                stages: stages
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data("\n".utf8))
            guard stages.count == SwingStage.allCases.count,
                  stages.allSatisfy(\.passed),
                  output.elapsedSeconds < 45.0 else {
                exit(EXIT_FAILURE)
            }
        case let .failed(reason):
            fputs("analysis failed: \(reason)\n", stderr)
            exit(EXIT_FAILURE)
        case .cancelled:
            fputs("analysis cancelled\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

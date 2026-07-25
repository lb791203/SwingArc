import Foundation

@main
struct ExportPPointGroundTruth {
    static func main() async throws {
        guard CommandLine.arguments.count == 12 else {
            throw ExportPPointGroundTruthError.usage
        }
        let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let view: PracticeCameraView
        switch CommandLine.arguments[2] {
        case "dtl":
            view = .downTheLine
        case "face-on":
            view = .faceOn
        default:
            throw ExportPPointGroundTruthError.usage
        }
        let outputDirectory = URL(
            fileURLWithPath: CommandLine.arguments[3],
            isDirectory: true
        )
        let frames = try CommandLine.arguments[4...11].map {
            guard let value = Int($0) else {
                throw ExportPPointGroundTruthError.usage
            }
            return value
        }
        let provider = try ExactVideoFrameProvider.load(url: videoURL)
        let markers = try zip(SwingStage.pStages, frames).map {
            stage,
            frame -> KeyframeMarker in
            guard let time = provider.timeline.presentationTime(
                sourceFrameIndex: frame
            )?.seconds else {
                throw ExportPPointGroundTruthError.frameOutOfRange(frame)
            }
            return KeyframeMarker(
                time: time,
                stage: stage,
                source: .manual,
                sourceFrameIndex: frame
            )
        }
        let receipt = try await PPointGroundTruthExportService.export(
            videoURL: videoURL,
            view: view,
            markers: markers,
            destinationDirectory: outputDirectory
        )
        print(receipt.url.path)
    }
}

private enum ExportPPointGroundTruthError: Error, CustomStringConvertible {
    case usage
    case frameOutOfRange(Int)

    var description: String {
        switch self {
        case .usage:
            return "usage: export-p-point-ground-truth " +
                "<video> <dtl|face-on> <output-directory> " +
                "<P1> <P2> <P3> <P4> <P5> <P6> <P7> <P8>"
        case let .frameOutOfRange(frame):
            return "frame out of range: \(frame)"
        }
    }
}

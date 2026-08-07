import AVFoundation
import Foundation

@main
struct AnnotationSourceFrameTimelineSmoke {
    static func main() async throws {
        let synthetic = SourceFrameTimeline(presentationTimes: [
            CMTime(value: 0, timescale: 240),
            CMTime(value: 1, timescale: 240),
            CMTime(value: 3, timescale: 240)
        ])!
        precondition(synthetic.count == 3)
        precondition(synthetic.timelineSHA256.count == 64)
        precondition(
            synthetic.presentationTime(sourceFrameIndex: 2)
                == CMTime(value: 3, timescale: 240)
        )

        guard CommandLine.arguments.count == 2 else { return }
        let provider = try ExactVideoFrameProvider.load(
            url: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        precondition(provider.frameCount > 0)
        if provider.url.lastPathComponent == "IMG_4692.MOV" {
            precondition(provider.frameCount == 1526)
        }
        let first = try provider.frame(at: 0)
        let last = try provider.frame(at: provider.frameCount - 1)
        precondition(first.sourceFrameIndex == 0)
        precondition(last.sourceFrameIndex == provider.frameCount - 1)
        precondition(first.presentationTime < last.presentationTime)
        precondition(first.image.width == last.image.width)
        precondition(first.image.height == last.image.height)
        print("TIMELINE \(provider.timelineSHA256) \(provider.frameCount)")

        let session = ExactVideoFrameSession()
        let metadata = try await session.open(url: provider.url)
        precondition(metadata.frameCount == provider.frameCount)
        precondition(metadata.timelineSHA256 == provider.timelineSHA256)
        let sessionFirst = try await session.frame(at: 0)
        precondition(sessionFirst.sourceFrameIndex == 0)
    }
}

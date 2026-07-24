import CoreGraphics
import Foundation

@main
struct VisionFullClipPoseExtractorSmoke {
    static func main() throws {
        let image = makeBlankImage()

        let empty = try VisionFullClipPoseExtractor.extract(frames: [])
        precondition(empty.isEmpty)

        do {
            _ = try VisionFullClipPoseExtractor.extract(frames: [
                VisionFullClipPoseSourceFrame(sourceFrameIndex: 0, sourceTime: 0, image: image),
                VisionFullClipPoseSourceFrame(sourceFrameIndex: 0, sourceTime: 0, image: image),
            ])
            preconditionFailure("Duplicate source frames must fail")
        } catch VisionFullClipPoseExtractorError.duplicateFrame(0) {}

        do {
            _ = try VisionFullClipPoseExtractor.extract(frames: [
                VisionFullClipPoseSourceFrame(sourceFrameIndex: 0, sourceTime: 1, image: image),
                VisionFullClipPoseSourceFrame(sourceFrameIndex: 1, sourceTime: 0, image: image),
            ])
            preconditionFailure("Non-monotonic source times must fail")
        } catch VisionFullClipPoseExtractorError.nonMonotonicTime {}

        let blank = try VisionFullClipPoseExtractor.extract(frames: [
            VisionFullClipPoseSourceFrame(sourceFrameIndex: 7, sourceTime: 0.25, image: image)
        ])
        precondition(blank.isEmpty, "A blank image must not fabricate a body candidate")

        print("All VisionFullClipPoseExtractor tests passed.")
    }

    private static func makeBlankImage() -> CGImage {
        let width = 64
        let height = 64
        let data = Data(repeating: 0, count: width * height * 4)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}

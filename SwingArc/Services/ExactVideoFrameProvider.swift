import AVFoundation
import CoreGraphics
import Foundation

struct ExactVideoFrame: @unchecked Sendable {
    let sourceFrameIndex: Int
    let presentationTime: CMTime
    let image: CGImage
}

enum ExactVideoFrameProviderError: Error, Equatable {
    case missingVideoTrack
    case timelineUnavailable
    case frameOutOfRange(Int)
    case decodeFailed(Int)
    case decodedNeighborFrame(requested: Int)
}

final class ExactVideoFrameProvider {
    let url: URL
    let timeline: SourceFrameTimeline
    let orientedSize: CGSize

    private let asset: AVURLAsset
    private let generator: AVAssetImageGenerator

    var frameCount: Int { timeline.count }
    var timelineSHA256: String { timeline.timelineSHA256 }

    private init(
        url: URL,
        asset: AVURLAsset,
        timeline: SourceFrameTimeline,
        orientedSize: CGSize
    ) {
        self.url = url
        self.asset = asset
        self.timeline = timeline
        self.orientedSize = orientedSize
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let tolerance = timeline.averageFrameRate.flatMap {
            FrameExtractionTolerancePolicy.halfFrameTime(sourceFrameRate: $0)
        } ?? .zero
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
    }

    static func load(url: URL) throws -> ExactVideoFrameProvider {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw ExactVideoFrameProviderError.missingVideoTrack
        }
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw ExactVideoFrameProviderError.timelineUnavailable
        }
        // Only presentation timestamps are needed here, so read the
        // compressed samples instead of decoding every frame to pixels.
        // Decoding a 240 FPS clip made opening P-point correction take
        // several seconds.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw ExactVideoFrameProviderError.timelineUnavailable
        }
        reader.add(output)
        guard reader.startReading() else {
            throw ExactVideoFrameProviderError.timelineUnavailable
        }
        var times: [CMTime] = []
        while let sample = output.copyNextSampleBuffer() {
            times.append(contentsOf: displayedPresentationTimes(in: sample))
        }
        guard reader.status == .completed,
              let timeline = SourceFrameTimeline(
                  presentationTimes: times
              ) else {
            throw ExactVideoFrameProviderError.timelineUnavailable
        }
        let transformed = track.naturalSize.applying(track.preferredTransform)
        let size = CGSize(
            width: abs(transformed.width),
            height: abs(transformed.height)
        )
        return .init(
            url: url,
            asset: asset,
            timeline: timeline,
            orientedSize: size
        )
    }

    /// Presentation times of the frames in one compressed sample buffer,
    /// skipping frames the decoder would not display.
    private static func displayedPresentationTimes(
        in sample: CMSampleBuffer
    ) -> [CMTime] {
        let count = CMSampleBufferGetNumSamples(sample)
        guard count > 0 else { return [] }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sample,
            createIfNecessary: false
        ) as? [[CFString: Any]]
        func isDisplayed(_ index: Int) -> Bool {
            guard let attachments, index < attachments.count else { return true }
            return (attachments[index][kCMSampleAttachmentKey_DoNotDisplay] as? Bool) != true
        }
        if count == 1 {
            return isDisplayed(0)
                ? [CMSampleBufferGetPresentationTimeStamp(sample)]
                : []
        }
        var entryCount: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &entryCount
        ) == noErr, entryCount > 0 else {
            return [CMSampleBufferGetPresentationTimeStamp(sample)]
        }
        var timing = [CMSampleTimingInfo](repeating: .invalid, count: entryCount)
        guard CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: entryCount,
            arrayToFill: &timing,
            entriesNeededOut: &entryCount
        ) == noErr else {
            return [CMSampleBufferGetPresentationTimeStamp(sample)]
        }
        if entryCount == count {
            return (0..<count).filter(isDisplayed).map { timing[$0].presentationTimeStamp }
        }
        // A single timing entry describes evenly spaced samples.
        let first = timing[0]
        return (0..<count).filter(isDisplayed).map { index in
            CMTimeAdd(
                first.presentationTimeStamp,
                CMTimeMultiply(first.duration, multiplier: Int32(index))
            )
        }
    }

    func frame(at sourceFrameIndex: Int) throws -> ExactVideoFrame {
        guard let time = timeline.presentationTime(
            sourceFrameIndex: sourceFrameIndex
        ) else {
            throw ExactVideoFrameProviderError.frameOutOfRange(
                sourceFrameIndex
            )
        }
        var actual = CMTime.invalid
        guard let image = try? generator.copyCGImage(
            at: time,
            actualTime: &actual
        ) else {
            throw ExactVideoFrameProviderError.decodeFailed(sourceFrameIndex)
        }
        guard timeline.matches(
            requestedSourceFrameIndex: sourceFrameIndex,
            actualTime: actual
        ) else {
            throw ExactVideoFrameProviderError.decodedNeighborFrame(
                requested: sourceFrameIndex
            )
        }
        return .init(
            sourceFrameIndex: sourceFrameIndex,
            presentationTime: actual,
            image: image
        )
    }
}

struct ExactVideoFrameSessionMetadata: Sendable {
    let frameCount: Int
    let timelineSHA256: String
    let orientedWidth: Int
    let orientedHeight: Int
}

actor ExactVideoFrameSession {
    private var provider: ExactVideoFrameProvider?

    func open(url: URL) throws -> ExactVideoFrameSessionMetadata {
        let provider = try ExactVideoFrameProvider.load(url: url)
        self.provider = provider
        return .init(
            frameCount: provider.frameCount,
            timelineSHA256: provider.timelineSHA256,
            orientedWidth: Int(provider.orientedSize.width.rounded()),
            orientedHeight: Int(provider.orientedSize.height.rounded())
        )
    }

    func frame(at sourceFrameIndex: Int) throws -> ExactVideoFrame {
        guard let provider else {
            throw ExactVideoFrameProviderError.timelineUnavailable
        }
        return try provider.frame(at: sourceFrameIndex)
    }

    func nearestSourceFrameIndex(at time: Double) -> Int? {
        provider?.timeline.nearestSourceFrameIndex(at: time)
    }

    func presentationTimeSeconds(
        at sourceFrameIndex: Int
    ) -> Double? {
        provider?.timeline.presentationTime(
            sourceFrameIndex: sourceFrameIndex
        )?.seconds
    }

    func presentationTime(
        at sourceFrameIndex: Int
    ) -> CMTime? {
        provider?.timeline.presentationTime(
            sourceFrameIndex: sourceFrameIndex
        )
    }
}

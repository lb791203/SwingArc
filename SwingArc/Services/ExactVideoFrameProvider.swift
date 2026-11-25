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
        // Decoded output is required: compressed samples carry media-time
        // PTS before the edit list is applied, which shifted frames by two
        // on B-frame H.264 clips. The decoded timeline is cached per file
        // (SourceFrameTimelineCache) so later opens of the same clip are fast.
        if let cached = SourceFrameTimelineCache.timeline(for: url) {
            let transformed = track.naturalSize.applying(track.preferredTransform)
            return .init(
                url: url,
                asset: asset,
                timeline: cached,
                orientedSize: CGSize(width: abs(transformed.width), height: abs(transformed.height))
            )
        }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
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
            times.append(CMSampleBufferGetPresentationTimeStamp(sample))
        }
        guard reader.status == .completed,
              let timeline = SourceFrameTimeline(
                  presentationTimes: times
              ) else {
            throw ExactVideoFrameProviderError.timelineUnavailable
        }
        SourceFrameTimelineCache.store(timeline, for: url)
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

/// In-memory cache of decoded source-frame timelines, keyed by file path,
/// size and modification date, so analysis and the P-point correction page
/// decode a clip's timeline only once per launch.
enum SourceFrameTimelineCache {
    private struct Key: Hashable {
        let path: String
        let size: Int
        let modified: Date
    }

    private static let lock = NSLock()
    private static var entries: [Key: SourceFrameTimeline] = [:]

    private static func key(for url: URL) -> Key? {
        guard let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        ), let size = values.fileSize, let modified = values.contentModificationDate else {
            return nil
        }
        return Key(path: url.standardizedFileURL.path, size: size, modified: modified)
    }

    static func timeline(for url: URL) -> SourceFrameTimeline? {
        guard let key = key(for: url) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return entries[key]
    }

    static func store(_ timeline: SourceFrameTimeline, for url: URL) {
        guard let key = key(for: url) else { return }
        lock.lock(); defer { lock.unlock() }
        if entries.count > 16 { entries.removeAll() }
        entries[key] = timeline
    }
}

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
    case cancelled
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

    static func load(
        url: URL,
        isCancelled: @escaping () -> Bool = { false }
    ) throws -> ExactVideoFrameProvider {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw ExactVideoFrameProviderError.missingVideoTrack
        }
        // Decoded output is required: compressed samples carry media-time
        // PTS before the edit list is applied, which shifted frames by two
        // on B-frame H.264 clips. The decoded timeline is cached per file
        // version and concurrent opens of the same file share one decode.
        let timeline = try SourceFrameTimelineCache.timeline(for: url) {
            try decodeTimeline(asset: asset, track: track, isCancelled: isCancelled)
        }
        let transformed = track.naturalSize.applying(track.preferredTransform)
        return .init(
            url: url,
            asset: asset,
            timeline: timeline,
            orientedSize: CGSize(width: abs(transformed.width), height: abs(transformed.height))
        )
    }

    /// Reads every decoded sample's presentation time. Checks `isCancelled`
    /// between samples so a scan for a project the user left stops early.
    static func decodeTimeline(
        asset: AVAsset,
        track: AVAssetTrack,
        isCancelled: () -> Bool
    ) throws -> SourceFrameTimeline {
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw ExactVideoFrameProviderError.timelineUnavailable
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
            if isCancelled() {
                reader.cancelReading()
                throw ExactVideoFrameProviderError.cancelled
            }
            times.append(CMSampleBufferGetPresentationTimeStamp(sample))
        }
        guard reader.status == .completed,
              let timeline = SourceFrameTimeline(presentationTimes: times) else {
            throw ExactVideoFrameProviderError.timelineUnavailable
        }
        return timeline
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
        let provider = try ExactVideoFrameProvider.load(
            url: url,
            isCancelled: { Task.isCancelled }
        )
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

/// In-memory cache of decoded source-frame timelines, so analysis, the
/// player and the P-point correction page decode a clip's timeline once.
///
/// - The key is the file version: path, file identifier (inode), size and
///   modification date, read fresh each time (URL caches resource values).
///   A timeline is stored only if the version is unchanged after decoding.
/// - Concurrent requests for the same version wait for one decode.
/// - Entries are evicted least recently used, bounded by total timestamps.
nonisolated enum SourceFrameTimelineCache {
    struct Key: Hashable {
        let path: String
        let fileIdentifier: String
        let size: Int
        let modified: Date
    }

    /// About 2.4 MB of CMTime values: roughly 80 minutes of 30 fps video.
    static let maximumTotalFrames = 150_000

    private static let condition = NSCondition()
    nonisolated(unsafe) private static var entries: [Key: SourceFrameTimeline] = [:]
    nonisolated(unsafe) private static var lastUse: [Key: UInt64] = [:]
    nonisolated(unsafe) private static var useCounter: UInt64 = 0
    nonisolated(unsafe) private static var inFlight: Set<Key> = []

    static func key(for url: URL) -> Key? {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        guard let values = try? fresh.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey
        ]), let size = values.fileSize, let modified = values.contentModificationDate else {
            return nil
        }
        let identifier = values.fileResourceIdentifier.map { String(describing: $0) } ?? ""
        return Key(
            path: url.standardizedFileURL.path,
            fileIdentifier: identifier,
            size: size,
            modified: modified
        )
    }

    /// Returns the cached timeline for the file's current version, or runs
    /// `decode` once (other callers for the same version wait for it).
    static func timeline(
        for url: URL,
        decode: () throws -> SourceFrameTimeline
    ) throws -> SourceFrameTimeline {
        guard let key = key(for: url) else { return try decode() }
        condition.lock()
        while true {
            if let cached = entries[key] {
                touch(key)
                condition.unlock()
                return cached
            }
            if !inFlight.contains(key) { break }
            condition.wait()
        }
        inFlight.insert(key)
        condition.unlock()

        let result = Result { try decode() }

        condition.lock()
        inFlight.remove(key)
        // Store only if the file did not change while it was decoded.
        if case let .success(timeline) = result, Self.key(for: url) == key {
            store(timeline, for: key)
        }
        condition.broadcast()
        condition.unlock()
        return try result.get()
    }

    static func cachedTimeline(for url: URL) -> SourceFrameTimeline? {
        guard let key = key(for: url) else { return nil }
        condition.lock(); defer { condition.unlock() }
        if let cached = entries[key] { touch(key); return cached }
        return nil
    }

    static func removeAll() {
        condition.lock(); defer { condition.unlock() }
        entries.removeAll()
        lastUse.removeAll()
    }

    // Caller holds the lock.
    private static func touch(_ key: Key) {
        useCounter += 1
        lastUse[key] = useCounter
    }

    // Caller holds the lock.
    private static func store(_ timeline: SourceFrameTimeline, for key: Key) {
        // A newer version of the same path replaces the old one.
        for stale in entries.keys where stale.path == key.path && stale != key {
            entries[stale] = nil
            lastUse[stale] = nil
        }
        entries[key] = timeline
        touch(key)
        var total = entries.values.reduce(0) { $0 + $1.count }
        while total > maximumTotalFrames, entries.count > 1,
              let oldest = lastUse.filter({ $0.key != key }).min(by: { $0.value < $1.value })?.key {
            total -= entries[oldest]?.count ?? 0
            entries[oldest] = nil
            lastUse[oldest] = nil
        }
    }
}

import AVFoundation
import CoreGraphics
import Foundation

/// Regression check for exact source-frame reading on real clips, with
/// baselines that do not come from the provider itself:
/// - the decoded frame count against track duration × nominal frame rate;
/// - the generator's own actualTime for every frame (provider throws when
///   it lands on a neighbour);
/// - repeated images between consecutive frames (a shifted timeline shows
///   up as duplicated or skipped pictures);
/// - the timeline cache: concurrent opens decode once, and replacing the
///   file at the same path is not served from the old entry.
///
/// Run with:
///   xcrun swiftc -parse-as-library \
///     SwingArc/Models/FrameExtractionTolerancePolicy.swift \
///     SwingArc/Services/ExactVideoFrameProvider.swift \
///     Tests/ExactFrameTimelineDiagnostics.swift -o /tmp/exact-frames && \
///   /tmp/exact-frames <video> [<video> ...]
@main
struct ExactFrameTimelineDiagnostics {
    static func main() throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let arguments = Array(CommandLine.arguments.dropFirst())
        // --allow-repeats: for clips with genuinely frozen frames.
        let allowRepeats = arguments.contains("--allow-repeats")
        let paths = arguments.filter { !$0.hasPrefix("--") }
        precondition(!paths.isEmpty, "Pass one or more video paths")
        var anyFailure = false
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let provider = try ExactVideoFrameProvider.load(url: url)
            var failures: [Int] = []
            var repeatedPairs = 0
            var previousFingerprint: [UInt8]?
            for index in 0..<provider.frameCount {
                do {
                    let frame = try provider.frame(at: index)
                    let fingerprint = fingerprint(frame.image)
                    if let previousFingerprint, previousFingerprint == fingerprint {
                        repeatedPairs += 1
                    }
                    previousFingerprint = fingerprint
                } catch {
                    failures.append(index)
                    previousFingerprint = nil
                }
            }
            let asset = AVURLAsset(url: url)
            let track = asset.tracks(withMediaType: .video).first!
            let expected = track.timeRange.duration.seconds * Double(track.nominalFrameRate)
            let countMatches = abs(Double(provider.frameCount) - expected) <= 1.5
            let isConstantRate = isConstantFrameRate(track)
            let firstTime = provider.timeline.presentationTime(sourceFrameIndex: 0)?.seconds ?? .nan
            print(
                "\(url.lastPathComponent): frames=\(provider.frameCount) " +
                    "expected≈\(String(format: "%.1f", expected)) first=\(firstTime)s " +
                    "neighbourFailures=\(failures.count) \(failures.prefix(10)) " +
                    "repeatedImagePairs=\(repeatedPairs)"
            )
            var problems: [String] = []
            if !failures.isEmpty { problems.append("\(failures.count) frames decoded to a neighbour") }
            if !countMatches && isConstantRate {
                problems.append("constant-rate clip has \(provider.frameCount) frames, expected ≈\(String(format: "%.1f", expected))")
            } else if !countMatches {
                print("  variable frame rate: count check skipped")
            }
            if repeatedPairs > 0 && !allowRepeats {
                problems.append("\(repeatedPairs) consecutive frames show the same picture")
            }
            for problem in problems { print("  FAIL: \(problem)") }
            anyFailure = anyFailure || !problems.isEmpty
        }
        try checkCache(using: URL(fileURLWithPath: paths[0]))
        precondition(!anyFailure, "Frame timeline check failed; see FAIL lines above")
        print("timeline cache: one decode for concurrent opens, replaced file re-decoded, cancelled wait returns, stale decode rejected, oversized entry not kept but shared with waiters ✓")
    }

    /// Constant rate from the track's own metadata, not from the timeline
    /// under test: the shortest frame duration matches the nominal rate.
    /// Dropped frames in the decoded timeline therefore cannot turn a
    /// constant-rate clip into "variable" and skip the count check.
    static func isConstantFrameRate(_ track: AVAssetTrack) -> Bool {
        let nominal = Double(track.nominalFrameRate)
        let minimum = track.minFrameDuration.seconds
        guard nominal > 0, minimum.isFinite, minimum > 0 else { return true }
        return abs(nominal * minimum - 1) <= 0.02
    }

    /// 16×16 grey thumbnail bytes, enough to tell consecutive frames apart.
    static func fingerprint(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16 * 16)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 16, height: 16,
                bitsPerComponent: 8, bytesPerRow: 16,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        return bytes
    }

    static func checkCache(using video: URL) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("exact-frame-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("clip.mov")
        try FileManager.default.copyItem(at: video, to: copy)

        SourceFrameTimelineCache.removeAll()
        let lock = NSLock()
        var decodes = 0
        let asset = AVURLAsset(url: copy)
        let track = asset.tracks(withMediaType: .video).first!
        DispatchQueue.concurrentPerform(iterations: 4) { _ in
            _ = try? SourceFrameTimelineCache.timeline(for: copy) {
                lock.lock(); decodes += 1; lock.unlock()
                return try ExactVideoFrameProvider.decodeTimeline(
                    asset: asset, track: track, isCancelled: { false }
                )
            }
        }
        precondition(decodes == 1, "Concurrent opens decoded \(decodes) times; expected 1")

        // Replace the file at the same path (new inode); reuse the same URL.
        let replacement = directory.appendingPathComponent("replacement.mov")
        try FileManager.default.copyItem(at: video, to: replacement)
        try FileManager.default.removeItem(at: copy)
        try FileManager.default.moveItem(at: replacement, to: copy)
        var redecoded = false
        let replacedAsset = AVURLAsset(url: copy)
        let replacedTrack = replacedAsset.tracks(withMediaType: .video).first!
        _ = try SourceFrameTimelineCache.timeline(for: copy) {
            redecoded = true
            return try ExactVideoFrameProvider.decodeTimeline(
                asset: replacedAsset,
                track: replacedTrack,
                isCancelled: { false }
            )
        }
        precondition(redecoded, "A replaced file at the same path was served from the old cache entry")

        // A waiter whose task is cancelled stops waiting promptly.
        SourceFrameTimelineCache.removeAll()
        let started = DispatchSemaphore(value: 0)
        let decoderDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? SourceFrameTimelineCache.timeline(for: copy) {
                started.signal()
                Thread.sleep(forTimeInterval: 1.5)
                return try ExactVideoFrameProvider.decodeTimeline(
                    asset: replacedAsset, track: replacedTrack, isCancelled: { false }
                )
            }
            decoderDone.signal()
        }
        started.wait()
        let waitStart = Date()
        var waiterError: Error?
        do {
            _ = try SourceFrameTimelineCache.timeline(
                for: copy,
                isCancelled: { Date().timeIntervalSince(waitStart) > 0.1 }
            ) { preconditionFailure("The waiter must not decode") }
        } catch {
            waiterError = error
        }
        let waited = Date().timeIntervalSince(waitStart)
        precondition(
            (waiterError as? ExactVideoFrameProviderError) == .cancelled && waited < 0.6,
            "Cancelled waiter returned after \(waited)s with \(String(describing: waiterError))"
        )
        decoderDone.wait()

        // A file replaced while decoding: the stale timeline is not returned.
        SourceFrameTimelineCache.removeAll()
        var changedError: Error?
        do {
            _ = try SourceFrameTimelineCache.timeline(for: copy) {
                let timeline = try ExactVideoFrameProvider.decodeTimeline(
                    asset: replacedAsset, track: replacedTrack, isCancelled: { false }
                )
                let swap = directory.appendingPathComponent("swap.mov")
                try FileManager.default.copyItem(at: video, to: swap)
                try FileManager.default.removeItem(at: copy)
                try FileManager.default.moveItem(at: swap, to: copy)
                return timeline
            }
        } catch {
            changedError = error
        }
        precondition(
            (changedError as? ExactVideoFrameProviderError) == .fileChangedDuringDecode,
            "A timeline decoded from a replaced file must not be returned"
        )
        precondition(SourceFrameTimelineCache.cachedTimeline(for: copy) == nil)

        // One timeline over the frame budget is returned but not kept.
        SourceFrameTimelineCache.removeAll()
        let oversized = SourceFrameTimeline(
            presentationTimes: (0...SourceFrameTimelineCache.maximumTotalFrames).map {
                CMTime(value: CMTimeValue($0), timescale: 600)
            }
        )!
        _ = try SourceFrameTimelineCache.timeline(for: copy) { oversized }
        precondition(
            SourceFrameTimelineCache.cachedTimeline(for: copy) == nil,
            "A single timeline over the cache budget must not be kept"
        )

        // Concurrent opens of an over-budget video still decode once.
        var oversizedDecodes = 0
        var oversizedResults = 0
        DispatchQueue.concurrentPerform(iterations: 4) { _ in
            let timeline = try? SourceFrameTimelineCache.timeline(for: copy) {
                lock.lock(); oversizedDecodes += 1; lock.unlock()
                Thread.sleep(forTimeInterval: 0.3)
                return oversized
            }
            if timeline != nil { lock.lock(); oversizedResults += 1; lock.unlock() }
        }
        precondition(
            oversizedDecodes == 1 && oversizedResults == 4,
            "Over-budget concurrent opens decoded \(oversizedDecodes) times, \(oversizedResults)/4 got a timeline"
        )
        precondition(SourceFrameTimelineCache.cachedTimeline(for: copy) == nil)
    }
}

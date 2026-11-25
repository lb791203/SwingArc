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
        let paths = Array(CommandLine.arguments.dropFirst())
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
            let firstTime = provider.timeline.presentationTime(sourceFrameIndex: 0)?.seconds ?? .nan
            print(
                "\(url.lastPathComponent): frames=\(provider.frameCount) " +
                    "expected≈\(String(format: "%.1f", expected)) first=\(firstTime)s " +
                    "neighbourFailures=\(failures.count) \(failures.prefix(10)) " +
                    "repeatedImagePairs=\(repeatedPairs)"
            )
            if !countMatches { print("  frame count differs from duration × nominal rate (VFR clips may)") }
            anyFailure = anyFailure || !failures.isEmpty
        }
        try checkCache(using: URL(fileURLWithPath: paths[0]))
        precondition(!anyFailure, "Some source frames decoded to a neighbouring frame")
        print("timeline cache: concurrent opens decode once; replaced file is re-decoded ✓")
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
        _ = try SourceFrameTimelineCache.timeline(for: copy) {
            redecoded = true
            return try ExactVideoFrameProvider.decodeTimeline(
                asset: AVURLAsset(url: copy),
                track: AVURLAsset(url: copy).tracks(withMediaType: .video).first!,
                isCancelled: { false }
            )
        }
        precondition(redecoded, "A replaced file at the same path was served from the old cache entry")
    }
}

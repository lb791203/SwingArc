import AVFoundation
import Foundation

@main
struct InventoryVideos {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(
                Data("usage: inventory-videos <video-directory>\n".utf8)
            )
            Foundation.exit(EXIT_FAILURE)
        }

        let directory = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let videos = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let clips = try await videos.asyncMap { url in
            PrecisionVideoInventory.makeDevelopmentClip(
                metadata: try await metadata(for: url)
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(clips))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func metadata(for url: URL) async throws -> InventoryVideoMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw InventoryError.invalidDuration(url.lastPathComponent)
        }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw InventoryError.missingVideoTrack(url.lastPathComponent)
        }
        let frameRate = Double(try await track.load(.nominalFrameRate))
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
        guard frameRate.isFinite, frameRate > 0 else {
            throw InventoryError.invalidFrameRate(url.lastPathComponent)
        }
        return InventoryVideoMetadata(
            fileName: url.lastPathComponent,
            sourceFrameRate: frameRate,
            duration: duration,
            width: Int(abs(oriented.width).rounded()),
            height: Int(abs(oriented.height).rounded())
        )
    }
}

private enum InventoryError: Error, CustomStringConvertible {
    case invalidDuration(String)
    case missingVideoTrack(String)
    case invalidFrameRate(String)

    var description: String {
        switch self {
        case let .invalidDuration(file): return "invalid video duration: \(file)"
        case let .missingVideoTrack(file): return "missing video track: \(file)"
        case let .invalidFrameRate(file): return "invalid video frame rate: \(file)"
        }
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            try await values.append(transform(element))
        }
        return values
    }
}

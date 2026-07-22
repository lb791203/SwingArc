import Foundation
import AVFoundation

enum CapturedVideoStoreError: Error, Equatable {
    case missingSource
    case emptyFile
    case invalidDuration
    case missingVideoTrack
    case copyFailed
    case finalizeFailed
}

/// Turns an AVFoundation-owned temporary recording into validated app media.
/// Only the store-owned partial file is deleted when validation fails; the
/// source recording remains available for diagnostics or a retry.
struct CapturedVideoStore {
    let destinationDirectory: URL
    private let fileManager: FileManager

    init(
        destinationDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.destinationDirectory = destinationDirectory
        self.fileManager = fileManager
    }

    func persist(
        sourceURL: URL,
        prefix: String,
        quality: PracticeCaptureQuality
    ) async throws -> RecordedPracticeClip {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CapturedVideoStoreError.missingSource
        }

        let sourceValues: URLResourceValues
        do {
            sourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        } catch {
            throw CapturedVideoStoreError.missingSource
        }
        guard let sourceSize = sourceValues.fileSize, sourceSize > 0 else {
            throw CapturedVideoStoreError.emptyFile
        }

        do {
            try fileManager.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw CapturedVideoStoreError.copyFailed
        }

        let identifier = UUID().uuidString
        let partialURL = destinationDirectory
            .appendingPathComponent("\(identifier).partial.mp4")
        let finalURL = destinationDirectory
            .appendingPathComponent("\(sanitized(prefix))-\(identifier).mp4")
        defer { try? fileManager.removeItem(at: partialURL) }

        do {
            try fileManager.copyItem(at: sourceURL, to: partialURL)
        } catch {
            throw CapturedVideoStoreError.copyFailed
        }

        let copiedValues = try? partialURL.resourceValues(forKeys: [.fileSizeKey])
        guard let copiedSize = copiedValues?.fileSize, copiedSize > 0 else {
            throw CapturedVideoStoreError.emptyFile
        }

        let asset = AVURLAsset(url: partialURL)
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw CapturedVideoStoreError.invalidDuration
        }
        let seconds = CMTimeGetSeconds(duration)
        guard duration.isNumeric, seconds.isFinite, seconds > 0 else {
            throw CapturedVideoStoreError.invalidDuration
        }

        let videoTracks: [AVAssetTrack]
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw CapturedVideoStoreError.missingVideoTrack
        }
        guard !videoTracks.isEmpty else {
            throw CapturedVideoStoreError.missingVideoTrack
        }

        do {
            try fileManager.moveItem(at: partialURL, to: finalURL)
        } catch {
            throw CapturedVideoStoreError.finalizeFailed
        }
        try? fileManager.removeItem(at: sourceURL)
        return RecordedPracticeClip(url: finalURL, quality: quality)
    }

    private func sanitized(_ prefix: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let value = prefix.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(value).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "capture" : result
    }
}

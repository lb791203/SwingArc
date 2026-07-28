import Foundation
import AVFoundation

enum CapturedVideoStoreError: Error, Equatable {
    case missingSource
    case emptyFile
    case invalidDuration
    case missingVideoTrack
    case unplayable
    case copyFailed
    case finalizeFailed
}

enum VideoAssetValidationError: Error, Equatable {
    case invalidDuration
    case missingVideoTrack
    case unplayable
}

struct VideoAssetMetadata: Equatable {
    let duration: Double
    let videoTrackCount: Int
}

enum VideoAssetValidator {
    static func validate(url: URL) async throws -> VideoAssetMetadata {
        let asset = AVURLAsset(url: url)
        let isPlayable: Bool
        do {
            isPlayable = try await asset.load(.isPlayable)
        } catch {
            throw VideoAssetValidationError.unplayable
        }
        guard isPlayable else {
            throw VideoAssetValidationError.unplayable
        }

        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw VideoAssetValidationError.invalidDuration
        }
        let seconds = CMTimeGetSeconds(duration)
        guard duration.isNumeric, seconds.isFinite, seconds > 0 else {
            throw VideoAssetValidationError.invalidDuration
        }

        let videoTracks: [AVAssetTrack]
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw VideoAssetValidationError.missingVideoTrack
        }
        guard !videoTracks.isEmpty else {
            throw VideoAssetValidationError.missingVideoTrack
        }
        return VideoAssetMetadata(
            duration: seconds,
            videoTrackCount: videoTracks.count
        )
    }
}

enum ImportedVideoStoreError: Error, Equatable {
    case emptyFile
    case writeFailed
    case invalidVideo
    case finalizeFailed
}

struct ImportedVideoStore {
    let destinationDirectory: URL
    private let fileManager: FileManager

    init(
        destinationDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.destinationDirectory = destinationDirectory
        self.fileManager = fileManager
    }

    func persist(data: Data) async throws -> URL {
        guard !data.isEmpty else { throw ImportedVideoStoreError.emptyFile }
        do {
            try fileManager.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw ImportedVideoStoreError.writeFailed
        }

        let identifier = UUID().uuidString
        let partialURL = destinationDirectory
            .appendingPathComponent("\(identifier).partial.mp4")
        let finalURL = destinationDirectory
            .appendingPathComponent("imported-\(identifier).mp4")
        defer { try? fileManager.removeItem(at: partialURL) }

        do {
            try data.write(to: partialURL, options: .atomic)
        } catch {
            throw ImportedVideoStoreError.writeFailed
        }
        do {
            _ = try await VideoAssetValidator.validate(url: partialURL)
        } catch {
            throw ImportedVideoStoreError.invalidVideo
        }
        do {
            try fileManager.moveItem(at: partialURL, to: finalURL)
        } catch {
            throw ImportedVideoStoreError.finalizeFailed
        }
        return finalURL
    }
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

        do {
            _ = try await VideoAssetValidator.validate(url: partialURL)
        } catch let error as VideoAssetValidationError {
            switch error {
            case .invalidDuration:
                throw CapturedVideoStoreError.invalidDuration
            case .missingVideoTrack:
                throw CapturedVideoStoreError.missingVideoTrack
            case .unplayable:
                throw CapturedVideoStoreError.unplayable
            }
        } catch {
            throw CapturedVideoStoreError.unplayable
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

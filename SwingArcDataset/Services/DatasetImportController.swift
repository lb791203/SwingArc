import AVFoundation
import CryptoKit
import Foundation

struct DatasetImportReceipt: Equatable, Sendable {
    let clip: GolfClipIdentity
    let split: GolfDatasetSplit
    let securityScopedBookmark: Data
}

enum DatasetImportControllerError: Error, Equatable, LocalizedError {
    case unreadableVideo
    case unreadablePPointTruth
    case mediaHashMismatch
    case timelineHashMismatch
    case frameCountMismatch
    case incompletePPointTruth
    case invalidPPointTruthFrame(Int)
    case bookmarkCreationFailed
    case missingRegistry
    case unreadableRegistry

    var errorDescription: String? {
        switch self {
        case .unreadableVideo:
            return "无法读取视频或精确源帧时间线。"
        case .unreadablePPointTruth:
            return "无法读取 P1–P8 真值 JSON。"
        case .mediaHashMismatch:
            return "P 点真值与所选视频的媒体哈希不一致。"
        case .timelineHashMismatch:
            return "P 点真值与所选视频的源帧时间线不一致。"
        case .frameCountMismatch:
            return "P 点真值与所选视频的帧数不一致。"
        case .incompletePPointTruth:
            return "P 点真值必须完整包含一次 P1–P8。"
        case .invalidPPointTruthFrame(let frame):
            return "P 点真值帧 \(frame) 超出视频范围。"
        case .bookmarkCreationFailed:
            return "无法保存视频的安全访问书签。"
        case .missingRegistry:
            return "数据集尚未建立匿名球员与拆分注册表。"
        case .unreadableRegistry:
            return "数据集注册表存在但无法读取；为避免覆盖，已停止导入。"
        }
    }
}

private struct DatasetPPointTruthDocument: Decodable {
    struct Media: Decodable {
        let sha256: String
        let timelineSHA256: String
        let frameCount: Int
    }

    struct Stage: Decodable {
        let code: String
        let sourceFrameIndex: Int
    }

    let media: Media
    let view: String
    let stages: [Stage]
}

enum DatasetImportController {
    static func initialState(store: GolfDatasetStore) throws -> DatasetImportState {
        let registry: GolferRegistry
        do {
            registry = try store.loadRegistry()
        } catch let error as CocoaError
        where error.code == .fileReadNoSuchFile {
            throw DatasetImportControllerError.missingRegistry
        } catch {
            throw DatasetImportControllerError.unreadableRegistry
        }
        return DatasetImportReducer.reduce(.empty, .loadRegistry(registry))
    }

    static func verify(
        videoURL: URL,
        pPointTruthURL: URL
    ) async throws -> (media: DatasetVerifiedMedia, bookmark: Data) {
        let metadata: ExactVideoFrameSessionMetadata
        let mediaSHA256: String
        do {
            let session = ExactVideoFrameSession()
            async let metadataTask = session.open(url: videoURL)
            async let hashTask = Task.detached(priority: .utility) {
                try AnnotationStore.mediaSHA256(url: videoURL)
            }.value
            metadata = try await metadataTask
            mediaSHA256 = try await hashTask
        } catch {
            throw DatasetImportControllerError.unreadableVideo
        }

        let truthData: Data
        let truth: DatasetPPointTruthDocument
        do {
            truthData = try Data(contentsOf: pPointTruthURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            truth = try decoder.decode(DatasetPPointTruthDocument.self, from: truthData)
        } catch {
            throw DatasetImportControllerError.unreadablePPointTruth
        }
        guard truth.media.sha256 == mediaSHA256 else {
            throw DatasetImportControllerError.mediaHashMismatch
        }
        guard truth.media.timelineSHA256 == metadata.timelineSHA256 else {
            throw DatasetImportControllerError.timelineHashMismatch
        }
        guard truth.media.frameCount == metadata.frameCount else {
            throw DatasetImportControllerError.frameCountMismatch
        }
        guard let truthView = GolfDatasetView(rawValue: truth.view) else {
            throw DatasetImportControllerError.unreadablePPointTruth
        }

        let expectedCodes = Set((1...8).map { "P\($0)" })
        let stageGroups = Dictionary(grouping: truth.stages, by: \.code)
        guard truth.stages.count == expectedCodes.count,
              Set(stageGroups.keys) == expectedCodes,
              stageGroups.values.allSatisfy({ $0.count == 1 }) else {
            throw DatasetImportControllerError.incompletePPointTruth
        }
        for stage in truth.stages
        where stage.sourceFrameIndex < 0 || stage.sourceFrameIndex >= metadata.frameCount {
            throw DatasetImportControllerError.invalidPPointTruthFrame(
                stage.sourceFrameIndex
            )
        }

        let bookmark: Data
        do {
            bookmark = try videoURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw DatasetImportControllerError.bookmarkCreationFailed
        }

        let asset = AVURLAsset(url: videoURL)
        let sourceTimescale: Int
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                throw DatasetImportControllerError.unreadableVideo
            }
            sourceTimescale = Int(try await track.load(.naturalTimeScale))
        } catch {
            throw DatasetImportControllerError.unreadableVideo
        }
        let media = GolfMediaIdentity(
            fileName: videoURL.lastPathComponent,
            sha256: mediaSHA256,
            timelineSHA256: metadata.timelineSHA256,
            frameCount: metadata.frameCount,
            orientedWidth: metadata.orientedWidth,
            orientedHeight: metadata.orientedHeight,
            sourceTimescale: sourceTimescale
        )
        return (
            DatasetVerifiedMedia(
                media: media,
                pPointTruthSHA256: sha256(truthData),
                pPointTruthView: truthView,
                pPointTruthData: truthData
            ),
            bookmark
        )
    }

    static func importClip(
        state: DatasetImportState,
        clipID: String,
        store: GolfDatasetStore
    ) throws -> DatasetImportReceipt {
        let clip = try state.makeClip(clipID: clipID)
        guard let registry = state.registry,
              let split = state.split,
              let bookmark = state.securityScopedBookmark,
              let verifiedMedia = state.verifiedMedia else {
            throw DatasetImportIssue.incompleteIdentity
        }
        try store.saveRegistry(registry)
        try store.saveClip(clip)
        try store.savePPointTruthData(
            verifiedMedia.pPointTruthData,
            clipID: clip.clipID
        )
        return DatasetImportReceipt(
            clip: clip,
            split: split,
            securityScopedBookmark: bookmark
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

struct PPointGroundTruthExportReceipt: Equatable {
    let url: URL
    let includesRawVideo: Bool
}

enum PPointGroundTruthExportService {
    static func export(
        videoURL: URL,
        view: PracticeCameraView,
        markers: [KeyframeMarker],
        destinationDirectory: URL? = nil,
        now: Date = Date()
    ) async throws -> PPointGroundTruthExportReceipt {
        let mediaSHA256: String
        let metadata: ExactVideoFrameSessionMetadata
        do {
            async let hashTask = Task.detached(priority: .utility) {
                try AnnotationStore.mediaSHA256(url: videoURL)
            }.value
            let session = ExactVideoFrameSession()
            async let metadataTask = session.open(url: videoURL)
            mediaSHA256 = try await hashTask
            metadata = try await metadataTask
        } catch {
            throw PPointGroundTruthExportError.unreadableVideo
        }

        let package = try PPointGroundTruthPackageBuilder.make(
            media: PPointGroundTruthMedia(
                fileName: videoURL.lastPathComponent,
                sha256: mediaSHA256,
                timelineSHA256: metadata.timelineSHA256,
                frameCount: metadata.frameCount,
                width: metadata.orientedWidth,
                height: metadata.orientedHeight
            ),
            view: view == .downTheLine ? .downTheLine : .faceOn,
            markers: markers,
            createdAt: now
        )
        return try write(
            package: package,
            destinationDirectory: destinationDirectory
                ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                    "SwingArcPPointExports",
                    isDirectory: true
                )
        )
    }

    static func write(
        package: PPointGroundTruthPackage,
        destinationDirectory: URL
    ) throws -> PPointGroundTruthExportReceipt {
        do {
            try FileManager.default.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
            let identity = String(package.media.sha256.prefix(12))
            let fileName = "p-points-\(identity)-\(package.view.rawValue).json"
            let url = destinationDirectory.appendingPathComponent(fileName)
            let data = try PPointGroundTruthCoding.makeEncoder().encode(package)
            try data.write(to: url, options: .atomic)
            return PPointGroundTruthExportReceipt(
                url: url,
                includesRawVideo: false
            )
        } catch {
            throw PPointGroundTruthExportError.writeFailed
        }
    }
}

extension PPointGroundTruthExportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .missingManualStages(codes):
            return "请先人工确认 \(codes.map(\.rawValue).joined(separator: "、"))。"
        case let .missingExactSourceFrames(codes):
            return "\(codes.map(\.rawValue).joined(separator: "、")) 缺少精确源帧，请重新确认。"
        case .frameOutOfRange:
            return "部分 P 点超出视频帧范围，请重新确认。"
        case .nonIncreasingFrames:
            return "P1–P8 帧序不正确，请检查人工修正。"
        case .unreadableVideo:
            return "无法读取视频身份，请重新打开视频后再试。"
        case .writeFailed:
            return "P 点标准答案文件生成失败。"
        }
    }
}

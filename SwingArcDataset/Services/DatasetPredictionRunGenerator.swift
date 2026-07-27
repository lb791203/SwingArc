import Foundation
import Combine
import CoreGraphics
import AVFoundation

public struct DatasetPredictionSourceFrame: @unchecked Sendable {
    public let image: CGImage
    public let sourceTime: Double

    public init(image: CGImage, sourceTime: Double) {
        self.image = image
        self.sourceTime = sourceTime
    }
}

public struct DatasetPredictionFrameSource: @unchecked Sendable {
    public let frameCount: Int
    public let orientedFrameSize: CGSize
    private let frameAtClosure: (Int) throws -> DatasetPredictionSourceFrame

    public init(
        frameCount: Int,
        orientedFrameSize: CGSize,
        frameAt: @escaping (Int) throws -> DatasetPredictionSourceFrame
    ) {
        self.frameCount = frameCount
        self.orientedFrameSize = orientedFrameSize
        frameAtClosure = frameAt
    }

    public func frame(at sourceFrameIndex: Int) throws
        -> DatasetPredictionSourceFrame
    {
        try frameAtClosure(sourceFrameIndex)
    }
}

private struct DatasetPredictionGeneratorDependencies: @unchecked Sendable {
    let frameSourceLoader: (URL) throws -> DatasetPredictionFrameSource
    let candidateExtractor:
        (CGImage, Int, Double) -> [GolfPoseCandidateFrame]
    let visionFrameworkVersion: String
    let visionRequestVersion: String
}

@MainActor
public final class DatasetPredictionRunGenerator: ObservableObject {
    @Published public var isGenerating: Bool = false
    @Published public var progressText: String = ""
    @Published public var lastErrorMessage: String? = nil

    private let dependencies: DatasetPredictionGeneratorDependencies

    public init(
        frameSourceLoader:
            ((URL) throws -> DatasetPredictionFrameSource)? = nil,
        candidateExtractor:
            ((CGImage, Int, Double) -> [GolfPoseCandidateFrame])? = nil,
        visionFrameworkVersion: String? = nil,
        visionRequestVersion: String? = nil
    ) {
        dependencies = DatasetPredictionGeneratorDependencies(
            frameSourceLoader: frameSourceLoader ?? { url in
                let provider = try ExactVideoFrameProvider.load(url: url)
                return DatasetPredictionFrameSource(
                    frameCount: provider.frameCount,
                    orientedFrameSize: provider.orientedSize,
                    frameAt: { sourceFrameIndex in
                        let frame = try provider.frame(at: sourceFrameIndex)
                        return DatasetPredictionSourceFrame(
                            image: frame.image,
                            sourceTime: CMTimeGetSeconds(
                                frame.presentationTime
                            )
                        )
                    }
                )
            },
            candidateExtractor: candidateExtractor ?? {
                image, sourceFrameIndex, sourceTime in
                VisionPoseExtractor.extractCandidates(
                    from: image,
                    sourceFrameIndex: sourceFrameIndex,
                    sourceTime: sourceTime
                )
            },
            visionFrameworkVersion: visionFrameworkVersion ??
                VisionPoseExtractor.visionFrameworkVersion,
            visionRequestVersion: visionRequestVersion ??
                VisionPoseExtractor.visionRequestVersion
        )
    }

    public func generateManualBootstrapRun(
        clip: GolfClipIdentity,
        store: GolfDatasetStore,
        anchors: [GolfSubjectAnchorDecision],
        videoURL: URL,
        targetSize: Double = 512.0
    ) async -> Result<GolfPredictionRun, GolfManualBootstrapRunError> {
        isGenerating = true
        progressText = "正在解码全视频并提取主体轨迹…"
        lastErrorMessage = nil
        defer { isGenerating = false }

        let dependencies = dependencies
        let worker = Task.detached(priority: .userInitiated) {
            Self.generate(
                clip: clip,
                store: store,
                anchors: anchors,
                videoURL: videoURL,
                targetSize: targetSize,
                dependencies: dependencies
            )
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }

        switch result {
        case .success:
            progressText = "Prediction Run 已生成并通过校验。"
        case .failure(let error):
            lastErrorMessage = error.description
            progressText = Task.isCancelled ? "生成已取消。" : "生成失败。"
        }
        return result
    }

    nonisolated private static func generate(
        clip: GolfClipIdentity,
        store: GolfDatasetStore,
        anchors: [GolfSubjectAnchorDecision],
        videoURL: URL,
        targetSize: Double,
        dependencies: DatasetPredictionGeneratorDependencies
    ) -> Result<GolfPredictionRun, GolfManualBootstrapRunError> {
        let accessing = videoURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                videoURL.stopAccessingSecurityScopedResource()
            }
        }

        let frameSource: DatasetPredictionFrameSource
        do {
            try Task.checkCancellation()
            frameSource = try dependencies.frameSourceLoader(videoURL)
        } catch {
            return failure(
                prefix: "Failed to load video provider",
                error: error
            )
        }
        guard frameSource.frameCount == clip.media.frameCount else {
            return .failure(.validationFailed(
                "Decoded frame count \(frameSource.frameCount) does not match " +
                    "clip identity \(clip.media.frameCount)"
            ))
        }

        var allCandidates: [GolfPoseCandidateFrame] = []
        for frameIndex in 0..<frameSource.frameCount {
            do {
                try Task.checkCancellation()
                let frame = try frameSource.frame(at: frameIndex)
                let candidates = dependencies.candidateExtractor(
                    frame.image,
                    frameIndex,
                    frame.sourceTime
                )
                allCandidates.append(contentsOf: candidates)
            } catch {
                return failure(
                    prefix: "Failed to decode frame \(frameIndex)",
                    error: error
                )
            }
        }

        do {
            try Task.checkCancellation()
        } catch {
            return failure(prefix: "Generation cancelled", error: error)
        }
        let buildResult = GolfManualBootstrapRunBuilder.build(
            clipID: clip.clipID,
            mediaSHA256: clip.media.sha256,
            timelineSHA256: clip.media.timelineSHA256,
            anchors: anchors,
            candidates: allCandidates,
            visionFrameworkVersion: dependencies.visionFrameworkVersion,
            visionRequestVersion: dependencies.visionRequestVersion,
            orientedFrameSize: frameSource.orientedFrameSize,
            targetSize: targetSize
        )

        switch buildResult {
        case .success(let run):
            let existingSnapshot: GolfDatasetSnapshot
            do {
                existingSnapshot = try store.loadSnapshot()
            } catch {
                return failure(
                    prefix: "Failed to load dataset snapshot",
                    error: error
                )
            }
            guard existingSnapshot.clips.contains(clip) else {
                return .failure(.validationFailed(
                    "Dataset snapshot does not contain the exact clip identity " +
                        "'\(clip.clipID)'"
                ))
            }

            var updatedPredictions = existingSnapshot.predictions
            var matchingExistingRun: GolfPredictionRun?
            if let existingRun = updatedPredictions.first(where: { $0.predictionRunID == run.predictionRunID }) {
                guard existingRun == run else {
                    let msg = "Existing run '\(run.predictionRunID)' has mismatched content"
                    return .failure(.validationFailed(msg))
                }
                matchingExistingRun = existingRun
            } else {
                updatedPredictions.append(run)
            }

            let validationSnapshot = GolfDatasetSnapshot(
                registry: existingSnapshot.registry,
                clips: existingSnapshot.clips,
                predictions: updatedPredictions,
                revisions: existingSnapshot.revisions
            )

            let validationErrors = GolfDatasetValidator.validate(snapshot: validationSnapshot)
            guard validationErrors.isEmpty else {
                let msg = validationErrors.map(\.description).joined(separator: "; ")
                return .failure(.validationFailed(msg))
            }

            if let matchingExistingRun {
                return .success(matchingExistingRun)
            }
            do {
                try Task.checkCancellation()
                try store.appendPrediction(run)
                return .success(run)
            } catch GolfDatasetStoreError.predictionAlreadyExists {
                return .success(run)
            } catch {
                return failure(
                    prefix: "Failed to append prediction run",
                    error: error
                )
            }

        case .failure(let err):
            return .failure(err)
        }
    }

    nonisolated private static func failure(
        prefix: String,
        error: Error
    ) -> Result<GolfPredictionRun, GolfManualBootstrapRunError> {
        .failure(.validationFailed(
            "\(prefix): \(error.localizedDescription)"
        ))
    }
}

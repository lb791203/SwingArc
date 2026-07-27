import Foundation
import Combine
import CoreGraphics
import CoreMedia

public enum DatasetSubjectAnchorGeometry {
    public static func aspectFitRect(
        imageSize: CGSize,
        containerSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return .zero
        }
        let scale = min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    public static func normalizedImagePoint(
        at screenPoint: CGPoint,
        imageRect: CGRect
    ) -> GolfNormalizedPoint? {
        guard imageRect.width > 0,
              imageRect.height > 0,
              imageRect.contains(screenPoint) else {
            return nil
        }
        return GolfNormalizedPoint(
            x: Double((screenPoint.x - imageRect.minX) / imageRect.width),
            y: Double((screenPoint.y - imageRect.minY) / imageRect.height)
        )
    }

    public static func screenRect(
        for normalizedRect: GolfNormalizedRect,
        in imageRect: CGRect
    ) -> CGRect {
        CGRect(
            x: imageRect.minX + CGFloat(normalizedRect.x) * imageRect.width,
            y: imageRect.minY + CGFloat(normalizedRect.y) * imageRect.height,
            width: CGFloat(normalizedRect.width) * imageRect.width,
            height: CGFloat(normalizedRect.height) * imageRect.height
        )
    }
}

public final class DatasetSubjectAnchorController: ObservableObject, @unchecked Sendable {
    @Published public var currentFrameCandidates: [GolfPoseCandidateFrame] = []
    @Published public var loadedAnchors: [GolfSubjectAnchorDecision] = []
    @Published public var selectedAnchorIDs: Set<String> = []
    @Published public var annotatorID: String = "annotator-mac"
    @Published public var statusMessage: String? = nil
    @Published public var currentFrameImage: CGImage? = nil

    private var currentTask: Task<Void, Never>? = nil

    public init() {}

    public func replaceLoadedAnchors(
        _ anchors: [GolfSubjectAnchorDecision],
        selectingAnchorID: String? = nil
    ) {
        let availableIDs = Set(anchors.map(\.anchorID))
        loadedAnchors = anchors
        selectedAnchorIDs.formIntersection(availableIDs)
        if let selectingAnchorID, availableIDs.contains(selectingAnchorID) {
            selectedAnchorIDs.insert(selectingAnchorID)
        }
    }

    public func resetState() {
        currentTask?.cancel()
        currentTask = nil
        currentFrameCandidates = []
        loadedAnchors = []
        selectedAnchorIDs = []
        statusMessage = nil
        currentFrameImage = nil
    }

    public func loadFrameCandidates(
        videoURL: URL,
        sourceFrameIndex: Int
    ) {
        currentTask?.cancel()
        currentTask = Task { @MainActor in
            do {
                let provider = try ExactVideoFrameProvider.load(url: videoURL)
                let frame = try provider.frame(at: sourceFrameIndex)
                guard !Task.isCancelled else { return }
                self.currentFrameImage = frame.image
                let time = CMTimeGetSeconds(frame.presentationTime)
                let candidates = VisionPoseExtractor.extractCandidates(
                    from: frame.image,
                    sourceFrameIndex: sourceFrameIndex,
                    sourceTime: time
                )
                guard !Task.isCancelled else { return }
                self.currentFrameCandidates = candidates
                self.statusMessage = "Loaded \(candidates.count) candidates at frame \(sourceFrameIndex)"
            } catch {
                guard !Task.isCancelled else { return }
                self.statusMessage = "Failed to load frame \(sourceFrameIndex): \(error.localizedDescription)"
            }
        }
    }

    public func findCandidate(
        at point: GolfNormalizedPoint,
        in candidates: [GolfPoseCandidateFrame]
    ) -> GolfPoseCandidateFrame? {
        let matching = candidates.filter { candidate in
            let b = candidate.bodyBounds
            return point.x >= b.x && point.x <= b.x + b.width &&
                   point.y >= b.y && point.y <= b.y + b.height
        }
        guard matching.count == 1 else {
            return nil
        }
        return matching.first
    }

    public func makeAnchor(
        clipID: String,
        mediaSHA256: String,
        timelineSHA256: String,
        sourceFrameIndex: Int,
        candidateIndex: Int,
        clickPoint: GolfNormalizedPoint,
        visionFrameworkVersion: String = VisionPoseExtractor.visionFrameworkVersion,
        visionRequestRevision: String = VisionPoseExtractor.visionRequestVersion
    ) -> GolfSubjectAnchorDecision {
        let anchorID = "anchor-\(clipID)-f\(sourceFrameIndex)-c\(candidateIndex)-\(UUID().uuidString.prefix(8))"
        return GolfSubjectAnchorDecision(
            anchorID: anchorID,
            clipID: clipID,
            mediaSHA256: mediaSHA256,
            timelineSHA256: timelineSHA256,
            sourceFrameIndex: sourceFrameIndex,
            candidateIndex: candidateIndex,
            normalizedClickPoint: clickPoint,
            visionFrameworkVersion: visionFrameworkVersion,
            visionRequestRevision: visionRequestRevision,
            annotatorID: annotatorID,
            decidedAt: Date()
        )
    }
}

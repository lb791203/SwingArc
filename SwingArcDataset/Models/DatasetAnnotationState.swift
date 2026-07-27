import Foundation

public enum DatasetAnnotationAction: Equatable, Sendable {
    case step(Int)
    case jumpToFrame(Int)
    case acceptPrediction(GolfLandmark, decidedAt: Date)
    case correctPoint(GolfLandmark, GolfNormalizedPoint, decidedAt: Date)
    case setOccluded(GolfLandmark, decidedAt: Date)
    case setOutOfFrame(GolfLandmark, decidedAt: Date)
    case setUnresolved(GolfLandmark, decidedAt: Date)
    case acceptUnresolvedFrame(decidedAt: Date)
}

/// A display-only point. It never mutates the immutable prediction run.
public struct DatasetLandmarkPresentation: Equatable, Sendable {
    public let landmark: GolfLandmark
    public let point: GolfNormalizedPoint
    public let isPrediction: Bool
    public let heatmapConfidence: Double?

    public init(
        landmark: GolfLandmark,
        point: GolfNormalizedPoint,
        isPrediction: Bool,
        heatmapConfidence: Double?
    ) {
        self.landmark = landmark
        self.point = point
        self.isPrediction = isPrediction
        self.heatmapConfidence = heatmapConfidence
    }
}

public struct DatasetAnnotationState: Equatable, Sendable {
    /// Held-out blind passes intentionally have no loaded prediction object.
    public let predictionRun: GolfPredictionRun?
    public let parentPredictionRunID: String
    public let mediaFrameCount: Int
    public let annotationQueue: [GolfAnnotationQueueItem]
    public internal(set) var currentSourceFrameIndex: Int
    public internal(set) var decisions: [AnnotationDecisionKey: GolfAnnotationDecision]
    public let annotatorID: String
    public let revisionID: String

    public init(
        predictionRun: GolfPredictionRun?,
        parentPredictionRunID: String? = nil,
        mediaFrameCount: Int,
        annotationQueue: [GolfAnnotationQueueItem],
        currentSourceFrameIndex: Int,
        decisions: [AnnotationDecisionKey: GolfAnnotationDecision] = [:],
        annotatorID: String,
        revisionID: String
    ) {
        self.predictionRun = predictionRun
        self.parentPredictionRunID = parentPredictionRunID ?? predictionRun?.predictionRunID ?? ""
        self.mediaFrameCount = max(0, mediaFrameCount)
        self.annotationQueue = annotationQueue
        self.currentSourceFrameIndex = Self.clamped(
            currentSourceFrameIndex,
            mediaFrameCount: max(0, mediaFrameCount)
        )
        self.decisions = decisions
        self.annotatorID = annotatorID
        self.revisionID = revisionID
    }

    public var frameCount: Int { mediaFrameCount }

    public var currentQueuePosition: Int? {
        annotationQueue.firstIndex {
            $0.sourceFrameIndex == currentSourceFrameIndex
        }
    }

    public var reviewedQueueFrameCount: Int {
        annotationQueue.reduce(into: 0) { count, item in
            if frameIsReviewed(item.sourceFrameIndex) {
                count += 1
            }
        }
    }

    public var pendingQueueFrameCount: Int {
        max(0, annotationQueue.count - reviewedQueueFrameCount)
    }

    public func frameIsReviewed(_ sourceFrameIndex: Int) -> Bool {
        let decided = Set(
            decisions.compactMap { key, decision in
                key.frameIndex == sourceFrameIndex ? decision.landmark : nil
            }
        )
        return GolfLandmark.allCases.allSatisfy { decided.contains($0) }
    }

    public var decisionsForCurrentFrame: [GolfAnnotationDecision] {
        decisions.filter { $0.key.frameIndex == currentSourceFrameIndex }
            .values
            .sorted {
                (GolfLandmark.allCases.firstIndex(of: $0.landmark) ?? 0)
                    < (GolfLandmark.allCases.firstIndex(of: $1.landmark) ?? 0)
            }
    }

    public var currentPredictionFrame: GolfPredictionFrame? {
        predictionRun?.frames.first { $0.sourceFrameIndex == currentSourceFrameIndex }
    }

    public var currentFrameIsReviewed: Bool {
        let decided = Set(decisionsForCurrentFrame.map(\.landmark))
        return GolfLandmark.allCases.allSatisfy { decided.contains($0) }
    }

    public var allowsPredictionAcceptance: Bool {
        guard let run = predictionRun else { return false }
        if run.runKind == .manualBootstrap {
            return run.frames.contains { !$0.points.isEmpty }
        }
        return true
    }

    /// Whether the batch action can resolve every still-undecided landmark.
    /// Existing manual decisions remain valid even when this frame has no prediction.
    public var canAcceptCurrentFrame: Bool {
        guard frameCount > 0, allowsPredictionAcceptance else { return false }
        return GolfLandmark.allCases.allSatisfy { landmark in
            let key = AnnotationDecisionKey(
                frameIndex: currentSourceFrameIndex,
                landmark: landmark
            )
            if decisions[key] != nil {
                return true
            }
            guard let point = currentPredictionFrame?
                .points[landmark]?
                .resolvedFullFramePoint else {
                return false
            }
            return Self.isUnitPoint(point)
        }
    }

    public var canSaveCurrentFrame: Bool {
        guard currentFrameIsReviewed else { return false }
        return decisionsForCurrentFrame.allSatisfy {
            (try? $0.validated()) != nil
        }
    }

    public var currentFrameIsComplete: Bool {
        guard currentFrameIsReviewed else { return false }
        for decision in decisionsForCurrentFrame {
            guard decision.kind != .unresolved else { return false }
            do {
                let prediction = decision.kind == .acceptedPrediction
                    ? currentPredictionFrame?.points[decision.landmark]
                    : nil
                guard try decision.validated().resolvedLandmark(prediction: prediction) != nil else {
                    return false
                }
            } catch {
                return false
            }
        }
        return true
    }

    /// Prediction-first display: an undecided point is shown from the run, while
    /// accepted/corrected decisions override it. Hidden and unresolved decisions draw nothing.
    public func presentation(for landmark: GolfLandmark) -> DatasetLandmarkPresentation? {
        let key = AnnotationDecisionKey(frameIndex: currentSourceFrameIndex, landmark: landmark)
        if let decision = decisions[key] {
            guard let point = decision.fullFramePoint,
                  decision.kind == .acceptedPrediction || decision.kind == .correctedPoint else {
                return nil
            }
            return DatasetLandmarkPresentation(
                landmark: landmark,
                point: point,
                isPrediction: decision.kind == .acceptedPrediction,
                heatmapConfidence: currentPredictionFrame?.points[landmark]?.heatmapConfidence
            )
        }
        guard let prediction = currentPredictionFrame?.points[landmark],
              let point = prediction.resolvedFullFramePoint,
              Self.isUnitPoint(point) else {
            return nil
        }
        return DatasetLandmarkPresentation(
            landmark: landmark,
            point: point,
            isPrediction: true,
            heatmapConfidence: prediction.heatmapConfidence
        )
    }

    public func fullFramePointToROI(_ point: GolfNormalizedPoint) -> GolfNormalizedPoint? {
        guard Self.isUnitPoint(point), let transform = usableROITransform else { return nil }
        let result = transform.fullFramePointToROI(point)
        return Self.isUnitPoint(result) ? result : nil
    }

    public func roiPointToFullFrame(_ point: GolfNormalizedPoint) -> GolfNormalizedPoint? {
        guard Self.isUnitPoint(point), let transform = usableROITransform else { return nil }
        let result = transform.roiPointToFullFrame(point)
        return Self.isUnitPoint(result) ? result : nil
    }

    private var usableROITransform: GolfROIAffineTransform? {
        guard let transform = currentPredictionFrame?.roiTransform else { return nil }
        let values = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty,
                      transform.invA, transform.invB, transform.invC, transform.invD, transform.invTx, transform.invTy]
        guard values.allSatisfy(\.isFinite),
              abs(transform.a * transform.d - transform.b * transform.c) > 0.000_000_001,
              abs(transform.invA * transform.invD - transform.invB * transform.invC) > 0.000_000_001 else {
            return nil
        }
        return transform
    }

    fileprivate static func isUnitPoint(_ point: GolfNormalizedPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    fileprivate static func clamped(_ index: Int, mediaFrameCount: Int) -> Int {
        guard mediaFrameCount > 0 else { return 0 }
        return max(0, min(mediaFrameCount - 1, index))
    }
}

public struct AnnotationDecisionKey: Hashable, Equatable, Sendable {
    public let frameIndex: Int
    public let landmark: GolfLandmark

    public init(frameIndex: Int, landmark: GolfLandmark) {
        self.frameIndex = frameIndex
        self.landmark = landmark
    }
}

public enum DatasetAnnotationReducer {
    public static func reduce(
        _ state: DatasetAnnotationState,
        _ action: DatasetAnnotationAction
    ) -> DatasetAnnotationState {
        var next = state
        switch action {
        case .step(let delta):
            next.currentSourceFrameIndex = DatasetAnnotationState.clamped(
                next.currentSourceFrameIndex + delta,
                mediaFrameCount: next.mediaFrameCount
            )
        case .jumpToFrame(let sourceFrameIndex):
            next.currentSourceFrameIndex = DatasetAnnotationState.clamped(
                sourceFrameIndex,
                mediaFrameCount: next.mediaFrameCount
            )
        case .acceptPrediction(let landmark, let decidedAt):
            guard next.allowsPredictionAcceptance else { return next }
            guard let point = next.currentPredictionFrame?.points[landmark]?.resolvedFullFramePoint,
                  DatasetAnnotationState.isUnitPoint(point) else { return next }
            next.replace(landmark, kind: .acceptedPrediction, point: point, decidedAt: decidedAt)
        case .correctPoint(let landmark, let point, let decidedAt):
            guard DatasetAnnotationState.isUnitPoint(point) else { return next }
            next.replace(landmark, kind: .correctedPoint, point: point, decidedAt: decidedAt)
        case .setOccluded(let landmark, let decidedAt):
            next.replace(landmark, kind: .occluded, point: nil, decidedAt: decidedAt)
        case .setOutOfFrame(let landmark, let decidedAt):
            next.replace(landmark, kind: .outOfFrame, point: nil, decidedAt: decidedAt)
        case .setUnresolved(let landmark, let decidedAt):
            next.replace(landmark, kind: .unresolved, point: nil, decidedAt: decidedAt)
        case .acceptUnresolvedFrame(let decidedAt):
            guard next.allowsPredictionAcceptance else { return next }
            for landmark in GolfLandmark.allCases where next.decision(for: landmark) == nil {
                guard let point = next.currentPredictionFrame?.points[landmark]?.resolvedFullFramePoint,
                      DatasetAnnotationState.isUnitPoint(point) else { continue }
                next.replace(landmark, kind: .acceptedPrediction, point: point, decidedAt: decidedAt)
            }
        }
        return next
    }
}

private extension DatasetAnnotationState {
    func decision(for landmark: GolfLandmark) -> GolfAnnotationDecision? {
        decisions[AnnotationDecisionKey(frameIndex: currentSourceFrameIndex, landmark: landmark)]
    }

    mutating func replace(
        _ landmark: GolfLandmark,
        kind: GolfAnnotationDecisionKind,
        point: GolfNormalizedPoint?,
        decidedAt: Date
    ) {
        decisions[AnnotationDecisionKey(frameIndex: currentSourceFrameIndex, landmark: landmark)] = GolfAnnotationDecision(
            landmark: landmark,
            kind: kind,
            fullFramePoint: point,
            annotatorID: annotatorID,
            decidedAt: decidedAt
        )
    }
}

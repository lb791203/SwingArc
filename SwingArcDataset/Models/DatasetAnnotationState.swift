import Foundation

// MARK: - Annotation Action

public enum DatasetAnnotationAction: Equatable, Sendable {
    case step(Int)
    case acceptPrediction(GolfLandmark)
    case correctPoint(GolfLandmark, GolfNormalizedPoint)
    case setOccluded(GolfLandmark)
    case setOutOfFrame(GolfLandmark)
    case setUnresolved(GolfLandmark)
    case acceptUnresolvedFrame
}

// MARK: - Annotation State

public struct DatasetAnnotationState: Equatable, Sendable {
    /// The immutable prediction run driving this annotation session.
    public let predictionRun: GolfPredictionRun

    /// Current frame index in the source timeline.
    public internal(set) var currentSourceFrameIndex: Int

    /// Keyed by `(sourceFrameIndex, landmark)` to guarantee one decision per landmark per frame.
    /// Using a flat dictionary so replacements are free of duplicates by construction.
    public internal(set) var decisions: [AnnotationDecisionKey: GolfAnnotationDecision]

    /// Stable annotator identity for this session.
    public let annotatorID: String

    /// Current revision ID.
    public let revisionID: String

    public init(
        predictionRun: GolfPredictionRun,
        currentSourceFrameIndex: Int,
        decisions: [AnnotationDecisionKey: GolfAnnotationDecision] = [:],
        annotatorID: String,
        revisionID: String
    ) {
        self.predictionRun = predictionRun
        self.currentSourceFrameIndex = currentSourceFrameIndex
        self.decisions = decisions
        self.annotatorID = annotatorID
        self.revisionID = revisionID
    }

    // MARK: Derived Properties

    /// Total frame count from the prediction run.
    public var frameCount: Int {
        predictionRun.frames.count
    }

    /// Decisions that belong to the currently displayed frame.
    public var decisionsForCurrentFrame: [GolfAnnotationDecision] {
        decisions.filter { $0.key.frameIndex == currentSourceFrameIndex }
            .values
            // Deterministic order: GolfLandmark.allCases order
            .sorted { lhs, rhs in
                let lhsIndex = GolfLandmark.allCases.firstIndex(of: lhs.landmark) ?? 0
                let rhsIndex = GolfLandmark.allCases.firstIndex(of: rhs.landmark) ?? 0
                return lhsIndex < rhsIndex
            }
    }

    /// The prediction frame for the current source index, if available.
    public var currentPredictionFrame: GolfPredictionFrame? {
        predictionRun.frames.first(where: { $0.sourceFrameIndex == currentSourceFrameIndex })
    }

    /// All five landmarks have a decision, including `unresolved`.
    public var currentFrameIsReviewed: Bool {
        let decidedLandmarks = Set(decisionsForCurrentFrame.map(\.landmark))
        return GolfLandmark.allCases.allSatisfy { decidedLandmarks.contains($0) }
    }

    /// All five decisions are contractually valid for saving.
    /// `unresolved` is rejected by validation, so if all five are validated it's savable.
    public var canSaveCurrentFrame: Bool {
        guard currentFrameIsReviewed else { return false }
        do {
            for decision in decisionsForCurrentFrame {
                _ = try decision.validated()
            }
            return true
        } catch {
            return false
        }
    }

    /// All five decisions can produce resolved training targets.
    /// `unresolved` resolves to nil → not complete.
    public var currentFrameIsComplete: Bool {
        guard currentFrameIsReviewed else { return false }
        // Must have prediction for the frame to resolve acceptedPrediction decisions
        guard let predFrame = currentPredictionFrame else { return false }
        for decision in decisionsForCurrentFrame {
            if decision.kind == .unresolved { return false }
            do {
                let validated = try decision.validated()
                let prediction = predFrame.points[decision.landmark]
                if try validated.resolvedLandmark(prediction: prediction) == nil {
                    return false
                }
            } catch {
                return false
            }
        }
        return true
    }
}

// MARK: - Decision Key

/// Unique key for a single landmark decision at a specific frame.
public struct AnnotationDecisionKey: Hashable, Equatable, Sendable {
    public let frameIndex: Int
    public let landmark: GolfLandmark

    public init(frameIndex: Int, landmark: GolfLandmark) {
        self.frameIndex = frameIndex
        self.landmark = landmark
    }
}

// MARK: - Reducer

public enum DatasetAnnotationReducer {
    public static func reduce(
        _ state: DatasetAnnotationState,
        _ action: DatasetAnnotationAction
    ) -> DatasetAnnotationState {
        var next = state
        switch action {
        case .step(let delta):
            let newIndex = next.currentSourceFrameIndex + delta
            next.currentSourceFrameIndex = max(0, min(next.frameCount - 1, newIndex))

        case .acceptPrediction(let landmark):
            guard let predFrame = next.currentPredictionFrame,
                  let predPoint = predFrame.points[landmark],
                  predPoint.resolvedFullFramePoint != nil else {
                // No prediction available — cannot accept
                return next
            }
            let key = AnnotationDecisionKey(
                frameIndex: next.currentSourceFrameIndex,
                landmark: landmark
            )
            let decisionPoint = predPoint.resolvedFullFramePoint!
            let decision = GolfAnnotationDecision(
                landmark: landmark,
                kind: .acceptedPrediction,
                fullFramePoint: decisionPoint,
                annotatorID: next.annotatorID,
                decidedAt: Date(timeIntervalSince1970: 0) // injected stable time; real time set by controller
            )
            next.decisions[key] = decision

        case .correctPoint(let landmark, let point):
            let key = AnnotationDecisionKey(
                frameIndex: next.currentSourceFrameIndex,
                landmark: landmark
            )
            let decision = GolfAnnotationDecision(
                landmark: landmark,
                kind: .correctedPoint,
                fullFramePoint: point,
                annotatorID: next.annotatorID,
                decidedAt: Date(timeIntervalSince1970: 0)
            )
            next.decisions[key] = decision

        case .setOccluded(let landmark):
            let key = AnnotationDecisionKey(
                frameIndex: next.currentSourceFrameIndex,
                landmark: landmark
            )
            let decision = GolfAnnotationDecision(
                landmark: landmark,
                kind: .occluded,
                fullFramePoint: nil,
                annotatorID: next.annotatorID,
                decidedAt: Date(timeIntervalSince1970: 0)
            )
            next.decisions[key] = decision

        case .setOutOfFrame(let landmark):
            let key = AnnotationDecisionKey(
                frameIndex: next.currentSourceFrameIndex,
                landmark: landmark
            )
            let decision = GolfAnnotationDecision(
                landmark: landmark,
                kind: .outOfFrame,
                fullFramePoint: nil,
                annotatorID: next.annotatorID,
                decidedAt: Date(timeIntervalSince1970: 0)
            )
            next.decisions[key] = decision

        case .setUnresolved(let landmark):
            let key = AnnotationDecisionKey(
                frameIndex: next.currentSourceFrameIndex,
                landmark: landmark
            )
            let decision = GolfAnnotationDecision(
                landmark: landmark,
                kind: .unresolved,
                fullFramePoint: nil,
                annotatorID: next.annotatorID,
                decidedAt: Date(timeIntervalSince1970: 0)
            )
            next.decisions[key] = decision

        case .acceptUnresolvedFrame:
            // Fill in acceptedPrediction for pending landmarks that have predictions.
            // Preserve existing corrected/occluded/outOfFrame/unresolved decisions.
            guard let predFrame = next.currentPredictionFrame else { return next }
            for landmark in GolfLandmark.allCases {
                let key = AnnotationDecisionKey(
                    frameIndex: next.currentSourceFrameIndex,
                    landmark: landmark
                )
                // Skip if already decided
                if next.decisions[key] != nil { continue }
                // Only accept if prediction exists with a full-frame point
                if let predPoint = predFrame.points[landmark],
                   predPoint.resolvedFullFramePoint != nil {
                    let decision = GolfAnnotationDecision(
                        landmark: landmark,
                        kind: .acceptedPrediction,
                        fullFramePoint: predPoint.resolvedFullFramePoint!,
                        annotatorID: next.annotatorID,
                        decidedAt: Date(timeIntervalSince1970: 0)
                    )
                    next.decisions[key] = decision
                }
            }
        }
        return next
    }
}

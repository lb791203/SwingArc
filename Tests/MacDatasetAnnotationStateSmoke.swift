import Foundation

private let decisionTime = Date(timeIntervalSince1970: 1_753_408_123.25)

private func point(_ x: Double, _ y: Double) -> GolfNormalizedPoint {
    GolfNormalizedPoint(x: x, y: y)
}

private func transform() -> GolfROIAffineTransform {
    GolfROIAffineTransform(
        a: 2.0, b: 0.0, c: 0.0, d: 2.0, tx: -0.25, ty: -0.25,
        invA: 0.5, invB: 0.0, invC: 0.0, invD: 0.5, invTx: 0.125, invTy: 0.125
    )
}

private func predictionPoint(_ coordinate: GolfNormalizedPoint = point(0.4, 0.6)) -> GolfPredictionPoint {
    GolfPredictionPoint(
        roiX: 0.55,
        roiY: 0.75,
        heatmapConfidence: 0.91,
        heatmapDispersion: 0.04,
        visibilityProbabilities: [0.9, 0.08, 0.02],
        preTrackingFullFramePoint: coordinate,
        postTrackingFullFramePoint: coordinate,
        trackingStatus: "tracked"
    )
}

private func predictionFrame(
    _ sourceFrameIndex: Int,
    points: [GolfLandmark: GolfPredictionPoint]
) -> GolfPredictionFrame {
    GolfPredictionFrame(
        sourceFrameIndex: sourceFrameIndex,
        sourceTime: Double(sourceFrameIndex) / 30.0,
        roiTransform: transform(),
        points: points
    )
}

private func state(
    mediaFrameCount: Int = 757,
    currentFrame: Int = 542,
    frames: [GolfPredictionFrame]? = nil,
    queue: [GolfAnnotationQueueItem] = []
) -> DatasetAnnotationState {
    let resolvedFrames = frames ?? [
        predictionFrame(100, points: Dictionary(uniqueKeysWithValues: GolfLandmark.allCases.map { ($0, predictionPoint()) })),
        predictionFrame(220, points: Dictionary(uniqueKeysWithValues: GolfLandmark.allCases.map { ($0, predictionPoint()) })),
        predictionFrame(542, points: Dictionary(uniqueKeysWithValues: GolfLandmark.allCases.map { ($0, predictionPoint()) }))
    ]
    return DatasetAnnotationState(
        predictionRun: GolfPredictionRun(
            predictionRunID: "real-run",
            clipID: "real-clip",
            mediaSHA256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            visionFrameworkVersion: "vision",
            visionRequestVersion: "body-pose",
            roiAlgorithmVersion: "stable-roi",
            roiConfigSHA256: String(repeating: "c", count: 64),
            modelSHA256: String(repeating: "d", count: 64),
            decoderVersion: "decoder",
            trackerVersion: "tracker",
            createdAt: decisionTime,
            frames: resolvedFrames,
            provenanceHash: String(repeating: "e", count: 64)
        ),
        mediaFrameCount: mediaFrameCount,
        annotationQueue: queue,
        currentSourceFrameIndex: currentFrame,
        annotatorID: "test-annotator",
        revisionID: "revision-1"
    )
}

private func reduce(
    _ state: DatasetAnnotationState,
    _ action: DatasetAnnotationAction
) -> DatasetAnnotationState {
    DatasetAnnotationReducer.reduce(state, action)
}

private func allPredictions(_ state: DatasetAnnotationState) -> DatasetAnnotationState {
    GolfLandmark.allCases.reduce(state) { partial, landmark in
        reduce(partial, .acceptPrediction(landmark, decidedAt: decisionTime))
    }
}

private func testMediaRangeAndSparsePredictionNavigation() {
    var value = state()
    precondition(value.frameCount == 757)
    precondition(value.currentSourceFrameIndex == 542)
    value = reduce(value, .step(-5))
    precondition(value.currentSourceFrameIndex == 537, "source navigation must not follow sparse prediction frames")
    value = reduce(value, .step(-9_999))
    precondition(value.currentSourceFrameIndex == 0)
    value = reduce(value, .step(9_999))
    precondition(value.currentSourceFrameIndex == 756)
    precondition(value.currentPredictionFrame == nil, "sparse predictions must remain sparse")
    print("  ✓ media range and sparse prediction navigation")
}

private func testEmptyMediaIsSafe() {
    var value = state(mediaFrameCount: 0, currentFrame: 99, frames: [])
    precondition(value.frameCount == 0)
    precondition(value.currentSourceFrameIndex == 0)
    value = reduce(value, .step(1))
    precondition(value.currentSourceFrameIndex == 0)
    print("  ✓ empty media is safe")
}

private func testManualDecisionsDoNotRequirePrediction() {
    var value = state(currentFrame: 101)
    value = reduce(value, .correctPoint(.grip, point(0.2, 0.3), decidedAt: decisionTime))
    value = reduce(value, .setOccluded(.shaftStart, decidedAt: decisionTime))
    value = reduce(value, .setOutOfFrame(.shaftEnd, decidedAt: decisionTime))
    value = reduce(value, .correctPoint(.clubhead, point(0.7, 0.8), decidedAt: decisionTime))
    value = reduce(value, .setOccluded(.ball, decidedAt: decisionTime))
    precondition(value.currentFrameIsReviewed)
    precondition(value.currentFrameIsComplete, "corrected and hidden decisions do not need a prediction")
    precondition(value.canSaveCurrentFrame)
    precondition(value.canAcceptCurrentFrame, "manual-only frames remain eligible for the batch action")
    print("  ✓ manual decisions do not require prediction")
}

private func testAcceptedPredictionNeedsPrediction() {
    var value = state(currentFrame: 101)
    precondition(!value.canAcceptCurrentFrame)
    value = reduce(value, .acceptPrediction(.ball, decidedAt: decisionTime))
    precondition(value.decisionsForCurrentFrame.isEmpty)
    value = reduce(value, .setUnresolved(.ball, decidedAt: decisionTime))
    precondition(!value.currentFrameIsComplete)
    print("  ✓ accepted prediction needs prediction")
}

private func testDecidedAtReplacementAndBatchPreservation() {
    var value = state()
    value = reduce(value, .correctPoint(.grip, point(0.1, 0.2), decidedAt: decisionTime))
    value = reduce(value, .setOccluded(.grip, decidedAt: decisionTime.addingTimeInterval(2)))
    let grip = value.decisionsForCurrentFrame.first { $0.landmark == .grip }
    precondition(grip?.kind == .occluded)
    precondition(grip?.decidedAt == decisionTime.addingTimeInterval(2))
    value = reduce(value, .acceptUnresolvedFrame(decidedAt: decisionTime.addingTimeInterval(3)))
    precondition(value.decisionsForCurrentFrame.count == 5)
    precondition(value.decisionsForCurrentFrame.first { $0.landmark == .grip }?.kind == .occluded)
    precondition(value.decisionsForCurrentFrame.filter { $0.kind == .acceptedPrediction }.allSatisfy { $0.decidedAt == decisionTime.addingTimeInterval(3) })
    print("  ✓ injected timestamps, replacement, and batch preservation")
}

private func testPredictionRemainsImmutableAndPresentationIsPredictionFirst() {
    var value = state()
    let original = value.predictionRun
    let predicted = value.presentation(for: .grip)
    precondition(predicted?.point == point(0.4, 0.6))
    precondition(predicted?.isPrediction == true)
    value = reduce(value, .correctPoint(.grip, point(0.9, 0.1), decidedAt: decisionTime))
    let corrected = value.presentation(for: .grip)
    precondition(corrected?.point == point(0.9, 0.1))
    precondition(corrected?.isPrediction == false)
    value = reduce(value, .setOccluded(.ball, decidedAt: decisionTime))
    value = reduce(value, .setUnresolved(.shaftEnd, decidedAt: decisionTime))
    precondition(value.presentation(for: .ball) == nil)
    precondition(value.presentation(for: .shaftEnd) == nil)
    precondition(value.predictionRun == original)
    print("  ✓ prediction-first presentation and immutable prediction")
}

private func testROIRoundTripAndInvalidTransformRejection() {
    let value = state()
    let source = point(0.35, 0.55)
    let roi = value.fullFramePointToROI(source)
    precondition(roi != nil)
    precondition(value.roiPointToFullFrame(roi!) == source)
    let invalidFrame = predictionFrame(542, points: [:])
    let invalidTransform = GolfROIAffineTransform(
        a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0,
        invA: .nan, invB: 0, invC: 0, invD: 1, invTx: 0, invTy: 0
    )
    let invalid = state(frames: [GolfPredictionFrame(
        sourceFrameIndex: invalidFrame.sourceFrameIndex,
        sourceTime: invalidFrame.sourceTime,
        roiTransform: invalidTransform,
        points: invalidFrame.points
    )])
    precondition(invalid.fullFramePointToROI(source) == nil)
    precondition(invalid.roiPointToFullFrame(point(0.5, 0.5)) == nil)
    print("  ✓ ROI round trip and invalid transform rejection")
}

@main
struct MacDatasetAnnotationStateSmoke {
    static func main() {
        print("Checkpoint A: DatasetAnnotationState & Reducer smoke tests")
        testMediaRangeAndSparsePredictionNavigation()
        testEmptyMediaIsSafe()
        testManualDecisionsDoNotRequirePrediction()
        testAcceptedPredictionNeedsPrediction()
        testDecidedAtReplacementAndBatchPreservation()
        testPredictionRemainsImmutableAndPresentationIsPredictionFirst()
        testROIRoundTripAndInvalidTransformRejection()
        print("All Checkpoint A tests passed.")
    }
}

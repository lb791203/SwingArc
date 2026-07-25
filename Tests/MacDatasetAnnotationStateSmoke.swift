import Foundation

// MARK: - Fixtures

private func fixturePoint(x: Double, y: Double) -> GolfNormalizedPoint {
    GolfNormalizedPoint(x: x, y: y)
}

private func fixturePredictionPoint(
    hasFullFrame: Bool = true,
    roiX: Double = 0.25,
    roiY: Double = 0.75,
    confidence: Double = 0.91,
    dispersion: Double = 0.04
) -> GolfPredictionPoint {
    GolfPredictionPoint(
        roiX: roiX,
        roiY: roiY,
        heatmapConfidence: confidence,
        heatmapDispersion: dispersion,
        visibilityProbabilities: [0.9, 0.08, 0.02],
        preTrackingFullFramePoint: hasFullFrame ? fixturePoint(x: 0.40, y: 0.60) : nil,
        postTrackingFullFramePoint: hasFullFrame ? fixturePoint(x: 0.401, y: 0.601) : nil,
        trackingStatus: "tracked",
        anomalyReason: nil
    )
}

private func fixtureAnnotationState(
    frameCount: Int = 757,
    frame: Int = 542
) -> DatasetAnnotationState {
    let roiTransform = GolfROIAffineTransform(
        a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0,
        invA: 1.0, invB: 0.0, invC: 0.0, invD: 1.0, invTx: 0.0, invTy: 0.0
    )

    var predictionFrames: [GolfPredictionFrame] = []
    // Generate predictions for all 757 frames so any frame can be navigated to
    for i in 0..<757 {
        var points: [GolfLandmark: GolfPredictionPoint] = [:]
        for landmark in GolfLandmark.allCases {
            points[landmark] = fixturePredictionPoint(hasFullFrame: true)
        }
        predictionFrames.append(GolfPredictionFrame(
            sourceFrameIndex: i,
            sourceTime: Double(i) / 30.0,
            roiTransform: roiTransform,
            points: points,
            anomalyReason: nil
        ))
    }

    let predictionRun = GolfPredictionRun(
        schemaVersion: 1,
        predictionRunID: "pred-run-001",
        clipID: "clip-001",
        mediaSHA256: String(repeating: "a", count: 64),
        timelineSHA256: String(repeating: "b", count: 64),
        visionFrameworkVersion: "1.0.0",
        visionRequestVersion: "VNDetectHumanBodyPoseRequest-v1",
        roiAlgorithmVersion: "roi-v1",
        roiConfigSHA256: String(repeating: "c", count: 64),
        modelSHA256: String(repeating: "d", count: 64),
        decoderVersion: "decoder-v1",
        trackerVersion: "tracker-v1",
        createdAt: Date(timeIntervalSince1970: 1000),
        frames: predictionFrames,
        provenanceHash: String(repeating: "e", count: 64)
    )

    return DatasetAnnotationState(
        predictionRun: predictionRun,
        currentSourceFrameIndex: frame,
        decisions: [:],
        annotatorID: "test-annotator",
        revisionID: "rev-001"
    )
}

// MARK: - Tests

private func testInitialFrame() throws {
    let state = fixtureAnnotationState()
    precondition(state.currentSourceFrameIndex == 542, "Expected initial frame 542")
    precondition(state.frameCount == 757, "Expected 757 total frames")
    print("  ✓ testInitialFrame")
}

private func testStepMinusFive() throws {
    var state = fixtureAnnotationState()
    state = DatasetAnnotationReducer.reduce(state, .step(-5))
    precondition(state.currentSourceFrameIndex == 537, "Expected 537 after -5")
    print("  ✓ testStepMinusFive")
}

private func testStepBackAndForth() throws {
    var state = fixtureAnnotationState(frame: 542)
    state = DatasetAnnotationReducer.reduce(state, .step(-5))
    precondition(state.currentSourceFrameIndex == 537)
    state = DatasetAnnotationReducer.reduce(state, .step(+5))
    precondition(state.currentSourceFrameIndex == 542, "Expected back to 542")
    print("  ✓ testStepBackAndForth")
}

private func testStepClipping() throws {
    var state = fixtureAnnotationState(frame: 2)
    state = DatasetAnnotationReducer.reduce(state, .step(-5))
    precondition(state.currentSourceFrameIndex == 0, "Expected clipped to 0, got \(state.currentSourceFrameIndex)")

    state = fixtureAnnotationState(frame: 754)
    state = DatasetAnnotationReducer.reduce(state, .step(+5))
    precondition(state.currentSourceFrameIndex == 756, "Expected clipped to 756, got \(state.currentSourceFrameIndex)")
    print("  ✓ testStepClipping")
}

private func testAllFiveAcceptPredictionMakesComplete() throws {
    var state = fixtureAnnotationState()
    for landmark in GolfLandmark.allCases {
        state = DatasetAnnotationReducer.reduce(state, .acceptPrediction(landmark))
    }
    precondition(state.decisionsForCurrentFrame.count == 5, "Expected 5 decisions, got \(state.decisionsForCurrentFrame.count)")
    precondition(state.currentFrameIsReviewed, "All five decisions => reviewed")
    precondition(state.currentFrameIsComplete, "No unresolved => complete")
    print("  ✓ testAllFiveAcceptPredictionMakesComplete")
}

private func testBallOutOfFrameHasNilCoordinate() throws {
    var state = fixtureAnnotationState()
    state = DatasetAnnotationReducer.reduce(state, .setOutOfFrame(.ball))
    let decision = state.decisionsForCurrentFrame.first(where: { $0.landmark == .ball })
    precondition(decision != nil, "ball decision must exist")
    precondition(decision?.kind == .outOfFrame, "must be outOfFrame")
    precondition(decision?.fullFramePoint == nil, "outOfFrame must have nil coordinate")
    print("  ✓ testBallOutOfFrameHasNilCoordinate")
}

private func testShaftEndUnresolvedCanSaveButNotComplete() throws {
    var state = fixtureAnnotationState()
    // Mark 4 landmarks accepted, 1 unresolved
    for landmark in GolfLandmark.allCases where landmark != .shaftEnd {
        state = DatasetAnnotationReducer.reduce(state, .acceptPrediction(landmark))
    }
    state = DatasetAnnotationReducer.reduce(state, .setUnresolved(.shaftEnd))

    precondition(state.canSaveCurrentFrame, "All five decided should be savable")
    precondition(!state.currentFrameIsComplete, "unresolved shaftEnd should make incomplete")
    precondition(state.decisionsForCurrentFrame.count == 5, "Must have 5 decisions")
    print("  ✓ testShaftEndUnresolvedCanSaveButNotComplete")
}

private func testCorrectedPointUsesFullFrameCoordinate() throws {
    var state = fixtureAnnotationState()
    let correctedCoord = fixturePoint(x: 0.511, y: 0.422)
    state = DatasetAnnotationReducer.reduce(state, .correctPoint(.grip, correctedCoord))
    let decision = state.decisionsForCurrentFrame.first(where: { $0.landmark == .grip })
    precondition(decision?.kind == .correctedPoint)
    precondition(decision?.fullFramePoint == correctedCoord, "Corrected point must preserve the exact coordinate")
    print("  ✓ testCorrectedPointUsesFullFrameCoordinate")
}

private func testDuplicateDecisionReplacesPrevious() throws {
    var state = fixtureAnnotationState()
    state = DatasetAnnotationReducer.reduce(state, .acceptPrediction(.clubhead))
    state = DatasetAnnotationReducer.reduce(state, .setOccluded(.clubhead))
    let decisions = state.decisionsForCurrentFrame.filter { $0.landmark == .clubhead }
    precondition(decisions.count == 1, "Expected 1 decision for clubhead, got \(decisions.count)")
    precondition(decisions[0].kind == .occluded, "Last decision should be occluded")
    print("  ✓ testDuplicateDecisionReplacesPrevious")
}

private func testOriginalPredictionRunNotModified() throws {
    let original = fixtureAnnotationState()
    var state = original
    for landmark in GolfLandmark.allCases {
        state = DatasetAnnotationReducer.reduce(state, .acceptPrediction(landmark))
    }
    // The prediction run's frames should still have roiX/roiY intact
    let predFrame = state.predictionRun.frames[542]
    precondition(predFrame.points[.grip]?.roiX == 0.25, "Prediction ROI should not change")
    precondition(predFrame.points[.grip]?.roiY == 0.75, "Prediction ROI should not change")
    precondition(predFrame.points[.grip]?.heatmapConfidence == 0.91, "Prediction confidence should not change")
    print("  ✓ testOriginalPredictionRunNotModified")
}

private func testAcceptPredictionRequiresPrediction() throws {
    var state = fixtureAnnotationState()
    // Replace the run with one where a landmark has no prediction
    let roiforFakeFrame = GolfROIAffineTransform(
        a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0,
        invA: 1.0, invB: 0.0, invC: 0.0, invD: 1.0, invTx: 0.0, invTy: 0.0
    )
    var missingPoints: [GolfLandmark: GolfPredictionPoint] = [:]
    // Only add some landmarks
    for landmark in GolfLandmark.allCases where landmark != .ball {
        missingPoints[landmark] = fixturePredictionPoint(hasFullFrame: true)
    }
    let missingFrames = (0..<757).map { i in
        GolfPredictionFrame(
            sourceFrameIndex: i,
            sourceTime: Double(i) / 30.0,
            roiTransform: roiforFakeFrame,
            points: i == 542 ? missingPoints : [:],
            anomalyReason: nil
        )
    }
    let missingRun = GolfPredictionRun(
        schemaVersion: 1,
        predictionRunID: "pred-run-missing",
        clipID: "clip-001",
        mediaSHA256: String(repeating: "a", count: 64),
        timelineSHA256: String(repeating: "b", count: 64),
        visionFrameworkVersion: "1.0.0",
        visionRequestVersion: "VNDetectHumanBodyPoseRequest-v1",
        roiAlgorithmVersion: "roi-v1",
        roiConfigSHA256: String(repeating: "c", count: 64),
        modelSHA256: String(repeating: "d", count: 64),
        decoderVersion: "decoder-v1",
        trackerVersion: "tracker-v1",
        createdAt: Date(timeIntervalSince1970: 1000),
        frames: missingFrames,
        provenanceHash: String(repeating: "e", count: 64)
    )
    state = DatasetAnnotationState(
        predictionRun: missingRun,
        currentSourceFrameIndex: 542,
        decisions: [:],
        annotatorID: "test-annotator",
        revisionID: "rev-001"
    )
    // acceptPrediction for ball should not add a decision since there's no prediction
    state = DatasetAnnotationReducer.reduce(state, .acceptPrediction(.ball))
    let ballDecision = state.decisionsForCurrentFrame.first(where: { $0.landmark == .ball })
    precondition(ballDecision == nil, "acceptPrediction without prediction should not create decision")
    print("  ✓ testAcceptPredictionRequiresPrediction")
}

private func testAcceptUnresolvedFrameOnlyAcceptsPendingWithPredictions() throws {
    var state = fixtureAnnotationState()
    // Set some manual decisions first
    state = DatasetAnnotationReducer.reduce(state, .setOccluded(.ball))
    state = DatasetAnnotationReducer.reduce(state, .setUnresolved(.shaftEnd))
    // "Accept the current frame" - should fill in the 3 remaining with predictions
    // (grip, shaftStart, clubhead)
    state = DatasetAnnotationReducer.reduce(state, .acceptUnresolvedFrame)
    precondition(state.decisionsForCurrentFrame.count == 5, "Should now have 5 decisions total, got \(state.decisionsForCurrentFrame.count)")

    // Ball should still be occluded
    let ballDecision = state.decisionsForCurrentFrame.first(where: { $0.landmark == .ball })
    precondition(ballDecision?.kind == .occluded, "Ball should remain occluded")

    // shaftEnd should still be unresolved
    let shaftEndDecision = state.decisionsForCurrentFrame.first(where: { $0.landmark == .shaftEnd })
    precondition(shaftEndDecision?.kind == .unresolved, "shaftEnd should remain unresolved")

    // grip, shaftStart, clubhead should be accepted prediction
    for landmark in [GolfLandmark.grip, GolfLandmark.shaftStart, GolfLandmark.clubhead] {
        let decision = state.decisionsForCurrentFrame.first(where: { $0.landmark == landmark })
        precondition(decision?.kind == .acceptedPrediction, "\(landmark) should be acceptedPrediction")
    }
    print("  ✓ testAcceptUnresolvedFrameOnlyAcceptsPendingWithPredictions")
}

private func testDeterministicOutput() throws {
    let state1 = fixtureAnnotationState()
    var result1 = state1
    for _ in 0..<3 {
        for landmark in GolfLandmark.allCases {
            result1 = DatasetAnnotationReducer.reduce(result1, .acceptPrediction(landmark))
        }
        result1 = DatasetAnnotationReducer.reduce(result1, .step(+1))
    }
    // Reconstruct identical state and apply same actions
    let state2 = fixtureAnnotationState()
    var result2 = state2
    for _ in 0..<3 {
        for landmark in GolfLandmark.allCases {
            result2 = DatasetAnnotationReducer.reduce(result2, .acceptPrediction(landmark))
        }
        result2 = DatasetAnnotationReducer.reduce(result2, .step(+1))
    }
    // Decisions must match exactly
    precondition(result1.decisions == result2.decisions, "Deterministic reducer must produce identical decisions")
    print("  ✓ testDeterministicOutput")
}

// MARK: - Main

@main
struct MacDatasetAnnotationStateSmoke {
    static func main() throws {
        print("Checkpoint A: DatasetAnnotationState & Reducer smoke tests")
        print()

        try testInitialFrame()
        try testStepMinusFive()
        try testStepBackAndForth()
        try testStepClipping()
        try testAllFiveAcceptPredictionMakesComplete()
        try testBallOutOfFrameHasNilCoordinate()
        try testShaftEndUnresolvedCanSaveButNotComplete()
        try testCorrectedPointUsesFullFrameCoordinate()
        try testDuplicateDecisionReplacesPrevious()
        try testOriginalPredictionRunNotModified()
        try testAcceptPredictionRequiresPrediction()
        try testAcceptUnresolvedFrameOnlyAcceptsPendingWithPredictions()
        try testDeterministicOutput()

        print()
        print("All Checkpoint A tests passed.")
    }
}

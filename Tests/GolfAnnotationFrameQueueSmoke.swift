import Foundation

// MARK: - Test helpers

private func runTests() {
    testTrainingQueueExact()
    testValidationQueueSuperset()
    testMultiReasonFrame()
    testProtectedStatus()
    testBoundaryClipping()
    testDeterministicOrdering()
    testMissingPPointFailure()
    testNegativeSamplesCapped()
    testDuplicateAnomalyNoDuplicateReason()
    testDuplicateNegativeSamplesDedupedBeforeCap()
    testReasonsUniqueAndSorted()
    testTotalFramesZeroNoCrash()
    testTotalFramesNegativeNoCrash()
    testPPointOutOfOrderRejects()
    testPPointOutOfBoundsRejects()
    testProtectedFrameDeleteRejected()
    testUnprotectedFrameDeleteAllowed()
    testPolicyDrivesConstants()
    print("All GolfAnnotationFrameQueue tests passed.")
}

// MARK: - Training queue exact collection

private func testTrainingQueueExact() {
    let input = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [50, 300],
        preSwingNegativeSamples: [10, 30, 60, 80],
        postSwingNegativeSamples: [280, 350, 380]
    )

    let result = GolfAnnotationFrameQueueBuilder.build(input: input)
    precondition(!result.isEmpty, "Training queue must not be empty")

    let frames = result.map(\.sourceFrameIndex)

    // P1–P5 stride 4
    let sparse1 = Array(stride(from: 100, through: 200, by: 4))
    // P5–P8 stride 2
    let sparse2 = Array(stride(from: 200, through: 260, by: 2))
    // P6±12 dense
    let p6Dense = Array(208...232)
    // P8±12 dense
    let p8Dense = Array(248...272)

    let expected = Set(sparse1 + sparse2 + p6Dense + p8Dense + [50, 300, 10, 30, 60, 80, 280, 350, 380])

    precondition(
        Set(frames) == expected,
        "Training frames mismatch.\nGot: \(frames)\nExpected: \(expected.sorted())"
    )
    precondition(
        frames == frames.sorted(),
        "Training frames must be sorted"
    )

    // Dedup check
    precondition(
        frames.count == Set(frames).count,
        "Training frames must be unique"
    )
}

// MARK: - Validation queue superset of dense window

private func testValidationQueueSuperset() {
    let input = GolfAnnotationQueueInput(
        split: .validation,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )

    let result = GolfAnnotationFrameQueueBuilder.build(input: input)
    let frames = Set(result.map(\.sourceFrameIndex))

    // Validation must include P5-12 to P8+12 = 188...272
    let denseWindow = Set(188...272)
    precondition(
        frames.isSuperset(of: denseWindow),
        "Validation must include all frames 188...272"
    )
}

// MARK: - Multi-reason dedup

private func testMultiReasonFrame() {
    let input = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [220],  // 220 is also in P6 dense
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )

    let result = GolfAnnotationFrameQueueBuilder.build(input: input)
    let items220 = result.filter { $0.sourceFrameIndex == 220 }
    precondition(
        items220.count == 1,
        "Frame 220 must appear exactly once, got \(items220.count)"
    )
    // Should have both p6Dense and anomaly reasons
    let reasons = items220.first!.reasons
    precondition(
        reasons.contains(.p6Dense),
        "Frame 220 must include p6Dense reason"
    )
    precondition(
        reasons.contains(.anomaly),
        "Frame 220 must include anomaly reason"
    )
}

// MARK: - Protected status

private func testProtectedStatus() {
    let input = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [50],
        preSwingNegativeSamples: [10],
        postSwingNegativeSamples: []
    )

    let result = GolfAnnotationFrameQueueBuilder.build(input: input)

    // P-stage frames must be protected
    let p100 = result.first { $0.sourceFrameIndex == 100 }!
    precondition(p100.isProtected, "P1 frame must be protected")

    let p200 = result.first { $0.sourceFrameIndex == 200 }!
    precondition(p200.isProtected, "P5 frame must be protected")

    let p220 = result.first { $0.sourceFrameIndex == 220 }!
    precondition(p220.isProtected, "P6 frame must be protected")

    let p260 = result.first { $0.sourceFrameIndex == 260 }!
    precondition(p260.isProtected, "P8 frame must be protected")

    // Dense window frames must be protected
    let p210 = result.first { $0.sourceFrameIndex == 210 }!
    precondition(p210.isProtected, "P6 dense window frame must be protected")

    let p255 = result.first { $0.sourceFrameIndex == 255 }!
    precondition(p255.isProtected, "P8 dense window frame must be protected")

    // Sparse stride frames between P1–P5 (not P-stage endpoints) should not be protected
    let p104 = result.first { $0.sourceFrameIndex == 104 }!
    precondition(!p104.isProtected, "Sparse stride frame must not be protected")

    // Negative samples must not be protected
    let neg10 = result.first { $0.sourceFrameIndex == 10 }!
    precondition(!neg10.isProtected, "Negative sample must not be protected")

    // Anomaly frames must not be protected
    let anom50 = result.first { $0.sourceFrameIndex == 50 }!
    precondition(!anom50.isProtected, "Anomaly frame must not be protected")
}

// MARK: - Boundary clipping

private func testBoundaryClipping() {
    // P6-12 would go below 0 if P6=5
    let inputNearStart = GolfAnnotationQueueInput(
        split: .training,
        p1: 5,
        p5: 30,
        p6: 5,
        p8: 60,
        totalFrames: 100,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
    let resultStart = GolfAnnotationFrameQueueBuilder.build(input: inputNearStart)
    let framesStart = resultStart.map(\.sourceFrameIndex)
    precondition(
        framesStart.allSatisfy { $0 >= 0 },
        "No negative frames allowed"
    )

    // P8+12 would exceed total if totalFrames=270
    let inputNearEnd = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 270,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: [300, 310]
    )
    let resultEnd = GolfAnnotationFrameQueueBuilder.build(input: inputNearEnd)
    let framesEnd = resultEnd.map(\.sourceFrameIndex)
    precondition(
        framesEnd.allSatisfy { $0 < 270 },
        "No frames beyond totalFrames"
    )
    // 300, 310 should be excluded
    precondition(
        !framesEnd.contains(300) && !framesEnd.contains(310),
        "Out-of-range negative samples must be excluded"
    )
}

// MARK: - Deterministic ordering

private func testDeterministicOrdering() {
    let input = GolfAnnotationQueueInput(
        split: .validation,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [50, 300, 150],
        preSwingNegativeSamples: [10, 30, 60, 80],
        postSwingNegativeSamples: [280, 350, 380]
    )

    let run1 = GolfAnnotationFrameQueueBuilder.build(input: input)
    let run2 = GolfAnnotationFrameQueueBuilder.build(input: input)
    precondition(
        run1 == run2,
        "Queue must be deterministic across runs"
    )
}

// MARK: - Missing P-point failure

private func testMissingPPointFailure() {
    let input = GolfAnnotationQueueInput(
        split: .training,
        p1: nil,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )

    let result = GolfAnnotationFrameQueueBuilder.build(input: input)
    precondition(
        result.isEmpty,
        "Missing required P-point must yield empty queue"
    )
}

// MARK: - Negative samples capped

private func testNegativeSamplesCapped() {
    let input = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [],
        preSwingNegativeSamples: Array(stride(from: 0, through: 96, by: 4)),
        postSwingNegativeSamples: Array(stride(from: 264, through: 399, by: 4))
    )

    let result = GolfAnnotationFrameQueueBuilder.build(input: input)

    let preCount = result.filter { $0.reasons.contains(.preSwingNegative) }.count
    let postCount = result.filter { $0.reasons.contains(.postSwingNegative) }.count

    precondition(
        preCount <= 10,
        "Pre-swing negatives must be capped at 10, got \(preCount)"
    )
    precondition(
        postCount <= 10,
        "Post-swing negatives must be capped at 10, got \(postCount)"
    )
}

// MARK: - Duplicate anomaly no duplicate reason

private func testDuplicateAnomalyNoDuplicateReason() {
    let input = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [50, 50, 50, 220],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
    let result = GolfAnnotationFrameQueueBuilder.build(input: input)
    let item50 = result.first { $0.sourceFrameIndex == 50 }!
    let anomalyCount = item50.reasons.filter { $0 == .anomaly }.count
    precondition(anomalyCount == 1, "Duplicate anomaly must not produce duplicate reason, got \(anomalyCount)")
    // Frame 220 also has p6Dense
    let item220 = result.first { $0.sourceFrameIndex == 220 }!
    let anomalyCount220 = item220.reasons.filter { $0 == .anomaly }.count
    precondition(anomalyCount220 == 1, "Frame 220 anomaly reason must appear once, got \(anomalyCount220)")
}

// MARK: - Duplicate negative samples deduped before cap

private func testDuplicateNegativeSamplesDedupedBeforeCap() {
    let preSwing = [10, 10, 10, 20, 20, 30, 40, 50, 60, 70, 80, 90]
    let input = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [],
        preSwingNegativeSamples: preSwing,
        postSwingNegativeSamples: []
    )
    let result = GolfAnnotationFrameQueueBuilder.build(input: input)
    let preCount = result.filter { $0.reasons.contains(.preSwingNegative) }.count
    // Unique frames: 10,20,30,40,50,60,70,80,90 = 9, all fit within 10 cap
    precondition(preCount == 9, "Deduped pre-swing unique frames should be 9, got \(preCount)")

    // Now test with more than 10 unique
    let preSwingOverflow = Array(stride(from: 0, through: 100, by: 4))
    let input2 = GolfAnnotationQueueInput(
        split: .training,
        p1: 200,
        p5: 300,
        p6: 310,
        p8: 350,
        totalFrames: 400,
        anomalyFrames: [],
        preSwingNegativeSamples: preSwingOverflow,
        postSwingNegativeSamples: []
    )
    let result2 = GolfAnnotationFrameQueueBuilder.build(input: input2)
    let preCount2 = result2.filter { $0.reasons.contains(.preSwingNegative) }.count
    precondition(preCount2 == 10, "Pre-swing negatives must be capped at 10 after dedup, got \(preCount2)")
}

// MARK: - Reasons unique and sorted

private func testReasonsUniqueAndSorted() {
    let input = GolfAnnotationQueueInput(
        split: .validation,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [210],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
    let result = GolfAnnotationFrameQueueBuilder.build(input: input)
    for item in result {
        // Reasons must be unique within each item
        let uniqueReasons = Set(item.reasons)
        precondition(
            uniqueReasons.count == item.reasons.count,
            "Frame \(item.sourceFrameIndex) has duplicate reasons: \(item.reasons)"
        )
        // Reasons must be sorted
        precondition(
            item.reasons == item.reasons.sorted(),
            "Frame \(item.sourceFrameIndex) reasons not sorted: \(item.reasons)"
        )
    }
}

// MARK: - totalFrames zero no crash

private func testTotalFramesZeroNoCrash() {
    let input = GolfAnnotationQueueInput(
        split: .training,
        p1: 0,
        p5: 0,
        p6: 0,
        p8: 0,
        totalFrames: 0,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
    let result = GolfAnnotationFrameQueueBuilder.build(input: input)
    precondition(result.isEmpty, "totalFrames=0 must yield empty queue")
}

// MARK: - totalFrames negative no crash

private func testTotalFramesNegativeNoCrash() {
    let input = GolfAnnotationQueueInput(
        split: .training,
        p1: 0,
        p5: 5,
        p6: 6,
        p8: 10,
        totalFrames: -5,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
    let result = GolfAnnotationFrameQueueBuilder.build(input: input)
    precondition(result.isEmpty, "Negative totalFrames must yield empty queue")
}

// MARK: - P-point out of order rejects

private func testPPointOutOfOrderRejects() {
    // P5 before P1
    let input1 = GolfAnnotationQueueInput(
        split: .training,
        p1: 200,
        p5: 100,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
    let result1 = GolfAnnotationFrameQueueBuilder.build(input: input1)
    precondition(result1.isEmpty, "P5 < P1 must yield empty queue")

    // P6 before P5
    let input2 = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 150,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
    let result2 = GolfAnnotationFrameQueueBuilder.build(input: input2)
    precondition(result2.isEmpty, "P6 < P5 must yield empty queue")

    // P8 before P6
    let input3 = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 260,
        p8: 220,
        totalFrames: 400,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
    let result3 = GolfAnnotationFrameQueueBuilder.build(input: input3)
    precondition(result3.isEmpty, "P8 < P6 must yield empty queue")
}

// MARK: - P-point out of bounds rejects

private func testPPointOutOfBoundsRejects() {
    // P1 negative
    let input1 = GolfAnnotationQueueInput(
        split: .training,
        p1: -5,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
    let result1 = GolfAnnotationFrameQueueBuilder.build(input: input1)
    precondition(result1.isEmpty, "Negative P1 must yield empty queue")

    // P8 >= totalFrames
    let input2 = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 400,
        totalFrames: 400,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
    let result2 = GolfAnnotationFrameQueueBuilder.build(input: input2)
    precondition(result2.isEmpty, "P8 >= totalFrames must yield empty queue")

    // P6 > P8 range
    let input3 = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 300,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
    let result3 = GolfAnnotationFrameQueueBuilder.build(input: input3)
    precondition(result3.isEmpty, "P6 > P8 must yield empty queue")
}

// MARK: - Protected frame delete rejected

private func testProtectedFrameDeleteRejected() {
    let input = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
    let result = GolfAnnotationFrameQueueBuilder.build(input: input)

    // P-stage frames
    for frame in [100, 200, 220, 260] {
        let item = result.first { $0.sourceFrameIndex == frame }!
        precondition(item.isProtected, "Frame \(frame) must be protected")
        let deletion = GolfAnnotationFrameQueueBuilder.requestDeletion(of: item, from: result)
        precondition(deletion == nil, "Protected frame \(frame) deletion must be rejected")
    }

    // Dense window frames
    for frame in [208, 215, 232, 248, 260, 272] {
        let item = result.first { $0.sourceFrameIndex == frame }!
        guard item.isProtected else { continue }
        let deletion = GolfAnnotationFrameQueueBuilder.requestDeletion(of: item, from: result)
        precondition(deletion == nil, "Protected dense frame \(frame) deletion must be rejected")
    }
}

// MARK: - Unprotected frame delete allowed

private func testUnprotectedFrameDeleteAllowed() {
    let input = GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 200,
        p6: 220,
        p8: 260,
        totalFrames: 400,
        anomalyFrames: [50],
        preSwingNegativeSamples: [10],
        postSwingNegativeSamples: [350]
    )
    let result = GolfAnnotationFrameQueueBuilder.build(input: input)

    // Sparse stride frame
    let sparse = result.first { $0.sourceFrameIndex == 104 }!
    precondition(!sparse.isProtected, "104 must be unprotected")
    let deletion1 = GolfAnnotationFrameQueueBuilder.requestDeletion(of: sparse, from: result)
    precondition(deletion1 != nil, "Unprotected sparse frame deletion must succeed")
    precondition(
        !deletion1!.contains { $0.sourceFrameIndex == 104 },
        "Deleted frame must be removed from result"
    )

    // Anomaly frame
    let anom = result.first { $0.sourceFrameIndex == 50 }!
    precondition(!anom.isProtected, "50 must be unprotected")
    let deletion2 = GolfAnnotationFrameQueueBuilder.requestDeletion(of: anom, from: result)
    precondition(deletion2 != nil, "Unprotected anomaly frame deletion must succeed")

    // Negative sample
    let neg = result.first { $0.sourceFrameIndex == 10 }!
    precondition(!neg.isProtected, "10 must be unprotected")
    let deletion3 = GolfAnnotationFrameQueueBuilder.requestDeletion(of: neg, from: result)
    precondition(deletion3 != nil, "Unprotected negative frame deletion must succeed")
}

// MARK: - Policy drives constants

private func testPolicyDrivesConstants() {
    let policy = GolfAnnotationQueuePolicy.v1
    precondition(policy.sparseP1P5Stride == 4, "Policy stride P1-P5 must be 4")
    precondition(policy.sparseP5P8Stride == 2, "Policy stride P5-P8 must be 2")
    precondition(policy.denseWindowRadius == 12, "Policy dense radius must be 12")
    precondition(policy.maxNegativeSamples == 10, "Policy negative limit must be 10")
}

@main
struct GolfAnnotationFrameQueueTestRunner {
    static func main() {
        runTests()
    }
}

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

@main
struct GolfAnnotationFrameQueueTestRunner {
    static func main() {
        runTests()
    }
}

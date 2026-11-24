import Foundation

/// Run with:
///   xcrun swiftc -parse-as-library \
///     SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift \
///     Tests/PoseOnlyStageRulesSmoke.swift -o /tmp/pose-only-rules && /tmp/pose-only-rules
@main
struct PoseOnlyStageRulesSmoke {
    static func main() {
        checksGeometryStages()
        checksTempoInvariance()
        checksLocalRefinementReachesDenseResult()
        checksStrictResultIsNeverRefined()
    }

    /// P1 must be the last still address frame even when the takeaway starts
    /// with a flat, sideways hand move. P4 must be the first frame of the top
    /// plateau. P2/P3 come from hip/shoulder height, not equal splits.
    private static func checksGeometryStages() {
        let result = SwingStageDetector.detectPoseOnlyCandidates(takeawayScenario(timeScale: 1))
        precondition(frame(.address, in: result) == 3, "P1 must be the last still address frame, not a flat takeaway frame")
        precondition(frame(.takeaway, in: result) == 7, "P2 must be the hands closest to hip height")
        precondition(frame(.leadArmParallelBackswing, in: result) == 9, "P3 must be the hands closest to shoulder height")
        precondition(frame(.top, in: result) == 12, "P4 must be the first frame of the top plateau, not the last high-hand frame")
        precondition(frame(.impact, in: result) == 17, "P7 must be the first downswing frame back at address height")
        precondition(frame(.shaftParallelDownswing, in: result) == nil)
        precondition(frame(.followThrough, in: result) == nil)
        let frames = result.detections.compactMap(\.sourceFrameIndex)
        precondition(zip(frames, frames.dropFirst()).allSatisfy(<), "Stages must stay in swing order")
    }

    /// The same positions on an 8x slow-motion timeline give the same frames.
    private static func checksTempoInvariance() {
        let realTime = SwingStageDetector.detectPoseOnlyCandidates(takeawayScenario(timeScale: 1))
        let slowMotion = SwingStageDetector.detectPoseOnlyCandidates(takeawayScenario(timeScale: 8))
        precondition(
            realTime.detections.map(\.sourceFrameIndex) == slowMotion.detections.map(\.sourceFrameIndex),
            "Body-only stages must not depend on the timeline speed"
        )
    }

    /// A 240 FPS swing sampled every 20 frames must reach the frames that a
    /// full dense pass finds, with a bounded number of extra decodes.
    private static func checksLocalRefinementReachesDenseResult() {
        let frameCount = 520
        let dense = (0..<frameCount).map(denseSwingSample)
        let denseResult = SwingStageDetector.detectPoseOnlyCandidates(dense)
        let sparse = stride(from: 0, to: frameCount, by: 20).map(denseSwingSample)
        let strictFailure = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: Set(SwingStage.pStages)
        )
        var decodedFrames = 0
        let refined = LocalStageRefinement.refine(
            strictResult: strictFailure,
            poseSamples: sparse,
            maximumSourceFrameIndex: frameCount - 1,
            maximumHalfSpan: 60
        ) { requested in
            decodedFrames += requested.count
            return requested.map(denseSwingSample)
        }
        let bodyStages: [SwingStage] = [
            .address, .takeaway, .leadArmParallelBackswing,
            .top, .leadArmParallelDownswing, .impact
        ]
        for stage in bodyStages {
            guard let expected = frame(stage, in: denseResult),
                  let actual = frame(stage, in: refined.result) else {
                preconditionFailure("\(stage) must resolve on dense and refined samples")
            }
            precondition(
                abs(expected - actual) <= 2,
                "\(stage) refined to \(actual), dense pass found \(expected)"
            )
        }
        precondition(decodedFrames <= 120, "Refinement decoded \(decodedFrames) frames; budget is 120")
        precondition(
            refined.poseSamples.count == Set(refined.poseSamples.compactMap(\.sourceFrameIndex)).count,
            "Refined samples must not duplicate source frames"
        )
    }

    private static func checksStrictResultIsNeverRefined() {
        let strictSuccess = SwingAnalysisResult(
            detectedMarkers: [KeyframeMarker(time: 0.42, stage: .impact)],
            unresolvedStages: Set(SwingStage.pStages).subtracting([.impact]),
            detections: [
                SwingStageDetection(
                    stage: .impact,
                    time: 0.42,
                    sourceFrameIndex: 101,
                    confidence: 0.9,
                    status: .confirmed
                )
            ]
        )
        var sampled = false
        let refined = LocalStageRefinement.refine(
            strictResult: strictSuccess,
            poseSamples: takeawayScenario(timeScale: 1),
            maximumSourceFrameIndex: 1_000,
            maximumHalfSpan: 60
        ) { _ in
            sampled = true
            return []
        }
        precondition(refined.result == strictSuccess)
        precondition(!sampled, "Strict solver results must not trigger extra decoding")
    }

    // MARK: - Fixtures

    private static func takeawayScenario(timeScale: Double) -> [SwingPoseSample] {
        let hands: [(CGFloat, CGFloat)] = [
            (0.500, 0.820), (0.502, 0.821), (0.499, 0.819), (0.500, 0.820), // address
            (0.460, 0.820), (0.420, 0.800),                                   // flat takeaway
            (0.400, 0.700), (0.400, 0.580), (0.420, 0.450), (0.450, 0.340),   // backswing
            (0.500, 0.240), (0.520, 0.200), (0.530, 0.192), (0.540, 0.190),   // top plateau
            (0.520, 0.300), (0.500, 0.450), (0.480, 0.600), (0.500, 0.800),   // downswing
            (0.560, 0.700), (0.620, 0.500), (0.660, 0.300)                    // follow-through
        ]
        return hands.enumerated().map { index, hand in
            sample(
                frame: index,
                time: Double(index) / 30 * timeScale,
                hand: CGPoint(x: hand.0, y: hand.1)
            )
        }
    }

    /// 240 FPS swing: address 0–119, backswing 120–339, top hold 340–359,
    /// downswing 360–419, follow-through after 420.
    private static func denseSwingSample(_ frame: Int) -> SwingPoseSample {
        let hand = denseSwingHand(frame)
        return sample(
            frame: frame,
            time: Double(frame) / 240,
            hand: CGPoint(x: hand.x, y: hand.y)
        )
    }

    private static func denseSwingHand(_ frame: Int) -> (x: Double, y: Double) {
        func smoothstep(_ value: Double) -> Double {
            let u = min(1, max(0, value))
            return u * u * (3 - 2 * u)
        }
        let f = Double(frame)
        if frame < 120 {
            return (0.50, 0.82)
        }
        if frame < 340 {
            let u = smoothstep((f - 120) / 220)
            return (0.50 - 0.08 * sin(Double.pi * u), 0.82 - 0.62 * u)
        }
        if frame < 360 {
            return (0.50, 0.20)
        }
        if frame < 420 {
            let u = pow((f - 360) / 60, 2)
            return (0.50 - 0.02 * u, 0.20 + 0.60 * u)
        }
        let u = min(1, (f - 420) / 60)
        return (0.48 + 0.15 * u, 0.80 - 0.55 * smoothstep(u))
    }

    private static func sample(frame: Int, time: Double, hand: CGPoint) -> SwingPoseSample {
        SwingPoseSample(
            time: time,
            leftWrist: CGPoint(x: hand.x - 0.01, y: hand.y),
            rightWrist: CGPoint(x: hand.x + 0.01, y: hand.y),
            leftElbow: CGPoint(x: 0.42, y: min(0.95, hand.y + 0.08)),
            rightElbow: CGPoint(x: 0.58, y: min(0.95, hand.y + 0.08)),
            leftShoulder: CGPoint(x: 0.40, y: 0.34),
            rightShoulder: CGPoint(x: 0.60, y: 0.34),
            leftHip: CGPoint(x: 0.43, y: 0.58),
            rightHip: CGPoint(x: 0.57, y: 0.58),
            head: CGPoint(x: 0.50, y: 0.16),
            spineAngle: 18,
            aggregateConfidence: 0.92,
            sourceFrameIndex: frame
        )
    }

    private static func frame(_ stage: SwingStage, in result: SwingAnalysisResult) -> Int? {
        result.detections.first { $0.stage == stage }?.sourceFrameIndex
    }
}

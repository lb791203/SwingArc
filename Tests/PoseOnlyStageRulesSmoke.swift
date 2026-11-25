import Foundation

/// Run with:
///   xcrun swiftc -parse-as-library \
///     SwingArc/Models/{DrawingModels,SwingMetricModels,SwingObservationModels,WorkspaceModels,FrameExtractionTolerancePolicy}.swift \
///     SwingArc/Services/{StageCalibration,SwingInputQualityEvaluator,SwingStageDetector}.swift \
///     Tests/PoseOnlyStageRulesSmoke.swift -o /tmp/pose-only-rules && /tmp/pose-only-rules
@main
struct PoseOnlyStageRulesSmoke {
    static func main() {
        checksGeometryStages()
        checksTempoInvariance()
        checksLocalRefinementReachesDenseResult()
        checksStrictResultIsNeverRefined()
        checksRefinementPlanIncludesAdjacentFrames()
        checksRefinementKeepsResolvedStages()
        checksVisionAvailabilityPolicy()
        checksLeadArmGeometryDefinesArmParallel()
        checksBentLeadArmIsNotArmParallel()
        checksHeightFallbackIsOnlyForReview()
        checksDenseWristSpikeIsIgnored()
    }

    /// P3/P5 come from lead-arm geometry: the straight lead arm closest to
    /// horizontal. P2 and P7 have no shaft or ball evidence on the body-only
    /// path, so they are reported for review, not confirmed.
    private static func checksLeadArmGeometryDefinesArmParallel() {
        let result = SwingStageDetector.detectPoseOnlyCandidates(armSwingScenario(bentLeadArmNearParallel: false))
        precondition(frame(.address, in: result) == 5, "P1 \(String(describing: frame(.address, in: result)))")
        precondition(frame(.takeaway, in: result) == 8, "P2 \(String(describing: frame(.takeaway, in: result)))")
        precondition(frame(.leadArmParallelBackswing, in: result) == 12, "P3 must be the straight lead arm nearest horizontal")
        precondition(frame(.top, in: result) == 17)
        precondition(frame(.leadArmParallelDownswing, in: result) == 24, "P5 must be the straight lead arm nearest horizontal")
        precondition(frame(.impact, in: result) == 30)
        precondition(status(.leadArmParallelBackswing, in: result) == .confirmed)
        precondition(status(.takeaway, in: result) == .lowConfidence, "Body-only P2 has no shaft evidence")
        precondition(status(.impact, in: result) == .lowConfidence, "Body-only P7 cannot tell a practice swing from a hit")
    }

    /// A bent lead arm is not "lead arm parallel"; with the arm joints visible
    /// the stage stays unresolved instead of falling back to hand height.
    private static func checksBentLeadArmIsNotArmParallel() {
        let result = SwingStageDetector.detectPoseOnlyCandidates(armSwingScenario(bentLeadArmNearParallel: true))
        precondition(frame(.leadArmParallelBackswing, in: result) == nil, "Bent lead arm must not become P3")
        precondition(frame(.leadArmParallelDownswing, in: result) == nil, "Bent lead arm must not become P5")
        precondition(frame(.top, in: result) == 17)
    }

    /// Without lead-arm joints, P3/P5 fall back to hand height but are only
    /// offered for review.
    private static func checksHeightFallbackIsOnlyForReview() {
        let result = SwingStageDetector.detectPoseOnlyCandidates(takeawayScenario(timeScale: 1))
        precondition(status(.leadArmParallelBackswing, in: result) == .lowConfidence)
        precondition(status(.leadArmParallelDownswing, in: result) != .confirmed)
    }

    /// One bad Vision wrist in a dense refinement run must not become P4.
    private static func checksDenseWristSpikeIsIgnored() {
        let clean = (0..<520).map(denseSwingSample)
        var spiked = clean
        let hand = denseSwingHand(300)
        spiked[300] = sample(frame: 300, time: 300.0 / 240, hand: CGPoint(x: hand.x, y: hand.y - 0.25))
        let cleanResult = SwingStageDetector.detectPoseOnlyCandidates(clean)
        let spikedResult = SwingStageDetector.detectPoseOnlyCandidates(spiked)
        precondition(
            cleanResult.detections.map(\.sourceFrameIndex) == spikedResult.detections.map(\.sourceFrameIndex),
            "A single-frame wrist spike inside a dense run must not move any stage"
        )
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

    /// Observed 0, 60, 120 with a candidate on 60: the plan must request 59
    /// and 61 as well as the strided frames.
    private static func checksRefinementPlanIncludesAdjacentFrames() {
        let detection = SwingStageDetection(
            stage: .top,
            time: 1,
            sourceFrameIndex: 60,
            confidence: 0.8,
            status: .confirmed
        )
        let frames = LocalStageRefinementPlan.sourceFrames(
            around: [detection],
            observedSourceFrames: [0, 60, 120],
            maximumSourceFrameIndex: 239,
            maximumHalfSpan: 60
        )
        precondition(frames.contains(59) && frames.contains(61), "Plan \(frames) skips the adjacent frames")
        precondition(!frames.contains(60), "Observed frames must not be requested again")
    }

    private static func checksRefinementKeepsResolvedStages() {
        func result(_ statuses: [SwingStage: SwingStageDetectionStatus]) -> SwingAnalysisResult {
            SwingAnalysisResult(
                detectedMarkers: [],
                unresolvedStages: [],
                detections: statuses.map { stage, status in
                    SwingStageDetection(
                        stage: stage,
                        time: status == .unresolved ? nil : 1,
                        sourceFrameIndex: status == .unresolved ? nil : 30,
                        confidence: status == .confirmed ? 0.8 : 0.5,
                        status: status
                    )
                }
            )
        }
        let current = result([.top: .confirmed, .impact: .lowConfidence, .followThrough: .unresolved])
        precondition(LocalStageRefinement.isAcceptable(
            result([.top: .confirmed, .impact: .confirmed, .followThrough: .unresolved]),
            replacing: current
        ))
        precondition(!LocalStageRefinement.isAcceptable(
            result([.top: .unresolved, .impact: .confirmed, .followThrough: .confirmed]),
            replacing: current
        ), "Swapping a resolved stage for another must be rejected")
        precondition(!LocalStageRefinement.isAcceptable(
            result([.top: .lowConfidence, .impact: .lowConfidence, .followThrough: .unresolved]),
            replacing: current
        ), "Downgrading a confirmed stage must be rejected")
    }

    private static func checksVisionAvailabilityPolicy() {
        typealias Policy = PoseDetectionAvailabilityPolicy
        precondition(Policy.isUnavailable(requests: 40, failed: 40, withPerson: 0))
        precondition(
            Policy.isUnavailable(requests: 40, failed: 30, withPerson: 0),
            "Mostly failed requests with no person found are a Vision problem"
        )
        precondition(!Policy.isUnavailable(requests: 40, failed: 30, withPerson: 4))
        precondition(!Policy.isUnavailable(requests: 40, failed: 5, withPerson: 0))
        precondition(!Policy.isUnavailable(requests: 0, failed: 0, withPerson: 0))
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

    private static func takeawayScenario(
        timeScale: Double,
        leftShoulderY: CGFloat = 0.34,
        rightShoulderY: CGFloat = 0.34
    ) -> [SwingPoseSample] {
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
                hand: CGPoint(x: hand.0, y: hand.1),
                leftShoulderY: leftShoulderY,
                rightShoulderY: rightShoulderY
            )
        }
    }

    /// A swing driven by the lead-arm angle φ from straight down (lead =
    /// left, the lower shoulder). Address 0–5, backswing 6–17, top hold
    /// 17–19, downswing 20–31 (impact at φ≈22° on frame 30), follow-through.
    private static func armSwingScenario(bentLeadArmNearParallel: Bool) -> [SwingPoseSample] {
        var angles: [Double] = Array(repeating: 10, count: 6)
        angles += (1...12).map { 10 + 140 * Double($0) / 12 }
        angles += [150, 150]
        angles += (1...12).map { 150 - 140 * Double($0) / 12 }
        angles += [-20, -50, -80, -110, -130, -140]
        let leadShoulder = CGPoint(x: 0.46, y: 0.37)
        let trailShoulder = CGPoint(x: 0.56, y: 0.34)
        let armLength = 0.32
        return angles.enumerated().map { index, degrees in
            let radians = degrees * .pi / 180
            let wrist = CGPoint(
                x: leadShoulder.x + armLength * sin(radians),
                y: leadShoulder.y + armLength * cos(radians)
            )
            var elbow = CGPoint(x: (leadShoulder.x + wrist.x) / 2, y: (leadShoulder.y + wrist.y) / 2)
            if bentLeadArmNearParallel, (60...120).contains(abs(degrees)) {
                // Push the elbow off the shoulder–wrist line: ~127° elbow.
                elbow.x += 0.08 * cos(radians)
                elbow.y -= 0.08 * sin(radians)
            }
            let trailWrist = CGPoint(x: wrist.x + 0.02, y: wrist.y)
            return SwingPoseSample(
                time: Double(index) / 30,
                leftWrist: wrist,
                rightWrist: trailWrist,
                leftElbow: elbow,
                rightElbow: CGPoint(x: (trailShoulder.x + trailWrist.x) / 2 + 0.05, y: (trailShoulder.y + trailWrist.y) / 2 + 0.05),
                leftShoulder: leadShoulder,
                rightShoulder: trailShoulder,
                leftHip: CGPoint(x: 0.47, y: 0.60),
                rightHip: CGPoint(x: 0.57, y: 0.60),
                head: CGPoint(x: 0.51, y: 0.20),
                spineAngle: 18,
                aggregateConfidence: 0.92,
                sourceFrameIndex: index
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

    private static func sample(
        frame: Int,
        time: Double,
        hand: CGPoint,
        leftShoulderY: CGFloat = 0.34,
        rightShoulderY: CGFloat = 0.34
    ) -> SwingPoseSample {
        SwingPoseSample(
            time: time,
            leftWrist: CGPoint(x: hand.x - 0.01, y: hand.y),
            rightWrist: CGPoint(x: hand.x + 0.01, y: hand.y),
            leftElbow: CGPoint(x: 0.42, y: min(0.95, hand.y + 0.08)),
            rightElbow: CGPoint(x: 0.58, y: min(0.95, hand.y + 0.08)),
            leftShoulder: CGPoint(x: 0.40, y: leftShoulderY),
            rightShoulder: CGPoint(x: 0.60, y: rightShoulderY),
            leftHip: CGPoint(x: 0.43, y: 0.58),
            rightHip: CGPoint(x: 0.57, y: 0.58),
            head: CGPoint(x: 0.50, y: 0.16),
            spineAngle: 18,
            aggregateConfidence: 0.92,
            sourceFrameIndex: frame
        )
    }

    private static func status(_ stage: SwingStage, in result: SwingAnalysisResult) -> SwingStageDetectionStatus? {
        result.detections.first { $0.stage == stage }?.status
    }

    private static func frame(_ stage: SwingStage, in result: SwingAnalysisResult) -> Int? {
        result.detections.first { $0.stage == stage }?.sourceFrameIndex
    }
}

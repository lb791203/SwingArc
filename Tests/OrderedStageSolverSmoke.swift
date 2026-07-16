import Foundation

@main
struct OrderedStageSolverSmoke {
    static func main() {
        let evidence = fixture(includeImpactObjects: true)
        let result = OrderedStageSolver.solve(evidence: evidence)

        precondition(result.detections.map(\.stage) == SwingStage.allCases)
        let resolved = result.detections.compactMap(\.time)
        precondition(zip(resolved, resolved.dropFirst()).allSatisfy(<))
        precondition(detection(.leadArmParallelDownswing, in: result).time == 0.50)
        precondition(detection(.impact, in: result).time == 0.60)
        precondition(detection(.impact, in: result).sourceFrameIndex == 36)
        precondition(detection(.impact, in: result).status == .confirmed)
        precondition(detection(.finish, in: result).time == 0.90)

        let missingObjects = OrderedStageSolver.solve(evidence: fixture(includeImpactObjects: false))
        precondition(detection(.impact, in: missingObjects).status != .confirmed)
        precondition(detection(.impact, in: missingObjects).time != nil)

        let frames = evidence.map {
            SwingFrameSample(
                sourceFrameIndex: $0.sourceFrameIndex,
                time: $0.time,
                pose: $0.pose,
                objectEvidence: $0.objectEvidence
            )
        }
        precondition(SwingStageDetector.detect(frames: frames).detections.count == 8)
    }

    private static func fixture(includeImpactObjects: Bool) -> [SwingFrameEvidence] {
        let ball = CGPoint(x: 0.50, y: 0.84)
        let neutralObject = SwingObjectEvidence(
            shaft: ClubShaftEvidence(
                start: CGPoint(x: 0.49, y: 0.72),
                end: CGPoint(x: 0.55, y: 0.84),
                confidence: 0.75
            ),
            ball: BallEvidence(center: ball, radius: 0.012, confidence: 0.9),
            stableBall: ball,
            ballLocalChange: 0
        )
        let horizontalShaft = SwingObjectEvidence(
            shaft: ClubShaftEvidence(
                start: CGPoint(x: 0.42, y: 0.66),
                end: CGPoint(x: 0.68, y: 0.66),
                confidence: 0.9
            ),
            ball: BallEvidence(center: ball, radius: 0.012, confidence: 0.9),
            stableBall: ball,
            ballLocalChange: 0
        )
        let impactObject = includeImpactObjects
            ? SwingObjectEvidence(
                shaft: ClubShaftEvidence(
                    start: CGPoint(x: 0.54, y: 0.61),
                    end: ball,
                    confidence: 0.98
                ),
                ball: nil,
                stableBall: ball,
                ballLocalChange: 1
            )
            : .empty

        return [
            make(0.00, hand: CGPoint(x: 0.50, y: 0.76), armAngle: 68, velocityY: 0.00, headSpeed: 0.01, hipSpeed: 0.01, object: neutralObject),
            make(0.10, hand: CGPoint(x: 0.44, y: 0.65), armAngle: 35, velocityY: -1.10, headSpeed: 0.02, hipSpeed: 0.02, object: horizontalShaft),
            make(0.20, hand: CGPoint(x: 0.25, y: 0.40), armAngle: 1, velocityY: -1.40, headSpeed: 0.02, hipSpeed: 0.02, shoulderAngle: 16, object: neutralObject),
            // A tempting impact-like local maximum before P4. Ordered solving must reject it.
            make(0.25, hand: CGPoint(x: 0.51, y: 0.61), armAngle: 25, velocityY: 2.20, headSpeed: 0.03, hipSpeed: 0.03, hipAngle: 18, object: impactObject),
            make(0.30, hand: CGPoint(x: 0.30, y: 0.20), armAngle: 58, velocityY: -0.80, headSpeed: 0.02, hipSpeed: 0.02, shoulderAngle: 30, object: neutralObject),
            make(0.40, hand: CGPoint(x: 0.33, y: 0.27), armAngle: 48, velocityY: 0.70, headSpeed: 0.02, hipSpeed: 0.03, shoulderAngle: 28, hipAngle: 8, object: neutralObject),
            make(0.50, hand: CGPoint(x: 0.28, y: 0.42), armAngle: 2, velocityY: 1.50, headSpeed: 0.02, hipSpeed: 0.04, shoulderAngle: 20, hipAngle: 20, object: neutralObject),
            make(0.60, hand: CGPoint(x: 0.54, y: 0.61), armAngle: 28, velocityY: 2.20, headSpeed: 0.03, hipSpeed: 0.04, shoulderAngle: 10, hipAngle: 32, object: impactObject),
            make(0.70, hand: CGPoint(x: 0.72, y: 0.42), armAngle: 3, velocityY: -1.50, headSpeed: 0.02, hipSpeed: 0.03, shoulderAngle: -12, hipAngle: 38, object: horizontalShaft),
            make(0.80, hand: CGPoint(x: 0.68, y: 0.28), armAngle: 45, velocityY: -0.80, headSpeed: 0.02, hipSpeed: 0.02, shoulderAngle: -20, hipAngle: 42, object: neutralObject),
            make(0.90, hand: CGPoint(x: 0.66, y: 0.22), armAngle: 60, velocityY: 0.01, headSpeed: 0.01, hipSpeed: 0.01, shoulderAngle: -24, hipAngle: 44, object: neutralObject),
            make(1.00, hand: CGPoint(x: 0.66, y: 0.22), armAngle: 60, velocityY: 0.00, headSpeed: 0.01, hipSpeed: 0.01, shoulderAngle: -24, hipAngle: 44, object: neutralObject),
            // One slightly noisy Vision frame must not invalidate the plateau.
            make(1.10, hand: CGPoint(x: 0.66, y: 0.22), armAngle: 60, velocityY: 0.00, headSpeed: 0.09, hipSpeed: 0.01, shoulderAngle: -24, hipAngle: 44, object: neutralObject),
            make(1.20, hand: CGPoint(x: 0.66, y: 0.22), armAngle: 60, velocityY: 0.00, headSpeed: 0.01, hipSpeed: 0.01, shoulderAngle: -24, hipAngle: 44, object: neutralObject),
            // A later, higher-scoring stable pose must not replace the first finish plateau.
            make(1.30, hand: CGPoint(x: 0.66, y: 0.22), armAngle: 60, velocityY: 0.00, headSpeed: 0.01, hipSpeed: 0.01, shoulderAngle: 80, hipAngle: 80, object: neutralObject),
            make(1.40, hand: CGPoint(x: 0.66, y: 0.22), armAngle: 60, velocityY: 0.00, headSpeed: 0.01, hipSpeed: 0.01, shoulderAngle: 80, hipAngle: 80, object: neutralObject),
            make(1.50, hand: CGPoint(x: 0.66, y: 0.22), armAngle: 60, velocityY: 0.00, headSpeed: 0.01, hipSpeed: 0.01, shoulderAngle: 80, hipAngle: 80, object: neutralObject),
            make(1.60, hand: CGPoint(x: 0.66, y: 0.22), armAngle: 60, velocityY: 0.00, headSpeed: 0.01, hipSpeed: 0.01, shoulderAngle: 80, hipAngle: 80, object: neutralObject),
            // Later walking must not replace the first stable finish window.
            make(1.70, hand: CGPoint(x: 0.50, y: 0.55), armAngle: 25, velocityY: 2.00, headSpeed: 0.40, hipSpeed: 0.35, object: .empty)
        ]
    }

    private static func make(
        _ time: Double,
        hand: CGPoint,
        armAngle: Double,
        velocityY: CGFloat,
        headSpeed: Double,
        hipSpeed: Double,
        shoulderAngle: Double = 0,
        hipAngle: Double = 0,
        object: SwingObjectEvidence
    ) -> SwingFrameEvidence {
        let frameIndex = Int((time * 60).rounded())
        let pose = completePose(time: time, frameIndex: frameIndex, hand: hand)
        return SwingFrameEvidence(
            sourceFrameIndex: frameIndex,
            time: time,
            pose: pose,
            objectEvidence: object,
            leadArm: .left,
            leadArmAngle: armAngle,
            leadArmExtension: 176,
            shoulderAngle: shoulderAngle,
            hipAngle: hipAngle,
            handCenter: hand,
            hipCenter: CGPoint(x: 0.50, y: 0.62),
            handVelocity: CGPoint(x: 0, y: velocityY),
            handAcceleration: .zero,
            headSpeed: headSpeed,
            hipSpeed: hipSpeed,
            poseCoverage: 0.95
        )
    }

    private static func completePose(
        time: Double,
        frameIndex: Int,
        hand: CGPoint
    ) -> SwingPoseSample {
        SwingPoseSample(
            time: time,
            leftWrist: hand,
            rightWrist: CGPoint(x: hand.x + 0.03, y: hand.y),
            leftElbow: CGPoint(x: (0.45 + hand.x) / 2, y: (0.36 + hand.y) / 2),
            rightElbow: CGPoint(x: (0.58 + hand.x) / 2, y: (0.36 + hand.y) / 2),
            leftShoulder: CGPoint(x: 0.45, y: 0.36),
            rightShoulder: CGPoint(x: 0.58, y: 0.36),
            leftHip: CGPoint(x: 0.45, y: 0.62),
            rightHip: CGPoint(x: 0.58, y: 0.62),
            head: CGPoint(x: 0.515, y: 0.16),
            spineAngle: 0,
            aggregateConfidence: 0.95,
            sourceFrameIndex: frameIndex,
            leftKnee: CGPoint(x: 0.46, y: 0.78),
            rightKnee: CGPoint(x: 0.57, y: 0.78),
            leftAnkle: CGPoint(x: 0.46, y: 0.94),
            rightAnkle: CGPoint(x: 0.57, y: 0.94)
        )
    }

    private static func detection(_ stage: SwingStage, in result: SwingAnalysisResult) -> SwingStageDetection {
        result.detections.first { $0.stage == stage }!
    }
}

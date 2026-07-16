import Foundation

@main
struct ImpactCorridorResolverSmoke {
    static func main() {
        let stableBall = CGPoint(x: 0.70, y: 0.82)
        let alignedShaft = ClubShaftEvidence(
            start: CGPoint(x: 0.50, y: 0.60),
            end: CGPoint(x: 0.60, y: 0.71),
            confidence: 0.95
        )
        let timeline = [
            temporalFrame(sourceFrameIndex: 477, sustainedDownswing: false),
            temporalFrame(sourceFrameIndex: 478),
            temporalFrame(
                sourceFrameIndex: 480,
                shaft: alignedShaft,
                stableBall: stableBall,
                shaftAngleContinuity: 0.90
            ),
            temporalFrame(
                sourceFrameIndex: 481,
                stableBall: stableBall,
                ballLocalChange: 1,
                shaftAngleContinuity: 0.90
            ),
            temporalFrame(
                sourceFrameIndex: 482,
                shaft: alignedShaft,
                stableBall: stableBall,
                ballLocalChange: 1,
                sustainedDownswing: false,
                sustainedFollowThrough: true,
                direction: .stable
            ),
            temporalFrame(
                sourceFrameIndex: 483,
                shaft: alignedShaft,
                stableBall: stableBall,
                ballLocalChange: 1
            )
        ]

        let candidates = ImpactCorridorResolver.candidates(in: timeline)
        precondition(candidates.map(\.sourceFrameIndex) == [478, 480, 481])
        precondition(candidates.first { $0.sourceFrameIndex == 481 }?.requirementsSatisfied == true)
        precondition(candidates.first { $0.sourceFrameIndex == 478 }?.maximumStatus == .lowConfidence)
        precondition(candidates.first { $0.sourceFrameIndex == 480 }?.hasClubEvidence == true)
        precondition(candidates.first { $0.sourceFrameIndex == 480 }?.hasBallEvidence == true)
        precondition(ImpactCorridor(candidates: candidates).candidates == candidates)

        let timelineWithoutObjects = timeline.map { temporal in
            temporalFrame(
                sourceFrameIndex: temporal.frame.sourceFrameIndex,
                sustainedDownswing: temporal.sustainedDownswing,
                sustainedFollowThrough: temporal.sustainedFollowThrough
            )
        }
        let withoutObjects = ImpactCorridorResolver.candidates(in: timelineWithoutObjects)
        precondition(!withoutObjects.isEmpty)
        precondition(withoutObjects.allSatisfy { $0.maximumStatus != .confirmed })

        let crowdedTimeline = (600...606).map { sourceFrameIndex in
            temporalFrame(
                sourceFrameIndex: sourceFrameIndex,
                stableBall: sourceFrameIndex >= 602 ? stableBall : nil,
                ballLocalChange: sourceFrameIndex >= 602 ? 0.60 : 0
            )
        }
        let bestFive = ImpactCorridorResolver.candidates(in: crowdedTimeline)
        precondition(bestFive.count == 5)
        precondition(bestFive.map(\.sourceFrameIndex) == [602, 603, 604, 605, 606])
    }

    private static func temporalFrame(
        sourceFrameIndex: Int,
        shaft: ClubShaftEvidence? = nil,
        stableBall: CGPoint? = nil,
        ballLocalChange: Double = 0,
        sustainedDownswing: Bool = true,
        sustainedFollowThrough: Bool = false,
        direction: SwingMotionDirection? = nil,
        shaftAngleContinuity: Double = 0
    ) -> SwingTemporalFrame {
        let time = Double(sourceFrameIndex) / 30
        let hand = CGPoint(x: 0.50, y: 0.61)
        let pose = completePose(time: time, sourceFrameIndex: sourceFrameIndex, hand: hand)
        let frame = SwingFrameEvidence(
            sourceFrameIndex: sourceFrameIndex,
            time: time,
            pose: pose,
            objectEvidence: SwingObjectEvidence(
                shaft: shaft,
                ball: stableBall.map {
                    BallEvidence(center: $0, radius: 0.012, confidence: 0.95)
                },
                stableBall: stableBall,
                ballLocalChange: ballLocalChange
            ),
            leadArm: .left,
            leadArmAngle: 30,
            leadArmExtension: 175,
            shoulderAngle: 12,
            hipAngle: 32,
            handCenter: hand,
            hipCenter: CGPoint(x: 0.50, y: 0.62),
            handVelocity: CGPoint(x: 0, y: 1.50),
            handAcceleration: CGPoint(x: 0, y: 4),
            headSpeed: 0.02,
            hipSpeed: 0.03,
            poseCoverage: 1
        )
        return SwingTemporalFrame(
            frame: frame,
            direction: direction
                ?? (sustainedDownswing ? .downswing : (sustainedFollowThrough ? .backswing : .stable)),
            sustainedBackswing: false,
            sustainedDownswing: sustainedDownswing,
            sustainedFollowThrough: sustainedFollowThrough,
            isAddressBoundary: false,
            isTopPlateauEnd: false,
            isFinishPlateauStart: false,
            shaftAngleContinuity: shaftAngleContinuity,
            ballStability: stableBall == nil ? 0 : 1,
            qualityFlags: []
        )
    }

    private static func completePose(
        time: Double,
        sourceFrameIndex: Int,
        hand: CGPoint
    ) -> SwingPoseSample {
        SwingPoseSample(
            time: time,
            leftWrist: hand,
            rightWrist: CGPoint(x: hand.x + 0.03, y: hand.y),
            leftElbow: CGPoint(x: 0.47, y: 0.49),
            rightElbow: CGPoint(x: 0.55, y: 0.49),
            leftShoulder: CGPoint(x: 0.44, y: 0.36),
            rightShoulder: CGPoint(x: 0.56, y: 0.36),
            leftHip: CGPoint(x: 0.45, y: 0.62),
            rightHip: CGPoint(x: 0.55, y: 0.62),
            head: CGPoint(x: 0.50, y: 0.16),
            spineAngle: 0,
            aggregateConfidence: 0.95,
            sourceFrameIndex: sourceFrameIndex,
            leftKnee: CGPoint(x: 0.46, y: 0.78),
            rightKnee: CGPoint(x: 0.54, y: 0.78),
            leftAnkle: CGPoint(x: 0.46, y: 0.94),
            rightAnkle: CGPoint(x: 0.54, y: 0.94)
        )
    }
}

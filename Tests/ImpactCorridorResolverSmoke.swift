import Foundation

@main
struct ImpactCorridorResolverSmoke {
    static func main() {
        verifyBuiltTimelineDoesNotCloseCorridorDuringBackswing()

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

        let horizontalImpact = [
            temporalFrame(sourceFrameIndex: 700),
            temporalFrame(
                sourceFrameIndex: 701,
                sustainedDownswing: false,
                sustainedFollowThrough: false,
                direction: .stable
            ),
            temporalFrame(
                sourceFrameIndex: 702,
                sustainedDownswing: false,
                sustainedFollowThrough: true,
                direction: .backswing
            )
        ]
        precondition(
            ImpactCorridorResolver.candidates(in: horizontalImpact)
                .contains { $0.sourceFrameIndex == 701 },
            "The impact corridor must remain open while hand motion rotates through horizontal"
        )

        let frontViewHorizontalImpact = [
            temporalFrame(sourceFrameIndex: 710),
            temporalFrame(
                sourceFrameIndex: 711,
                sustainedDownswing: false,
                sustainedFollowThrough: false,
                direction: .stable,
                hipAngle: 0,
                handVelocity: CGPoint(x: 1.0, y: 0),
                handAcceleration: CGPoint(x: 4.0, y: 0)
            ),
            temporalFrame(
                sourceFrameIndex: 712,
                sustainedDownswing: false,
                sustainedFollowThrough: true,
                direction: .backswing
            )
        ]
        let provisional = ImpactCorridorResolver.candidates(in: frontViewHorizontalImpact)
            .first { $0.sourceFrameIndex == 711 }
        precondition(
            provisional?.maximumStatus == .lowConfidence,
            "A front-view horizontal body candidate must survive for sparse object extraction"
        )

        let bodyOnlyCorridor = [
            temporalFrame(
                sourceFrameIndex: 720,
                hipAngle: 0,
                handVelocity: CGPoint(x: 0.35, y: 0.55),
                handAcceleration: CGPoint(x: 4.0, y: 0),
                handCenter: CGPoint(x: 0.50, y: 0.50)
            ),
            temporalFrame(
                sourceFrameIndex: 721,
                hipAngle: 0,
                handVelocity: CGPoint(x: 0.90, y: 0),
                handAcceleration: CGPoint(x: 2.5, y: 0),
                handCenter: CGPoint(x: 0.50, y: 0.615)
            ),
            temporalFrame(
                sourceFrameIndex: 722,
                sustainedDownswing: false,
                sustainedFollowThrough: true,
                direction: .backswing
            )
        ]
        let bodyOnlyCandidates = ImpactCorridorResolver.candidates(in: bodyOnlyCorridor)
        precondition(
            bodyOnlyCandidates.max(by: { $0.score < $1.score })?.sourceFrameIndex == 721,
            "Without object evidence, hand-to-hip proximity must outrank an earlier acceleration spike"
        )
    }

    private static func verifyBuiltTimelineDoesNotCloseCorridorDuringBackswing() {
        let impactOrdinals = Set([34, 35, 36])
        let lateDownswingOrdinals = Set([69, 70, 71])
        let evidence = (0...78).map { ordinal -> SwingFrameEvidence in
            let time = Double(ordinal) / 30
            let velocityY: CGFloat
            switch ordinal {
            case 0...8, 24...29, 58...68, 76...78:
                velocityY = 0
            case 9...23, 45...57:
                velocityY = -0.50
            default:
                velocityY = 1.50
            }

            let isCorridorFrame = impactOrdinals.contains(ordinal)
                || lateDownswingOrdinals.contains(ordinal)
            let hand = isCorridorFrame
                ? CGPoint(x: 0.50, y: 0.61)
                : CGPoint(x: 0.20, y: 0.20)
            let stableBall = isCorridorFrame ? CGPoint(x: 0.70, y: 0.82) : nil
            let alignedShaft = isCorridorFrame
                ? ClubShaftEvidence(
                    start: CGPoint(x: 0.50, y: 0.60),
                    end: CGPoint(x: 0.60, y: 0.71),
                    confidence: 0.95
                )
                : nil
            let pose = completePose(
                time: time,
                sourceFrameIndex: 1_000 + ordinal,
                hand: hand
            )
            return SwingFrameEvidence(
                sourceFrameIndex: 1_000 + ordinal,
                time: time,
                pose: pose,
                rawPose: pose,
                objectEvidence: SwingObjectEvidence(
                    shaft: alignedShaft,
                    ball: stableBall.map {
                        BallEvidence(center: $0, radius: 0.012, confidence: 0.95)
                    },
                    stableBall: stableBall,
                    ballLocalChange: isCorridorFrame ? 0.80 : 0
                ),
                leadArm: .left,
                leadArmAngle: 30,
                leadArmExtension: 175,
                shoulderAngle: 12,
                hipAngle: isCorridorFrame ? 32 : 0,
                handCenter: hand,
                hipCenter: CGPoint(x: 0.50, y: 0.62),
                handVelocity: CGPoint(x: 0, y: velocityY),
                handAcceleration: isCorridorFrame ? CGPoint(x: 0, y: 4) : .zero,
                headSpeed: velocityY == 0 ? 0.01 : 0.03,
                hipSpeed: velocityY == 0 ? 0.01 : 0.03,
                poseCoverage: 1
            )
        }

        let timeline = SwingEvidenceTimeline.build(from: evidence)
        guard let downswingStart = timeline.firstIndex(where: \.sustainedDownswing) else {
            preconditionFailure("fixture must contain sustained downswing")
        }
        precondition(timeline[..<downswingStart].contains {
            $0.sustainedBackswing && $0.sustainedFollowThrough
        })
        precondition(timeline.contains {
            $0.frame.sourceFrameIndex >= 1_045 && $0.sustainedFollowThrough
        })
        precondition(timeline.contains(where: \.isAddressBoundary))
        precondition(timeline.contains(where: \.isTopPlateauEnd))
        precondition(timeline.contains(where: \.isFinishPlateauStart))

        let candidates = ImpactCorridorResolver.candidates(in: timeline)
        let candidateFrames = Set(candidates.map(\.sourceFrameIndex))
        precondition(
            candidateFrames.isSuperset(of: [1_034, 1_035, 1_036]),
            "pre-top backswing closed the corridor before P6: \(candidates)"
        )
        precondition(
            candidateFrames.isDisjoint(with: [1_069, 1_070, 1_071]),
            "actual follow-through did not close the corridor: \(candidates)"
        )
    }

    private static func temporalFrame(
        sourceFrameIndex: Int,
        shaft: ClubShaftEvidence? = nil,
        stableBall: CGPoint? = nil,
        ballLocalChange: Double = 0,
        sustainedDownswing: Bool = true,
        sustainedFollowThrough: Bool = false,
        direction: SwingMotionDirection? = nil,
        shaftAngleContinuity: Double = 0,
        hipAngle: Double = 32,
        handVelocity: CGPoint = CGPoint(x: 0, y: 1.50),
        handAcceleration: CGPoint = CGPoint(x: 0, y: 4),
        handCenter: CGPoint = CGPoint(x: 0.50, y: 0.61)
    ) -> SwingTemporalFrame {
        let time = Double(sourceFrameIndex) / 30
        let hand = handCenter
        let pose = completePose(time: time, sourceFrameIndex: sourceFrameIndex, hand: hand)
        let frame = SwingFrameEvidence(
            sourceFrameIndex: sourceFrameIndex,
            time: time,
            pose: pose,
            rawPose: pose,
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
            hipAngle: hipAngle,
            handCenter: hand,
            hipCenter: CGPoint(x: 0.50, y: 0.62),
            handVelocity: handVelocity,
            handAcceleration: handAcceleration,
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

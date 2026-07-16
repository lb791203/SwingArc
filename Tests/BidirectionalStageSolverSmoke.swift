import Foundation

@main
struct BidirectionalStageSolverSmoke {
    static func main() {
        let evidence = fixture(includeImpactObjects: true)
        let timeline = SwingEvidenceTimeline.build(from: evidence)
        precondition(timeline.first(where: \.isAddressBoundary)?.frame.sourceFrameIndex == 120)
        precondition(timeline.first(where: \.isTopPlateauEnd)?.frame.sourceFrameIndex == 240)
        precondition(timeline.first(where: \.isFinishPlateauStart)?.frame.sourceFrameIndex == 360)

        let impactCandidates = ImpactCorridorResolver.candidates(in: timeline)
        precondition(impactCandidates.count > 1)
        let candidateSets = impactCandidates.map {
            BidirectionalStageCandidateResolver.candidates(timeline: timeline, impact: $0)
        }
        precondition(candidateSets.allSatisfy { $0.candidates(for: .impact).count == 1 })
        let centeredImpactSet = candidateSets.first { $0.impact.sourceFrameIndex == 300 }!
        for stage in [
            SwingStage.takeaway,
            .leadArmParallelBackswing,
            .leadArmParallelDownswing,
            .followThrough
        ] {
            let candidates = centeredImpactSet.candidates(for: stage)
            precondition(candidates.count > 1, "expected multiple \(stage) candidates")
            precondition(zip(candidates, candidates.dropFirst()).allSatisfy {
                $0.score >= $1.score
            })
        }

        let result = ConstrainedSwingPathSolver.solve(
            candidateSets: candidateSets,
            timeline: timeline
        )
        let expected: [SwingStage: Int] = [
            .address: 120,
            .takeaway: 168,
            .leadArmParallelBackswing: 204,
            .top: 240,
            .leadArmParallelDownswing: 276,
            .impact: 300,
            .followThrough: 324,
            .finish: 360
        ]
        for (stage, frame) in expected {
            precondition(detection(stage, in: result).sourceFrameIndex == frame)
        }
        let resolvedFrames = result.detections.compactMap(\.sourceFrameIndex)
        precondition(resolvedFrames.count == SwingStage.allCases.count)
        precondition(zip(resolvedFrames, resolvedFrames.dropFirst()).allSatisfy(<))
        precondition(
            detection(.leadArmParallelBackswing, in: result).sourceFrameIndex!
                < detection(.leadArmParallelDownswing, in: result).sourceFrameIndex!
        )
        precondition(detection(.top, in: result).sourceFrameIndex == 240)
        precondition(detection(.finish, in: result).sourceFrameIndex == 360)

        let objectlessEvidence = fixture(includeImpactObjects: false)
        let objectlessTimeline = SwingEvidenceTimeline.build(from: objectlessEvidence)
        let objectlessResult = ConstrainedSwingPathSolver.solve(
            candidateSets: ImpactCorridorResolver.candidates(in: objectlessTimeline).map {
                BidirectionalStageCandidateResolver.candidates(
                    timeline: objectlessTimeline,
                    impact: $0
                )
            },
            timeline: objectlessTimeline
        )
        let objectlessImpact = detection(.impact, in: objectlessResult)
        precondition(objectlessImpact.sourceFrameIndex == 300)
        precondition(objectlessImpact.status == .lowConfidence)
        precondition(!objectlessImpact.hasClubEvidence)
        precondition(!objectlessImpact.hasBallEvidence)

        let noAddressTimeline = timeline.map { temporal in
            SwingTemporalFrame(
                frame: temporal.frame,
                direction: temporal.direction,
                sustainedBackswing: temporal.sustainedBackswing,
                sustainedDownswing: temporal.sustainedDownswing,
                sustainedFollowThrough: temporal.sustainedFollowThrough,
                isAddressBoundary: false,
                isTopPlateauEnd: temporal.isTopPlateauEnd,
                isFinishPlateauStart: temporal.isFinishPlateauStart,
                shaftAngleContinuity: temporal.shaftAngleContinuity,
                ballStability: temporal.ballStability,
                qualityFlags: temporal.qualityFlags
            )
        }
        let noAddressResult = solve(timeline: noAddressTimeline)
        precondition(detection(.address, in: noAddressResult).status == .unresolved)
        precondition(detection(.address, in: noAddressResult).sourceFrameIndex == nil)

        let noTopTimeline = timeline.map { temporal in
            SwingTemporalFrame(
                frame: temporal.frame,
                direction: temporal.direction,
                sustainedBackswing: temporal.sustainedBackswing,
                sustainedDownswing: temporal.sustainedDownswing,
                sustainedFollowThrough: temporal.sustainedFollowThrough,
                isAddressBoundary: temporal.isAddressBoundary,
                isTopPlateauEnd: false,
                isFinishPlateauStart: temporal.isFinishPlateauStart,
                shaftAngleContinuity: temporal.shaftAngleContinuity,
                ballStability: temporal.ballStability,
                qualityFlags: temporal.qualityFlags
            )
        }
        precondition(detection(.top, in: solve(timeline: noTopTimeline)).status == .unresolved)
    }

    private static func solve(timeline: [SwingTemporalFrame]) -> SwingAnalysisResult {
        ConstrainedSwingPathSolver.solve(
            candidateSets: ImpactCorridorResolver.candidates(in: timeline).map {
                BidirectionalStageCandidateResolver.candidates(timeline: timeline, impact: $0)
            },
            timeline: timeline
        )
    }

    private static func fixture(includeImpactObjects: Bool) -> [SwingFrameEvidence] {
        (60...420).map { sourceFrameIndex in
            let time = Double(sourceFrameIndex) / 120
            let velocityY: CGFloat
            switch sourceFrameIndex {
            case ...120, 237...240, 360...399:
                velocityY = 0
            case 121...236:
                velocityY = sourceFrameIndex == 198 ? 0.80 : (sourceFrameIndex <= 180 ? -0.14 : -0.70)
            case 241...323, 400...:
                velocityY = sourceFrameIndex >= 400 ? 0.60 : 1.20
            default:
                velocityY = -0.90
            }

            let isNoisyFinishFrame = sourceFrameIndex == 372
            let hand = handPosition(sourceFrameIndex: sourceFrameIndex)
            let shoulderAngle = shoulderTurn(sourceFrameIndex: sourceFrameIndex)
            let hipAngle = hipTurn(sourceFrameIndex: sourceFrameIndex)
            let pose = completePose(
                time: time,
                sourceFrameIndex: sourceFrameIndex,
                hand: hand
            )
            let object = objectEvidence(
                sourceFrameIndex: sourceFrameIndex,
                includeImpactObjects: includeImpactObjects
            )
            return SwingFrameEvidence(
                sourceFrameIndex: sourceFrameIndex,
                time: time,
                pose: pose,
                objectEvidence: object,
                leadArm: .left,
                leadArmAngle: leadArmAngle(sourceFrameIndex: sourceFrameIndex),
                leadArmExtension: 176,
                shoulderAngle: shoulderAngle,
                hipAngle: hipAngle,
                handCenter: hand,
                hipCenter: CGPoint(x: 0.50, y: 0.62),
                handVelocity: isNoisyFinishFrame
                    ? CGPoint(x: 0, y: -0.65)
                    : CGPoint(x: 0, y: velocityY),
                handAcceleration: (298...302).contains(sourceFrameIndex)
                    ? CGPoint(x: 0, y: sourceFrameIndex == 300 ? 4.0 : 2.4)
                    : .zero,
                headSpeed: isNoisyFinishFrame ? 0.22 : (velocityY == 0 ? 0.01 : 0.03),
                hipSpeed: isNoisyFinishFrame ? 0.18 : (velocityY == 0 ? 0.01 : 0.03),
                poseCoverage: 1
            )
        }
    }

    private static func handPosition(sourceFrameIndex: Int) -> CGPoint {
        switch sourceFrameIndex {
        case ...120:
            return CGPoint(x: 0.50, y: 0.76)
        case 121...240:
            let progress = CGFloat(sourceFrameIndex - 120) / 120
            return CGPoint(x: 0.50 - progress * 0.23, y: 0.76 - progress * 0.55)
        case 241...300:
            let progress = CGFloat(sourceFrameIndex - 240) / 60
            return CGPoint(x: 0.27 + progress * 0.26, y: 0.21 + progress * 0.40)
        case 301...359:
            let progress = CGFloat(sourceFrameIndex - 300) / 59
            return CGPoint(x: 0.53 + progress * 0.15, y: 0.61 - progress * 0.36)
        case 360...399:
            return CGPoint(x: 0.68, y: 0.25)
        default:
            return CGPoint(x: 0.48, y: 0.58)
        }
    }

    private static func leadArmAngle(sourceFrameIndex: Int) -> Double {
        let targets = [204, 276, 324]
        let nearestDistance = targets.map { abs(sourceFrameIndex - $0) }.min() ?? 100
        if nearestDistance == 0 { return 0 }
        if nearestDistance == 1 { return 6 }
        if sourceFrameIndex == 240 { return 58 }
        return 48
    }

    private static func shoulderTurn(sourceFrameIndex: Int) -> Double {
        if sourceFrameIndex <= 240 {
            return min(32, Double(max(0, sourceFrameIndex - 120)) / 120 * 32)
        }
        return max(-28, 32 - Double(sourceFrameIndex - 240) * 0.5)
    }

    private static func hipTurn(sourceFrameIndex: Int) -> Double {
        if (298...302).contains(sourceFrameIndex) { return 32 }
        if sourceFrameIndex >= 324 && sourceFrameIndex < 400 { return 42 }
        if (270...282).contains(sourceFrameIndex) { return 24 }
        return sourceFrameIndex > 240 ? 10 : 2
    }

    private static func objectEvidence(
        sourceFrameIndex: Int,
        includeImpactObjects: Bool
    ) -> SwingObjectEvidence {
        let stableBall = CGPoint(x: 0.70, y: 0.82)
        if (167...169).contains(sourceFrameIndex) {
            return SwingObjectEvidence(
                shaft: ClubShaftEvidence(
                    start: CGPoint(x: 0.42, y: 0.66),
                    end: CGPoint(x: 0.68, y: 0.66),
                    confidence: sourceFrameIndex == 168 ? 0.98 : 0.80
                ),
                ball: BallEvidence(center: stableBall, radius: 0.012, confidence: 0.95),
                stableBall: stableBall,
                ballLocalChange: 0
            )
        }
        if includeImpactObjects, (299...301).contains(sourceFrameIndex) {
            return SwingObjectEvidence(
                shaft: ClubShaftEvidence(
                    start: CGPoint(x: 0.53, y: 0.61),
                    end: stableBall,
                    confidence: sourceFrameIndex == 300 ? 0.99 : 0.80
                ),
                ball: nil,
                stableBall: stableBall,
                ballLocalChange: sourceFrameIndex == 300 ? 1 : 0.70
            )
        }
        return .empty
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
            leftElbow: CGPoint(x: (0.45 + hand.x) / 2, y: (0.36 + hand.y) / 2),
            rightElbow: CGPoint(x: (0.58 + hand.x) / 2, y: (0.36 + hand.y) / 2),
            leftShoulder: CGPoint(x: 0.45, y: 0.36),
            rightShoulder: CGPoint(x: 0.58, y: 0.36),
            leftHip: CGPoint(x: 0.45, y: 0.62),
            rightHip: CGPoint(x: 0.58, y: 0.62),
            head: CGPoint(x: 0.515, y: 0.16),
            spineAngle: 0,
            aggregateConfidence: 0.98,
            sourceFrameIndex: sourceFrameIndex,
            leftKnee: CGPoint(x: 0.46, y: 0.78),
            rightKnee: CGPoint(x: 0.57, y: 0.78),
            leftAnkle: CGPoint(x: 0.46, y: 0.94),
            rightAnkle: CGPoint(x: 0.57, y: 0.94)
        )
    }

    private static func detection(
        _ stage: SwingStage,
        in result: SwingAnalysisResult
    ) -> SwingStageDetection {
        result.detections.first { $0.stage == stage }!
    }
}

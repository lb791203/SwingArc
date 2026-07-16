import Foundation

@main
struct BidirectionalStageSolverSmoke {
    static func main() {
        if let scenario = CommandLine.arguments.dropFirst().first {
            switch scenario {
            case "missing-p2":
                verifyMissingTakeawayShaftKeepsPath()
            case "transition-quality":
                verifyObservedTransitionQualityRanksPaths()
            case "counter-rotating-p7":
                verifyCounterRotatingFollowThroughCannotConfirm()
            case "chest-continuation":
                verifyChestContinuationIsRequired()
            case "impact-anchor":
                verifyDeclaredImpactAnchorCannotDiverge()
            default:
                preconditionFailure("unknown scenario: \(scenario)")
            }
            return
        }

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

        verifyMissingTakeawayShaftKeepsPath()
        verifyObservedTransitionQualityRanksPaths()
        verifyCounterRotatingFollowThroughCannotConfirm()
        verifyChestContinuationIsRequired()
        verifyDeclaredImpactAnchorCannotDiverge()
    }

    private static func verifyMissingTakeawayShaftKeepsPath() {
        let evidence = fixture(
            includeImpactObjects: true,
            includeTakeawayShaft: false
        )
        let timeline = SwingEvidenceTimeline.build(from: evidence)
        let candidateSets = ImpactCorridorResolver.candidates(in: timeline).map {
            BidirectionalStageCandidateResolver.candidates(timeline: timeline, impact: $0)
        }
        let centered = candidateSets.first { $0.impact.sourceFrameIndex == 300 }!
        let bodyOnlyP2 = centered.candidates(for: .takeaway)
        precondition(!bodyOnlyP2.isEmpty)
        precondition(bodyOnlyP2.allSatisfy {
            !$0.requirementsSatisfied && $0.maximumStatus == .lowConfidence
        })

        let result = ConstrainedSwingPathSolver.solve(
            candidateSets: candidateSets,
            timeline: timeline
        )
        precondition(result.detections.allSatisfy { $0.sourceFrameIndex != nil })
        let takeaway = detection(.takeaway, in: result)
        precondition(takeaway.status == .lowConfidence)
        precondition(!takeaway.hasClubEvidence)
        precondition(result.detections.filter { $0.stage != .takeaway }.allSatisfy {
            $0.status != .unresolved
        })
    }

    private static func verifyObservedTransitionQualityRanksPaths() {
        let fixture = transitionQualityFixture()
        let result = ConstrainedSwingPathSolver.solve(
            candidateSets: [fixture.marginal, fixture.strong],
            timeline: fixture.timeline
        )
        precondition(
            detection(.impact, in: result).sourceFrameIndex == 1_010,
            "equal-evidence paths must be ranked by observed transition support"
        )
    }

    private static func verifyCounterRotatingFollowThroughCannotConfirm() {
        let timeline = SwingEvidenceTimeline.build(from: fixture(
            includeImpactObjects: true,
            counterRotateAtFollowThrough: true
        ))
        let centered = candidateSet(impactFrame: 300, timeline: timeline)
        let p7 = centered.candidates(for: .followThrough).filter {
            (323...325).contains($0.sourceFrameIndex)
        }
        precondition(!p7.isEmpty)
        precondition(p7.allSatisfy {
            !$0.requirementsSatisfied && $0.maximumStatus == .lowConfidence
        })
        let result = ConstrainedSwingPathSolver.solve(
            candidateSets: [centered],
            timeline: timeline
        )
        let followThrough = detection(.followThrough, in: result)
        precondition(followThrough.sourceFrameIndex != nil)
        precondition(followThrough.status == .lowConfidence)
    }

    private static func verifyChestContinuationIsRequired() {
        let timeline = SwingEvidenceTimeline.build(from: fixture(
            includeImpactObjects: true,
            reverseChestAtFollowThrough: true
        ))
        let centered = candidateSet(impactFrame: 300, timeline: timeline)
        let p7 = centered.candidates(for: .followThrough).filter {
            (323...325).contains($0.sourceFrameIndex)
        }
        precondition(!p7.isEmpty)
        precondition(p7.allSatisfy { !$0.requirementsSatisfied })
    }

    private static func verifyDeclaredImpactAnchorCannotDiverge() {
        let timeline = SwingEvidenceTimeline.build(from: fixture(includeImpactObjects: true))
        let impactCandidates = ImpactCorridorResolver.candidates(in: timeline)
        let centeredImpactSet = candidateSet(impactFrame: 300, timeline: timeline)
        let otherImpact = impactCandidates.first {
            $0.sourceFrameIndex != centeredImpactSet.impact.sourceFrameIndex
        }!
        var candidates = centeredImpactSet.candidatesByStage
        candidates[.impact] = [otherImpact]
        let divergent = StageCandidateSet(
            impact: centeredImpactSet.impact,
            candidatesByStage: candidates
        )
        let result = ConstrainedSwingPathSolver.solve(
            candidateSets: [divergent],
            timeline: timeline
        )
        precondition(result.unresolvedStages == Set(SwingStage.allCases))
    }

    private static func solve(timeline: [SwingTemporalFrame]) -> SwingAnalysisResult {
        ConstrainedSwingPathSolver.solve(
            candidateSets: ImpactCorridorResolver.candidates(in: timeline).map {
                BidirectionalStageCandidateResolver.candidates(timeline: timeline, impact: $0)
            },
            timeline: timeline
        )
    }

    private static func candidateSet(
        impactFrame: Int,
        timeline: [SwingTemporalFrame]
    ) -> StageCandidateSet {
        let impact = ImpactCorridorResolver.candidates(in: timeline).first {
            $0.sourceFrameIndex == impactFrame
        }!
        return BidirectionalStageCandidateResolver.candidates(
            timeline: timeline,
            impact: impact
        )
    }

    private static func fixture(
        includeImpactObjects: Bool,
        includeTakeawayShaft: Bool = true,
        counterRotateAtFollowThrough: Bool = false,
        reverseChestAtFollowThrough: Bool = false
    ) -> [SwingFrameEvidence] {
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
            let isP7Neighborhood = (323...325).contains(sourceFrameIndex)
            let shoulderAngle = reverseChestAtFollowThrough && isP7Neighborhood
                ? 18
                : shoulderTurn(sourceFrameIndex: sourceFrameIndex)
            let hipAngle = counterRotateAtFollowThrough && isP7Neighborhood
                ? -42
                : hipTurn(sourceFrameIndex: sourceFrameIndex)
            let pose = completePose(
                time: time,
                sourceFrameIndex: sourceFrameIndex,
                hand: hand
            )
            let object = objectEvidence(
                sourceFrameIndex: sourceFrameIndex,
                includeImpactObjects: includeImpactObjects,
                includeTakeawayShaft: includeTakeawayShaft
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
        includeImpactObjects: Bool,
        includeTakeawayShaft: Bool
    ) -> SwingObjectEvidence {
        let stableBall = CGPoint(x: 0.70, y: 0.82)
        if includeTakeawayShaft, (167...169).contains(sourceFrameIndex) {
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

    private static func transitionQualityFixture() -> (
        timeline: [SwingTemporalFrame],
        marginal: StageCandidateSet,
        strong: StageCandidateSet
    ) {
        var timeline: [SwingTemporalFrame] = []
        let marginal = appendTransitionSegment(
            to: &timeline,
            startTime: 0,
            startSourceFrame: 100,
            hasStrongSupport: false
        )
        let strong = appendTransitionSegment(
            to: &timeline,
            startTime: 2,
            startSourceFrame: 1_000,
            hasStrongSupport: true
        )
        return (timeline, marginal, strong)
    }

    private static func appendTransitionSegment(
        to timeline: inout [SwingTemporalFrame],
        startTime: Double,
        startSourceFrame: Int,
        hasStrongSupport: Bool
    ) -> StageCandidateSet {
        let startIndex = timeline.count
        let localStageIndices: [SwingStage: Int] = [
            .address: 0,
            .takeaway: 2,
            .leadArmParallelBackswing: 4,
            .top: 6,
            .leadArmParallelDownswing: 8,
            .impact: 10,
            .followThrough: 12,
            .finish: 16
        ]
        let candidateIndices = Set(localStageIndices.values)

        for localIndex in 0...20 {
            let isBackswing = (1...4).contains(localIndex)
            let isDownswing = (6...10).contains(localIndex)
            let isFollowThrough = (11...15).contains(localIndex)
            let isStableTop = (5...6).contains(localIndex)
            let isStableFinish = (16...20).contains(localIndex)
            let retainEvidence = hasStrongSupport || candidateIndices.contains(localIndex)
            let direction: SwingMotionDirection
            if isBackswing && retainEvidence {
                direction = .backswing
            } else if isDownswing && retainEvidence && localIndex != 6 {
                direction = .downswing
            } else if isFollowThrough && retainEvidence {
                direction = .backswing
            } else {
                direction = .stable
            }
            let stable = hasStrongSupport && (isStableTop || isStableFinish)
                || candidateIndices.contains(localIndex) && (localIndex == 0 || localIndex == 6 || localIndex == 16)
            let velocityY: CGFloat
            switch direction {
            case .backswing: velocityY = -0.60
            case .downswing: velocityY = 0.75
            case .stable: velocityY = stable ? 0 : 0.45
            }
            let sourceFrameIndex = startSourceFrame + localIndex
            let time = startTime + Double(localIndex) * 0.05
            let hand = CGPoint(x: 0.50, y: 0.50)
            let frame = SwingFrameEvidence(
                sourceFrameIndex: sourceFrameIndex,
                time: time,
                pose: completePose(
                    time: time,
                    sourceFrameIndex: sourceFrameIndex,
                    hand: hand
                ),
                objectEvidence: .empty,
                leadArm: .left,
                leadArmAngle: 0,
                leadArmExtension: 176,
                shoulderAngle: 20,
                hipAngle: 24,
                handCenter: hand,
                hipCenter: CGPoint(x: 0.50, y: 0.62),
                handVelocity: CGPoint(x: 0, y: velocityY),
                handAcceleration: .zero,
                headSpeed: stable ? 0.01 : 0.16,
                hipSpeed: stable ? 0.01 : 0.16,
                poseCoverage: 1
            )
            timeline.append(SwingTemporalFrame(
                frame: frame,
                direction: direction,
                sustainedBackswing: isBackswing && retainEvidence,
                sustainedDownswing: isDownswing && retainEvidence,
                sustainedFollowThrough: isFollowThrough && retainEvidence,
                isAddressBoundary: localIndex == 0,
                isTopPlateauEnd: localIndex == 6,
                isFinishPlateauStart: localIndex == 16,
                shaftAngleContinuity: 0,
                ballStability: 0,
                qualityFlags: []
            ))
        }

        let candidates = Dictionary(uniqueKeysWithValues: localStageIndices.map { stage, localIndex in
            let index = startIndex + localIndex
            let frame = timeline[index].frame
            return (stage, [StageCandidate(
                stage: stage,
                evidenceIndex: index,
                sourceFrameIndex: frame.sourceFrameIndex,
                time: frame.time,
                score: 0.80,
                requirementsSatisfied: true,
                maximumStatus: .confirmed,
                hasClubEvidence: false,
                hasBallEvidence: false
            )])
        })
        let impact = candidates[.impact]!.first!
        return StageCandidateSet(impact: impact, candidatesByStage: candidates)
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

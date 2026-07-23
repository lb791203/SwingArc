import Foundation

@main
struct BidirectionalStageSolverSmoke {
    private enum FollowThroughExtensionProfile {
        case extended
        case bentExact
        case occluded
    }

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
            .shaftParallelDownswing,
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
            .shaftParallelDownswing: 288,
            .impact: 300
        ]
        for (stage, frame) in expected {
            precondition(
                detection(stage, in: result).sourceFrameIndex == frame,
                "\(stage) expected \(frame), got \(String(describing: detection(stage, in: result).sourceFrameIndex))"
            )
        }
        let resolvedFrames = result.detections.compactMap(\.sourceFrameIndex)
        precondition(resolvedFrames.count == SwingStage.allCases.count)
        precondition(zip(resolvedFrames, resolvedFrames.dropFirst()).allSatisfy(<))
        precondition(
            detection(.leadArmParallelBackswing, in: result).sourceFrameIndex!
                < detection(.leadArmParallelDownswing, in: result).sourceFrameIndex!
        )
        precondition(
            detection(.leadArmParallelDownswing, in: result).sourceFrameIndex!
                < detection(.shaftParallelDownswing, in: result).sourceFrameIndex!
        )
        precondition(
            detection(.shaftParallelDownswing, in: result).sourceFrameIndex!
                < detection(.impact, in: result).sourceFrameIndex!
        )
        precondition(
            detection(.impact, in: result).sourceFrameIndex!
                < detection(.followThrough, in: result).sourceFrameIndex!
        )
        precondition(detection(.top, in: result).sourceFrameIndex == 240)
        precondition(!result.detections.contains { $0.stage == .finish })

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
        verifyFeaturePipelineCapsUnreliableLeadArmEvidence()
        verifyOccludedFollowThroughRemainsLowConfidence()
        verifyDeclaredImpactAnchorCannotDiverge()
        verifyStageAwareTransitionEvidenceScalesAcrossTempo()
        verifyTakeawayPositionEvidenceIsBodyScaleInvariant()
        verifyTakeawayResolverIsTempoInvariant()
        verifyParallelStageScoresRequireJointAgreement()
        verifyDeliveryAndReleaseRequireReliableShaftEvidence()
        verifyObjectSamplingSeedsDeliveryShaftNeighborhood()
    }

    private static func verifyDeliveryAndReleaseRequireReliableShaftEvidence() {
        let reliableTimeline = SwingEvidenceTimeline.build(from: fixture(
            includeImpactObjects: true
        ))
        let reliableSet = candidateSet(impactFrame: 300, timeline: reliableTimeline)
        precondition(
            reliableSet.candidates(for: .shaftParallelDownswing).contains {
                $0.sourceFrameIndex == 288 && $0.requirementsSatisfied && $0.hasClubEvidence
            },
            "P6 needs observed, reliable shaft-horizontal evidence before impact"
        )
        precondition(
            reliableSet.candidates(for: .followThrough).contains {
                $0.sourceFrameIndex == 324 && $0.requirementsSatisfied && $0.hasClubEvidence
            },
            "P8 needs observed, reliable shaft-horizontal evidence after impact"
        )

        let missingDeliveryTimeline = SwingEvidenceTimeline.build(from: fixture(
            includeImpactObjects: true,
            includeDeliveryShaft: false
        ))
        let missingDeliverySet = candidateSet(
            impactFrame: 300,
            timeline: missingDeliveryTimeline
        )
        precondition(missingDeliverySet.candidates(for: .shaftParallelDownswing).isEmpty)
        let missingDelivery = ConstrainedSwingPathSolver.solve(
            candidateSets: [missingDeliverySet],
            timeline: missingDeliveryTimeline
        )
        precondition(
            detection(.shaftParallelDownswing, in: missingDelivery).status == .unresolved,
            "P6 cannot be fabricated from arm or impact evidence when the shaft is absent"
        )

        let missingReleaseTimeline = SwingEvidenceTimeline.build(from: fixture(
            includeImpactObjects: true,
            includeReleaseShaft: false
        ))
        let missingReleaseSet = candidateSet(
            impactFrame: 300,
            timeline: missingReleaseTimeline
        )
        precondition(missingReleaseSet.candidates(for: .followThrough).isEmpty)
        let missingRelease = ConstrainedSwingPathSolver.solve(
            candidateSets: [missingReleaseSet],
            timeline: missingReleaseTimeline
        )
        precondition(
            detection(.followThrough, in: missingRelease).status == .unresolved,
            "P8 cannot substitute lead-arm evidence for missing shaft evidence"
        )
    }

    private static func verifyObjectSamplingSeedsDeliveryShaftNeighborhood() {
        let timeline = SwingEvidenceTimeline.build(from: fixture(
            includeImpactObjects: true,
            includeDeliveryShaft: false
        ))
        let impact = ImpactCorridorResolver.candidates(in: timeline).first {
            $0.sourceFrameIndex == 300
        }!
        let strict = BidirectionalStageCandidateResolver.candidates(
            timeline: timeline,
            impact: impact
        )
        precondition(strict.candidates(for: .shaftParallelDownswing).isEmpty)

        let sampling = BidirectionalStageCandidateResolver.objectSamplingCandidates(
            timeline: timeline,
            impact: impact
        ).candidates(for: .shaftParallelDownswing)
        precondition(!sampling.isEmpty)
        precondition(sampling.allSatisfy {
            !$0.requirementsSatisfied
                && $0.maximumStatus == .lowConfidence
                && !$0.hasClubEvidence
        })
        precondition(sampling.allSatisfy { $0.sourceFrameIndex < impact.sourceFrameIndex })
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
        let p8 = centered.candidates(for: .followThrough)
        precondition(!p8.isEmpty)
        precondition(p8.allSatisfy {
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
        let p8 = centered.candidates(for: .followThrough)
        precondition(!p8.isEmpty)
        precondition(p8.allSatisfy { !$0.requirementsSatisfied })
    }

    private static func verifyFeaturePipelineCapsUnreliableLeadArmEvidence() {
        let sourceEvidence = fixture(includeImpactObjects: true)
        let sourceFrames = sourceEvidence.map {
            SwingFrameSample(
                sourceFrameIndex: $0.sourceFrameIndex,
                time: $0.time,
                pose: $0.pose,
                objectEvidence: $0.objectEvidence
            )
        }
        let resolvedEvidence = SwingFeatureExtractor.extract(frames: sourceFrames)
        guard let resolvedSide = resolvedEvidence.first?.leadArm,
              resolvedSide != .unknown else {
            preconditionFailure("Fixture must resolve one immutable lead arm")
        }
        let resolvedTimeline = SwingEvidenceTimeline.build(from: resolvedEvidence)
        let resolvedImpact = ImpactCorridorResolver.candidates(in: resolvedTimeline).min {
            abs($0.sourceFrameIndex - 300) < abs($1.sourceFrameIndex - 300)
        }!
        let resolvedCandidates = BidirectionalStageCandidateResolver.candidates(
            timeline: resolvedTimeline,
            impact: resolvedImpact
        )
        let p5Frame = resolvedCandidates.candidates(
            for: .leadArmParallelDownswing
        ).first!.sourceFrameIndex
        let p7Frame = resolvedCandidates.candidates(for: .followThrough).first!.sourceFrameIndex

        let occludedFrames = sourceFrames.map { frame -> SwingFrameSample in
            guard frame.sourceFrameIndex == p5Frame, let pose = frame.pose else { return frame }
            return SwingFrameSample(
                sourceFrameIndex: frame.sourceFrameIndex,
                time: frame.time,
                pose: poseWithMissingElbow(pose, side: resolvedSide),
                objectEvidence: frame.objectEvidence
            )
        }
        let occludedTimeline = SwingEvidenceTimeline.build(
            from: SwingFeatureExtractor.extract(frames: occludedFrames)
        )
        let occludedIndex = occludedTimeline.firstIndex {
            $0.frame.sourceFrameIndex == p5Frame
        }!
        precondition(occludedTimeline[occludedIndex].frame.leadArmAngle != nil)
        precondition(occludedTimeline[occludedIndex].qualityFlags.contains(.missingLeadArm))
        let occludedImpact = ImpactCorridorResolver.candidates(in: occludedTimeline).min {
            abs($0.sourceFrameIndex - 300) < abs($1.sourceFrameIndex - 300)
        }!
        let occludedP5 = BidirectionalStageCandidateResolver.candidates(
            timeline: occludedTimeline,
            impact: occludedImpact
        ).candidates(for: .leadArmParallelDownswing).first {
            $0.sourceFrameIndex == p5Frame
        }!
        precondition(!occludedP5.requirementsSatisfied)
        precondition(occludedP5.maximumStatus == .lowConfidence)

        let swappedFrames = sourceFrames.map { frame -> SwingFrameSample in
            guard frame.sourceFrameIndex == p7Frame, let pose = frame.pose else { return frame }
            return SwingFrameSample(
                sourceFrameIndex: frame.sourceFrameIndex,
                time: frame.time,
                pose: poseWithSwappedLabels(pose),
                objectEvidence: frame.objectEvidence
            )
        }
        let swappedTimeline = SwingEvidenceTimeline.build(
            from: SwingFeatureExtractor.extract(frames: swappedFrames)
        )
        let swappedImpact = ImpactCorridorResolver.candidates(in: swappedTimeline).min {
            abs($0.sourceFrameIndex - 300) < abs($1.sourceFrameIndex - 300)
        }!
        let swappedP7 = BidirectionalStageCandidateResolver.candidates(
            timeline: swappedTimeline,
            impact: swappedImpact
        ).candidates(for: .followThrough).first {
            $0.sourceFrameIndex == p7Frame
        }!
        precondition(!swappedP7.requirementsSatisfied)
        precondition(swappedP7.maximumStatus == .lowConfidence)

        let ambiguousFrames = sourceFrames.map { frame -> SwingFrameSample in
            guard let pose = frame.pose else { return frame }
            return SwingFrameSample(
                sourceFrameIndex: frame.sourceFrameIndex,
                time: frame.time,
                pose: symmetricArmPose(pose),
                objectEvidence: .empty
            )
        }
        let ambiguousTimeline = SwingEvidenceTimeline.build(
            from: SwingFeatureExtractor.extract(frames: ambiguousFrames)
        )
        precondition(ambiguousTimeline.allSatisfy { $0.frame.leadArm == .unknown })
        let ambiguousResult = solve(timeline: ambiguousTimeline)
        for stage in [
            SwingStage.leadArmParallelBackswing,
            .leadArmParallelDownswing,
            .followThrough
        ] {
            precondition(detection(stage, in: ambiguousResult).status != .confirmed)
        }
    }

    private static func poseWithMissingElbow(
        _ pose: SwingPoseSample,
        side: LeadArmSide
    ) -> SwingPoseSample {
        SwingPoseSample(
            time: pose.time,
            leftWrist: pose.leftWrist,
            rightWrist: pose.rightWrist,
            leftElbow: side == .left ? nil : pose.leftElbow,
            rightElbow: side == .right ? nil : pose.rightElbow,
            leftShoulder: pose.leftShoulder,
            rightShoulder: pose.rightShoulder,
            leftHip: pose.leftHip,
            rightHip: pose.rightHip,
            head: pose.head,
            spineAngle: pose.spineAngle,
            aggregateConfidence: pose.aggregateConfidence,
            sourceFrameIndex: pose.sourceFrameIndex,
            leftKnee: pose.leftKnee,
            rightKnee: pose.rightKnee,
            leftAnkle: pose.leftAnkle,
            rightAnkle: pose.rightAnkle
        )
    }

    private static func poseWithSwappedLabels(_ pose: SwingPoseSample) -> SwingPoseSample {
        SwingPoseSample(
            time: pose.time,
            leftWrist: pose.rightWrist,
            rightWrist: pose.leftWrist,
            leftElbow: pose.rightElbow,
            rightElbow: pose.leftElbow,
            leftShoulder: pose.rightShoulder,
            rightShoulder: pose.leftShoulder,
            leftHip: pose.rightHip,
            rightHip: pose.leftHip,
            head: pose.head,
            spineAngle: pose.spineAngle,
            aggregateConfidence: pose.aggregateConfidence,
            sourceFrameIndex: pose.sourceFrameIndex,
            leftKnee: pose.rightKnee,
            rightKnee: pose.leftKnee,
            leftAnkle: pose.rightAnkle,
            rightAnkle: pose.leftAnkle
        )
    }

    private static func symmetricArmPose(_ pose: SwingPoseSample) -> SwingPoseSample {
        let axis: CGFloat = 0.515
        func mirror(_ point: CGPoint?) -> CGPoint? {
            point.map { CGPoint(x: axis * 2 - $0.x, y: $0.y) }
        }
        return SwingPoseSample(
            time: pose.time,
            leftWrist: pose.leftWrist,
            rightWrist: mirror(pose.leftWrist),
            leftElbow: pose.leftElbow,
            rightElbow: mirror(pose.leftElbow),
            leftShoulder: pose.leftShoulder,
            rightShoulder: mirror(pose.leftShoulder),
            leftHip: pose.leftHip,
            rightHip: mirror(pose.leftHip),
            head: pose.head,
            spineAngle: pose.spineAngle,
            aggregateConfidence: pose.aggregateConfidence,
            sourceFrameIndex: pose.sourceFrameIndex,
            leftKnee: pose.leftKnee,
            rightKnee: mirror(pose.leftKnee),
            leftAnkle: pose.leftAnkle,
            rightAnkle: mirror(pose.leftAnkle)
        )
    }

    private static func verifyOccludedFollowThroughRemainsLowConfidence() {
        let timeline = SwingEvidenceTimeline.build(from: fixture(
            includeImpactObjects: true,
            followThroughExtensionProfile: .occluded
        ))
        let centered = candidateSet(impactFrame: 300, timeline: timeline)
        let p8 = centered.candidates(for: .followThrough)
        precondition(!p8.isEmpty)
        precondition(p8.allSatisfy {
            !$0.requirementsSatisfied && $0.maximumStatus == .lowConfidence
        })
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

    private static func verifyStageAwareTransitionEvidenceScalesAcrossTempo() {
        for fps in [30, 60, 120] {
            let fast = candidatePath(
                frameOffsets: [0, 4, 10, 16, 20, 24, 32, 40],
                fps: fps
            )
            let slowTakeaway = candidatePath(
                frameOffsets: [0, 45, 51, 60, 64, 68, 76, 84],
                fps: fps
            )
            let uniform = candidatePath(
                frameOffsets: [0, 12, 24, 36, 48, 60, 72, 84],
                fps: fps
            )
            precondition(
                StagePathTieBreakEvidence.score(fast) == StagePathTieBreakEvidence.score(slowTakeaway),
                "Observed-evidence ties must not be broken by stage percentage at \(fps) FPS"
            )
            precondition(
                StagePathTieBreakEvidence.score(uniform) == StagePathTieBreakEvidence.score(slowTakeaway),
                "Tempo variants must not receive fixed phase-position rewards at \(fps) FPS"
            )
        }
    }

    private static func verifyTakeawayPositionEvidenceIsBodyScaleInvariant() {
        let basePose = completePose(
            time: 0,
            sourceFrameIndex: 0,
            hand: CGPoint(x: 0.38, y: 0.60)
        )
        let baseHip = SwingGeometry.center(basePose.leftHip, basePose.rightHip)!
        let baseScale = StableBodyScaleEvidence.estimate(from: [basePose, basePose])!
        let shoulderCenter = SwingGeometry.center(
            basePose.leftShoulder,
            basePose.rightShoulder
        )!
        precondition(
            abs(baseScale - SwingGeometry.distance(shoulderCenter, baseHip)) < 0.000_001,
            "Torso length must remain the stable scale when projected shoulder/hip widths narrow"
        )
        let baseHand = CGPoint(
            x: baseHip.x - CGFloat(baseScale * 1.45),
            y: shoulderCenter.y + CGFloat(baseScale * 0.72)
        )
        let baseScore = TakeawayStageEvidence.stageScore(
            hand: baseHand,
            hip: baseHip,
            shoulder: shoulderCenter,
            bodyScale: baseScale,
            leadArmAngle: 35,
            leadArmExtension: 165,
            shoulderTurn: 14
        )

        let scenarios: [(scale: CGFloat, translation: CGPoint, mirrored: Bool)] = [
            (0.45, CGPoint(x: 0.60, y: 0.12), false),
            (1.00, CGPoint(x: -0.10, y: 0.08), true),
            (1.60, CGPoint(x: 0.20, y: -0.16), false),
            (1.25, CGPoint(x: 1.10, y: 0.04), true)
        ]
        for scenario in scenarios {
            let pose = transformedPose(
                basePose,
                scale: scenario.scale,
                translation: scenario.translation,
                mirrored: scenario.mirrored
            )
            let hand = transformedPoint(
                baseHand,
                scale: scenario.scale,
                translation: scenario.translation,
                mirrored: scenario.mirrored
            )
            let hip = SwingGeometry.center(pose.leftHip, pose.rightHip)!
            let shoulder = SwingGeometry.center(pose.leftShoulder, pose.rightShoulder)!
            let bodyScale = StableBodyScaleEvidence.estimate(from: [pose, pose])!
            let score = TakeawayStageEvidence.stageScore(
                hand: hand,
                hip: hip,
                shoulder: shoulder,
                bodyScale: bodyScale,
                leadArmAngle: 35,
                leadArmExtension: 165,
                shoulderTurn: scenario.mirrored ? -14 : 14
            )
            precondition(abs(score - baseScore) < 0.000_001)
            precondition(
                abs(bodyScale / baseScale - Double(scenario.scale)) < 0.000_001
            )
        }

        let addressLike = TakeawayStageEvidence.stageScore(
            hand: CGPoint(
                x: baseHip.x - CGFloat(baseScale * 0.55),
                y: shoulderCenter.y + CGFloat(baseScale * 1.05)
            ),
            hip: baseHip,
            shoulder: shoulderCenter,
            bodyScale: baseScale,
            leadArmAngle: 80,
            leadArmExtension: 168,
            shoulderTurn: 1
        )
        let lateP3Like = TakeawayStageEvidence.stageScore(
            hand: CGPoint(
                x: baseHip.x - CGFloat(baseScale * 1.80),
                y: shoulderCenter.y + CGFloat(baseScale * 0.25)
            ),
            hip: baseHip,
            shoulder: shoulderCenter,
            bodyScale: baseScale,
            leadArmAngle: 13,
            leadArmExtension: 164,
            shoulderTurn: 22
        )
        precondition(baseScore > addressLike)
        precondition(baseScore > lateP3Like)
    }

    private static func verifyTakeawayResolverIsTempoInvariant() {
        for timeScale in [0.60, 1.0, 1.60] {
            let timeline = SwingEvidenceTimeline.build(from: fixture(
                includeImpactObjects: true,
                timeScale: timeScale
            ))
            let centered = candidateSet(impactFrame: 300, timeline: timeline)
            precondition(
                centered.candidates(for: .takeaway).first?.sourceFrameIndex == 168,
                "P2 evidence ranking changed at \(timeScale)x time scale"
            )
        }
    }

    private static func verifyParallelStageScoresRequireJointAgreement() {
        let unextendedExactAngle = ParallelStageEvidence.downswingScore(
            armHorizontal: 0.97,
            armExtension: 0,
            downward: 0,
            hipOpen: 0,
            coverage: 1
        )
        let extendedHorizontalBand = ParallelStageEvidence.downswingScore(
            armHorizontal: 0.65,
            armExtension: 0.40,
            downward: 0.07,
            hipOpen: 0,
            coverage: 1
        )
        precondition(extendedHorizontalBand > unextendedExactAngle)
        precondition(extendedHorizontalBand >= 0.32)

        let earlyExactFollowThrough = ParallelStageEvidence.followThroughScore(
            parallelEvidence: 0.98,
            armExtension: 0,
            postImpactRise: 0.05,
            hipTurn: 0.18,
            chestTurn: 1,
            hasContinuedTurn: true,
            coverage: 1
        )
        let laterParallelBand = ParallelStageEvidence.followThroughScore(
            parallelEvidence: 0.95,
            armExtension: 0.90,
            postImpactRise: 0,
            hipTurn: 0.20,
            chestTurn: 1,
            hasContinuedTurn: true,
            coverage: 1
        )
        precondition(
            laterParallelBand > earlyExactFollowThrough,
            "Sub-threshold velocity noise must not beat continued body rotation inside the P8 parallel band"
        )
    }

    private static func candidatePath(
        frameOffsets: [Int],
        fps: Int
    ) -> [StageCandidate] {
        precondition(frameOffsets.count == SwingStage.allCases.count)
        return zip(SwingStage.allCases, frameOffsets).enumerated().map {
            evidenceIndex, pair in
            StageCandidate(
                stage: pair.0,
                evidenceIndex: evidenceIndex,
                sourceFrameIndex: fps * 1_000 + pair.1,
                time: Double(pair.1) / Double(fps),
                score: 0.80,
                requirementsSatisfied: true,
                maximumStatus: .confirmed,
                hasClubEvidence: false,
                hasBallEvidence: false
            )
        }
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
        includeDeliveryShaft: Bool = true,
        includeReleaseShaft: Bool = true,
        counterRotateAtFollowThrough: Bool = false,
        reverseChestAtFollowThrough: Bool = false,
        followThroughExtensionProfile: FollowThroughExtensionProfile = .extended,
        timeScale: Double = 1
    ) -> [SwingFrameEvidence] {
        (60...420).map { sourceFrameIndex in
            let time = Double(sourceFrameIndex) / 120 * timeScale
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
            let isP8Neighborhood = (323...340).contains(sourceFrameIndex)
            let shoulderAngle = reverseChestAtFollowThrough && isP8Neighborhood
                ? 18
                : shoulderTurn(sourceFrameIndex: sourceFrameIndex)
            let hipAngle = counterRotateAtFollowThrough && isP8Neighborhood
                ? -42
                : hipTurn(sourceFrameIndex: sourceFrameIndex)
            let pose = completePose(
                time: time,
                sourceFrameIndex: sourceFrameIndex,
                hand: hand
            )
            let baseObject = objectEvidence(
                sourceFrameIndex: sourceFrameIndex,
                includeImpactObjects: includeImpactObjects,
                includeTakeawayShaft: includeTakeawayShaft,
                includeDeliveryShaft: includeDeliveryShaft,
                includeReleaseShaft: includeReleaseShaft
            )
            let object: SwingObjectEvidence
            if sourceFrameIndex == 324,
               followThroughExtensionProfile != .extended {
                object = SwingObjectEvidence(
                    shaft: ClubShaftEvidence(
                        start: CGPoint(x: 0.55, y: 0.50),
                        end: CGPoint(x: 0.75, y: 0.50),
                        confidence: 0.95
                    ),
                    ball: baseObject.ball,
                    stableBall: baseObject.stableBall,
                    ballLocalChange: baseObject.ballLocalChange
                )
            } else {
                object = baseObject
            }
            let leadArmExtension: Double?
            switch followThroughExtensionProfile {
            case .extended:
                leadArmExtension = 176
            case .bentExact:
                leadArmExtension = sourceFrameIndex == 324 ? 125 : 176
            case .occluded:
                leadArmExtension = isP8Neighborhood ? nil : 176
            }
            return SwingFrameEvidence(
                sourceFrameIndex: sourceFrameIndex,
                time: time,
                pose: pose,
                rawPose: pose,
                objectEvidence: object,
                leadArm: .left,
                leadArmAngle: leadArmAngle(sourceFrameIndex: sourceFrameIndex),
                leadArmExtension: leadArmExtension,
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
        includeTakeawayShaft: Bool,
        includeDeliveryShaft: Bool,
        includeReleaseShaft: Bool
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
        if includeDeliveryShaft, (287...289).contains(sourceFrameIndex) {
            return SwingObjectEvidence(
                shaft: ClubShaftEvidence(
                    start: CGPoint(x: 0.28, y: 0.53),
                    end: CGPoint(x: 0.60, y: 0.53),
                    confidence: sourceFrameIndex == 288 ? 0.98 : 0.80
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
        if includeReleaseShaft, (323...340).contains(sourceFrameIndex) {
            return SwingObjectEvidence(
                shaft: ClubShaftEvidence(
                    start: CGPoint(x: 0.48, y: 0.46),
                    end: CGPoint(x: 0.75, y: 0.46),
                    confidence: sourceFrameIndex == 324 ? 0.98 : 0.80
                ),
                ball: BallEvidence(center: stableBall, radius: 0.012, confidence: 0.95),
                stableBall: stableBall,
                ballLocalChange: 0
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
            .shaftParallelDownswing: 9,
            .impact: 10,
            .followThrough: 12
        ]
        let candidateIndices = Set(localStageIndices.values)

        for localIndex in 0...20 {
            let isBackswing = (1...4).contains(localIndex)
            let isDownswing = (6...10).contains(localIndex)
            let isFollowThrough = (11...15).contains(localIndex)
            let isStableTop = (5...6).contains(localIndex)
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
            let stable = hasStrongSupport && isStableTop
                || candidateIndices.contains(localIndex) && (localIndex == 0 || localIndex == 6)
            let velocityY: CGFloat
            switch direction {
            case .backswing: velocityY = -0.60
            case .downswing: velocityY = 0.75
            case .stable: velocityY = stable ? 0 : 0.45
            }
            let sourceFrameIndex = startSourceFrame + localIndex
            let time = startTime + Double(localIndex) * 0.05
            let hand = CGPoint(x: 0.50, y: 0.50)
            let pose = completePose(
                time: time,
                sourceFrameIndex: sourceFrameIndex,
                hand: hand
            )
            let frame = SwingFrameEvidence(
                sourceFrameIndex: sourceFrameIndex,
                time: time,
                pose: pose,
                rawPose: pose,
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

    private static func transformedPose(
        _ pose: SwingPoseSample,
        scale: CGFloat,
        translation: CGPoint,
        mirrored: Bool
    ) -> SwingPoseSample {
        func point(_ value: CGPoint?) -> CGPoint? {
            value.map {
                transformedPoint(
                    $0,
                    scale: scale,
                    translation: translation,
                    mirrored: mirrored
                )
            }
        }
        return SwingPoseSample(
            time: pose.time,
            leftWrist: point(pose.leftWrist),
            rightWrist: point(pose.rightWrist),
            leftElbow: point(pose.leftElbow),
            rightElbow: point(pose.rightElbow),
            leftShoulder: point(pose.leftShoulder),
            rightShoulder: point(pose.rightShoulder),
            leftHip: point(pose.leftHip),
            rightHip: point(pose.rightHip),
            head: point(pose.head),
            spineAngle: pose.spineAngle,
            aggregateConfidence: pose.aggregateConfidence,
            sourceFrameIndex: pose.sourceFrameIndex,
            leftKnee: point(pose.leftKnee),
            rightKnee: point(pose.rightKnee),
            leftAnkle: point(pose.leftAnkle),
            rightAnkle: point(pose.rightAnkle)
        )
    }

    private static func transformedPoint(
        _ point: CGPoint,
        scale: CGFloat,
        translation: CGPoint,
        mirrored: Bool
    ) -> CGPoint {
        CGPoint(
            x: translation.x + (mirrored ? -point.x : point.x) * scale,
            y: translation.y + point.y * scale
        )
    }

    private static func detection(
        _ stage: SwingStage,
        in result: SwingAnalysisResult
    ) -> SwingStageDetection {
        result.detections.first { $0.stage == stage }!
    }
}

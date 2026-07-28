import Foundation

@main
struct ContinuousEvidenceStageSolverSmoke {
    static func main() {
        verifyCompleteDetectedEvidenceResolvesEveryStage()
        verifyCanonicalObjectEvidenceCannotBeSubstituted()
    }

    private static func verifyCompleteDetectedEvidenceResolvesEveryStage() {
        let fixture = makeFixture(missingEvidenceFor: nil)
        let result = ConstrainedSwingPathSolver.solve(
            candidateSets: [fixture.candidateSet],
            timeline: fixture.timeline
        )
        precondition(result.unresolvedStages.isEmpty)
        for (index, stage) in SwingStage.pStages.enumerated() {
            let detection = detection(stage, in: result)
            precondition(detection.sourceFrameIndex == 100 + index)
            precondition(detection.evidence.sources.contains(.bodyPose))
        }
        precondition(detection(.takeaway, in: result).evidence.sources.contains(.shaft))
        precondition(detection(.shaftParallelDownswing, in: result).evidence.sources.contains(.shaft))
        precondition(detection(.impact, in: result).evidence.sources.isSuperset(of: [.clubhead, .ball]))
        precondition(detection(.followThrough, in: result).evidence.sources.contains(.shaft))
    }

    private static func verifyCanonicalObjectEvidenceCannotBeSubstituted() {
        for stage in [
            SwingStage.takeaway,
            .shaftParallelDownswing,
            .impact,
            .followThrough
        ] {
            let fixture = makeFixture(missingEvidenceFor: stage)
            let result = ConstrainedSwingPathSolver.solve(
                candidateSets: [fixture.candidateSet],
                timeline: fixture.timeline
            )
            for otherStage in SwingStage.pStages {
                let resolved = detection(otherStage, in: result)
                if otherStage == stage {
                    precondition(resolved.status == .unresolved)
                    precondition(resolved.sourceFrameIndex == nil)
                } else {
                    precondition(
                        resolved.sourceFrameIndex == 100 + SwingStage.pStages.firstIndex(of: otherStage)!,
                        "Missing \(stage) evidence must not move or erase \(otherStage)"
                    )
                }
            }
        }
    }

    private static func makeFixture(
        missingEvidenceFor missingStage: SwingStage?
    ) -> (timeline: [SwingTemporalFrame], candidateSet: StageCandidateSet) {
        let timeline = SwingStage.pStages.enumerated().map { index, stage in
            temporalFrame(
                index: index,
                stage: stage,
                objectEvidence: objectEvidence(
                    for: stage,
                    missing: stage == missingStage
                )
            )
        }
        let candidates = Dictionary(uniqueKeysWithValues: SwingStage.pStages.enumerated().map {
            index, stage in
            (stage, [StageCandidate(
                stage: stage,
                evidenceIndex: index,
                sourceFrameIndex: 100 + index,
                time: Double(index) * 0.1,
                score: 0.95,
                requirementsSatisfied: true,
                maximumStatus: .confirmed,
                hasClubEvidence: [.takeaway, .shaftParallelDownswing, .followThrough].contains(stage),
                hasBallEvidence: stage == .impact
            )])
        })
        return (
            timeline,
            StageCandidateSet(
                impact: candidates[.impact]![0],
                candidatesByStage: candidates
            )
        )
    }

    private static func temporalFrame(
        index: Int,
        stage: SwingStage,
        objectEvidence: SwingObjectEvidence
    ) -> SwingTemporalFrame {
        let pose = SwingPoseSample(
            time: Double(index) * 0.1,
            leftWrist: CGPoint(x: 0.4, y: 0.5),
            rightWrist: CGPoint(x: 0.42, y: 0.5),
            leftElbow: CGPoint(x: 0.35, y: 0.42),
            rightElbow: CGPoint(x: 0.47, y: 0.42),
            leftShoulder: CGPoint(x: 0.38, y: 0.3),
            rightShoulder: CGPoint(x: 0.55, y: 0.3),
            leftHip: CGPoint(x: 0.42, y: 0.62),
            rightHip: CGPoint(x: 0.52, y: 0.62),
            head: CGPoint(x: 0.47, y: 0.18),
            spineAngle: 10,
            aggregateConfidence: 0.95,
            sourceFrameIndex: 100 + index
        )
        let frame = SwingFrameEvidence(
            sourceFrameIndex: 100 + index,
            time: Double(index) * 0.1,
            pose: pose,
            rawPose: pose,
            objectEvidence: objectEvidence,
            leadArm: .left,
            leadArmAngle: 0,
            leadArmExtension: 175,
            shoulderAngle: 20,
            hipAngle: 15,
            handCenter: CGPoint(x: 0.41, y: 0.5),
            hipCenter: CGPoint(x: 0.47, y: 0.62),
            handVelocity: stage == .address ? .zero : CGPoint(x: 0, y: 0.5),
            handAcceleration: .zero,
            headSpeed: 0.01,
            hipSpeed: 0.01,
            poseCoverage: 1
        )
        return SwingTemporalFrame(
            frame: frame,
            direction: stage == .address ? .stable : .downswing,
            sustainedBackswing: [.takeaway, .leadArmParallelBackswing].contains(stage),
            sustainedDownswing: [.top, .leadArmParallelDownswing, .shaftParallelDownswing, .impact].contains(stage),
            sustainedFollowThrough: stage == .followThrough,
            isAddressBoundary: stage == .address,
            isTopPlateauEnd: stage == .top,
            isFinishPlateauStart: false,
            shaftAngleContinuity: 1,
            ballStability: 1,
            qualityFlags: []
        )
    }

    private static func objectEvidence(
        for stage: SwingStage,
        missing: Bool
    ) -> SwingObjectEvidence {
        let ball = CGPoint(x: 0.72, y: 0.82)
        if stage == .impact {
            var points: [SwingLandmark: TrackedSwingPoint] = [
                .ball: detectedPoint(ball)
            ]
            if !missing {
                points[.clubhead] = detectedPoint(ball)
            }
            return SwingObjectEvidence(
                shaft: nil,
                ball: BallEvidence(center: ball, radius: 0.01, confidence: 0.95),
                stableBall: ball,
                ballLocalChange: 0,
                trackedPoints: points
            )
        }
        guard [.takeaway, .shaftParallelDownswing, .followThrough].contains(stage),
              !missing else { return .empty }
        let start = CGPoint(x: 0.35, y: 0.55)
        let end = CGPoint(x: 0.70, y: 0.55)
        return SwingObjectEvidence(
            shaft: ClubShaftEvidence(start: start, end: end, confidence: 0.95),
            ball: nil,
            stableBall: nil,
            ballLocalChange: 0,
            trackedPoints: [
                .shaftStart: detectedPoint(start),
                .shaftEnd: detectedPoint(end)
            ]
        )
    }

    private static func detectedPoint(_ point: CGPoint) -> TrackedSwingPoint {
        TrackedSwingPoint(
            point: NormalizedPoint(x: point.x, y: point.y),
            confidence: 0.95,
            state: .detected,
            source: .coreMLGolf
        )
    }

    private static func detection(
        _ stage: SwingStage,
        in result: SwingAnalysisResult
    ) -> SwingStageDetection {
        result.detections.first { $0.stage == stage }!
    }
}

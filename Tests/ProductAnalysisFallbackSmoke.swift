import Foundation

@main
struct ProductAnalysisFallbackSmoke {
    static func main() {
        let poses = makePoseSequence()
        let strictFailure = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: Set(SwingStage.pStages)
        )

        let recovered = ProductAnalysisFallback.resolve(
            strictResult: strictFailure,
            poseSamples: poses
        )

        precondition(
            !recovered.detectedMarkers.isEmpty,
            "A successful Vision pose sequence must remain usable when strict P1-P8 solving fails"
        )
        precondition(
            recovered.detections.contains {
                $0.stage == .top && $0.status != .unresolved
            },
            "The pose-only fallback must retain a low-confidence top candidate for manual correction"
        )
        precondition(
            recovered.detections.contains {
                $0.stage == .address && $0.status == .lowConfidence
            },
            "A plausible low-confidence address frame must remain available for correction"
        )
        precondition(
            recovered.unresolvedStages.contains(.shaftParallelDownswing),
            "P6 must remain unresolved without trustworthy shaft evidence"
        )
        precondition(
            recovered.unresolvedStages.contains(.followThrough),
            "P8 must remain unresolved when no post-impact Vision event is available"
        )
        precondition(
            recovered.detections
                .filter { $0.status != .unresolved }
                .allSatisfy {
                    $0.status == .lowConfidence && $0.sourceFrameIndex != nil
                },
            "Body-only candidates must stay editable and retain their exact source frame"
        )

        let strictMarker = KeyframeMarker(time: 0.42, stage: .impact)
        let strictSuccess = SwingAnalysisResult(
            detectedMarkers: [strictMarker],
            unresolvedStages: Set(SwingStage.pStages).subtracting([.impact]),
            detections: [
                SwingStageDetection(
                    stage: .impact,
                    time: 0.42,
                    sourceFrameIndex: 425,
                    confidence: 0.9,
                    status: .confirmed
                )
            ]
        )
        precondition(
            ProductAnalysisFallback.resolve(
                strictResult: strictSuccess,
                poseSamples: poses
            ) == strictSuccess,
            "A strict result with real markers must never be replaced by fallback guesses"
        )

        let partialFinePass = Array(poses.prefix(4))
        let recoveredFromCoarseVision = ProductAnalysisFallback.resolve(
            strictResult: strictFailure,
            poseSamples: partialFinePass,
            supplementalPoseSamples: poses
        )
        precondition(
            recoveredFromCoarseVision.detectedMarkers.count >= 4,
            "A partial fine window must reuse the full coarse Vision sequence instead of returning zero P points"
        )
        precondition(
            recoveredFromCoarseVision.detections
                .filter { $0.status != .unresolved }
                .allSatisfy {
                $0.sourceFrameIndex != nil
            },
            "Coarse Vision fallback markers must still reference exact source frames"
        )

        precondition(
            !CandidateAttemptAcceptancePolicy.hasUsableStages(strictFailure),
            "A completed candidate window with zero P points is not a usable analysis"
        )
        precondition(
            CandidateAttemptAcceptancePolicy.hasUsableStages(strictSuccess),
            "A candidate window with at least one source-backed P point is usable"
        )

        let coarseSamples = poses.map {
            CoarseSwingSample(time: $0.time, pose: $0)
        }
        let partialAttempt = SwingAttempt(
            ordinal: 1,
            startTime: poses[4].time,
            endTime: poses[8].time
        )
        precondition(
            CoarseFallbackSelectionPolicy.samples(
                all: coarseSamples,
                preferredAttempt: partialAttempt,
                requiresFullSequence: true
            ).count == coarseSamples.count,
            "Rejecting a zero-P candidate must preserve the complete coarse Vision sequence"
        )
        precondition(
            CoarseFallbackSelectionPolicy.samples(
                all: coarseSamples,
                preferredAttempt: partialAttempt,
                requiresFullSequence: false
            ).count < coarseSamples.count,
            "A normal preferred attempt may still narrow the coarse sequence"
        )

        let higherFollowThrough = makePoseSequence(wristY: [
            0.78, 0.62, 0.43, 0.25,
            0.32, 0.40, 0.50,
            0.35, 0.10, 0.28, 0.52
        ])
        let firstSwingCycle = SwingStageDetector.detectPoseOnlyCandidates(
            higherFollowThrough
        )
        precondition(
            firstSwingCycle.detections.first(where: { $0.stage == .top })?
                .sourceFrameIndex == 403,
            "P4 must be the first complete backswing-to-downswing apex, not a later higher follow-through"
        )

        let geometry = makeViewAwareEvidence()
        let faceOnStages = PoseOnlyStageGeometry.resolve(
            evidence: geometry,
            topIndex: 6,
            view: .faceOn
        )
        precondition(
            faceOnStages == PoseOnlyBodyStageIndices(
                address: 0,
                takeaway: 3,
                leadArmParallelBackswing: 5,
                leadArmParallelDownswing: 8,
                impact: 9
            ),
            "Face-on fallback must use anatomical stage geometry instead of dividing P1-P4 into thirds"
        )

        let downTheLineStages = PoseOnlyStageGeometry.resolve(
            evidence: geometry,
            topIndex: 6,
            view: .downTheLine
        )
        precondition(
            downTheLineStages == PoseOnlyBodyStageIndices(
                address: 0,
                takeaway: 3,
                leadArmParallelBackswing: 5,
                leadArmParallelDownswing: 7,
                impact: 9
            ),
            "DTL fallback must use projected hand geometry distinct from the face-on arm-angle profile"
        )

        let postImpactPoseLoss = makePostImpactPoseLossSequence()
        precondition(
            PoseOnlyFollowThroughResolver.resolve(
                samples: postImpactPoseLoss,
                after: postImpactPoseLoss[1].time,
                view: .downTheLine
            )?.sourceFrameIndex == 205,
            "DTL P8 must use the first source-backed post-impact wrist-loss event"
        )
        precondition(
            PoseOnlyFollowThroughResolver.resolve(
                samples: postImpactPoseLoss,
                after: postImpactPoseLoss[1].time,
                view: .faceOn
            ) == nil,
            "FO P8 must not reuse the DTL wrist-occlusion rule"
        )
    }

    private static func makePoseSequence(
        wristY: [CGFloat] = [
            0.72, 0.68, 0.43, 0.48, 0.50, 0.25, 0.24,
            0.27, 0.36, 0.48, 0.59, 0.68, 0.57, 0.46
        ]
    ) -> [SwingPoseSample] {
        wristY.enumerated().map { index, y in
            SwingPoseSample(
                time: Double(index) / 60,
                leftWrist: CGPoint(x: 0.42, y: y),
                rightWrist: CGPoint(x: 0.46, y: y + 0.01),
                leftElbow: CGPoint(x: 0.40, y: max(0.26, y + 0.04)),
                rightElbow: CGPoint(x: 0.48, y: max(0.26, y + 0.04)),
                leftShoulder: CGPoint(x: 0.40, y: 0.42),
                rightShoulder: CGPoint(x: 0.52, y: 0.42),
                leftHip: CGPoint(x: 0.42, y: 0.64),
                rightHip: CGPoint(x: 0.50, y: 0.64),
                head: CGPoint(x: 0.46, y: 0.30),
                spineAngle: 8,
                aggregateConfidence: index == 0 ? 0.44 : 0.92,
                sourceFrameIndex: 400 + index,
                leftKnee: CGPoint(x: 0.42, y: 0.78),
                rightKnee: CGPoint(x: 0.50, y: 0.78),
                leftAnkle: CGPoint(x: 0.41, y: 0.94),
                rightAnkle: CGPoint(x: 0.51, y: 0.94)
            )
        }
    }

    private static func makeViewAwareEvidence() -> [SwingFrameEvidence] {
        let relativeY: [CGFloat] = [
            0.03, 0.03, 0.02, 0.00, -0.05, -0.10,
            -0.18, -0.10, -0.08, 0.025, -0.04
        ]
        let leadArmAngle: [Double] = [
            85, 84, 70, 41, 20, 0,
            45, 18, 0, 75, 40
        ]
        return relativeY.indices.map { index in
            let hip = CGPoint(x: 0.50, y: 0.64)
            let hand = CGPoint(
                x: index <= 6
                    ? 0.55 - CGFloat(index) * 0.03
                    : 0.37 + CGFloat(index - 6) * 0.045,
                y: hip.y + relativeY[index]
            )
            return SwingFrameEvidence(
                sourceFrameIndex: 100 + index,
                time: Double(index) / 30,
                pose: nil,
                objectEvidence: .empty,
                leadArm: .left,
                leadArmAngle: leadArmAngle[index],
                leadArmExtension: 165,
                shoulderAngle: 0,
                hipAngle: 0,
                handCenter: hand,
                hipCenter: hip,
                handVelocity: index == 0
                    ? .zero
                    : CGPoint(x: 0.25, y: relativeY[index] - relativeY[index - 1]),
                handAcceleration: .zero,
                headSpeed: 0,
                hipSpeed: 0,
                poseCoverage: 0.9
            )
        }
    }

    private static func makePostImpactPoseLossSequence() -> [SwingPoseSample] {
        (200...207).map { sourceFrameIndex in
            let hasWrist = sourceFrameIndex < 205
            return SwingPoseSample(
                time: Double(sourceFrameIndex) / 30,
                leftWrist: hasWrist ? CGPoint(x: 0.48, y: 0.61) : nil,
                rightWrist: nil,
                leftElbow: hasWrist ? CGPoint(x: 0.45, y: 0.54) : nil,
                rightElbow: nil,
                leftShoulder: CGPoint(x: 0.42, y: 0.40),
                rightShoulder: CGPoint(x: 0.54, y: 0.40),
                leftHip: CGPoint(x: 0.44, y: 0.64),
                rightHip: CGPoint(x: 0.52, y: 0.64),
                head: CGPoint(x: 0.48, y: 0.28),
                spineAngle: 7,
                aggregateConfidence: 0.72,
                sourceFrameIndex: sourceFrameIndex,
                leftKnee: CGPoint(x: 0.44, y: 0.78),
                rightKnee: CGPoint(x: 0.52, y: 0.78),
                leftAnkle: CGPoint(x: 0.43, y: 0.94),
                rightAnkle: CGPoint(x: 0.53, y: 0.94)
            )
        }
    }
}

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
            "P8 must remain unresolved without trustworthy shaft evidence"
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
}

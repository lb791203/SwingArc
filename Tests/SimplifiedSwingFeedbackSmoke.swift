import Foundation

@main
struct SimplifiedSwingFeedbackSmoke {
    static func main() {
        testExactFiveCardContract()
        testEstimatedSharedEvidenceDegradesOnlyConsumers()
        testMissingImpactEvidenceDegradesOnlyImpactCard()
        testAttentionSummaryUsesEvidenceBackedFinding()
        testDTLAcceptsMeasuredVisibleSideEvidence()
    }

    private static func testExactFiveCardContract() {
        let feedback = SwingFeedbackAssembler.make(
            artifact: fixtureArtifact(
                estimatedHandAtP3: false,
                includeImpactObjects: true
            ),
            detections: fixtureDetections(
                includeImpactEvidence: true
            ),
            findings: []
        )

        precondition(feedback.cards.count == 5)
        precondition(feedback.cards.map(\.category) == [
            .setup,
            .bodyStability,
            .handPath,
            .swingPlane,
            .impactAndRelease
        ])
        precondition(feedback.cards.allSatisfy {
            $0.status == .good
        })
        precondition(feedback.summary.title == "本次动作整体稳定")
        precondition(feedback.cards.flatMap(\.metrics).allSatisfy {
            $0.id.isMotionAnalysisOutput
        })
    }

    private static func testEstimatedSharedEvidenceDegradesOnlyConsumers() {
        let feedback = SwingFeedbackAssembler.make(
            artifact: fixtureArtifact(
                estimatedHandAtP3: true,
                includeImpactObjects: true
            ),
            detections: fixtureDetections(
                includeImpactEvidence: true
            ),
            findings: []
        )

        precondition(
            feedback.card(for: .handPath)?.status == .insufficientEvidence
        )
        precondition(
            feedback.card(for: .swingPlane)?.status == .insufficientEvidence
        )
        precondition(
            feedback.card(for: .bodyStability)?.status == .good
        )
        precondition(
            feedback.card(for: .impactAndRelease)?.status == .good
        )
    }

    private static func testMissingImpactEvidenceDegradesOnlyImpactCard() {
        let feedback = SwingFeedbackAssembler.make(
            artifact: fixtureArtifact(
                estimatedHandAtP3: false,
                includeImpactObjects: false
            ),
            detections: fixtureDetections(
                includeImpactEvidence: false
            ),
            findings: []
        )

        precondition(
            feedback.card(for: .impactAndRelease)?.status
                == .insufficientEvidence
        )
        precondition(
            feedback.card(for: .swingPlane)?.status == .good
        )
        precondition(
            feedback.card(for: .bodyStability)?.status == .good
        )
    }

    private static func testAttentionSummaryUsesEvidenceBackedFinding() {
        let finding = TechniqueFinding(
            kind: .overTheTop,
            severity: .significant,
            evidence: TechniqueEvidence(
                stages: [.leadArmParallelDownswing, .shaftParallelDownswing],
                normalizedMagnitude: 0.22
            )
        )
        let feedback = SwingFeedbackAssembler.make(
            artifact: fixtureArtifact(
                estimatedHandAtP3: false,
                includeImpactObjects: true
            ),
            detections: fixtureDetections(
                includeImpactEvidence: true
            ),
            findings: [finding]
        )

        precondition(
            feedback.card(for: .swingPlane)?.status == .attention
        )
        precondition(feedback.summary.title == "下杆路径略偏外。")
        precondition(feedback.summary.stages == finding.evidence.stages)
    }

    private static func testDTLAcceptsMeasuredVisibleSideEvidence() {
        let dtlArtifact = occludedFarSideArtifact(
            view: .downTheLine
        )
        let dtlFeedback = SwingFeedbackAssembler.make(
            artifact: dtlArtifact,
            detections: fixtureDetections(
                includeImpactEvidence: true
            ),
            findings: []
        )
        precondition(
            dtlFeedback.card(for: .setup)?.status == .good,
            "DTL setup must accept one directly measured body side"
        )
        precondition(
            dtlFeedback.card(for: .bodyStability)?.status == .good,
            "DTL body evidence must not require the occluded far side"
        )
        precondition(
            dtlFeedback.card(for: .handPath)?.status == .good,
            "A direct 0.60 hand measurement must support hand-path review"
        )

        let faceOnFeedback = SwingFeedbackAssembler.make(
            artifact: occludedFarSideArtifact(view: .faceOn),
            detections: fixtureDetections(
                includeImpactEvidence: true
            ),
            findings: []
        )
        precondition(
            faceOnFeedback.card(for: .setup)?.status
                == .insufficientEvidence,
            "Face-on setup must retain bilateral evidence requirements"
        )
    }

    private static func fixtureArtifact(
        estimatedHandAtP3: Bool,
        includeImpactObjects: Bool
    ) -> SwingAnalysisArtifact {
        let frames = SwingStage.pStages.enumerated().map { offset, stage in
            fixtureFrame(
                stage: stage,
                frameIndex: 100 + offset,
                estimatedHand: estimatedHandAtP3
                    && stage == .leadArmParallelBackswing,
                includeImpactObjects: includeImpactObjects
                    && stage == .impact
            )
        }
        return SwingAnalysisArtifact(
            schemaVersion: SwingAnalysisArtifact.currentSchemaVersion,
            modelVersion: "fixture",
            view: PracticeCameraView.downTheLine.rawValue,
            sourceFrameRate: 60,
            qualityIssues: [],
            frames: frames,
            stages: [],
            metrics: [
                SwingMetricValue(
                    id: .handPathLength,
                    value: 1.1,
                    unit: "person-height",
                    confidence: 0.9,
                    stage: "P2-P7",
                    availability: .measured
                ),
                SwingMetricValue(
                    id: .attackAngle,
                    value: -4,
                    unit: "deg",
                    confidence: 0.9,
                    stage: "P7",
                    availability: .measured
                )
            ]
        )
    }

    private static func fixtureDetections(
        includeImpactEvidence: Bool
    ) -> [SwingStageDetection] {
        SwingStage.pStages.enumerated().map { offset, stage in
            SwingStageDetection(
                stage: stage,
                time: Double(offset) / 60,
                sourceFrameIndex: 100 + offset,
                confidence: 0.9,
                status: .confirmed,
                hasClubEvidence: [
                    SwingStage.takeaway,
                    .shaftParallelDownswing,
                    .followThrough
                ].contains(stage),
                hasBallEvidence: stage == .impact
                    && includeImpactEvidence,
                hasBallChangeEvidence: stage == .impact
                    && includeImpactEvidence
            )
        }
    }

    private static func occludedFarSideArtifact(
        view: PracticeCameraView
    ) -> SwingAnalysisArtifact {
        let base = fixtureArtifact(
            estimatedHandAtP3: false,
            includeImpactObjects: true
        )
        let frames = base.frames.map { frame in
            var landmarks = frame.landmarks
            landmarks.removeValue(forKey: .leftShoulder)
            landmarks.removeValue(forKey: .leftHip)
            landmarks.removeValue(forKey: .leftKnee)
            landmarks.removeValue(forKey: .leftAnkle)
            if let hand = landmarks[.handCenter] {
                landmarks[.handCenter] = TrackedSwingPoint(
                    point: hand.point,
                    confidence: 0.60,
                    state: .detected,
                    source: .visionPose
                )
            }
            return SwingFrameObservation(
                sourceFrameIndex: frame.sourceFrameIndex,
                time: frame.time,
                landmarks: landmarks
            )
        }
        return SwingAnalysisArtifact(
            schemaVersion: base.schemaVersion,
            modelVersion: base.modelVersion,
            view: view.rawValue,
            sourceFrameRate: base.sourceFrameRate,
            qualityIssues: base.qualityIssues,
            frames: frames,
            stages: base.stages,
            metrics: base.metrics
        )
    }

    private static func fixtureFrame(
        stage: SwingStage,
        frameIndex: Int,
        estimatedHand: Bool,
        includeImpactObjects: Bool
    ) -> SwingFrameObservation {
        func point(
            _ x: Double,
            _ y: Double,
            state: SwingPointState = .detected,
            source: SwingPointSource = .visionPose
        ) -> TrackedSwingPoint {
            TrackedSwingPoint(
                point: NormalizedPoint(x: x, y: y),
                confidence: 0.9,
                state: state,
                source: source
            )
        }

        var landmarks: [SwingLandmark: TrackedSwingPoint] = [
            .head: point(0.50, 0.86),
            .leftShoulder: point(0.43, 0.72),
            .rightShoulder: point(0.57, 0.72),
            .leftHip: point(0.45, 0.50),
            .rightHip: point(0.55, 0.50),
            .leftKnee: point(0.45, 0.28),
            .rightKnee: point(0.55, 0.28),
            .leftAnkle: point(0.44, 0.06),
            .rightAnkle: point(0.56, 0.06),
            .handCenter: estimatedHand
                ? point(
                    0.38,
                    0.58,
                    state: .estimated,
                    source: .temporalPrediction
                )
                : point(0.38, 0.58)
        ]

        if [
            SwingStage.takeaway,
            .shaftParallelDownswing,
            .followThrough
        ].contains(stage) {
            landmarks[.shaftStart] = point(
                0.38,
                0.58,
                source: .coreMLGolf
            )
            landmarks[.shaftEnd] = point(
                0.62,
                0.42,
                source: .coreMLGolf
            )
        }
        if includeImpactObjects {
            landmarks[.clubhead] = point(
                0.68,
                0.10,
                source: .coreMLGolf
            )
            landmarks[.ball] = point(
                0.70,
                0.08,
                source: .coreMLGolf
            )
        }
        return SwingFrameObservation(
            sourceFrameIndex: frameIndex,
            time: Double(frameIndex - 100) / 60,
            landmarks: landmarks
        )
    }
}

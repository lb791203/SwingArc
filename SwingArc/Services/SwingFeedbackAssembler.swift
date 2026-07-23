import Foundation

enum SwingFeedbackAssembler {
    static let minimumMeasuredConfidence = 0.65

    static func make(
        artifact: SwingAnalysisArtifact,
        detections: [SwingStageDetection],
        findings: [TechniqueFinding]
    ) -> SimplifiedSwingFeedback {
        let cards = SwingFeedbackCategory.allCases.map {
            makeCard(
                category: $0,
                artifact: artifact,
                detections: detections,
                findings: findings
            )
        }
        return SimplifiedSwingFeedback(
            summary: makeSummary(cards: cards),
            cards: cards
        )
    }

    private static func makeCard(
        category: SwingFeedbackCategory,
        artifact: SwingAnalysisArtifact,
        detections: [SwingStageDetection],
        findings: [TechniqueFinding]
    ) -> SwingFeedbackCard {
        let framesByIndex = artifact.frames.reduce(
            into: [Int: SwingFrameObservation]()
        ) {
            $0[$1.sourceFrameIndex] = $1
        }
        var confidences: [Double] = []
        var sawEstimated = false

        for stage in category.stages {
            guard let detection = detections.first(where: {
                $0.stage == stage
            }),
            detection.status == .confirmed,
            detection.confidence >= minimumMeasuredConfidence,
            let frameIndex = detection.sourceFrameIndex,
            let frame = framesByIndex[frameIndex] else {
                return insufficientCard(
                    category: category,
                    state: .unavailable
                )
            }
            confidences.append(detection.confidence)

            for landmark in requiredLandmarks(
                for: category,
                stage: stage
            ) {
                let point = frame.landmarks[landmark]
                if point?.isEstimated == true {
                    sawEstimated = true
                    continue
                }
                guard isConclusionGrade(point) else {
                    return insufficientCard(
                        category: category,
                        state: .unavailable
                    )
                }
                confidences.append(point?.confidence ?? 0)
            }

            if category == .impactAndRelease,
               stage == .impact,
               !hasImpactEvidence(detection, frame: frame) {
                return insufficientCard(
                    category: category,
                    state: .unavailable
                )
            }
        }

        if sawEstimated {
            return insufficientCard(
                category: category,
                state: .estimated
            )
        }

        let metrics = artifact.metrics.filter {
            metricIDs(for: category).contains($0.id)
                && $0.id.isMotionAnalysisOutput
        }
        let matchedFinding = findings
            .filter {
                findingMatches($0, category: category)
            }
            .max {
                severityRank(for: $0) < severityRank(for: $1)
            }

        if let matchedFinding {
            return SwingFeedbackCard(
                category: category,
                status: .attention,
                conclusion: attentionConclusion(for: matchedFinding),
                stages: matchedFinding.evidence.stages,
                metrics: metrics,
                evidenceState: .measured,
                evidenceConfidence: confidences.min() ?? 0,
                attentionSeverity: severityRank(for: matchedFinding)
            )
        }

        return SwingFeedbackCard(
            category: category,
            status: .good,
            conclusion: goodConclusion(for: category),
            stages: category.stages,
            metrics: metrics,
            evidenceState: .measured,
            evidenceConfidence: confidences.min() ?? 0,
            attentionSeverity: nil
        )
    }

    private static func insufficientCard(
        category: SwingFeedbackCategory,
        state: SwingFeedbackEvidenceState
    ) -> SwingFeedbackCard {
        SwingFeedbackCard(
            category: category,
            status: .insufficientEvidence,
            conclusion: "\(category.title)所需画面证据不足，暂不判断动作好坏。",
            stages: category.stages,
            metrics: [],
            evidenceState: state,
            evidenceConfidence: 0,
            attentionSeverity: nil
        )
    }

    private static func requiredLandmarks(
        for category: SwingFeedbackCategory,
        stage: SwingStage
    ) -> [SwingLandmark] {
        switch category {
        case .setup:
            return [
                .head,
                .leftShoulder,
                .rightShoulder,
                .leftHip,
                .rightHip,
                .leftKnee,
                .rightKnee,
                .leftAnkle,
                .rightAnkle,
                .handCenter
            ]
        case .bodyStability:
            return [
                .head,
                .leftShoulder,
                .rightShoulder,
                .leftHip,
                .rightHip
            ]
        case .handPath:
            return [.handCenter]
        case .swingPlane:
            if [
                SwingStage.takeaway,
                .shaftParallelDownswing,
                .followThrough
            ].contains(stage) {
                return [.handCenter, .shaftStart, .shaftEnd]
            }
            return [.handCenter]
        case .impactAndRelease:
            if stage == .impact {
                return [.handCenter]
            }
            return [.handCenter, .shaftStart, .shaftEnd]
        }
    }

    private static func isConclusionGrade(
        _ point: TrackedSwingPoint?
    ) -> Bool {
        guard let point else { return false }
        return point.isMeasured
            && point.confidence.isFinite
            && point.confidence >= minimumMeasuredConfidence
    }

    private static func hasImpactEvidence(
        _ detection: SwingStageDetection,
        frame: SwingFrameObservation
    ) -> Bool {
        let measuredClubheadAndBall =
            isConclusionGrade(frame.landmarks[.clubhead])
            && isConclusionGrade(frame.landmarks[.ball])
        return detection.hasBallChangeEvidence || measuredClubheadAndBall
    }

    private static func findingMatches(
        _ finding: TechniqueFinding,
        category: SwingFeedbackCategory
    ) -> Bool {
        switch (finding.kind, category) {
        case (.postureLoss, .bodyStability),
             (.overTheTop, .swingPlane),
             (.chickenWing, .impactAndRelease):
            return true
        default:
            return false
        }
    }

    private static func attentionConclusion(
        for finding: TechniqueFinding
    ) -> String {
        switch finding.kind {
        case .postureLoss: return "上杆时身体有起身趋势。"
        case .overTheTop: return "下杆路径略偏外。"
        case .chickenWing: return "送杆阶段前侧手臂略收紧。"
        }
    }

    private static func severityRank(
        for finding: TechniqueFinding
    ) -> Int {
        switch finding.severity {
        case .attention: return 1
        case .significant: return 2
        }
    }

    private static func goodConclusion(
        for category: SwingFeedbackCategory
    ) -> String {
        switch category {
        case .setup:
            return "准备姿势关键点已完整识别，未发现明显异常。"
        case .bodyStability:
            return "P2–P7 身体关键点连续，未发现明显失稳。"
        case .handPath:
            return "P2–P7 手部路径连续可识别。"
        case .swingPlane:
            return "关键阶段的手部与杆身证据连续。"
        case .impactAndRelease:
            return "P6–P8 的击球与释放证据连续。"
        }
    }

    private static func metricIDs(
        for category: SwingFeedbackCategory
    ) -> Set<SwingMetricID> {
        switch category {
        case .setup:
            return [
                .spineTilt2D,
                .shoulderLineAngle2D,
                .hipLineAngle2D,
                .leadKneeAngle,
                .trailKneeAngle
            ]
        case .bodyStability:
            return [
                .headHorizontalDisplacement,
                .headVerticalDisplacement,
                .hipHorizontalDisplacement,
                .hipVerticalDisplacement,
                .spineTilt2D
            ]
        case .handPath:
            return [.handPathLength]
        case .swingPlane:
            return [
                .handPathLength,
                .clubheadPathLength,
                .shaftProjectionAngle,
                .swingPlaneProxy2D
            ]
        case .impactAndRelease:
            return [
                .downswingTime,
                .tempoRatio,
                .leadElbowAngle,
                .trailElbowAngle,
                .clubheadPathLength,
                .clubheadRelativeSpeed2D
            ]
        }
    }

    private static func makeSummary(
        cards: [SwingFeedbackCard]
    ) -> SwingFeedbackSummary {
        let attention = cards
            .filter { $0.status == .attention }
            .max { left, right in
                isLowerPriority(left, than: right)
            }
        if let attention {
            return SwingFeedbackSummary(
                title: attention.conclusion,
                observation: "该问题由\(attention.stages.map(\.evidenceCode).joined(separator: "、"))画面证据支持。",
                recommendation: recommendation(
                    for: attention.category
                ),
                stages: attention.stages
            )
        }
        if cards.allSatisfy({ $0.status == .good }) {
            return SwingFeedbackSummary(
                title: "本次动作整体稳定",
                observation: "五项动作反馈均有合格画面证据，未发现明显异常。",
                recommendation: "保持当前节奏，再录制同机位挥杆用于连续对比。",
                stages: []
            )
        }
        return SwingFeedbackSummary(
            title: "部分动作证据不足",
            observation: "只显示画面能够支持的结论，证据不足项目不会判断动作好坏。",
            recommendation: "固定手机并确保全身、球杆、杆头和球位持续入镜。",
            stages: []
        )
    }

    private static func isLowerPriority(
        _ left: SwingFeedbackCard,
        than right: SwingFeedbackCard
    ) -> Bool {
        let leftSeverity = left.attentionSeverity ?? 0
        let rightSeverity = right.attentionSeverity ?? 0
        if leftSeverity != rightSeverity {
            return leftSeverity < rightSeverity
        }
        if left.evidenceConfidence != right.evidenceConfidence {
            return left.evidenceConfidence < right.evidenceConfidence
        }
        let leftStage = left.stages.compactMap {
            SwingStage.pStages.firstIndex(of: $0)
        }.max() ?? 0
        let rightStage = right.stages.compactMap {
            SwingStage.pStages.firstIndex(of: $0)
        }.max() ?? 0
        return leftStage < rightStage
    }

    private static func recommendation(
        for category: SwingFeedbackCategory
    ) -> String {
        switch category {
        case .setup:
            return "重新对齐站位后录制一次，保持全身和球杆完整入镜。"
        case .bodyStability:
            return "用较慢速度练习，优先保持头部与髋部运动稳定。"
        case .handPath:
            return "用半挥杆练习，让双手沿稳定路径通过下杆区。"
        case .swingPlane:
            return "先做半挥杆，检查 P5–P6 的手部和杆身位置。"
        case .impactAndRelease:
            return "用小幅度击球练习，保持 P6 到 P8 的连续释放。"
        }
    }
}

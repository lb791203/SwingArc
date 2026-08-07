import SwiftUI

enum SimplifiedFeedbackDisplayPolicy {
    static func visibleMetrics(
        _ metrics: [SwingMetricValue]
    ) -> [SwingMetricValue] {
        Array(
            metrics.filter { metric in
                guard metric.id.isMotionAnalysisOutput,
                      metric.id.userFacingTitle != nil,
                      case .measured = metric.availability,
                      metric.value != nil
                else {
                    return false
                }
                return true
            }
            .prefix(3)
        )
    }

    static func stageCodes(
        _ stages: [SwingStage]
    ) -> [String] {
        stages.map(\.evidenceCode)
    }
}

#if DEBUG
enum SimplifiedFeedbackPreview {
    static func isEnabled(
        _ arguments: [String]
    ) -> Bool {
        arguments.contains("-swingarc-preview-feedback")
    }

    static func expandsHandPath(
        _ arguments: [String]
    ) -> Bool {
        arguments.contains("-swingarc-preview-feedback-expanded")
    }

    static let feedback = SimplifiedSwingFeedback(
        summary: SwingFeedbackSummary(
            title: "本次动作整体稳定",
            observation: "准备和身体控制较稳定，手部路径需要重点复核。",
            recommendation: "先检查 P3 到 P6 的手部运动，再修正对应阶段。",
            stages: [.leadArmParallelBackswing, .shaftParallelDownswing]
        ),
        cards: [
            card(.setup, .good, "站姿与身体轴线保持稳定。", [.address], .measured, 0.92),
            card(
                .bodyStability,
                .good,
                "头部与髋部位移处于稳定范围。",
                [.takeaway, .top, .impact],
                .measured,
                0.88
            ),
            card(
                .handPath,
                .attention,
                "下杆阶段手部路径略偏外。",
                [.leadArmParallelBackswing, .shaftParallelDownswing, .impact],
                .measured,
                0.84,
                metrics: [
                    metric(.handPathLength, 0.86, "身高", "P2-P7"),
                    metric(.leadElbowAngle, 151, "°", "P6")
                ]
            ),
            card(
                .swingPlane,
                .insufficientEvidence,
                "部分杆身点被遮挡，暂不判断挥杆平面。",
                [.takeaway, .top, .followThrough],
                .estimated,
                0.54
            ),
            card(
                .impactAndRelease,
                .insufficientEvidence,
                "击球区杆头与球位证据不足。",
                [.shaftParallelDownswing, .impact, .followThrough],
                .unavailable,
                0.38
            )
        ]
    )

    private static func card(
        _ category: SwingFeedbackCategory,
        _ status: SwingFeedbackStatus,
        _ conclusion: String,
        _ stages: [SwingStage],
        _ evidenceState: SwingFeedbackEvidenceState,
        _ confidence: Double,
        metrics: [SwingMetricValue] = []
    ) -> SwingFeedbackCard {
        SwingFeedbackCard(
            category: category,
            status: status,
            conclusion: conclusion,
            stages: stages,
            metrics: metrics,
            evidenceState: evidenceState,
            evidenceConfidence: confidence,
            attentionSeverity: status == .attention ? 2 : nil
        )
    }

    private static func metric(
        _ id: SwingMetricID,
        _ value: Double,
        _ unit: String,
        _ stage: String
    ) -> SwingMetricValue {
        SwingMetricValue(
            id: id,
            value: value,
            unit: unit,
            confidence: 0.86,
            stage: stage,
            availability: .measured
        )
    }
}
#endif

struct SimplifiedSwingFeedbackView: View {
    let feedback: SimplifiedSwingFeedback
    @Binding var expandedCategory: SwingFeedbackCategory?
    let onSelectStage: (SwingStage) -> Void
    let onAdjustStage: (SwingStage) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                summaryCard

                ForEach(feedback.cards) { card in
                    feedbackCard(card)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AnalysisTheme.proTourBackground)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(feedback.summary.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AnalysisTheme.proTourPrimaryText)

            Text(feedback.summary.observation)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AnalysisTheme.proTourPrimaryText.opacity(0.88))

            Label(
                feedback.summary.recommendation,
                systemImage: "arrow.turn.down.right"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AnalysisTheme.proTourSignal)

            if !feedback.summary.stages.isEmpty {
                stageChips(
                    feedback.summary.stages,
                    correctionEnabled: false
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            AnalysisTheme.proTourRaisedSurface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func feedbackCard(
        _ card: SwingFeedbackCard
    ) -> some View {
        let isExpanded = expandedCategory == card.category

        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedCategory = isExpanded ? nil : card.category
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(card.category.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AnalysisTheme.proTourPrimaryText)

                        Text(card.status.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(statusColor(card.status))
                    }

                    Spacer(minLength: 12)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(
                            isExpanded
                                ? AnalysisTheme.proTourSignal
                                : AnalysisTheme.proTourSecondaryText
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(card.conclusion)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AnalysisTheme.proTourPrimaryText.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            stageChips(card.stages, correctionEnabled: false)

            if isExpanded {
                Divider()
                    .overlay(.white.opacity(0.12))

                evidenceRow(card)

                let visibleMetrics = SimplifiedFeedbackDisplayPolicy.visibleMetrics(
                    card.metrics
                )
                if !visibleMetrics.isEmpty {
                    metricRows(visibleMetrics)
                }

                stageChips(card.stages, correctionEnabled: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(
            isExpanded
                ? AnalysisTheme.proTourRaisedSurface
                : AnalysisTheme.proTourSurface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isExpanded
                        ? AnalysisTheme.proTourSignal.opacity(0.48)
                        : .white.opacity(0.08),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(card.category.title)，\(card.status.title)，\(card.conclusion)"
        )
    }

    private func evidenceRow(
        _ card: SwingFeedbackCard
    ) -> some View {
        HStack {
            Label("证据", systemImage: "viewfinder")
                .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            Spacer()
            Text(card.evidenceState.title)
                .foregroundStyle(evidenceColor(card.evidenceState))
            Text("\(Int((card.evidenceConfidence * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(AnalysisTheme.proTourSecondaryText)
        }
        .font(.system(size: 13, weight: .semibold))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "证据\(card.evidenceState.title)，置信度\(Int((card.evidenceConfidence * 100).rounded()))%"
        )
    }

    private func metricRows(
        _ metrics: [SwingMetricValue]
    ) -> some View {
        VStack(spacing: 7) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                HStack {
                    Text(metric.id.userFacingTitle ?? "")
                        .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                    Spacer()
                    Text(metricValue(metric))
                        .monospacedDigit()
                        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                }
                .font(.system(size: 13, weight: .semibold))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func stageChips(
        _ stages: [SwingStage],
        correctionEnabled: Bool
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: correctionEnabled ? 82 : 42),
                    spacing: 8,
                    alignment: .leading
                )
            ],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(stages, id: \.rawValue) { stage in
                Button {
                    if correctionEnabled {
                        onAdjustStage(stage)
                    } else {
                        onSelectStage(stage)
                    }
                } label: {
                    Text(
                        correctionEnabled
                            ? "修正 \(stage.evidenceCode)"
                            : stage.evidenceCode
                    )
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        correctionEnabled
                            ? AnalysisTheme.proTourSignal
                            : AnalysisTheme.proTourPrimaryText
                    )
                    .padding(.horizontal, correctionEnabled ? 10 : 9)
                    .frame(minHeight: 30)
                    .background(
                        correctionEnabled
                            ? AnalysisTheme.proTourSignal.opacity(0.10)
                            : .white.opacity(0.07),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    correctionEnabled
                        ? "修正\(stage.shortName)"
                        : "查看\(stage.shortName)"
                )
            }
        }
    }

    private func statusColor(
        _ status: SwingFeedbackStatus
    ) -> Color {
        switch status {
        case .good:
            return AnalysisTheme.proTourSignal
        case .attention:
            return AnalysisTheme.proTourPaused
        case .insufficientEvidence:
            return AnalysisTheme.proTourSecondaryText
        }
    }

    private func evidenceColor(
        _ state: SwingFeedbackEvidenceState
    ) -> Color {
        switch state {
        case .measured:
            return AnalysisTheme.proTourSignal
        case .estimated:
            return AnalysisTheme.proTourPaused
        case .unavailable:
            return AnalysisTheme.proTourSecondaryText
        }
    }

    private func metricValue(
        _ metric: SwingMetricValue
    ) -> String {
        guard let value = metric.value else { return "—" }
        let formatted = abs(value.rounded() - value) < 0.01
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(formatted) \(metric.unit)"
    }
}

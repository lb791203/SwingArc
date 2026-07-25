import SwiftUI

struct LandmarkInspectorRowModel: Identifiable {
    let id: GolfLandmark
    let label: String
    let predictionPoint: GolfNormalizedPoint?
    let predictionConfidence: Double?
    let decisionPoint: GolfNormalizedPoint?
    let decisionKind: GolfAnnotationDecisionKind?

    var hasDecision: Bool { decisionKind != nil }
    var predictionDisplay: String { coordinateDisplay(predictionPoint) }
    var decisionDisplay: String { coordinateDisplay(decisionPoint) }

    private func coordinateDisplay(_ point: GolfNormalizedPoint?) -> String {
        guard let point else { return "—" }
        return String(format: "(%.4f, %.4f)", point.x, point.y)
    }
}

enum InspectorAction: String, CaseIterable {
    case acceptPrediction = "接受预测"
    case correctPoint = "修正坐标"
    case occluded = "遮挡"
    case outOfFrame = "出画"
    case unresolved = "无法确定"
}

struct DatasetKeypointInspector: View {
    let landmarks: [LandmarkInspectorRowModel]
    let predictionRunID: String
    let revisionID: String
    let isReviewed: Bool
    let isComplete: Bool
    let canSave: Bool
    let canAcceptFrame: Bool
    let isFrameEditable: Bool
    let allowsPredictionAcceptance: Bool
    let selectedLandmark: GolfLandmark?
    let onSelectLandmark: (GolfLandmark) -> Void
    let onAcceptPrediction: (GolfLandmark) -> Void
    let onCorrectPoint: (GolfLandmark) -> Void
    let onSetOccluded: (GolfLandmark) -> Void
    let onSetOutOfFrame: (GolfLandmark) -> Void
    let onSetUnresolved: (GolfLandmark) -> Void
    let onAcceptFrame: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Divider()
                ForEach(landmarks) { landmark in
                    landmarkSection(landmark)
                    if landmark.id != landmarks.last?.id { Divider() }
                }
                Divider()
                acceptFrameSection
            }
            .padding()
        }
        .frame(minWidth: 280)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("关键点检查器").font(.headline)
            Text("Prediction Run: \(predictionRunID)").font(.caption.monospaced()).foregroundColor(.secondary)
            Text("Revision: \(revisionID)").font(.caption.monospaced()).foregroundColor(.secondary)
            HStack(spacing: 8) {
                statusBadge("已复核", isReviewed, .green)
                statusBadge("可训练", isComplete, .blue)
                statusBadge("可保存", canSave, .purple)
            }
        }
    }

    private func statusBadge(_ title: String, _ condition: Bool, _ color: Color) -> some View {
        Text(title).font(.caption2).foregroundColor(condition ? color : .secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((condition ? color : .gray).opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }

    private func landmarkSection(_ landmark: LandmarkInspectorRowModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { onSelectLandmark(landmark.id) } label: {
                HStack {
                    Circle().fill(color(for: landmark.id)).frame(width: 10, height: 10)
                    Text(landmark.label).font(.subheadline.weight(.semibold))
                    Spacer()
                    if selectedLandmark == landmark.id { Image(systemName: "scope").foregroundColor(.accentColor) }
                    if landmark.hasDecision { Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption) }
                }
            }
            .buttonStyle(.plain)

            LabeledContent("预测坐标", value: landmark.predictionDisplay).font(.caption)
            LabeledContent("预测置信度", value: landmark.predictionConfidence.map { String(format: "%.3f", $0) } ?? "—").font(.caption)
            LabeledContent("人工坐标", value: landmark.decisionDisplay).font(.caption)
            if let decisionKind = landmark.decisionKind {
                LabeledContent("人工决定", value: decisionKind.rawValue).font(.caption)
            } else {
                Text("人工决定：未决定").font(.caption).foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                actionButton("接受预测", color: .green, enabled: isFrameEditable && allowsPredictionAcceptance && landmark.predictionPoint != nil) { onAcceptPrediction(landmark.id) }
                actionButton("修正坐标", color: .yellow, enabled: isFrameEditable) { onCorrectPoint(landmark.id) }
                actionButton("遮挡", color: .orange, enabled: isFrameEditable) { onSetOccluded(landmark.id) }
                actionButton("出画", color: .red, enabled: isFrameEditable) { onSetOutOfFrame(landmark.id) }
                actionButton("无法确定", color: .gray, enabled: isFrameEditable) { onSetUnresolved(landmark.id) }
            }
        }
    }

    private func actionButton(_ title: String, color: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption2).frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var acceptFrameSection: some View {
        VStack(spacing: 8) {
            Button("接受当前帧", action: onAcceptFrame)
                .buttonStyle(.borderedProminent)
                .disabled(!isFrameEditable || !canAcceptFrame)
                .controlSize(.large).frame(maxWidth: .infinity)
            if !canAcceptFrame {
                Text("存在既无预测也无明确决定的关键点").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func color(for landmark: GolfLandmark) -> Color {
        switch landmark {
        case .grip: .red
        case .shaftStart: .orange
        case .shaftEnd: .yellow
        case .clubhead: .green
        case .ball: .blue
        }
    }
}

#Preview {
    DatasetKeypointInspector(
        landmarks: GolfLandmark.allCases.map { LandmarkInspectorRowModel(id: $0, label: $0.rawValue, predictionPoint: nil, predictionConfidence: nil, decisionPoint: nil, decisionKind: nil) },
        predictionRunID: "—", revisionID: "—", isReviewed: false, isComplete: false, canSave: false, canAcceptFrame: false,
        isFrameEditable: false, allowsPredictionAcceptance: false, selectedLandmark: nil, onSelectLandmark: { _ in }, onAcceptPrediction: { _ in }, onCorrectPoint: { _ in },
        onSetOccluded: { _ in }, onSetOutOfFrame: { _ in }, onSetUnresolved: { _ in }, onAcceptFrame: {}
    )
}

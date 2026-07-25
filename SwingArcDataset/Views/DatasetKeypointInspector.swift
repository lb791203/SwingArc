import SwiftUI

/// View model for a single landmark row in the inspector.
struct LandmarkInspectorRowModel: Identifiable {
    let id: GolfLandmark
    let label: String
    let coordinate: GolfNormalizedPoint?
    let isPredicted: Bool
    let hasDecision: Bool
    let decisionKind: GolfAnnotationDecisionKind?

    var coordinateDisplay: String {
        guard let pt = coordinate else { return "—" }
        return String(format: "(%.4f, %.4f)", pt.x, pt.y)
    }
}

/// UI actions that map 1:1 to GolfAnnotationDecisionKind.
/// This is the only decision schema — no second persistent schema.
enum InspectorAction: String, CaseIterable {
    case acceptPrediction = "接受预测"
    case correctPoint = "修正坐标"
    case occluded = "遮挡"
    case outOfFrame = "出画"
    case unresolved = "无法确定"

    var systemImage: String {
        switch self {
        case .acceptPrediction: return "checkmark.circle"
        case .correctPoint: return "hand.draw"
        case .occluded: return "eye.slash"
        case .outOfFrame: return "rectangle.slash"
        case .unresolved: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .acceptPrediction: return .green
        case .correctPoint: return .yellow
        case .occluded: return .orange
        case .outOfFrame: return .red
        case .unresolved: return .gray
        }
    }
}

// MARK: - DatasetKeypointInspector

struct DatasetKeypointInspector: View {
    /// Rows for each of the five landmarks.
    let landmarks: [LandmarkInspectorRowModel]

    /// Prediction run ID for context.
    let predictionRunID: String

    /// Revision ID for context.
    let revisionID: String

    /// Whether the current frame has all five decisions (reviewed).
    let isReviewed: Bool

    /// Whether the current frame is complete for training export.
    let isComplete: Bool

    /// Whether the frame can be saved.
    let canSave: Bool

    /// Whether the "Accept Current Frame" button should be enabled.
    let canAcceptFrame: Bool

    /// Callbacks for each decision kind per landmark.
    let onAcceptPrediction: (GolfLandmark) -> Void
    let onCorrectPoint: (GolfLandmark) -> Void
    let onSetOccluded: (GolfLandmark) -> Void
    let onSetOutOfFrame: (GolfLandmark) -> Void
    let onSetUnresolved: (GolfLandmark) -> Void
    let onAcceptFrame: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerSection

                Divider()

                // Per-landmark rows
                ForEach(landmarks) { landmark in
                    landmarkSection(landmark)
                    if landmark.id != landmarks.last?.id {
                        Divider()
                    }
                }

                Divider()

                // Accept current frame
                acceptFrameSection
            }
            .padding()
        }
        .frame(minWidth: 260)
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("关键点检查器")
                .font(.headline)

            HStack {
                Text("Prediction Run:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(predictionRunID)
                    .font(.caption.monospaced())
            }

            HStack {
                Text("Revision:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(revisionID)
                    .font(.caption.monospaced())
            }

            HStack(spacing: 8) {
                statusBadge("已复核", condition: isReviewed, color: .green)
                statusBadge("可训练", condition: isComplete, color: .blue)
                statusBadge("可保存", condition: canSave, color: .purple)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ label: String, condition: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(condition ? color : Color.gray)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundColor(condition ? color : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            (condition ? color : Color.gray).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 4)
        )
    }

    @ViewBuilder
    private func landmarkSection(_ landmark: LandmarkInspectorRowModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Landmark header
            HStack {
                Circle()
                    .fill(color(for: landmark.id))
                    .frame(width: 10, height: 10)
                Text(landmark.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if landmark.hasDecision {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }

            // Coordinate display
            LabeledContent("原片坐标", value: landmark.coordinateDisplay)
                .font(.caption)

            // Decision kind display
            if let kind = landmark.decisionKind {
                LabeledContent("当前决定") {
                    Text(kind.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Action buttons
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 6) {
                actionButton(
                    title: "接受预测",
                    systemImage: "checkmark.circle",
                    color: .green
                ) {
                    onAcceptPrediction(landmark.id)
                }

                actionButton(
                    title: "修正坐标",
                    systemImage: "hand.draw",
                    color: .yellow
                ) {
                    onCorrectPoint(landmark.id)
                }

                actionButton(
                    title: "遮挡",
                    systemImage: "eye.slash",
                    color: .orange
                ) {
                    onSetOccluded(landmark.id)
                }

                actionButton(
                    title: "出画",
                    systemImage: "rectangle.slash",
                    color: .red
                ) {
                    onSetOutOfFrame(landmark.id)
                }

                actionButton(
                    title: "无法确定",
                    systemImage: "questionmark.circle",
                    color: .gray
                ) {
                    onSetUnresolved(landmark.id)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color.opacity(0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var acceptFrameSection: some View {
        VStack(spacing: 8) {
            Button("接受当前帧") {
                onAcceptFrame()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAcceptFrame)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            if !canAcceptFrame {
                Text("存在既无预测也无明确决定的关键点")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func color(for landmark: GolfLandmark) -> Color {
        switch landmark {
        case .grip: return .red
        case .shaftStart: return .orange
        case .shaftEnd: return .yellow
        case .clubhead: return .green
        case .ball: return .blue
        }
    }
}

#Preview {
    DatasetKeypointInspector(
        landmarks: GolfLandmark.allCases.map { landmark in
            LandmarkInspectorRowModel(
                id: landmark,
                label: landmark.rawValue,
                coordinate: GolfNormalizedPoint(x: 0.4, y: 0.6),
                isPredicted: true,
                hasDecision: true,
                decisionKind: .acceptedPrediction
            )
        },
        predictionRunID: "pred-run-001",
        revisionID: "rev-001",
        isReviewed: true,
        isComplete: true,
        canSave: true,
        canAcceptFrame: true,
        onAcceptPrediction: { _ in },
        onCorrectPoint: { _ in },
        onSetOccluded: { _ in },
        onSetOutOfFrame: { _ in },
        onSetUnresolved: { _ in },
        onAcceptFrame: {}
    )
    .frame(width: 280)
}

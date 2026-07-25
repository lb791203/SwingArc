import SwiftUI

/// Timeline position marker for P1–P8 stages.
struct TimelineStageMarker: Identifiable {
    let id: String
    let label: String
    let sourceFrameIndex: Int
    let isConfirmed: Bool
}

/// A compact timeline bar showing P1–P8 position, current frame, and navigation buttons.
struct DatasetTimelineView: View {
    let totalFrames: Int
    let currentFrame: Int
    let stages: [TimelineStageMarker]
    let onStep: (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Navigation buttons
            HStack(spacing: 12) {
                stepButton(amount: -5, label: "−5")
                stepButton(amount: -1, label: "−1")
                Spacer()

                VStack(spacing: 2) {
                    Text(totalFrames > 0 ? "帧 \(currentFrame + 1) / \(totalFrames)" : "无媒体帧")
                        .font(.caption.monospacedDigit())
                    Text("源帧 \(currentFrame)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
                stepButton(amount: +1, label: "+1")
                stepButton(amount: +5, label: "+5")
            }

            // Timeline bar
            GeometryReader { geometry in
                let barWidth = geometry.size.width
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    // Stage markers
                    ForEach(stages) { stage in
                        let ratio = totalFrames > 1
                            ? CGFloat(stage.sourceFrameIndex) / CGFloat(totalFrames - 1)
                            : 0.0
                        let position = ratio * barWidth
                        VStack(spacing: 2) {
                            Circle()
                                .fill(stage.isConfirmed ? Color.accentColor : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(stage.label)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(stage.isConfirmed ? .primary : .secondary)
                        }
                        .position(x: position, y: 8)
                        .frame(width: 20, height: 24)
                    }

                    // Current frame indicator
                    let currentRatio = totalFrames > 1
                        ? CGFloat(currentFrame) / CGFloat(totalFrames - 1)
                        : 0.0
                    let currentPosition = currentRatio * barWidth
                    Triangle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 8)
                        .position(x: currentPosition, y: -4)
                }
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func stepButton(amount: Int, label: String) -> some View {
        Button {
            onStep(amount)
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .frame(minWidth: 36, minHeight: 32)
                .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(totalFrames <= 0)
        .help("移动 \(label) 帧")
    }
}

/// Small triangle shape for the current-frame indicator.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    DatasetTimelineView(
        totalFrames: 757,
        currentFrame: 542,
        stages: [
            TimelineStageMarker(id: "P1", label: "P1", sourceFrameIndex: 100, isConfirmed: true),
            TimelineStageMarker(id: "P2", label: "P2", sourceFrameIndex: 140, isConfirmed: true),
            TimelineStageMarker(id: "P3", label: "P3", sourceFrameIndex: 175, isConfirmed: true),
            TimelineStageMarker(id: "P4", label: "P4", sourceFrameIndex: 210, isConfirmed: false),
            TimelineStageMarker(id: "P5", label: "P5", sourceFrameIndex: 250, isConfirmed: false),
            TimelineStageMarker(id: "P6", label: "P6", sourceFrameIndex: 280, isConfirmed: false),
            TimelineStageMarker(id: "P7", label: "P7", sourceFrameIndex: 310, isConfirmed: false),
            TimelineStageMarker(id: "P8", label: "P8", sourceFrameIndex: 340, isConfirmed: false),
        ],
        onStep: { _ in }
    )
    .frame(height: 80)
    .padding()
}

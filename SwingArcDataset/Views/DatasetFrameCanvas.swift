import SwiftUI

/// A single landmark point as displayed on the canvas.
struct CanvasLandmarkPoint: Identifiable {
    let id: GolfLandmark
    let label: String
    let normalizedPoint: GolfNormalizedPoint
    let isPrediction: Bool
    let isSelected: Bool

    static func from(decision: GolfAnnotationDecision, prediction: GolfPredictionPoint?) -> Self? {
        guard let point = decision.fullFramePoint else { return nil }
        guard decision.kind == .acceptedPrediction || decision.kind == .correctedPoint else {
            return nil
        }
        return CanvasLandmarkPoint(
            id: decision.landmark,
            label: decision.landmark.rawValue,
            normalizedPoint: point,
            isPrediction: decision.kind == .acceptedPrediction,
            isSelected: false
        )
    }
}

/// Shaft line between shaftStart and shaftEnd, drawn only when both are visible.
struct CanvasShaftLine {
    let start: CGPoint
    let end: CGPoint
}

/// Adjacent-frame trail entry showing where a landmark was in nearby frames.
struct CanvasTrailPoint: Identifiable {
    let id = UUID()
    let landmark: GolfLandmark
    let point: CGPoint
    let frameDelta: Int // e.g., -1, +1, -5, +5
}

// MARK: - DatasetFrameCanvas

/// The center annotation canvas displaying the full frame or ROI crop,
/// with keypoints, shaft line, adjacent-frame trails, and Vision skeleton.
struct DatasetFrameCanvas: View {
    /// The source image to display (full frame or ROI).
    let frameImage: CGImage?
    let imageSize: CGSize

    /// Whether we are showing the 512×512 ROI crop rather than the full frame.
    var showsROI: Bool = false

    /// Five resolved landmark points to draw.
    let landmarkPoints: [CanvasLandmarkPoint]

    /// Selected landmark for highlighting.
    let selectedLandmark: GolfLandmark?

    /// Adjacent-frame trail points (keyed by landmark, value is list of (delta, point)).
    let trailPoints: [CanvasLandmark: [(delta: Int, point: GolfNormalizedPoint)]]

    /// Available ROI transform for converting between coordinate spaces.
    let roiTransform: GolfROIAffineTransform?

    /// Callback when the user taps/drags to correct a point.
    let onCorrectPoint: (GolfLandmark, GolfNormalizedPoint) -> Void

    /// Toggle between full frame and ROI view.
    let onToggleROI: () -> Void

    /// Loading state for the frame image.
    let isLoading: Bool

    /// Error/status message.
    let statusMessage: String?

    @State private var dragLocation: CGPoint?
    @State private var zoom: CGFloat = 1.0
    @State private var zoomAtGestureStart: CGFloat = 1.0

    private let landmarkColors: [GolfLandmark: Color] = [
        .grip: .red,
        .shaftStart: .orange,
        .shaftEnd: .yellow,
        .clubhead: .green,
        .ball: .blue
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button(showsROI ? "原片" : "512 × 512 ROI") {
                    onToggleROI()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Canvas
            GeometryReader { geometry in
                let containerSize = geometry.size
                let imageRect = aspectFitRect(imageSize: imageSize, containerSize: containerSize)

                ZStack {
                    Color.black

                    if let image = frameImage {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(
                                width: imageRect.width,
                                height: imageRect.height
                            )
                            .position(
                                x: imageRect.midX,
                                y: imageRect.midY
                            )
                    } else if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("无可用帧数据")
                            .foregroundColor(.secondary)
                    }

                    // Draw adjacent frame trails
                    for (landmark, trails) in trailPoints {
                        ForEach(trails, id: \.delta) { trail in
                            let trailCG = CGPoint(
                                x: imageRect.minX + CGFloat(trail.point.x) * imageRect.width,
                                y: imageRect.minY + CGFloat(trail.point.y) * imageRect.height
                            )
                            // Transparency decreases with distance
                            let alpha = max(0.2, 1.0 - Double(abs(trail.delta)) * 0.15)
                            Circle()
                                .fill(landmarkColors[landmark]?.opacity(alpha) ?? Color.gray.opacity(alpha))
                                .frame(width: 6, height: 6)
                                .position(trailCG)
                        }
                    }

                    // Draw shaft line if both shaftStart and shaftEnd are visible
                    if let shaftStart = landmarkPoints.first(where: { $0.id == .shaftStart }),
                       let shaftEnd = landmarkPoints.first(where: { $0.id == .shaftEnd }) {
                        let startCG = CGPoint(
                            x: imageRect.minX + CGFloat(shaftStart.normalizedPoint.x) * imageRect.width,
                            y: imageRect.minY + CGFloat(shaftStart.normalizedPoint.y) * imageRect.height
                        )
                        let endCG = CGPoint(
                            x: imageRect.minX + CGFloat(shaftEnd.normalizedPoint.x) * imageRect.width,
                            y: imageRect.minY + CGFloat(shaftEnd.normalizedPoint.y) * imageRect.height
                        )
                        Path { path in
                            path.move(to: startCG)
                            path.addLine(to: endCG)
                        }
                        .stroke(Color.orange, lineWidth: 2)
                    }

                    // Draw landmark points
                    ForEach(landmarkPoints) { point in
                        let cgPoint = CGPoint(
                            x: imageRect.minX + CGFloat(point.normalizedPoint.x) * imageRect.width,
                            y: imageRect.minY + CGFloat(point.normalizedPoint.y) * imageRect.height
                        )
                        let isSelected = point.id == selectedLandmark
                        let color = landmarkColors[point.id] ?? Color.white

                        ZStack {
                            Circle()
                                .fill(color.opacity(0.85))
                            Circle()
                                .stroke(
                                    point.isPrediction ? Color.white.opacity(0.7) : Color.black,
                                    style: StrokeStyle(
                                        lineWidth: isSelected ? 3 : 2,
                                        dash: point.isPrediction ? [3, 3] : []
                                    )
                                )
                            Text(point.label.prefix(2).uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: isSelected ? 24 : 18, height: isSelected ? 24 : 18)
                        .position(cgPoint)
                    }
                }
                .scaleEffect(zoom)
                .clipped()
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = min(8, max(1, zoomAtGestureStart * value))
                        }
                        .onEnded { _ in
                            zoomAtGestureStart = zoom
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        zoom = 1
                        zoomAtGestureStart = 1
                    }
                }
            }
        }
    }

    /// Compute the aspect-fit rect for the image within the container.
    private func aspectFitRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        var rect: CGRect = .zero
        if abs(imageAspect - containerAspect) < 0.001 {
            rect.size = containerSize
        } else if imageAspect > containerAspect {
            // Image is wider: constrain by width
            rect.size.width = containerSize.width
            rect.size.height = containerSize.width / imageAspect
        } else {
            // Image is taller: constrain by height
            rect.size.height = containerSize.height
            rect.size.width = containerSize.height * imageAspect
        }
        rect.origin.x = (containerSize.width - rect.width) / 2
        rect.origin.y = (containerSize.height - rect.height) / 2
        return rect
    }
}

#Preview {
    DatasetFrameCanvas(
        frameImage: nil,
        imageSize: CGSize(width: 1920, height: 1080),
        landmarkPoints: [],
        selectedLandmark: nil,
        trailPoints: [:],
        roiTransform: nil,
        onCorrectPoint: { _, _ in },
        onToggleROI: {},
        isLoading: false,
        statusMessage: nil
    )
    .frame(width: 800, height: 500)
}

import SwiftUI

struct AnnotationFrameCanvas: View {
    let image: CGImage?
    let points: [String: AnnotationPoint]
    let selectedLandmark: String?
    let onMovePoint: (String, AnnotationPoint) -> Void

    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1
    @State private var dragLocation: CGPoint?

    private let coordinateSpaceName = "annotation-frame-canvas"

    var body: some View {
        GeometryReader { geometry in
            let imageRect = fittedImageRect(in: geometry.size)
            ZStack {
                Color.black

                if let image {
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
                } else {
                    ProgressView()
                        .tint(AnalysisTheme.proTourSignal)
                }

                landmarkLayer(
                    imageRect: imageRect,
                    containerSize: geometry.size
                )

                if let dragLocation, let image {
                    magnifier(
                        image: image,
                        at: dragLocation,
                        imageRect: imageRect,
                        containerSize: geometry.size
                    )
                }
            }
            .scaleEffect(zoom)
            .clipped()
            .contentShape(Rectangle())
            .coordinateSpace(name: coordinateSpaceName)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged {
                        zoom = min(8, max(1, zoomAtGestureStart * $0))
                    }
                    .onEnded { _ in
                        zoomAtGestureStart = zoom
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                    .onEnded { value in
                        setSelectedPoint(
                            at: value.location,
                            imageRect: imageRect,
                            containerSize: geometry.size
                        )
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.18)) {
                    zoom = 1
                    zoomAtGestureStart = 1
                }
            }
            .accessibilityLabel("标注画面")
        }
    }

    @ViewBuilder
    private func landmarkLayer(
        imageRect: CGRect,
        containerSize: CGSize
    ) -> some View {
        ForEach(points.keys.sorted(), id: \.self) { landmark in
            if let point = points[landmark],
               point.visibility == .visible,
               let x = point.x,
               let y = point.y {
                let position = CGPoint(
                    x: imageRect.minX + CGFloat(x) * imageRect.width,
                    y: imageRect.minY + CGFloat(y) * imageRect.height
                )
                landmarkMarker(
                    landmark: landmark,
                    point: point,
                    position: position,
                    imageRect: imageRect,
                    containerSize: containerSize
                )
            }
        }
    }

    private func landmarkMarker(
        landmark: String,
        point: AnnotationPoint,
        position: CGPoint,
        imageRect: CGRect,
        containerSize: CGSize
    ) -> some View {
        let selected = landmark == selectedLandmark
        return ZStack {
            Circle()
                .fill(
                    selected
                        ? AnalysisTheme.proTourSignal
                        : AnalysisTheme.proTourPrimaryText
                )
            Circle()
                .stroke(
                    point.source == .predicted
                        ? AnalysisTheme.proTourSignal.opacity(0.72)
                        : Color.black,
                    style: StrokeStyle(
                        lineWidth: selected ? 3 : 2,
                        dash: point.source == .predicted ? [4, 3] : []
                    )
                )
        }
        .frame(width: selected ? 24 : 18, height: selected ? 24 : 18)
        .position(position)
        .contentShape(Circle().inset(by: -12))
        .gesture(
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(coordinateSpaceName)
            )
            .onChanged { value in
                dragLocation = value.location
                move(
                    landmark: landmark,
                    original: point,
                    to: value.location,
                    imageRect: imageRect,
                    containerSize: containerSize
                )
            }
            .onEnded { _ in
                dragLocation = nil
            }
        )
        .accessibilityLabel(landmark)
        .accessibilityValue(
            point.source == .manual ? "人工标注" : "预测标注"
        )
    }

    private func magnifier(
        image: CGImage,
        at location: CGPoint,
        imageRect: CGRect,
        containerSize: CGSize
    ) -> some View {
        let base = inverseZoomed(
            location,
            containerSize: containerSize
        )
        let anchor = UnitPoint(
            x: imageRect.width > 0
                ? (base.x - imageRect.minX) / imageRect.width
                : 0.5,
            y: imageRect.height > 0
                ? (base.y - imageRect.minY) / imageRect.height
                : 0.5
        )
        return ZStack {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .scaleEffect(2, anchor: anchor)
            Circle()
                .stroke(AnalysisTheme.proTourSignal, lineWidth: 2)
            Path { path in
                path.move(to: CGPoint(x: 44, y: 60))
                path.addLine(to: CGPoint(x: 76, y: 60))
                path.move(to: CGPoint(x: 60, y: 44))
                path.addLine(to: CGPoint(x: 60, y: 76))
            }
            .stroke(AnalysisTheme.proTourSignal, lineWidth: 1)
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        .background(Color.black, in: Circle())
        .position(
            x: min(max(70, location.x), containerSize.width - 70),
            y: max(70, location.y - 90)
        )
        .allowsHitTesting(false)
    }

    private func fittedImageRect(in containerSize: CGSize) -> CGRect {
        guard let image else { return .zero }
        return AnnotationCanvasGeometry.aspectFitRect(
            imageSize: CGSize(width: image.width, height: image.height),
            containerSize: containerSize
        )
    }

    private func setSelectedPoint(
        at location: CGPoint,
        imageRect: CGRect,
        containerSize: CGSize
    ) {
        guard let selectedLandmark else { return }
        let base = inverseZoomed(location, containerSize: containerSize)
        guard imageRect.contains(base) else { return }
        let normalized = AnnotationCanvasGeometry.normalizedPoint(
            location: base,
            imageRect: imageRect
        )
        var point = points[selectedLandmark] ?? AnnotationPoint(
            x: nil,
            y: nil,
            visibility: .visible,
            source: .manual,
            confidence: nil
        )
        point.x = Double(normalized.x)
        point.y = Double(normalized.y)
        point.visibility = .visible
        point.source = .manual
        point.confidence = nil
        onMovePoint(selectedLandmark, point)
    }

    private func move(
        landmark: String,
        original: AnnotationPoint,
        to location: CGPoint,
        imageRect: CGRect,
        containerSize: CGSize
    ) {
        let base = inverseZoomed(location, containerSize: containerSize)
        let normalized = AnnotationCanvasGeometry.normalizedPoint(
            location: base,
            imageRect: imageRect
        )
        var moved = original
        moved.x = Double(normalized.x)
        moved.y = Double(normalized.y)
        moved.visibility = .visible
        moved.source = .manual
        moved.confidence = nil
        onMovePoint(landmark, moved)
    }

    private func inverseZoomed(
        _ point: CGPoint,
        containerSize: CGSize
    ) -> CGPoint {
        let center = CGPoint(
            x: containerSize.width / 2,
            y: containerSize.height / 2
        )
        return CGPoint(
            x: center.x + (point.x - center.x) / zoom,
            y: center.y + (point.y - center.y) / zoom
        )
    }
}

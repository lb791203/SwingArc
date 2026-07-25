import SwiftUI

struct CanvasLandmarkPoint: Identifiable {
    let id: GolfLandmark
    let label: String
    let fullFramePoint: GolfNormalizedPoint
    let isPrediction: Bool
}

/// Adjacent-frame evidence is always supplied in full-frame coordinates.
struct DatasetTrailPoint: Identifiable {
    let landmark: GolfLandmark
    let fullFramePoint: GolfNormalizedPoint
    let frameDelta: Int

    var id: String { "\(landmark.rawValue)-\(frameDelta)-\(fullFramePoint.x)-\(fullFramePoint.y)" }
}

/// The canvas deliberately has no zoom transform: hit testing must use the same
/// aspect-fit image rect that renders the source pixels.
struct DatasetFrameCanvas: View {
    let fullFrameImage: CGImage?
    let roiImage: CGImage?
    let fullFrameImageSize: CGSize
    let roiImageSize: CGSize
    var showsROI: Bool = false
    let landmarkPoints: [CanvasLandmarkPoint]
    let selectedLandmark: GolfLandmark?
    let trailPoints: [GolfLandmark: [(delta: Int, point: GolfNormalizedPoint)]]
    let visionSkeleton: [GolfNormalizedPoint]?
    let roiTransform: GolfROIAffineTransform?
    let onCorrectPoint: (GolfLandmark, GolfNormalizedPoint) -> Void
    let onToggleROI: () -> Void
    let isLoading: Bool
    let statusMessage: String?

    private let landmarkColors: [GolfLandmark: Color] = [
        .grip: .red, .shaftStart: .orange, .shaftEnd: .yellow, .clubhead: .green, .ball: .blue
    ]

    private var displayedImage: CGImage? { showsROI ? roiImage : fullFrameImage }
    private var displayedImageSize: CGSize { showsROI ? roiImageSize : fullFrameImageSize }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(showsROI ? "原片" : "512 × 512 ROI", action: onToggleROI)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(showsROI ? fullFrameImage == nil : roiImage == nil)
                Spacer()
                if let statusMessage {
                    Text(statusMessage).font(.caption).foregroundColor(.secondary)
                }
                if isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            GeometryReader { geometry in
                let imageRect = aspectFitRect(imageSize: displayedImageSize, containerSize: geometry.size)
                ZStack {
                    Color.black
                    if let image = displayedImage {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: imageRect.width, height: imageRect.height)
                            .position(x: imageRect.midX, y: imageRect.midY)
                    } else if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("无可用帧数据").foregroundColor(.secondary)
                    }

                    drawSkeleton(in: imageRect)
                    drawTrails(in: imageRect)
                    drawShaft(in: imageRect)
                    drawLandmarks(in: imageRect)
                }
                .contentShape(Rectangle())
                .gesture(correctionGesture(in: imageRect))
            }
        }
    }

    @ViewBuilder
    private func drawSkeleton(in imageRect: CGRect) -> some View {
        if let skeleton = visionSkeleton {
            let points = skeleton.compactMap(displayPoint)
            if points.count > 1 {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: screenPoint(first, in: imageRect))
                    for point in points.dropFirst() { path.addLine(to: screenPoint(point, in: imageRect)) }
                }
                .stroke(.cyan.opacity(0.65), lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private func drawTrails(in imageRect: CGRect) -> some View {
        ForEach(trailEntries) { trail in
            if let display = displayPoint(trail.fullFramePoint) {
                Circle()
                    .fill((landmarkColors[trail.landmark] ?? .gray).opacity(max(0.2, 1 - Double(abs(trail.frameDelta)) * 0.15)))
                    .frame(width: 6, height: 6)
                    .position(screenPoint(display, in: imageRect))
            }
        }
    }

    @ViewBuilder
    private func drawShaft(in imageRect: CGRect) -> some View {
        if let start = landmarkPoints.first(where: { $0.id == .shaftStart }).flatMap({ displayPoint($0.fullFramePoint) }),
           let end = landmarkPoints.first(where: { $0.id == .shaftEnd }).flatMap({ displayPoint($0.fullFramePoint) }) {
            Path { path in
                path.move(to: screenPoint(start, in: imageRect))
                path.addLine(to: screenPoint(end, in: imageRect))
            }
            .stroke(.orange, lineWidth: 2)
        }
    }

    @ViewBuilder
    private func drawLandmarks(in imageRect: CGRect) -> some View {
        ForEach(landmarkPoints) { landmark in
            if let display = displayPoint(landmark.fullFramePoint) {
                let isSelected = landmark.id == selectedLandmark
                let color = landmarkColors[landmark.id] ?? .white
                ZStack {
                    Circle().fill(color.opacity(0.85))
                    Circle().stroke(
                        landmark.isPrediction ? Color.white.opacity(0.7) : .black,
                        style: StrokeStyle(lineWidth: isSelected ? 3 : 2, dash: landmark.isPrediction ? [3, 3] : [])
                    )
                    Text(landmark.label.prefix(2).uppercased())
                        .font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                }
                .frame(width: isSelected ? 24 : 18, height: isSelected ? 24 : 18)
                .position(screenPoint(display, in: imageRect))
            }
        }
    }

    private var trailEntries: [DatasetTrailPoint] {
        trailPoints.flatMap { landmark, points in
            points.map { DatasetTrailPoint(landmark: landmark, fullFramePoint: $0.point, frameDelta: $0.delta) }
        }
    }

    private func correctionGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { gesture in
                guard let landmark = selectedLandmark,
                      imageRect.contains(gesture.location),
                      imageRect.width > 0, imageRect.height > 0 else { return }
                let imagePoint = GolfNormalizedPoint(
                    x: Double((gesture.location.x - imageRect.minX) / imageRect.width),
                    y: Double((gesture.location.y - imageRect.minY) / imageRect.height)
                )
                guard isUnitPoint(imagePoint) else { return }
                let fullFramePoint = showsROI
                    ? safeROIToFullFrame(imagePoint)
                    : imagePoint
                guard let fullFramePoint, isUnitPoint(fullFramePoint) else { return }
                onCorrectPoint(landmark, fullFramePoint)
            }
    }

    private func displayPoint(_ fullFramePoint: GolfNormalizedPoint) -> GolfNormalizedPoint? {
        guard isUnitPoint(fullFramePoint) else { return nil }
        guard showsROI else { return fullFramePoint }
        return safeFullFrameToROI(fullFramePoint)
    }

    private func safeFullFrameToROI(_ point: GolfNormalizedPoint) -> GolfNormalizedPoint? {
        guard let transform = usableROITransform else { return nil }
        let mapped = transform.fullFramePointToROI(point)
        return isUnitPoint(mapped) ? mapped : nil
    }

    private func safeROIToFullFrame(_ point: GolfNormalizedPoint) -> GolfNormalizedPoint? {
        guard let transform = usableROITransform else { return nil }
        let mapped = transform.roiPointToFullFrame(point)
        return isUnitPoint(mapped) ? mapped : nil
    }

    private var usableROITransform: GolfROIAffineTransform? {
        guard let roiTransform else { return nil }
        let values = [roiTransform.a, roiTransform.b, roiTransform.c, roiTransform.d, roiTransform.tx, roiTransform.ty,
                      roiTransform.invA, roiTransform.invB, roiTransform.invC, roiTransform.invD, roiTransform.invTx, roiTransform.invTy]
        guard values.allSatisfy(\.isFinite),
              abs(roiTransform.a * roiTransform.d - roiTransform.b * roiTransform.c) > 0.000_000_001,
              abs(roiTransform.invA * roiTransform.invD - roiTransform.invB * roiTransform.invC) > 0.000_000_001 else { return nil }
        return roiTransform
    }

    private func screenPoint(_ point: GolfNormalizedPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(point.x) * rect.width, y: rect.minY + CGFloat(point.y) * rect.height)
    }

    private func isUnitPoint(_ point: GolfNormalizedPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    private func aspectFitRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (containerSize.width - size.width) / 2, y: (containerSize.height - size.height) / 2, width: size.width, height: size.height)
    }
}

#Preview {
    DatasetFrameCanvas(
        fullFrameImage: nil, roiImage: nil,
        fullFrameImageSize: CGSize(width: 1920, height: 1080), roiImageSize: CGSize(width: 512, height: 512),
        landmarkPoints: [], selectedLandmark: nil, trailPoints: [:], visionSkeleton: nil, roiTransform: nil,
        onCorrectPoint: { _, _ in }, onToggleROI: {}, isLoading: false, statusMessage: nil
    )
    .frame(width: 800, height: 500)
}

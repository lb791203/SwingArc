import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 绘图工具类型
enum DrawingTool: String, CaseIterable, Identifiable, Codable {
    case select = "选择"
    case line = "直线"
    case arrow = "箭头"
    case circle = "圆圈"
    case angle = "量角器"
    case freehand = "手绘"
    
    var id: String { self.rawValue }
    
    var iconName: String {
        switch self {
        case .select: return "hand.tap"
        case .line: return "minus"
        case .arrow: return "arrow.up.right"
        case .circle: return "circle"
        case .angle: return "angle"
        case .freehand: return "scribble"
        }
    }

    var revealsColorPalette: Bool {
        self == .line || self == .arrow
    }
}

enum ArrowGeometry {
    static func headPoints(
        start: CGPoint,
        end: CGPoint,
        length: CGFloat,
        spread: CGFloat = .pi / 7
    ) -> (left: CGPoint, right: CGPoint)? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard hypot(dx, dy) > 0.001 else { return nil }

        let direction = atan2(dy, dx)
        return (
            left: CGPoint(
                x: end.x - length * cos(direction - spread),
                y: end.y - length * sin(direction - spread)
            ),
            right: CGPoint(
                x: end.x - length * cos(direction + spread),
                y: end.y - length * sin(direction + spread)
            )
        )
    }
}

/// 挥杆关键帧节点 (高尔夫标准 P 阶段)
enum SwingStage: String, CaseIterable, Identifiable, Codable {
    case address = "准备姿势 (Address)"
    case takeaway = "起杆 (Takeaway)"
    case leadArmParallelBackswing = "上杆左臂平行 (Lead Arm Parallel)"
    case top = "上杆顶点 (Top)"
    case leadArmParallelDownswing = "下杆左臂平行 (Lead Arm Parallel)"
    case shaftParallelDownswing = "下杆杆身平行 (Shaft Parallel)"
    case impact = "击球瞬间 (Impact)"
    case followThrough = "送杆 (Follow-Through)"
    case finish = "收杆 (Finish)"

    /// The canonical P-system track. `.finish` remains decodable so stored
    /// projects retain their historical marker, but it is not a P1–P8 stage.
    static let pStages: [SwingStage] = [
        .address,
        .takeaway,
        .leadArmParallelBackswing,
        .top,
        .leadArmParallelDownswing,
        .shaftParallelDownswing,
        .impact,
        .followThrough
    ]

    static let allCases = pStages
    
    var id: String { self.rawValue }
    
    var shortName: String {
        switch self {
        case .address: return "P1 准备"
        case .takeaway: return "P2 起杆"
        case .leadArmParallelBackswing: return "P3 上杆"
        case .top: return "P4 顶点"
        case .leadArmParallelDownswing: return "P5 下杆"
        case .shaftParallelDownswing: return "P6 杆身平行"
        case .impact: return "P7 击球"
        case .followThrough: return "P8 释放"
        case .finish: return "收杆（兼容）"
        }
    }
    
    var color: Color {
        switch self {
        case .address: return .blue
        case .takeaway: return .purple
        case .leadArmParallelBackswing: return .cyan
        case .top: return .orange
        case .leadArmParallelDownswing: return .yellow
        case .shaftParallelDownswing: return .purple
        case .impact: return .red
        case .followThrough: return .indigo
        case .finish: return .green
        }
    }
}

/// 录制的关键帧标记数据
enum KeyframeSource: String, Codable, Equatable {
    case automatic
    case manual
}

enum KeyframeAutomaticStatus: String, Codable, Equatable {
    case confirmed
    case lowConfidence
}

enum KeyframeEvidenceSource: String, Codable, Hashable {
    case bodyPose
    case grip
    case shaft
    case clubhead
    case ball
    case temporalTransition
    case manual
}

struct KeyframeEvidenceSnapshot: Codable, Equatable {
    let sources: Set<KeyframeEvidenceSource>
    let detectedPointCount: Int
    let estimatedPointCount: Int
    let hasClubEvidence: Bool
    let hasBallEvidence: Bool
    let hasBallChangeEvidence: Bool
}

struct KeyframeMarker: Identifiable, Codable, Equatable {
    let id: UUID
    let time: Double // 视频时间（秒）
    let stage: String // SwingStage rawValue
    let source: KeyframeSource
    let sourceFrameIndex: Int?
    let automaticStatus: KeyframeAutomaticStatus?
    let automaticConfidence: Double?
    let automaticEvidence: KeyframeEvidenceSnapshot?
    
    init(
        id: UUID = UUID(),
        time: Double,
        stage: SwingStage,
        source: KeyframeSource = .automatic,
        sourceFrameIndex: Int? = nil,
        automaticStatus: KeyframeAutomaticStatus? = nil,
        automaticConfidence: Double? = nil,
        automaticEvidence: KeyframeEvidenceSnapshot? = nil
    ) {
        self.id = id
        self.time = time
        self.stage = stage.rawValue
        self.source = source
        self.sourceFrameIndex = sourceFrameIndex
        if source == .automatic {
            self.automaticStatus = automaticStatus ?? .lowConfidence
            self.automaticConfidence = automaticConfidence
            self.automaticEvidence = automaticEvidence
        } else {
            self.automaticStatus = nil
            self.automaticConfidence = nil
            self.automaticEvidence = nil
        }
    }

    var isLocked: Bool { source == .manual }

    private enum CodingKeys: String, CodingKey {
        case id
        case time
        case stage
        case source
        case sourceFrameIndex
        case automaticStatus
        case automaticConfidence
        case automaticEvidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        time = try container.decode(Double.self, forKey: .time)
        stage = try container.decode(String.self, forKey: .stage)
        source = try container.decodeIfPresent(KeyframeSource.self, forKey: .source) ?? .automatic
        sourceFrameIndex = try container.decodeIfPresent(
            Int.self,
            forKey: .sourceFrameIndex
        )
        if source == .automatic {
            automaticStatus = try container.decodeIfPresent(
                KeyframeAutomaticStatus.self,
                forKey: .automaticStatus
            ) ?? .lowConfidence
            automaticConfidence = try container.decodeIfPresent(
                Double.self,
                forKey: .automaticConfidence
            )
            automaticEvidence = try container.decodeIfPresent(
                KeyframeEvidenceSnapshot.self,
                forKey: .automaticEvidence
            )
        } else {
            automaticStatus = nil
            automaticConfidence = nil
            automaticEvidence = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(time, forKey: .time)
        try container.encode(stage, forKey: .stage)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(
            sourceFrameIndex,
            forKey: .sourceFrameIndex
        )
        try container.encodeIfPresent(automaticStatus, forKey: .automaticStatus)
        try container.encodeIfPresent(
            automaticConfidence,
            forKey: .automaticConfidence
        )
        try container.encodeIfPresent(
            automaticEvidence,
            forKey: .automaticEvidence
        )
    }
}

enum StageMarkerMerger {
    static func merge(existing: [KeyframeMarker], automatic: [KeyframeMarker]) -> [KeyframeMarker] {
        let lockedStages = Set(existing.filter(\.isLocked).map(\.stage))
        return (existing.filter(\.isLocked) + automatic.filter { !lockedStages.contains($0.stage) })
            .sorted { $0.time < $1.time }
    }
}

/// 归一化绘图元素（坐标均为 0.0 - 1.0，适配不同屏幕及缩放）
struct DrawingElement: Identifiable, Equatable, Codable {
    let id: UUID
    var tool: DrawingTool
    var points: [CGPoint] // 归一化坐标点：(0,0)为左上角，(1,1)为右下角，与触摸/SwiftUI画布一致
    var color: Color
    var lineWidth: CGFloat
    var isKeyframeSpecific: Bool // 是否只在绘制时的时间点前后显示
    var videoTime: Double // 绘制时视频的时间（秒）
    
    init(
        id: UUID = UUID(),
        tool: DrawingTool,
        points: [CGPoint],
        color: Color = .green,
        lineWidth: CGFloat = 3.0,
        isKeyframeSpecific: Bool = false,
        videoTime: Double = 0.0
    ) {
        self.id = id
        self.tool = tool
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.isKeyframeSpecific = isKeyframeSpecific
        self.videoTime = videoTime
    }
    
    /// 检查该画线在当前视频时间是否应该显示
    func shouldShow(at currentTime: Double, threshold: Double = 0.15) -> Bool {
        if !isKeyframeSpecific { return true }
        return abs(currentTime - videoTime) <= threshold
    }

    private enum CodingKeys: String, CodingKey {
        case id, tool, points, color, lineWidth, isKeyframeSpecific, videoTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        tool = try container.decode(DrawingTool.self, forKey: .tool)
        points = try container.decode([PersistedPoint].self, forKey: .points).map(\.cgPoint)
        color = try container.decode(PersistedColor.self, forKey: .color).swiftUIColor
        lineWidth = try container.decode(CGFloat.self, forKey: .lineWidth)
        isKeyframeSpecific = try container.decode(Bool.self, forKey: .isKeyframeSpecific)
        videoTime = try container.decode(Double.self, forKey: .videoTime)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tool, forKey: .tool)
        try container.encode(points.map(PersistedPoint.init), forKey: .points)
        try container.encode(PersistedColor(color), forKey: .color)
        try container.encode(lineWidth, forKey: .lineWidth)
        try container.encode(isKeyframeSpecific, forKey: .isKeyframeSpecific)
        try container.encode(videoTime, forKey: .videoTime)
    }
}

/// The workspace display mode is authoritative for every saved line.  This
/// lets an existing project switch from frame-only annotations to persistent
/// annotations without requiring the user to redraw every element.
enum DrawingDisplayPolicy {
    static func shouldShow(_ element: DrawingElement, at currentTime: Double, isKeyframeMode: Bool) -> Bool {
        !isKeyframeMode || element.shouldShow(at: currentTime)
    }
}

/// Geometry shared by the drawing canvas and its interaction tests.
enum DrawingInteractionPolicy {
    static func allowsPointEditing(for tool: DrawingTool) -> Bool {
        tool == .line || tool == .arrow || tool == .angle
    }

    static func translated(_ element: DrawingElement, by requestedOffset: CGPoint) -> DrawingElement {
        guard !element.points.isEmpty else { return element }

        let minimumX = element.points.map(\.x).min() ?? 0
        let maximumX = element.points.map(\.x).max() ?? 1
        let minimumY = element.points.map(\.y).min() ?? 0
        let maximumY = element.points.map(\.y).max() ?? 1
        let offset = CGPoint(
            x: min(max(requestedOffset.x, -minimumX), 1 - maximumX),
            y: min(max(requestedOffset.y, -minimumY), 1 - maximumY)
        )

        var translated = element
        translated.points = element.points.map {
            CGPoint(x: $0.x + offset.x, y: $0.y + offset.y)
        }
        return translated
    }

    static func isHit(_ element: DrawingElement, at point: CGPoint, tolerance: CGFloat) -> Bool {
        guard element.points.count >= 2 else { return false }

        switch element.tool {
        case .line, .arrow:
            return distance(from: point, toSegmentFrom: element.points[0], to: element.points[1]) <= tolerance
        case .circle:
            let center = element.points[0]
            let radius = hypot(element.points[1].x - center.x, element.points[1].y - center.y)
            return hypot(point.x - center.x, point.y - center.y) <= radius + tolerance
        case .angle, .freehand:
            return zip(element.points, element.points.dropFirst()).contains {
                distance(from: point, toSegmentFrom: $0, to: $1) <= tolerance
            }
        case .select:
            return false
        }
    }

    private static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + projection * dx), point.y - (start.y + projection * dy))
    }
}

enum DrawingCanvasGeometry {
    static func interactionRect(videoRect: CGRect, canvasSize: CGSize) -> CGRect {
        guard videoRect.width > 0, videoRect.height > 0 else {
            // The AVPlayer layer can briefly report no video rect while a
            // stored project is reopening. Rendering against the whole canvas
            // during that window makes persisted normalized points jump and
            // grow, so wait for a real video rect instead.
            return .zero
        }
        return videoRect.intersection(CGRect(origin: .zero, size: canvasSize))
    }

    static func aspectFitRect(contentSize: CGSize, containerSize: CGSize) -> CGRect {
        guard contentSize.width > 0,
              contentSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return .zero
        }

        let scale = min(
            containerSize.width / contentSize.width,
            containerSize.height / contentSize.height
        )
        let fittedSize = CGSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale
        )
        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    static func denormalizedPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
    }
}

/// Circles are persisted as a center point plus a point on the circumference.
/// Keeping the conversion in one place prevents the editing canvas and media
/// exporters from interpreting the same two points as different geometries.
enum DrawingCircleGeometry {
    static func bounds(center: CGPoint, edge: CGPoint) -> CGRect {
        let radius = hypot(edge.x - center.x, edge.y - center.y)
        return CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
}

enum DrawingAngleDraftPhase: Equatable {
    case idle
    case definingFirstArm
    case awaitingSecondArm
    case definingSecondArm
}

/// A two-gesture angle draft. Points always use the persisted order
/// `[arm A endpoint, vertex, arm B endpoint]`.
struct DrawingAngleDraft: Equatable {
    private(set) var phase: DrawingAngleDraftPhase = .idle
    private(set) var points: [CGPoint] = []

    mutating func update(with point: CGPoint) {
        switch phase {
        case .idle:
            points = [point, point, point]
            phase = .definingFirstArm
        case .definingFirstArm:
            points[0] = point
        case .awaitingSecondArm:
            points[2] = point
            phase = .definingSecondArm
        case .definingSecondArm:
            points[2] = point
        }
    }

    /// Returns completed normalized points after the second valid gesture.
    /// Invalid first arms reset the draft; an invalid second arm remains
    /// pending so the user can try that arm again.
    mutating func endGesture(
        canvasSize: CGSize,
        minimumArmLength: CGFloat = 10
    ) -> [CGPoint]? {
        guard points.count == 3 else {
            reset()
            return nil
        }

        switch phase {
        case .definingFirstArm:
            guard screenDistance(
                from: points[0],
                to: points[1],
                canvasSize: canvasSize
            ) >= minimumArmLength else {
                reset()
                return nil
            }
            points[2] = points[1]
            phase = .awaitingSecondArm
            return nil

        case .definingSecondArm:
            guard screenDistance(
                from: points[2],
                to: points[1],
                canvasSize: canvasSize
            ) >= minimumArmLength else {
                points[2] = points[1]
                phase = .awaitingSecondArm
                return nil
            }
            let completed = points
            reset()
            return completed

        case .idle, .awaitingSecondArm:
            return nil
        }
    }

    mutating func reset() {
        phase = .idle
        points = []
    }

    private func screenDistance(
        from first: CGPoint,
        to second: CGPoint,
        canvasSize: CGSize
    ) -> CGFloat {
        hypot(
            (second.x - first.x) * canvasSize.width,
            (second.y - first.y) * canvasSize.height
        )
    }
}

struct DrawingAngleLayout: Equatable {
    let endpointA: CGPoint
    let vertex: CGPoint
    let endpointB: CGPoint
    let startRadians: CGFloat
    let signedSweepRadians: CGFloat
    let degrees: Double
    let arcPoints: [CGPoint]
    let labelCenter: CGPoint
}

enum DrawingAngleGeometry {
    static func layout(
        points: [CGPoint],
        preferredArcRadius: CGFloat = 25,
        labelOffset: CGFloat = 15,
        arcSegmentCount: Int = 24,
        minimumArmLength: CGFloat = 0.5
    ) -> DrawingAngleLayout? {
        guard points.count >= 3 else { return nil }

        let endpointA = points[0]
        let vertex = points[1]
        let endpointB = points[2]
        let armALength = hypot(endpointA.x - vertex.x, endpointA.y - vertex.y)
        let armBLength = hypot(endpointB.x - vertex.x, endpointB.y - vertex.y)
        let shortestArm = min(armALength, armBLength)
        guard shortestArm >= minimumArmLength else { return nil }

        let start = atan2(endpointA.y - vertex.y, endpointA.x - vertex.x)
        let end = atan2(endpointB.y - vertex.y, endpointB.x - vertex.x)
        let rawSweep = end - start
        let signedSweep = atan2(sin(rawSweep), cos(rawSweep))
        let degrees = abs(Double(signedSweep)) * 180 / Double.pi

        let radius = min(max(0, preferredArcRadius), shortestArm * 0.45)
        let segments = max(2, arcSegmentCount)
        let arcPoints = (0...segments).map { index in
            let progress = CGFloat(index) / CGFloat(segments)
            let radians = start + signedSweep * progress
            return CGPoint(
                x: vertex.x + cos(radians) * radius,
                y: vertex.y + sin(radians) * radius
            )
        }
        let bisector = start + signedSweep / 2
        let labelRadius = radius + max(0, labelOffset)
        let labelCenter = CGPoint(
            x: vertex.x + cos(bisector) * labelRadius,
            y: vertex.y + sin(bisector) * labelRadius
        )

        return DrawingAngleLayout(
            endpointA: endpointA,
            vertex: vertex,
            endpointB: endpointB,
            startRadians: start,
            signedSweepRadians: signedSweep,
            degrees: degrees,
            arcPoints: arcPoints,
            labelCenter: labelCenter
        )
    }
}

enum DrawingMagnifierPolicy {
    static func shouldShow(for tool: DrawingTool, isAdjustingControlPoint: Bool) -> Bool {
        tool == .select && isAdjustingControlPoint
    }
}

enum VideoZoomPolicy {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 4

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumScale), maximumScale)
    }

    static func adjustedScale(_ scale: CGFloat, multiplier: CGFloat) -> CGFloat {
        clampedScale(scale * multiplier)
    }
}

private struct PersistedPoint: Codable {
    let x: CGFloat
    let y: CGFloat

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

private struct PersistedColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    init(_ color: Color) {
        #if canImport(UIKit)
        var red: CGFloat = 0
        var green: CGFloat = 0.8
        var blue: CGFloat = 0.3
        var opacity: CGFloat = 1
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &opacity)
        self.red = Double(red)
        self.green = Double(green)
        self.blue = Double(blue)
        self.opacity = Double(opacity)
        #else
        self.red = 0
        self.green = 0.8
        self.blue = 0.3
        self.opacity = 1
        #endif
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

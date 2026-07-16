import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 绘图工具类型
enum DrawingTool: String, CaseIterable, Identifiable, Codable {
    case select = "选择"
    case line = "直线"
    case circle = "圆圈"
    case angle = "量角器"
    case freehand = "手绘"
    
    var id: String { self.rawValue }
    
    var iconName: String {
        switch self {
        case .select: return "arrow.up.and.pointer"
        case .line: return "line.horizontal.3"
        case .circle: return "circle"
        case .angle: return "angle"
        case .freehand: return "scribble"
        }
    }
}

/// 挥杆关键帧节点 (高尔夫标准 P 阶段)
enum SwingStage: String, CaseIterable, Identifiable {
    case address = "准备姿势 (Address)"
    case takeaway = "起杆 (Takeaway)"
    case leadArmParallelBackswing = "上杆左臂平行 (Lead Arm Parallel)"
    case top = "上杆顶点 (Top)"
    case leadArmParallelDownswing = "下杆左臂平行 (Lead Arm Parallel)"
    case impact = "击球瞬间 (Impact)"
    case followThrough = "送杆 (Follow-Through)"
    case finish = "收杆 (Finish)"
    
    var id: String { self.rawValue }
    
    var shortName: String {
        switch self {
        case .address: return "P1 准备"
        case .takeaway: return "P2 起杆"
        case .leadArmParallelBackswing: return "P3 上杆"
        case .top: return "P4 顶点"
        case .leadArmParallelDownswing: return "P5 下杆"
        case .impact: return "P6 击球"
        case .followThrough: return "P7 送杆"
        case .finish: return "P8 收杆"
        }
    }
    
    var color: Color {
        switch self {
        case .address: return .blue
        case .takeaway: return .purple
        case .leadArmParallelBackswing: return .cyan
        case .top: return .orange
        case .leadArmParallelDownswing: return .yellow
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

struct KeyframeMarker: Identifiable, Codable, Equatable {
    let id: UUID
    let time: Double // 视频时间（秒）
    let stage: String // SwingStage rawValue
    let source: KeyframeSource
    
    init(id: UUID = UUID(), time: Double, stage: SwingStage, source: KeyframeSource = .automatic) {
        self.id = id
        self.time = time
        self.stage = stage.rawValue
        self.source = source
    }

    var isLocked: Bool { source == .manual }

    private enum CodingKeys: String, CodingKey { case id, time, stage, source }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        time = try container.decode(Double.self, forKey: .time)
        stage = try container.decode(String.self, forKey: .stage)
        source = try container.decodeIfPresent(KeyframeSource.self, forKey: .source) ?? .automatic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(time, forKey: .time)
        try container.encode(stage, forKey: .stage)
        try container.encode(source, forKey: .source)
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
    var points: [CGPoint] // 归一化坐标点：(0,0)为左下角，(1,1)为右上角 (Vision/AVFoundation标准)
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

enum VideoZoomPolicy {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 4

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumScale), maximumScale)
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

import SwiftUI

/// 绘图工具类型
enum DrawingTool: String, CaseIterable, Identifiable {
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
    case top = "上杆顶点 (Top)"
    case downswing = "下杆 (Downswing)"
    case impact = "击球瞬间 (Impact)"
    case followThrough = "送杆 (Follow-Through)"
    case finish = "收杆 (Finish)"
    
    var id: String { self.rawValue }
    
    var shortName: String {
        switch self {
        case .address: return "P1 准备"
        case .takeaway: return "P2 起杆"
        case .top: return "P4 顶点"
        case .downswing: return "P5 下杆"
        case .impact: return "P6 击球"
        case .followThrough: return "P7 送杆"
        case .finish: return "P8 收杆"
        }
    }
    
    var color: Color {
        switch self {
        case .address: return .blue
        case .takeaway: return .purple
        case .top: return .orange
        case .downswing: return .yellow
        case .impact: return .red
        case .followThrough: return .indigo
        case .finish: return .green
        }
    }
}

/// 录制的关键帧标记数据
struct KeyframeMarker: Identifiable, Codable, Equatable {
    let id: UUID
    let time: Double // 视频时间（秒）
    let stage: String // SwingStage rawValue
    
    init(id: UUID = UUID(), time: Double, stage: SwingStage) {
        self.id = id
        self.time = time
        self.stage = stage.rawValue
    }
}

/// 归一化绘图元素（坐标均为 0.0 - 1.0，适配不同屏幕及缩放）
struct DrawingElement: Identifiable, Equatable {
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
}

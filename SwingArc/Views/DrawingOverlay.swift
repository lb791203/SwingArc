import SwiftUI

/// 手动绘制控制点标识
struct SelectedControlPoint: Equatable {
    let elementId: UUID
    let pointIndex: Int // 关节点在 points 数组中的索引
}

struct DrawingOverlay: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    @Binding var drawings: [DrawingElement]
    @Binding var activeTool: DrawingTool
    @Binding var selectedColor: Color
    @Binding var strokeWidth: CGFloat
    @Binding var isKeyframeMode: Bool
    var videoRect: CGRect? = nil
    var isInteractionEnabled: Bool = true
    
    @State private var currentPoints: [CGPoint] = []
    @State private var angleDraft = DrawingAngleDraft()
    @State private var selectedControlPoint: SelectedControlPoint? = nil
    @State private var selectedElementId: UUID? = nil
    @State private var selectedElementOrigin: DrawingElement? = nil
    @State private var elementDragStartPoint: CGPoint? = nil
    
    // 触碰与微调状态
    @State private var touchLocation: CGPoint = .zero
    @State private var isDragging = false
    
    // 自动追踪显示开关
    var showPoseSkeleton: Bool
    var showHeadStability: Bool
    var showSpineAngle: Bool
    
    var body: some View {
        GeometryReader { geometry in
            let rect = DrawingCanvasGeometry.interactionRect(
                videoRect: videoRect ?? playbackManager.videoRect,
                canvasSize: geometry.size
            )

            ZStack {
                if !rect.isEmpty {
                    // 1. 只在实际视频画面内捕获绘制手势。
                    Color.clear
                        .contentShape(VideoDrawingInteractionShape(interactionRect: rect))
                        .allowsHitTesting(isInteractionEnabled)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    handleDragChanged(value, in: rect)
                                }
                                .onEnded { value in
                                    handleDragEnded(in: rect)
                                }
                        )
                    
                    // 2. 向量绘制 Canvas 层
                    Canvas { context, size in
                        var videoContext = context
                        var videoClip = Path()
                        videoClip.addRect(rect)
                        videoContext.clip(to: videoClip)

                        // 绘制 Vision 自动计算数据
                        if let pose = playbackManager.currentPose {
                            if showPoseSkeleton {
                                drawPoseSkeleton(context: videoContext, pose: pose, rect: rect)
                            }
                            if showHeadStability {
                                drawHeadStability(context: videoContext, pose: pose, rect: rect)
                            }
                            if showSpineAngle {
                                drawSpineAngle(context: videoContext, pose: pose, rect: rect)
                            }
                        }
                        
                        // 绘制已保存的手动线条
                        for element in drawings {
                            // 检查该线条在当前视频时间戳下是否应该显现
                            if DrawingDisplayPolicy.shouldShow(
                                element,
                                at: playbackManager.currentTime,
                                isKeyframeMode: isKeyframeMode
                            ) {
                                drawElement(context: videoContext, element: element, rect: rect)
                            }
                        }
                        
                        // 绘制当前正在画的临时线条
                        let inProgressPoints = activeTool == .angle
                            ? angleDraft.points
                            : currentPoints
                        if activeTool != .select && !inProgressPoints.isEmpty {
                            let tempElement = DrawingElement(
                                tool: activeTool,
                                points: inProgressPoints,
                                color: selectedColor,
                                lineWidth: strokeWidth,
                                isKeyframeSpecific: isKeyframeMode,
                                videoTime: playbackManager.currentTime
                            )
                            drawElement(context: videoContext, element: tempElement, rect: rect)
                        }
                        
                        // 在选择工具模式下，绘制控制端点把手 (Handles)
                        if isInteractionEnabled && activeTool == .select {
                            drawControlHandles(context: videoContext, rect: rect)
                        }
                        
                        // 3. 绘制微调向量放大镜
                        if isInteractionEnabled && isDragging,
                           DrawingMagnifierPolicy.shouldShow(
                                for: activeTool,
                                isAdjustingControlPoint: selectedControlPoint != nil
                           ) {
                            drawVectorMagnifier(context: context, rect: rect, size: size)
                        }
                    }
                    .allowsHitTesting(false) // 确保 Canvas 能够穿透触摸，使底层的 gesture 检测层捕获手势
                    
                    // 4. 显示头部起伏高度文字提示
                    if showHeadStability, let pose = playbackManager.currentPose, let head = pose.headCenter {
                        let yPos = rect.minY + head.y * rect.height
                        let xPos = rect.minX + head.x * rect.width
                        Text("头部高度")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .position(x: xPos, y: yPos - (pose.headRadius ?? 0.06) * rect.height - 15)
                            .allowsHitTesting(false) // 同样允许触摸穿透
                    }

                    if isInteractionEnabled,
                       activeTool == .angle,
                       angleDraft.phase == .awaitingSecondArm,
                       angleDraft.points.count == 3 {
                        let vertex = angleDraft.points[1]
                        let vertexPosition = CGPoint(
                            x: rect.minX + vertex.x * rect.width,
                            y: rect.minY + vertex.y * rect.height
                        )
                        Text("再拖出第二条边")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(.black.opacity(0.72), in: Capsule())
                            .position(
                                x: min(max(vertexPosition.x, rect.minX + 72), rect.maxX - 72),
                                y: max(rect.minY + 20, vertexPosition.y - 34)
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .onChange(of: activeTool) { oldTool, newTool in
            if oldTool == .angle, newTool != .angle {
                resetAngleDraft()
            }
        }
        .onChange(of: isInteractionEnabled) { _, enabled in
            if !enabled {
                resetAngleDraft()
            }
        }
        .onDisappear(perform: resetAngleDraft)
    }
    
    // MARK: - 绘制函数
    
    /// 绘制手动绘制元素
    private func drawElement(context: GraphicsContext, element: DrawingElement, rect: CGRect) {
        guard element.points.count >= 2 else { return }
        
        // 转换所有点到屏幕坐标
        let screenPoints = element.points.map {
            DrawingCanvasGeometry.denormalizedPoint($0, in: rect)
        }
        
        var path = Path()
        
        switch element.tool {
        case .line:
            path.move(to: screenPoints[0])
            path.addLine(to: screenPoints[1])
            context.stroke(path, with: .color(element.color), lineWidth: element.lineWidth)

        case .arrow:
            let start = screenPoints[0]
            let end = screenPoints[1]
            path.move(to: start)
            path.addLine(to: end)
            if let head = ArrowGeometry.headPoints(start: start, end: end, length: 14) {
                path.move(to: head.left)
                path.addLine(to: end)
                path.addLine(to: head.right)
            }
            context.stroke(
                path,
                with: .color(element.color),
                style: StrokeStyle(lineWidth: element.lineWidth, lineCap: .round, lineJoin: .round)
            )
            
        case .circle:
            let center = screenPoints[0]
            let edge = screenPoints[1]
            path.addEllipse(in: DrawingCircleGeometry.bounds(center: center, edge: edge))
            context.stroke(path, with: .color(element.color), lineWidth: element.lineWidth)
            
        case .angle:
            guard screenPoints.count >= 3 else { return }

            // 点序固定为端点 A、顶点、端点 B。等待第二笔时，
            // B 与顶点重合，因此只会看到已经完成的第一条边。
            path.move(to: screenPoints[0])
            path.addLine(to: screenPoints[1])
            path.addLine(to: screenPoints[2])
            context.stroke(path, with: .color(element.color), lineWidth: element.lineWidth)

            guard let layout = DrawingAngleGeometry.layout(points: screenPoints) else {
                return
            }

            var arcPath = Path()
            if let firstArcPoint = layout.arcPoints.first {
                arcPath.move(to: firstArcPoint)
                for point in layout.arcPoints.dropFirst() {
                    arcPath.addLine(to: point)
                }
            }
            context.stroke(arcPath, with: .color(element.color.opacity(0.5)), lineWidth: 2.0)

            context.draw(
                Text(String(format: "%.1f°", layout.degrees))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(element.color),
                at: layout.labelCenter,
                anchor: .center
            )
            
        case .freehand:
            path.move(to: screenPoints[0])
            for i in 1..<screenPoints.count {
                path.addLine(to: screenPoints[i])
            }
            context.stroke(path, with: .color(element.color), style: StrokeStyle(lineWidth: element.lineWidth, lineCap: .round, lineJoin: .round))
            
        case .select:
            break
        }
    }
    
    /// 绘制关节点调试骨架
    private func drawPoseSkeleton(context: GraphicsContext, pose: PoseEstimationResult, rect: CGRect) {
        let bones = [
            ("leftShoulder", "rightShoulder"),
            ("leftShoulder", "leftElbow"),
            ("leftElbow", "leftWrist"),
            ("rightShoulder", "rightElbow"),
            ("rightElbow", "rightWrist"),
            ("leftShoulder", "leftHip"),
            ("rightShoulder", "rightHip"),
            ("leftHip", "rightHip"),
            ("leftHip", "leftKnee"),
            ("leftKnee", "leftAnkle"),
            ("rightHip", "rightKnee"),
            ("rightKnee", "rightAnkle")
        ]
        
        // 绘制骨架线
        for (jointA, jointB) in bones {
            if let pA = pose.point(for: jointA), let pB = pose.point(for: jointB) {
                var path = Path()
                path.move(to: CGPoint(x: rect.minX + pA.x * rect.width, y: rect.minY + pA.y * rect.height))
                path.addLine(to: CGPoint(x: rect.minX + pB.x * rect.width, y: rect.minY + pB.y * rect.height))
                context.stroke(path, with: .color(.cyan.opacity(0.6)), lineWidth: 2)
            }
        }
        
        // 绘制关节圆点
        for (_, joint) in pose.keypoints {
            let screenPos = CGPoint(
                x: rect.minX + joint.position.x * rect.width,
                y: rect.minY + joint.position.y * rect.height
            )
            var dot = Path()
            dot.addEllipse(in: CGRect(x: screenPos.x - 3.5, y: screenPos.y - 3.5, width: 7, height: 7))
            context.fill(dot, with: .color(.green))
            context.stroke(dot, with: .color(.white), lineWidth: 1)
        }
    }
    
    /// 绘制头部稳定定位圈
    private func drawHeadStability(context: GraphicsContext, pose: PoseEstimationResult, rect: CGRect) {
        guard let head = pose.headCenter, let r = pose.headRadius else { return }
        
        let screenCenter = CGPoint(x: rect.minX + head.x * rect.width, y: rect.minY + head.y * rect.height)
        let screenRadius = r * rect.width
        
        // 头部稳定圈 (圆圈)
        var circlePath = Path()
        circlePath.addEllipse(in: CGRect(
            x: screenCenter.x - screenRadius,
            y: screenCenter.y - screenRadius,
            width: screenRadius * 2,
            height: screenRadius * 2
        ))
        context.stroke(circlePath, with: .color(.green), lineWidth: 2.5)
        
        // 头部横向切线 (用于查看下摆下沉)
        var linePath = Path()
        linePath.move(to: CGPoint(x: screenCenter.x - screenRadius * 2, y: screenCenter.y - screenRadius))
        linePath.addLine(to: CGPoint(x: screenCenter.x + screenRadius * 2, y: screenCenter.y - screenRadius))
        context.stroke(linePath, with: .color(.green.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
    
    /// 绘制脊椎夹角
    private func drawSpineAngle(context: GraphicsContext, pose: PoseEstimationResult, rect: CGRect) {
        guard let shoulder = pose.shoulderMid, let hip = pose.hipMid, let angle = pose.spineAngle else { return }
        
        let pShoulder = CGPoint(x: rect.minX + shoulder.x * rect.width, y: rect.minY + shoulder.y * rect.height)
        let pHip = CGPoint(x: rect.minX + hip.x * rect.width, y: rect.minY + hip.y * rect.height)
        
        // 绘制脊椎中轴线
        var spinePath = Path()
        spinePath.move(to: pHip)
        spinePath.addLine(to: pShoulder)
        context.stroke(spinePath, with: .color(.orange), lineWidth: 3)
        
        // 绘制对比垂直虚线 (从髋部向上延伸)
        var vertPath = Path()
        vertPath.move(to: pHip)
        vertPath.addLine(to: CGPoint(x: pHip.x, y: pShoulder.y - 30))
        context.stroke(vertPath, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
        
        // 绘制角度圆弧
        var arcPath = Path()
        let arcRadius: CGFloat = 20.0
        // 垂直向上是 -90 度 (-pi/2)
        let endAngle = Angle(radians: -Double.pi / 2)
        // 倾斜线角度，计算得到弧度
        let startAngle = Angle(radians: -Double.pi / 2 + (angle * .pi / 180.0))
        
        arcPath.addArc(
            center: pHip,
            radius: arcRadius,
            startAngle: min(startAngle, endAngle),
            endAngle: max(startAngle, endAngle),
            clockwise: false
        )
        context.stroke(arcPath, with: .color(.orange.opacity(0.5)), lineWidth: 2)
        
        // 绘制脊椎弯曲度数文字
        let textPos = CGPoint(x: pHip.x + (angle >= 0 ? 25 : -25), y: pHip.y - 45)
        context.draw(
            Text(String(format: "脊椎角 %.1f°", abs(angle)))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.orange),
            at: textPos,
            anchor: angle >= 0 ? .leading : .trailing
        )
    }
    
    /// 绘制控制点把手，以便用户拖动调整
    private func drawControlHandles(context: GraphicsContext, rect: CGRect) {
        for element in drawings {
            if element.shouldShow(at: playbackManager.currentTime) {
                guard DrawingInteractionPolicy.allowsPointEditing(for: element.tool) else { continue }
                
                for (_, pt) in element.points.enumerated() {
                    let screenPos = CGPoint(
                        x: rect.minX + pt.x * rect.width,
                        y: rect.minY + pt.y * rect.height
                    )
                    
                    var outerCircle = Path()
                    outerCircle.addEllipse(in: CGRect(x: screenPos.x - 7, y: screenPos.y - 7, width: 14, height: 14))
                    context.fill(outerCircle, with: .color(.white))
                    context.stroke(outerCircle, with: .color(element.color), lineWidth: 2)
                    
                    var innerDot = Path()
                    innerDot.addEllipse(in: CGRect(x: screenPos.x - 2.5, y: screenPos.y - 2.5, width: 5, height: 5))
                    context.fill(innerDot, with: .color(element.color))
                }
            }
        }
    }
    
    /// 绘制矢量线段放大镜（只渲染线段向量，防止大拇指遮挡）
    private func drawVectorMagnifier(context: GraphicsContext, rect: CGRect, size: CGSize) {
        let magRadius: CGFloat = 55.0
        let zoomScale: CGFloat = 2.0
        
        // 放大镜窗口中心：置于手指当前触碰点上方 75pt 处，以防手指遮挡
        let magCenter = CGPoint(x: touchLocation.x, y: touchLocation.y - 80)
        
        // 确保放大镜不会超出视图边缘
        var clampedCenter = magCenter
        if clampedCenter.x < magRadius + 10 { clampedCenter.x = magRadius + 10 }
        if clampedCenter.x > size.width - magRadius - 10 { clampedCenter.x = size.width - magRadius - 10 }
        if clampedCenter.y < magRadius + 10 { clampedCenter.y = magRadius + 10 }
        
        // 剪切为圆形放大镜视窗
        var magContext = context
        var circleClip = Path()
        circleClip.addEllipse(in: CGRect(
            x: clampedCenter.x - magRadius,
            y: clampedCenter.y - magRadius,
            width: magRadius * 2,
            height: magRadius * 2
        ))
        magContext.clip(to: circleClip)
        
        // 填充放大镜背景
        magContext.fill(circleClip, with: .color(Color(white: 0.08, opacity: 0.9)))
        
        // 计算坐标转换偏移矩阵：
        // 目标是让 touchLocation 对准放大镜正中心，并执行 zoomScale 缩放
        // 转换公式：NewPt = magCenter + (OriginalPt - touchLocation) * zoomScale
        
        // 绘制 Vision 姿态 skeleton 放大
        if let pose = playbackManager.currentPose {
            if showPoseSkeleton {
                drawScaledPoseSkeleton(context: &magContext, pose: pose, rect: rect, center: clampedCenter, touchLoc: touchLocation, scale: zoomScale)
            }
            if showSpineAngle {
                drawScaledSpineAngle(context: &magContext, pose: pose, rect: rect, center: clampedCenter, touchLoc: touchLocation, scale: zoomScale)
            }
        }
        
        // 绘制手动划线放大
        for element in drawings {
            if element.shouldShow(at: playbackManager.currentTime) {
                drawScaledElement(context: &magContext, element: element, rect: rect, center: clampedCenter, touchLoc: touchLocation, scale: zoomScale)
            }
        }
        
        // 绘制当前正在画的临时线条放大
        let inProgressPoints = activeTool == .angle
            ? angleDraft.points
            : currentPoints
        if activeTool != .select && !inProgressPoints.isEmpty {
            let tempElement = DrawingElement(
                tool: activeTool,
                points: inProgressPoints,
                color: selectedColor,
                lineWidth: strokeWidth,
                isKeyframeSpecific: isKeyframeMode,
                videoTime: playbackManager.currentTime
            )
            drawScaledElement(context: &magContext, element: tempElement, rect: rect, center: clampedCenter, touchLoc: touchLocation, scale: zoomScale)
        }
        
        // 绘制放大镜外框装饰（科技感白圆环 + 靶心十字）
        var outerBorder = Path()
        outerBorder.addEllipse(in: CGRect(
            x: clampedCenter.x - magRadius,
            y: clampedCenter.y - magRadius,
            width: magRadius * 2,
            height: magRadius * 2
        ))
        context.stroke(outerBorder, with: .color(.white), lineWidth: 2)
        
        // 靶心十字
        var crossPath = Path()
        crossPath.move(to: CGPoint(x: clampedCenter.x - 6, y: clampedCenter.y))
        crossPath.addLine(to: CGPoint(x: clampedCenter.x + 6, y: clampedCenter.y))
        crossPath.move(to: CGPoint(x: clampedCenter.x, y: clampedCenter.y - 6))
        crossPath.addLine(to: CGPoint(x: clampedCenter.x, y: clampedCenter.y + 6))
        context.stroke(crossPath, with: .color(.red.opacity(0.8)), lineWidth: 1.5)
    }
    
    // MARK: - 缩放比例辅助绘制函数
    
    private func zoomPoint(pt: CGPoint, rect: CGRect, center: CGPoint, touchLoc: CGPoint, scale: CGFloat) -> CGPoint {
        let screenPt = CGPoint(
            x: rect.minX + pt.x * rect.width,
            y: rect.minY + pt.y * rect.height
        )
        return CGPoint(
            x: center.x + (screenPt.x - touchLoc.x) * scale,
            y: center.y + (screenPt.y - touchLoc.y) * scale
        )
    }
    
    private func drawScaledElement(context: inout GraphicsContext, element: DrawingElement, rect: CGRect, center: CGPoint, touchLoc: CGPoint, scale: CGFloat) {
        guard element.points.count >= 2 else { return }
        
        let zoomedPoints = element.points.map { pt in
            zoomPoint(pt: pt, rect: rect, center: center, touchLoc: touchLoc, scale: scale)
        }
        
        var path = Path()
        switch element.tool {
        case .line:
            path.move(to: zoomedPoints[0])
            path.addLine(to: zoomedPoints[1])
            context.stroke(path, with: .color(element.color), lineWidth: element.lineWidth * scale)
        case .arrow:
            let start = zoomedPoints[0]
            let end = zoomedPoints[1]
            path.move(to: start)
            path.addLine(to: end)
            if let head = ArrowGeometry.headPoints(start: start, end: end, length: 14 * scale) {
                path.move(to: head.left)
                path.addLine(to: end)
                path.addLine(to: head.right)
            }
            context.stroke(
                path,
                with: .color(element.color),
                style: StrokeStyle(
                    lineWidth: element.lineWidth * scale,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        case .circle:
            let zCenter = zoomedPoints[0]
            let zEdge = zoomedPoints[1]
            path.addEllipse(in: DrawingCircleGeometry.bounds(center: zCenter, edge: zEdge))
            context.stroke(path, with: .color(element.color), lineWidth: element.lineWidth * scale)
        case .angle:
            guard zoomedPoints.count >= 3 else { return }
            path.move(to: zoomedPoints[0])
            path.addLine(to: zoomedPoints[1])
            path.addLine(to: zoomedPoints[2])
            context.stroke(path, with: .color(element.color), lineWidth: element.lineWidth * scale)

            guard let layout = DrawingAngleGeometry.layout(
                points: zoomedPoints,
                preferredArcRadius: 25 * scale,
                labelOffset: 15 * scale
            ) else { return }
            var arcPath = Path()
            if let firstArcPoint = layout.arcPoints.first {
                arcPath.move(to: firstArcPoint)
                for point in layout.arcPoints.dropFirst() {
                    arcPath.addLine(to: point)
                }
            }
            context.stroke(
                arcPath,
                with: .color(element.color.opacity(0.5)),
                lineWidth: 2 * scale
            )
            context.draw(
                Text(String(format: "%.1f°", layout.degrees))
                    .font(.system(size: 11 * scale, weight: .bold))
                    .foregroundColor(element.color),
                at: layout.labelCenter,
                anchor: .center
            )
        case .freehand:
            path.move(to: zoomedPoints[0])
            for i in 1..<zoomedPoints.count {
                path.addLine(to: zoomedPoints[i])
            }
            context.stroke(path, with: .color(element.color), style: StrokeStyle(lineWidth: element.lineWidth * scale, lineCap: .round, lineJoin: .round))
        case .select:
            break
        }
    }
    
    private func drawScaledPoseSkeleton(context: inout GraphicsContext, pose: PoseEstimationResult, rect: CGRect, center: CGPoint, touchLoc: CGPoint, scale: CGFloat) {
        let bones = [
            ("leftShoulder", "rightShoulder"), ("leftShoulder", "leftElbow"), ("leftElbow", "leftWrist"),
            ("rightShoulder", "rightElbow"), ("rightElbow", "rightWrist"), ("leftShoulder", "leftHip"),
            ("rightShoulder", "rightHip"), ("leftHip", "rightHip")
        ]
        
        for (jointA, jointB) in bones {
            if let pA = pose.point(for: jointA), let pB = pose.point(for: jointB) {
                let zpA = zoomPoint(pt: pA, rect: rect, center: center, touchLoc: touchLoc, scale: scale)
                let zpB = zoomPoint(pt: pB, rect: rect, center: center, touchLoc: touchLoc, scale: scale)
                var path = Path()
                path.move(to: zpA)
                path.addLine(to: zpB)
                context.stroke(path, with: .color(.cyan.opacity(0.5)), lineWidth: 1.5 * scale)
            }
        }
        
        // 绘制关节圈点
        for (_, joint) in pose.keypoints {
            let zPos = zoomPoint(pt: joint.position, rect: rect, center: center, touchLoc: touchLoc, scale: scale)
            var dot = Path()
            dot.addEllipse(in: CGRect(x: zPos.x - 3, y: zPos.y - 3, width: 6, height: 6))
            context.fill(dot, with: .color(.green))
        }
    }
    
    private func drawScaledSpineAngle(context: inout GraphicsContext, pose: PoseEstimationResult, rect: CGRect, center: CGPoint, touchLoc: CGPoint, scale: CGFloat) {
        guard let shoulder = pose.shoulderMid, let hip = pose.hipMid else { return }
        
        let zpShoulder = zoomPoint(pt: shoulder, rect: rect, center: center, touchLoc: touchLoc, scale: scale)
        let zpHip = zoomPoint(pt: hip, rect: rect, center: center, touchLoc: touchLoc, scale: scale)
        
        var spinePath = Path()
        spinePath.move(to: zpHip)
        spinePath.addLine(to: zpShoulder)
        context.stroke(spinePath, with: .color(.orange), lineWidth: 2 * scale)
    }
    
    // MARK: - 触摸手势控制逻辑
    
    private func handleDragChanged(_ value: DragGesture.Value, in rect: CGRect) {
        isDragging = true
        touchLocation = value.location
        
        // 映射坐标至归一化值 (0.0 到 1.0)
        let normX = max(0.0, min(1.0, (value.location.x - rect.minX) / rect.width))
        let normY = max(0.0, min(1.0, (value.location.y - rect.minY) / rect.height))
        let normPoint = CGPoint(x: normX, y: normY)
        
        // 磁吸吸附：如果在关节附近，强行吸附（手绘模式除外）
        var finalPoint = normPoint
        if activeTool != .freehand && activeTool != .select {
            if let pose = playbackManager.currentPose {
                for (_, joint) in pose.keypoints {
                    let jX = rect.minX + joint.position.x * rect.width
                    let jY = rect.minY + joint.position.y * rect.height
                    let dist = sqrt(pow(value.location.x - jX, 2) + pow(value.location.y - jY, 2))
                    
                    // 15 像素距离内磁贴吸附
                    if dist < 15.0 {
                        finalPoint = joint.position
                        // 修正放大镜靶心坐标
                        touchLocation = CGPoint(x: jX, y: jY)
                        break
                    }
                }
            }
        }
        
        if activeTool == .select {
            // 选择并拖拽已有的手动划线端点
            if selectedControlPoint == nil && selectedElementId == nil {
                // 查找最近的控制端点
                var closestDist: CGFloat = 30.0 // 30像素触碰阈值
                for element in drawings {
                    guard DrawingInteractionPolicy.allowsPointEditing(for: element.tool) else { continue }
                    if DrawingDisplayPolicy.shouldShow(
                        element,
                        at: playbackManager.currentTime,
                        isKeyframeMode: isKeyframeMode
                    ) {
                        for (idx, pt) in element.points.enumerated() {
                            let pX = rect.minX + pt.x * rect.width
                            let pY = rect.minY + pt.y * rect.height
                            let dist = sqrt(pow(value.location.x - pX, 2) + pow(value.location.y - pY, 2))
                            if dist < closestDist {
                                closestDist = dist
                                selectedControlPoint = SelectedControlPoint(elementId: element.id, pointIndex: idx)
                            }
                        }
                    }
                }

                // 没有点中端点时，点住线身或圆弧可整体移动标注。
                if selectedControlPoint == nil {
                    let hitTolerance = max(0.02, 18 / min(rect.width, rect.height))
                    if let element = drawings.reversed().first(where: {
                        DrawingDisplayPolicy.shouldShow(
                            $0,
                            at: playbackManager.currentTime,
                            isKeyframeMode: isKeyframeMode
                        ) && DrawingInteractionPolicy.isHit($0, at: normPoint, tolerance: hitTolerance)
                    }) {
                        selectedElementId = element.id
                        selectedElementOrigin = element
                        elementDragStartPoint = normPoint
                    }
                }
            }
            
            // 如果已选中控制点，执行位置移动
            if let control = selectedControlPoint, let index = drawings.firstIndex(where: { $0.id == control.elementId }) {
                // 同样支持在微调时磁力吸附其他人体关节
                if let pose = playbackManager.currentPose {
                    for (_, joint) in pose.keypoints {
                        let jX = rect.minX + joint.position.x * rect.width
                        let jY = rect.minY + joint.position.y * rect.height
                        let dist = sqrt(pow(value.location.x - jX, 2) + pow(value.location.y - jY, 2))
                        if dist < 15.0 {
                            finalPoint = joint.position
                            touchLocation = CGPoint(x: jX, y: jY)
                            break
                        }
                    }
                }
                drawings[index].points[control.pointIndex] = finalPoint
            } else if let elementId = selectedElementId,
                      let origin = selectedElementOrigin,
                      let startPoint = elementDragStartPoint,
                      let index = drawings.firstIndex(where: { $0.id == elementId }) {
                drawings[index] = DrawingInteractionPolicy.translated(
                    origin,
                    by: CGPoint(x: normPoint.x - startPoint.x, y: normPoint.y - startPoint.y)
                )
            }
            
        } else if activeTool == .angle {
            angleDraft.update(with: finalPoint)
        } else {
            // 新建直线、箭头、圆圈或手绘动作
            if currentPoints.isEmpty {
                currentPoints.append(finalPoint)
                currentPoints.append(finalPoint)
            } else {
                switch activeTool {
                case .line, .arrow, .circle:
                    currentPoints[1] = finalPoint
                case .freehand:
                    currentPoints.append(finalPoint)
                case .select, .angle:
                    break
                }
            }
        }
    }
    
    private func handleDragEnded(in rect: CGRect) {
        isDragging = false
        
        if activeTool == .select {
            selectedControlPoint = nil
            selectedElementId = nil
            selectedElementOrigin = nil
            elementDragStartPoint = nil
        } else if activeTool == .angle {
            guard let completedPoints = angleDraft.endGesture(
                canvasSize: rect.size
            ) else { return }

            drawings.append(DrawingElement(
                tool: .angle,
                points: completedPoints,
                color: selectedColor,
                lineWidth: strokeWidth,
                isKeyframeSpecific: isKeyframeMode,
                videoTime: playbackManager.currentTime
            ))
            // 两条边都确定后进入选择模式，立即显示三个可编辑把手。
            activeTool = .select
        } else {
            guard !currentPoints.isEmpty else { return }

            let newElement = DrawingElement(
                tool: activeTool,
                points: currentPoints,
                color: selectedColor,
                lineWidth: strokeWidth,
                isKeyframeSpecific: isKeyframeMode,
                videoTime: playbackManager.currentTime
            )
            drawings.append(newElement)
            
            // 清理临时绘制点
            currentPoints = []
        }
    }

    private func resetAngleDraft() {
        angleDraft.reset()
        isDragging = false
    }
}

private struct VideoDrawingInteractionShape: Shape {
    let interactionRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(interactionRect)
        return path
    }
}

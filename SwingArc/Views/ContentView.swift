import SwiftUI
import PhotosUI

private enum MediaAction {
    case save
    case share

    var title: String {
        switch self {
        case .save: return "保存"
        case .share: return "分享"
        }
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @StateObject private var playbackManager = VideoPlaybackManager()
    
    // 绘画与工具状态
    @State private var drawings: [DrawingElement] = []
    @State private var drawingHistory: [[DrawingElement]] = [] // 用于撤销
    @State private var drawingRedoHistory: [[DrawingElement]] = [] // 用于重做
    @State private var activeTool: DrawingTool = .line
    @State private var selectedColor: Color = .green
    @State private var strokeWidth: CGFloat = 3.0
    @State private var isKeyframeMode: Bool = true // 默认关键帧画线
    
    // 自动分析开关
    @State private var showPoseSkeleton = false
    @State private var showHeadStability = false
    @State private var showSpineAngle = false
    @State private var showGrid = false
    
    // 录制关键帧标记
    @State private var keyframes: [KeyframeMarker] = []
    
    // 导入与摄像模态框
    @State private var showCameraView = false
    @State private var showVideoPicker = false
    @State private var selectedPickerItem: PhotosPickerItem? = nil
    
    // 控制右侧分析面板显示/隐藏，最大化视频 analysis 区域
    @State private var showRightPanel = true
    
    // AI 分析结果面板状态
    @State private var showAnalysisReport = false
    @State private var pendingMediaAction: MediaAction?
    @State private var sharePayload: SharePayload?
    @State private var isExporting = false
    @State private var mediaStatusMessage: String?

    private var analysisPresentation: AnalysisWorkspacePresentation {
        AnalysisWorkspacePresentation(state: playbackManager.analysisState)
    }

    private var visibleKeyframes: [KeyframeMarker] {
        analysisPresentation.allowsPoseOverlays ? keyframes : []
    }
    
    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            
            ZStack {
                // 主背景：深色极客风
                Color(red: 0.05, green: 0.07, blue: 0.12).ignoresSafeArea()
                
                if playbackManager.player != nil {
                    // 已载入视频：展示播放界面
                    if isLandscape {
                        // 横屏布局：最大化分析视窗，侧边工具栏
                        HStack(spacing: 0) {
                            // 左侧：专业画线画笔工具箱
                            leftToolPanel
                                .frame(width: 56) // 缩窄为 56pt
                                .background(Color(white: 0.08).opacity(0.85))
                            
                            // 中央：视频视窗
                            VStack(spacing: 0) {
                                videoViewportZone(isLandscape: true)
                                bottomControlPanel(isLandscape: true)
                            }
                            
                            // 右侧：自动追踪与人体指标监测面板
                            if showRightPanel && analysisPresentation.allowsPoseOverlays {
                                rightAnalysisPanel
                                    .frame(width: 180) // 缩窄为 180pt
                                    .background(Color(white: 0.08).opacity(0.85))
                            }
                        }
                    } else {
                        // 竖屏布局：上下结构，优先大屏视频显示
                        VStack(spacing: 0) {
                            // 顶部导入与切换栏
                            topMenuBar
                                .frame(height: 50)
                            
                            // 播放器画板 (解除固定高度限制，自动撑满可用空间)
                            videoViewportZone(isLandscape: false)
                            

                            
                            // 底部操作控制面板
                            bottomControlPanel(isLandscape: false)
                        }
                    }
                } else {
                    // 未载入视频：展示空状态和导入面板
                    emptyStateView
                }
                
                // AI 评估报告浮层 (GolfFix 竞品风格)
                if showAnalysisReport {
                    analysisReportOverlay
                }
            }
        }
        .statusBarHidden(true)
        .photosPicker(isPresented: $showVideoPicker, selection: $selectedPickerItem, matching: .videos)
        .onChange(of: selectedPickerItem) { newItem in
            if let item = newItem {
                loadSelectedVideo(from: item)
            }
        }
        .sheet(isPresented: $showCameraView) {
            CameraView(onRecordCompleted: { recordedURL in
                loadVideoFromURL(recordedURL)
            })
        }
        .confirmationDialog(
            "\(pendingMediaAction?.title ?? "")内容",
            isPresented: Binding(
                get: { pendingMediaAction != nil },
                set: { if !$0 { pendingMediaAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("当前帧") { performMediaAction(kind: .frame) }
            Button("标注视频") { performMediaAction(kind: .annotatedVideo) }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.url])
        }
        .alert("SwingArc", isPresented: Binding(
            get: { mediaStatusMessage != nil },
            set: { if !$0 { mediaStatusMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(mediaStatusMessage ?? "")
        }
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    ProgressView("正在生成媒体…")
                        .tint(.white)
                        .padding(18)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    // MARK: - 子视图组件
    
    /// 顶部栏
    private var topMenuBar: some View {
        HStack {
            Button(action: { showVideoPicker = true }) {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("视频分析")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            HStack(spacing: 8) {
                Menu {
                    Button("保存") { pendingMediaAction = .save }
                    Button("分享") { pendingMediaAction = .share }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }

                Button(action: { showCameraView = true }) {
                    Image(systemName: "camera")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        )
    }
    
    /// 空白导入状态页
    private var emptyStateView: some View {
        VStack(spacing: 30) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 70))
                .foregroundColor(.green.opacity(0.7))
                .shadow(color: .green.opacity(0.3), radius: 10)
            
            VStack(spacing: 10) {
                Text("高尔夫挥杆画线分析")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("请从本地相册导入视频，或启动内置高速相机录制挥杆。我们为您提供 120 FPS 慢动作和 Vision AI 自动追踪。")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            HStack(spacing: 20) {
                Button(action: { showVideoPicker = true }) {
                    HStack {
                        Image(systemName: "photo")
                        Text("相册导入")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 140, height: 50)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                
                Button(action: { showCameraView = true }) {
                    HStack {
                        Image(systemName: "video")
                        Text("高速录制")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 140, height: 50)
                    .background(Color.red)
                    .cornerRadius(12)
                }
            }
            
            // 示例视频直接载入
            Button(action: {
                loadDemoVideo()
            }) {
                Text("或者：载入网络演示视频")
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .padding(.top, 10)
            }
        }
    }
    
    /// 播放器主视窗
    private func videoViewportZone(isLandscape: Bool) -> some View {
        ZStack {
            if let player = playbackManager.player {
                // 底层视频画面
                PlayerViewRepresentable(player: player) { rect in
                    playbackManager.videoRect = rect
                }
                
                // 静态校正格栅线
                if showGrid {
                    GridView(rect: playbackManager.videoRect)
                        .allowsHitTesting(false) // 确保网格线不会拦截触摸手势
                }
                
                // 顶层画板与自动追踪层
                DrawingOverlay(
                    playbackManager: playbackManager,
                    drawings: $drawings,
                    activeTool: $activeTool,
                    selectedColor: $selectedColor,
                    strokeWidth: $strokeWidth,
                    isKeyframeMode: $isKeyframeMode,
                    showPoseSkeleton: showPoseSkeleton,
                    showHeadStability: showHeadStability,
                    showSpineAngle: showSpineAngle
                )
                
                // 竖屏浮动紧凑工具栏 (左侧浮动，最大化垂直分析空间)
                if !isLandscape {
                    HStack {
                        if analysisPresentation.allowsPoseOverlays {
                            // AI 分析完成后才允许显示体态叠层。
                            VStack(spacing: 16) {
                            Button(action: { showPoseSkeleton.toggle() }) {
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(showPoseSkeleton ? .green : .white)
                                    .frame(width: 32, height: 32)
                                    .background(showPoseSkeleton ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            Button(action: { showHeadStability.toggle() }) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(showHeadStability ? .green : .white)
                                    .frame(width: 32, height: 32)
                                    .background(showHeadStability ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            Button(action: { showSpineAngle.toggle() }) {
                                Image(systemName: "line.diagonal")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(showSpineAngle ? .green : .white)
                                    .frame(width: 32, height: 32)
                                    .background(showSpineAngle ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            Button(action: { showGrid.toggle() }) {
                                Image(systemName: "grid")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(showGrid ? .green : .white)
                                    .frame(width: 32, height: 32)
                                    .background(showGrid ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                        }
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(20)
                            .padding(.leading, 12)
                        }
                        
                        Spacer()
                        
                        // 画笔工具箱 (右侧)
                        VStack(spacing: 12) {
                            ForEach(DrawingTool.allCases) { tool in
                                Button(action: { activeTool = tool }) {
                                    Image(systemName: tool.iconName)
                                        .font(.system(size: 16))
                                        .foregroundColor(activeTool == tool ? .green : .white)
                                        .frame(width: 36, height: 36)
                                        .background(activeTool == tool ? Color.green.opacity(0.2) : Color.clear)
                                        .overlay(
                                            Circle()
                                                .stroke(activeTool == tool ? Color.green : Color.white.opacity(0.3), lineWidth: 1.5)
                                        )
                                        .clipShape(Circle())
                                }
                            }
                            
                            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 24, height: 1)
                            
                            // 颜色选择浮动点
                            let colors: [Color] = [.green, .red, .cyan]
                            ForEach(colors, id: \.self) { color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == color ? 1.5 : 0)
                                    )
                                    .onTapGesture {
                                        selectedColor = color
                                    }
                            }
                            
                            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 24, height: 1)
                            
                            // 撤销与清除快捷键
                            Button(action: undoDrawing) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            
                            Button(action: clearAllDrawings) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.red)
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .padding(.trailing, 12)
                        
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // 4. AI 自动扫描科技风遮罩 (DeepSwing 竞品风格)
                if playbackManager.isScanning {
                    ZStack {
                        Color.black.opacity(0.7)
                        
                        VStack(spacing: 16) {
                            ProgressView(value: playbackManager.scanProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                                .frame(width: 160)
                                .scaleEffect(x: 1.0, y: 1.5, anchor: .center)
                            
                            Text("AI 正在深度解析挥杆平面...")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("\(Int(playbackManager.scanProgress * 100))%")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        
                        // 激光扫描条动画
                        GeometryReader { scanGeo in
                            let yOffset = CGFloat(playbackManager.scanProgress) * scanGeo.size.height
                            Rectangle()
                                .fill(
                                    LinearGradient(colors: [.clear, .green.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                                )
                                .frame(height: 30)
                                .shadow(color: .green.opacity(0.8), radius: 5)
                                .offset(y: yOffset - 15)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .clipped()
    }
    
    /// 左侧工具面板 (画笔、颜色、橡皮擦)
    private var leftToolPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                // Logo
                Text("Swing")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.green)
                    .padding(.top, 10)
                
                Divider().background(Color.gray.opacity(0.3))
                
                // 工具选择列表 (去掉了文本，仅保留高透图标以压缩横向宽度)
                ForEach(DrawingTool.allCases) { tool in
                    Button(action: {
                        activeTool = tool
                    }) {
                        Image(systemName: tool.iconName)
                            .font(.system(size: 18))
                            .foregroundColor(activeTool == tool ? .green : .white.opacity(0.8))
                            .frame(width: 44, height: 44) // 完美的苹果 HIG 标准触控尺寸
                            .background(activeTool == tool ? Color.green.opacity(0.18) : Color.clear)
                            .cornerRadius(8)
                    }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                // 颜色快速选择
                let colors: [Color] = [.green, .red, .cyan, .yellow, .white]
                VStack(spacing: 8) {
                    ForEach(colors, id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selectedColor == color ? 2.0 : 0)
                            )
                            .onTapGesture {
                                selectedColor = color
                            }
                    }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                // 撤销与清除
                Button(action: undoDrawing) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                
                Button(action: clearAllDrawings) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 36, height: 36)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Circle())
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 4)
        }
    }
    
    /// 右侧分析仪数据板 (横屏专用)
    private var rightAnalysisPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text("AI 追踪设置")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 12)
                    .padding(.horizontal)
                
                VStack(spacing: 6) {
                    Toggle(isOn: $showPoseSkeleton) {
                        Label("关节骨骼网格", systemImage: "figure.walk")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    
                    Toggle(isOn: $showHeadStability) {
                        Label("头部稳定指示圆", systemImage: "person.crop.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    
                    Toggle(isOn: $showSpineAngle) {
                        Label("脊椎角度监测", systemImage: "line.diagonal")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    
                    Toggle(isOn: $showGrid) {
                        Label("基准对齐网格", systemImage: "grid")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                }
                .padding(.horizontal)
                
                Divider().background(Color.gray.opacity(0.2))
                
                Text("实时身体指标")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal)
                
                VStack(spacing: 8) {
                    // 实时脊椎角度展示
                    MetricCard(
                        title: "身体轴线/脊椎倾斜角",
                        value: playbackManager.currentPose?.spineAngle != nil ?
                            String(format: "%.1f°", abs(playbackManager.currentPose!.spineAngle!)) : "未识别",
                        color: .orange
                    )
                    
                    // 头部高度沉降提示
                    MetricCard(
                        title: "头部起伏状态",
                        value: playbackManager.currentPose?.headCenter != nil ? "锁定中" : "未识别",
                        color: .green
                    )
                }
                .padding(.horizontal)
                
                Divider().background(Color.gray.opacity(0.2))
                
                // 画线模式切换 (关键帧模式 vs 全局显示)
                VStack(alignment: .leading, spacing: 4) {
                    Text("画线显示设置")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.gray)
                    
                    Picker("画线显示", selection: $isKeyframeMode) {
                        Text("仅在绘制帧").tag(true)
                        Text("全局持续").tag(false)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
    }
    
    /// 底部控制面板 (Timeline 进度轴、播放速度、逐帧步进、关键节点)
    private func bottomControlPanel(isLandscape: Bool) -> some View {
        VStack(spacing: 12) {
            // 1. Timeline 进度拖拽轴
            HStack(spacing: 8) {
                Text(formatTime(playbackManager.currentTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
                
                // 进度条与关键节点指示器叠加
                GeometryReader { timelineGeo in
                    ZStack(alignment: .leading) {
                        // 底层 Slider
                        Slider(
                            value: Binding(
                                get: { playbackManager.currentTime },
                                set: { newValue in playbackManager.seek(to: newValue) }
                            ),
                            in: 0...max(0.1, playbackManager.duration)
                        )
                        .accentColor(.green)
                        
                        // 标记在进度条上的关键帧小圆点
                        ForEach(visibleKeyframes) { marker in
                            let pct = marker.time / max(0.1, playbackManager.duration)
                            let posX = pct * (timelineGeo.size.width - 16) + 8 // 略微居中补偿
                            Circle()
                                .fill(SwingStage.allCases.first(where: { $0.rawValue == marker.stage })?.color ?? .white)
                                .frame(width: 8, height: 8)
                                .position(x: posX, y: timelineGeo.size.height / 2)
                                .onTapGesture {
                                    playbackManager.seek(to: marker.time)
                                }
                        }
                    }
                }
                .frame(height: 20)
                
                Text(formatTime(playbackManager.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
            
            // 2. 高尔夫关键阶段快捷标记定位
            if analysisPresentation.allowsPoseOverlays {
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SwingStage.allCases) { stage in
                        let savedMarker = keyframes.first(where: { $0.stage == stage.rawValue })
                        
                        Button(action: {
                            print("DEBUG: Tap stage button \(stage.shortName)")
                            if let marker = savedMarker {
                                playbackManager.seek(to: marker.time)
                            } else {
                                saveKeyframe(stage: stage)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(stage.color)
                                    .frame(width: 6, height: 6)
                                Text(savedMarker == nil ? "\(stage.shortName) 未确定" : stage.shortName)
                                    .font(.system(size: 11, weight: .bold))
                                if savedMarker != nil {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9))
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8) // 高度缩减
                            .contentShape(Rectangle()) // 确保整个背景区域都可以接收点击
                            .background(savedMarker != nil ? stage.color.opacity(0.35) : Color.white.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(savedMarker != nil ? stage.color : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(PlainButtonStyle()) // 使用 PlainStyle，防止 List/ScrollView 拦截手势
                    }
                    
                    // 重置标记按钮
                    if !visibleKeyframes.isEmpty {
                        Button(action: { keyframes.removeAll() }) {
                            Text("重置")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
                    .padding(.horizontal)
                }
            }
            
            // 3. 核心控制按键栏 (慢速、播放暂停、逐帧拨盘)
            HStack {
                // 回放速度选择改用 Menu 节省空间
                let speeds = [0.1, 0.25, 0.5, 1.0]
                Menu {
                    ForEach(speeds, id: \.self) { rate in
                        Button(action: { playbackManager.setSpeed(rate) }) {
                            Text(String(format: "%.2fx", rate))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(String(format: "%.2fx", playbackManager.playbackSpeed))
                            .font(.system(size: 14, weight: .bold))
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.green)
                    .frame(width: 70)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
                }
                
                Spacer()
                
                // 逐帧微调与播放暂停大按钮 (一体化中心)
                HStack(spacing: 16) {
                    Button(action: {
                        if playbackManager.isPlaying {
                            playbackManager.pause()
                        } else {
                            playbackManager.play()
                        }
                    }) {
                        Image(systemName: playbackManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 46))
                            .foregroundColor(.green)
                            .shadow(color: .green.opacity(0.4), radius: 6)
                    }
                    
                    // 自定义旋转拨轮微调器
                    JogDialView { forward in
                        playbackManager.stepFrame(forward: forward)
                    }
                    .frame(width: 140) // 放大飞轮
                }
                
                Spacer()
                
                Button(action: runAISwingAnalysis) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                        Text(playbackManager.isScanning ? "分析中" : "AI 分析")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.cyan.opacity(0.12))
                    .clipShape(Capsule())
                }
                .disabled(playbackManager.isScanning)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .padding(.top, 6)
        .background(Color(white: 0.06).opacity(0.95))
    }
    
    // MARK: - 辅助绘制元素与开关
    
    private func toggleButton(title: String, isOn: Binding<Bool>, icon: String) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isOn.wrappedValue ? .green : .gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOn.wrappedValue ? Color.green.opacity(0.12) : Color.white.opacity(0.04))
            .cornerRadius(15)
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(isOn.wrappedValue ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
    }
    
    // MARK: - 绘图撤销、清除
    
    private func undoDrawing() {
        guard !drawings.isEmpty else { return }
        // 压入撤销历史
        drawingRedoHistory.append(drawings)
        drawings.removeLast()
    }
    
    private func clearAllDrawings() {
        if !drawings.isEmpty {
            drawingHistory.append(drawings)
            drawings.removeAll()
            drawingRedoHistory.removeAll()
        }
    }
    
    // MARK: - 视频导入逻辑
    
    private func loadSelectedVideo(from pickerItem: PhotosPickerItem) {
        pickerItem.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data?):
                // PhotosPicker 返回数据，必须存入本地临时沙盒才能由 AVPlayer 加载
                let tempDir = NSTemporaryDirectory()
                let tempURL = URL(fileURLWithPath: tempDir).appendingPathComponent("imported_swing.mp4")
                
                try? FileManager.default.removeItem(at: tempURL)
                
                do {
                    try data.write(to: tempURL)
                    DispatchQueue.main.async {
                        loadVideoFromURL(tempURL)
                    }
                } catch {
                    print("Error saving video data to sandbox: \(error)")
                }
            case .failure(let error):
                print("Photos picker loading error: \(error.localizedDescription)")
            default:
                break
            }
        }
    }
    
    private func loadVideoFromURL(_ url: URL) {
        drawings.removeAll()
        keyframes.removeAll()
        playbackManager.loadVideo(url: url)
    }
    
    /// 加载网络示例高尔夫挥杆视频 (LG Golf Slo-Mo 慢动作教程视频)
    private func loadDemoVideo() {
        // 由于是网络视频，可以直接使用公开直链
        if let url = URL(string: "http://www.lg-golf.com/images/tutorials/fullswingslomo.mp4") {
            loadVideoFromURL(url)
        }
    }
    
    /// 标记节点
    private func saveKeyframe(stage: SwingStage) {
        let marker = KeyframeMarker(time: playbackManager.currentTime, stage: stage)
        // 滤重，防止同阶段多次标记
        keyframes.removeAll(where: { $0.stage == stage.rawValue })
        keyframes.append(marker)
        keyframes.sort(by: { $0.time < $1.time })
    }
    
    // MARK: - 时间格式化
    
    private func formatTime(_ time: Double) -> String {
        guard !time.isNaN else { return "00:00.00" }
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        let hundredths = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", mins, secs, hundredths)
    }
    
    // MARK: - AI 分析结果
    
    private func runAISwingAnalysis() {
        playbackManager.analyzeSwing { result in
            self.keyframes = result.detectedMarkers
            withAnimation(.spring()) { self.showAnalysisReport = true }
        }
    }

    private func performMediaAction(kind: MediaExportKind) {
        guard let action = pendingMediaAction, let asset = playbackManager.currentAsset else {
            mediaStatusMessage = "没有可保存或分享的视频。"
            pendingMediaAction = nil
            return
        }

        pendingMediaAction = nil
        let time = playbackManager.currentTime
        let drawingsForFrame = drawings.filter { $0.shouldShow(at: time) }
        isExporting = true

        Task {
            do {
                let exportURL = try await MediaExportService.export(
                    kind: kind,
                    asset: asset,
                    time: time,
                    drawings: kind == .frame ? drawingsForFrame : drawings
                )

                switch action {
                case .save:
                    try await MediaExportService.saveToPhotoLibrary(exportURL, kind: kind)
                    mediaStatusMessage = kind == .frame ? "当前帧已保存到相册。" : "标注视频已保存到相册。"
                case .share:
                    sharePayload = SharePayload(url: exportURL)
                }
            } catch {
                mediaStatusMessage = error.localizedDescription
            }
            isExporting = false
        }
    }
    
    private var analysisReportOverlay: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showAnalysisReport = false }
                }
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.green)
                        .font(.title3)
                    Text("AI 分析结果")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { withAnimation { showAnalysisReport = false } }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title3)
                    }
                }
                .padding(.bottom, 2)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("已识别 \(analysisPresentation.markers.count) / 8 个关键阶段")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(analysisPresentation.unresolvedStages.isEmpty ? "所有阶段均可在时间轴中逐帧核对。" : "未确定阶段可在时间轴逐帧手动设置。")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                .padding(12)
                .background(Color.white.opacity(0.04))
                .cornerRadius(12)

                if let analysisFailureMessage {
                    Text(analysisFailureMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.orange.opacity(0.10))
                        .cornerRadius(12)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("体态叠层")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    Toggle("骨架", isOn: $showPoseSkeleton)
                    Toggle("头部轨迹", isOn: $showHeadStability)
                    Toggle("身体倾斜", isOn: $showSpineAngle)
                    if let angle = playbackManager.currentPose?.spineAngle {
                        Text(String(format: "当前帧身体倾斜：%.1f°", abs(angle)))
                            .font(.system(size: 11))
                            .foregroundColor(.cyan)
                    } else {
                        Text("暂停或拖动到清晰人体帧后可显示当前体态。")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.04))
                .cornerRadius(12)
                
                // Action
                Button(action: { withAnimation { showAnalysisReport = false } }) {
                    Text("查看视频阶段细节")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Color(red: 0.08, green: 0.10, blue: 0.15))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .frame(maxWidth: 320)
            .shadow(color: .black.opacity(0.4), radius: 12)
        }
        .transition(.opacity)
    }

    private var analysisFailureMessage: String? {
        switch playbackManager.analysisFailure {
        case .noVideo:
            return "没有可分析的视频。请先导入或录制一段挥杆视频。"
        case .invalidDuration:
            return "这段视频无法读取有效时长，请更换视频后重试。"
        case .insufficientPoseEvidence:
            return "未检测到足够清晰的人体关节点；请使用全身入镜、侧面且光线充足的视频后重试。"
        case nil:
            return nil
        }
    }
}

// MARK: - 指标展示卡片

struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }
}

// MARK: - 静态基准线网格

struct GridView: View {
    let rect: CGRect
    
    var body: some View {
        Path { path in
            // 两条纵向对准参考线
            let colWidth = rect.width / 3.0
            for i in 1...2 {
                let x = rect.minX + CGFloat(i) * colWidth
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            
            // 两条横向对准参考线
            let rowHeight = rect.height / 3.0
            for i in 1...2 {
                let y = rect.minY + CGFloat(i) * rowHeight
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
}

// MARK: - V1 Sports 风格飞轮微调控制器 (微调拨盘)

struct JogDialView: View {
    let onStep: (Bool) -> Void
    @GestureState private var dragOffset: CGFloat = 0
    @State private var lastOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let stepDistance: CGFloat = 8.0 // 每滑动 8 像素步进一帧
            
            ZStack {
                // 飞轮滚动线背景 (仿物理拨圈刻度)
                HStack(spacing: 4) {
                    ForEach(0..<18) { i in
                        Rectangle()
                            .fill(Color.white.opacity(i % 5 == 0 ? 0.6 : 0.25))
                            .frame(width: 1.5, height: i % 5 == 0 ? 12 : 6)
                    }
                }
                .offset(x: lastOffset + dragOffset)
                
                // 中心刻度对齐线 (绿色)
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 2, height: 16)
                    .shadow(color: .green.opacity(0.8), radius: 2)
            }
            .frame(width: width, height: 26)
            .background(Color.white.opacity(0.06))
            .cornerRadius(13)
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.width
                    }
                    .onChanged { value in
                        let delta = value.translation.width
                        let currentStepCount = Int(delta / stepDistance)
                        let lastStepCount = Int(self.lastOffset / stepDistance)
                        
                        if currentStepCount != lastStepCount {
                            let forward = currentStepCount > lastStepCount
                            onStep(forward)
                            self.lastOffset = delta
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.lastOffset = 0
                        }
                    }
            )
        }
        .frame(height: 26)
    }
}

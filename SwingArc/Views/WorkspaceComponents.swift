import SwiftUI

struct WorkspaceHeaderView: View {
    let projectName: String
    let saveStatus: WorkspaceSaveStatus
    let hasResults: Bool
    let isRegularLayout: Bool
    let showsProjectSidebar: Bool
    let showsInspector: Bool
    let onBack: () -> Void
    let onToggleProjectSidebar: () -> Void
    let onToggleInspector: () -> Void
    let onShowResults: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("返回项目库")

            if isRegularLayout {
                Button(action: onToggleProjectSidebar) {
                    Image(systemName: showsProjectSidebar ? "sidebar.left" : "sidebar.left")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(showsProjectSidebar ? "收起项目栏" : "展开项目栏")
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(projectName)
                    .font(.headline)
                    .lineLimit(1)
                if !saveStatus.label.isEmpty {
                    Label(saveStatus.label, systemImage: saveStatus == .failed ? "exclamationmark.circle" : "checkmark")
                        .font(.caption2)
                        .foregroundStyle(saveStatus == .failed ? Color.red : Color.white.opacity(0.58))
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 4)

            if hasResults {
                Button(action: onShowResults) {
                    Image(systemName: "list.bullet.rectangle")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("查看分析结果")
            }

            Button(action: onExport) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("导出")

            if isRegularLayout {
                Button(action: onToggleInspector) {
                    Image(systemName: "sidebar.right")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(showsInspector ? "收起检查器" : "展开检查器")
            }
        }
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(minHeight: 52)
        .background(AnalysisTheme.chrome)
    }
}

struct StageTimelineView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    let keyframes: [KeyframeMarker]
    let presentation: AnalysisWorkspacePresentation
    let onStageTap: (SwingStage, KeyframeMarker?) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(formatTime(playbackManager.currentTime))
                Slider(
                    value: Binding(
                        get: { min(playbackManager.currentTime, max(playbackManager.duration, 0)) },
                        set: { playbackManager.seek(to: $0) }
                    ),
                    in: 0...max(playbackManager.duration, 0.001)
                )
                .tint(AnalysisTheme.current)
                .accessibilityLabel("视频时间轴")
                Text(formatTime(playbackManager.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 3) {
                ForEach(SwingStage.allCases) { stage in
                    let descriptor = StageDisplayDescriptor(
                        stage: stage,
                        keyframes: keyframes,
                        presentation: presentation,
                        currentTime: playbackManager.currentTime,
                        frameDuration: VideoFramePolicy.frameDuration(sourceFrameRate: playbackManager.sourceFrameRate)
                    )
                    Button {
                        onStageTap(stage, descriptor.marker)
                    } label: {
                        VStack(spacing: 3) {
                            Text(stage.pNumber)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.84))
                            Image(
                                systemName: StageStripPolicy
                                    .indicator(for: descriptor.resultState)
                                    .rawValue
                            )
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(descriptor.stageStripColor)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: StageStripPolicy.buttonHeight)
                        .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .bottom) {
                            if descriptor.isCurrent {
                                Capsule()
                                    .fill(AnalysisTheme.current)
                                    .frame(height: 3)
                                    .padding(.horizontal, 5)
                                    .padding(.bottom, 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(descriptor.accessibilityLabel)
                    .accessibilityHint(descriptor.marker == nil ? "打开人工设置" : "跳到该阶段")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxHeight: StageStripPolicy.maximumTotalHeight)
        .background(AnalysisTheme.chrome)
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "00:00.00" }
        let value = max(time, 0)
        let minutes = Int(value) / 60
        let seconds = Int(value) % 60
        let hundredths = Int((value.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }
}

struct PlaybackControlsView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    @Binding var interactionMode: WorkspaceInteractionMode
    let hasResults: Bool
    let onToggleDrawing: () -> Void
    let onAnalyze: () -> Void
    let onShowResults: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(PlaybackRate.allCases) { rate in
                    Button(rate.label) { playbackManager.setSpeed(rate.value) }
                }
            } label: {
                Text(speedLabel)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .frame(minWidth: 48, minHeight: 44)
                    .background(AnalysisTheme.raisedChrome, in: Capsule())
            }
            .accessibilityLabel("播放速度，当前 \(speedLabel)")

            controlButton("backward.frame.fill", label: "后退一帧") {
                playbackManager.stepFrame(forward: false)
            }

            Button {
                if playbackManager.isPlaying {
                    playbackManager.pause()
                } else {
                    interactionMode = WorkspaceModeTransition.beginPlayback.mode
                    playbackManager.play()
                }
            } label: {
                Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.bold))
                    .frame(width: 54, height: 54)
                    .foregroundStyle(.black)
                    .background(AnalysisTheme.confirmed, in: Circle())
            }
            .accessibilityLabel(playbackManager.isPlaying ? "暂停" : "播放")

            controlButton("forward.frame.fill", label: "前进一帧") {
                playbackManager.stepFrame(forward: true)
            }

            Button(action: onToggleDrawing) {
                Image(systemName: "pencil.tip")
                    .frame(width: 44, height: 44)
                    .background(
                        interactionMode == .drawing ? AnalysisTheme.current : AnalysisTheme.raisedChrome,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(interactionMode == .drawing ? .black : .white)
            }
            .accessibilityLabel(interactionMode == .drawing ? "结束画线" : "画线")

            Button(action: hasResults ? onShowResults : onAnalyze) {
                VStack(spacing: 1) {
                    Image(systemName: hasResults ? "list.bullet.rectangle" : "sparkles")
                    Text(hasResults ? "结果" : "AI")
                        .font(.caption2.weight(.semibold))
                }
                .frame(width: 50, height: 44)
                .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(AnalysisTheme.pose)
            }
            .disabled(playbackManager.isScanning)
            .accessibilityLabel(hasResults ? "查看分析结果" : "开始 AI 分析")
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(AnalysisTheme.canvasBackground)
    }

    private var speedLabel: String {
        PlaybackRate.allCases.first(where: { abs($0.value - playbackManager.playbackSpeed) < 0.001 })?.label
            ?? String(format: "%.2g×", playbackManager.playbackSpeed)
    }

    private func controlButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
                .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(label)
    }
}

struct DrawingToolRail: View {
    @Binding var activeTool: DrawingTool
    @Binding var selectedColor: Color
    @Binding var isKeyframeMode: Bool
    let onUndo: () -> Void
    let onClear: () -> Void
    let onDone: () -> Void

    @State private var confirmsClear = false
    @State private var showsColorPalette = false

    var body: some View {
        VStack(spacing: 5) {
            railButton(
                systemImage: "xmark",
                label: "关闭画线工具",
                isActive: false
            ) {
                showsColorPalette = false
                onDone()
            }

            ForEach(DrawingTool.allCases) { tool in
                toolButton(tool)
            }

            Button {
                showsColorPalette = false
                isKeyframeMode.toggle()
            } label: {
                Image(systemName: isKeyframeMode ? "pin.fill" : "rectangle.inset.filled")
                    .frame(width: 44, height: 44)
                    .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 11))
            }
            .foregroundStyle(.white)
            .accessibilityLabel(isKeyframeMode ? "仅当前 P 点显示" : "全视频显示")
            .accessibilityHint(isKeyframeMode ? "切换为全视频显示" : "切换为仅当前 P 点显示")

            DrawingUndoControl(
                onUndo: onUndo,
                onRequestClear: { confirmsClear = true }
            )
        }
        .padding(6)
        .frame(maxWidth: WorkspaceAccessoryPolicy.drawingRailMaximumWidth)
        .fixedSize(horizontal: true, vertical: false)
        .background(AnalysisTheme.chrome.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        .confirmationDialog("清除所有标注？", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("清除", role: .destructive, action: onClear)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除项目中的所有画线。")
        }
        .onAppear {
            showsColorPalette = activeTool.revealsColorPalette
        }
        .onChange(of: activeTool) { _, tool in
            showsColorPalette = tool.revealsColorPalette
        }
    }

    private func toolButton(_ tool: DrawingTool) -> some View {
        railButton(
            systemImage: tool.iconName,
            label: tool.rawValue,
            isActive: activeTool == tool,
            symbolColor: tool.revealsColorPalette ? selectedColor : nil
        ) {
            if activeTool == tool, tool.revealsColorPalette {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showsColorPalette.toggle()
                }
            } else {
                activeTool = tool
                showsColorPalette = tool.revealsColorPalette
            }
        }
        .overlay(alignment: .trailing) {
            if activeTool == tool, tool.revealsColorPalette, showsColorPalette {
                DrawingColorPalette(selectedColor: $selectedColor) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showsColorPalette = false
                    }
                }
                .fixedSize()
                .offset(x: -52)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .zIndex(activeTool == tool && showsColorPalette ? 2 : 0)
    }

    private func railButton(
        systemImage: String,
        label: String,
        isActive: Bool,
        symbolColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
                .foregroundStyle(symbolColor ?? (isActive ? AnalysisTheme.current : .white))
                .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 11))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(isActive ? AnalysisTheme.current : .clear, lineWidth: 2)
                )
        }
        .accessibilityLabel(label)
    }
}

private struct DrawingColorPalette: View {
    @Binding var selectedColor: Color
    let onSelect: () -> Void

    private let colors: [(name: String, color: Color)] = [
        ("红色", .red),
        ("黄色", .yellow),
        ("绿色", .green),
        ("蓝色", .blue),
        ("白色", .white)
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, option in
                Button {
                    selectedColor = option.color
                    onSelect()
                } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(option.color)
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.65), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.name)
            }
        }
        .padding(6)
        .background(AnalysisTheme.chrome.opacity(0.96), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
    }
}

private struct DrawingUndoControl: View {
    let onUndo: () -> Void
    let onRequestClear: () -> Void

    var body: some View {
        Image(systemName: "arrow.uturn.backward")
            .frame(width: 44, height: 44)
            .foregroundStyle(.white)
            .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.6)
                    .exclusively(before: TapGesture())
                    .onEnded { value in
                        switch value {
                        case .first(true):
                            if DrawingRailPolicy.undoIntent(isLongPress: true) == .confirmClearAll {
                                onRequestClear()
                            }
                        case .second:
                            if DrawingRailPolicy.undoIntent(isLongPress: false) == .undoLast {
                                onUndo()
                            }
                        default:
                            break
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("撤销")
            .accessibilityHint("轻点撤销最后一笔，长按清除全部标注")
            .accessibilityAction(named: Text("撤销"), onUndo)
            .accessibilityAction(named: Text("清除全部标注"), onRequestClear)
    }
}

struct AnalysisProgressCard: View {
    let phase: AnalysisProgressPhase
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        let presentation = AnalysisProgressPresentation(phase: phase, progress: progress)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title).font(.subheadline.weight(.semibold))
                    Text(presentation.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(presentation.percentage)%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                Button("取消", action: onCancel)
                    .font(.caption.weight(.semibold))
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(AnalysisTheme.confirmed)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(presentation.title)，\(presentation.percentage)%")
    }
}

struct AnalysisFailureBanner: View {
    let failure: AnalysisFailure

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(AnalysisFailurePresentation(failure: failure).message)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(AnalysisTheme.current)
        .padding(10)
        .background(AnalysisTheme.chrome)
        .accessibilityElement(children: .combine)
    }
}

struct StageInspectorView: View {
    let presentation: AnalysisWorkspacePresentation
    let keyframes: [KeyframeMarker]
    let sourceFrameRate: Double
    let onSeek: (Double) -> Void
    let onAdjust: (SwingStage) -> Void

    var body: some View {
        let descriptors = SwingStage.allCases.map {
            StageDisplayDescriptor(
                stage: $0,
                keyframes: keyframes,
                presentation: presentation,
                currentTime: -1,
                frameDuration: 0
            )
        }
        let summary = StageResultSummary(statuses: descriptors.map(\.resultState))

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("阶段结果")
                    .font(.headline)
                Text("已确认 \(summary.confirmed) · 待核对 \(summary.review) · 未确定 \(summary.unresolved)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(descriptors, id: \.stage.id) { descriptor in
                        HStack(spacing: 10) {
                            Text(descriptor.stage.pNumber)
                                .font(.subheadline.weight(.bold))
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(descriptor.stage.displayName)
                                    .font(.subheadline.weight(.medium))
                                Text(descriptor.detailText(sourceFrameRate: sourceFrameRate))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let marker = descriptor.marker {
                                Button("查看") { onSeek(marker.time) }
                                    .font(.caption.weight(.semibold))
                            }
                            Button("调整") { onAdjust(descriptor.stage) }
                                .font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(descriptor.borderColor))
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }
}

struct WorkspaceInspectorView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    let presentation: AnalysisWorkspacePresentation
    let keyframes: [KeyframeMarker]
    @Binding var showPoseSkeleton: Bool
    @Binding var showHeadStability: Bool
    @Binding var showSpineAngle: Bool
    @Binding var showGrid: Bool
    let onCancelAnalysis: () -> Void
    let onSeek: (Double) -> Void
    let onAdjust: (SwingStage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if playbackManager.isScanning {
                AnalysisProgressCard(
                    phase: playbackManager.analysisProgressPhase,
                    progress: playbackManager.scanProgress,
                    onCancel: onCancelAnalysis
                )
            } else {
                StageInspectorView(
                    presentation: presentation,
                    keyframes: keyframes,
                    sourceFrameRate: playbackManager.sourceFrameRate,
                    onSeek: onSeek,
                    onAdjust: onAdjust
                )
            }

            if let failure = playbackManager.analysisFailure {
                AnalysisFailureBanner(failure: failure)
            }

            Divider().overlay(.white.opacity(0.14))

            VStack(alignment: .leading, spacing: 8) {
                Text("叠层")
                    .font(.headline)
                Toggle("骨架", isOn: $showPoseSkeleton)
                Toggle("头部轨迹", isOn: $showHeadStability)
                Toggle("身体倾斜", isOn: $showSpineAngle)
                Toggle("参考网格", isOn: $showGrid)
            }
            .disabled(!presentation.allowsPoseOverlays)

            if !presentation.allowsPoseOverlays {
                Text("分析完成后可开启人体叠层")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .foregroundStyle(.white)
        .background(AnalysisTheme.chrome)
    }
}

struct StageAdjustmentBar: View {
    let stage: SwingStage
    let detection: SwingStageDetection?
    @ObservedObject var playbackManager: VideoPlaybackManager
    let onCancel: () -> Void
    let onSetCurrentFrame: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text(stage.shortName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(confidenceLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(confidenceColor)
                Spacer(minLength: 4)
                Text("\(formatTime(playbackManager.currentTime)) · #\(currentFrame)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.68))
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                }
                .foregroundStyle(.white.opacity(0.78))
                .accessibilityLabel("取消调整")
            }

            HStack(spacing: 8) {
                frameButton(systemImage: "backward.frame.fill", label: "前一帧") {
                    playbackManager.stepFrame(forward: false)
                }

                Button(action: onSetCurrentFrame) {
                    Text("设为当前帧")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .background(AnalysisTheme.confirmed, in: RoundedRectangle(cornerRadius: 12))

                frameButton(systemImage: "forward.frame.fill", label: "后一帧") {
                    playbackManager.stepFrame(forward: true)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AnalysisTheme.chrome)
        .overlay(alignment: .top) { Divider().overlay(.white.opacity(0.10)) }
    }

    private var currentFrame: Int {
        Int((playbackManager.currentTime * max(playbackManager.sourceFrameRate, 1)).rounded())
    }

    private var confidenceLabel: String {
        switch detection?.status {
        case .confirmed: return "已确认"
        case .lowConfidence: return "待核对"
        case .unresolved, nil: return "未确定"
        }
    }

    private var confidenceColor: Color {
        switch detection?.status {
        case .confirmed: return AnalysisTheme.confirmed
        case .lowConfidence: return AnalysisTheme.current
        case .unresolved, nil: return .white.opacity(0.55)
        }
    }

    private func formatTime(_ value: Double) -> String {
        String(format: "%.3fs", max(value, 0))
    }

    private func frameButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 48, height: 44)
                .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }
}

struct WorkspaceProjectSidebar: View {
    let projects: [LocalProjectSummary]
    let selectedProjectID: UUID
    let onSelect: (LocalProjectSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("项目")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(projects) { project in
                        Button { onSelect(project) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text(project.modifiedAt, format: .relative(presentation: .named))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                project.id == selectedProjectID ? AnalysisTheme.raisedChrome : .clear,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .background(AnalysisTheme.chrome)
    }
}

struct GridView: View {
    let rect: CGRect

    var body: some View {
        Canvas { context, _ in
            guard rect.width > 0, rect.height > 0 else { return }
            var path = Path()
            for index in 1..<3 {
                let x = rect.minX + rect.width * CGFloat(index) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                let y = rect.minY + rect.height * CGFloat(index) / 3
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }
}

private struct StageDisplayDescriptor {
    let stage: SwingStage
    let marker: KeyframeMarker?
    let detection: SwingStageDetection?
    let isCurrent: Bool

    init(
        stage: SwingStage,
        keyframes: [KeyframeMarker],
        presentation: AnalysisWorkspacePresentation,
        currentTime: Double,
        frameDuration: Double
    ) {
        self.stage = stage
        marker = keyframes.first { $0.stage == stage.rawValue }
        detection = presentation.detection(for: stage)
        if let marker, currentTime >= 0 {
            isCurrent = abs(marker.time - currentTime) <= max(frameDuration * 1.5, 0.02)
        } else {
            isCurrent = false
        }
    }

    var resultState: StageResultState {
        if marker?.isLocked == true { return .manual }
        if detection?.status == .lowConfidence { return .review }
        if marker != nil { return .confirmed }
        return .unresolved
    }

    var stageStripColor: Color {
        switch resultState {
        case .confirmed, .manual: return AnalysisTheme.confirmed
        case .review: return AnalysisTheme.current
        case .unresolved: return .white.opacity(0.42)
        }
    }

    var symbol: String {
        if isCurrent { return "location.fill" }
        switch resultState {
        case .confirmed: return "checkmark"
        case .manual: return "lock.fill"
        case .review: return "exclamationmark"
        case .unresolved: return "minus"
        }
    }

    var shortStatus: String {
        if isCurrent { return "当前" }
        switch resultState {
        case .confirmed: return "已确认"
        case .manual: return "已锁定"
        case .review: return "待核对"
        case .unresolved: return "未确定"
        }
    }

    var foregroundColor: Color {
        isCurrent ? .black : .white
    }

    var backgroundColor: Color {
        if isCurrent { return AnalysisTheme.current }
        switch resultState {
        case .confirmed, .manual: return AnalysisTheme.confirmed.opacity(0.18)
        case .review: return AnalysisTheme.current.opacity(0.16)
        case .unresolved: return AnalysisTheme.raisedChrome
        }
    }

    var borderColor: Color {
        if isCurrent { return AnalysisTheme.current }
        switch resultState {
        case .confirmed, .manual: return AnalysisTheme.confirmed.opacity(0.72)
        case .review: return AnalysisTheme.current.opacity(0.78)
        case .unresolved: return .white.opacity(0.10)
        }
    }

    var accessibilityLabel: String {
        var parts = [stage.shortName, shortStatus]
        if let marker {
            parts.append(String(format: "%.3f 秒", marker.time))
        }
        return parts.joined(separator: "，")
    }

    func detailText(sourceFrameRate: Double) -> String {
        guard let marker else { return shortStatus }
        let frame = detection?.sourceFrameIndex
            ?? Int((marker.time * max(sourceFrameRate, 1)).rounded())
        var parts = [
            String(format: "%.3f 秒", marker.time),
            "第 \(frame) 帧",
            shortStatus
        ]
        if let detection {
            parts.append("置信度 \(Int((detection.confidence * 100).rounded()))%")
            if stage == .takeaway || stage == .impact {
                parts.append(detection.hasClubEvidence ? "有杆身" : "无杆身")
            }
            if stage == .impact {
                parts.append(detection.hasBallEvidence ? "有球位" : "无球位")
            }
        }
        return parts.joined(separator: " · ")
    }
}

private extension SwingStage {
    var pNumber: String {
        "P\((SwingStage.allCases.firstIndex(of: self) ?? 0) + 1)"
    }

    var displayName: String {
        switch self {
        case .address: return "准备"
        case .takeaway: return "起杆"
        case .leadArmParallelBackswing: return "上杆左臂平行"
        case .top: return "上杆顶点"
        case .leadArmParallelDownswing: return "下杆左臂平行"
        case .impact: return "击球"
        case .followThrough: return "送杆"
        case .finish: return "收杆"
        }
    }
}

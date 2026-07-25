import SwiftUI

struct AnalysisWorkspaceView: View {
    let project: LocalProjectSummary
    let projects: [LocalProjectSummary]
    @ObservedObject var playbackManager: VideoPlaybackManager
    @Binding var drawings: [DrawingElement]
    @Binding var keyframes: [KeyframeMarker]
    @Binding var isKeyframeMode: Bool
    @Binding var showPoseSkeleton: Bool
    @Binding var showHeadStability: Bool
    @Binding var showSpineAngle: Bool
    @Binding var showGrid: Bool
    @Binding var practiceCameraView: PracticeCameraView?
    let saveStatus: WorkspaceSaveStatus
    let onBack: () -> Void
    let onSelectProject: (LocalProjectSummary) -> Void
    let onExport: () -> Void
    let onAnalyze: () -> Void
    let onCancelAnalysis: () -> Void
    let onSetManualStage: (SwingStage) -> Void
    let onCorrectPPoints: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var interactionMode: WorkspaceInteractionMode = .idle
    @State private var activeTool: DrawingTool = .line
    @State private var selectedColor: Color = .white
    @State private var strokeWidth: CGFloat = 3
    @State private var showsProjectSidebar = true
    @State private var showsInspector = true
    @State private var showsResultsSheet = false
    @State private var adjustmentStage: SwingStage?
    @State private var expandedFeedbackCategory: SwingFeedbackCategory?

    private var presentation: AnalysisWorkspacePresentation {
        AnalysisWorkspacePresentation(state: playbackManager.analysisState)
    }

    private var simplifiedFeedback: SimplifiedSwingFeedback? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if SimplifiedFeedbackPreview.isEnabled(arguments) {
            return SimplifiedFeedbackPreview.feedback
        }
        #endif

        return playbackManager.simplifiedFeedback(
            view: practiceCameraView,
            manualMarkers: keyframes
        )
    }

    private var trajectoryStageTimes: [SwingTrajectoryStageTime] {
        playbackManager.correctedDetections(manualMarkers: keyframes).compactMap {
            guard let time = $0.time else { return nil }
            return SwingTrajectoryStageTime(stage: $0.stage, time: time)
        }
    }

    private var trajectoryFrames: [SwingFrameObservation] {
        playbackManager.analysisOutput?.observationFrames ?? []
    }

    var body: some View {
        GeometryReader { geometry in
            let isRegularLayout = horizontalSizeClass == .regular && geometry.size.width >= 900

            HStack(spacing: 0) {
                if isRegularLayout && showsProjectSidebar {
                    WorkspaceProjectSidebar(
                        projects: projects,
                        selectedProjectID: project.id,
                        onSelect: onSelectProject
                    )
                    .frame(width: 210)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                centerWorkbench(isRegularLayout: isRegularLayout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isRegularLayout && showsInspector {
                    WorkspaceInspectorView(
                        playbackManager: playbackManager,
                        presentation: presentation,
                        keyframes: keyframes,
                        showPoseSkeleton: $showPoseSkeleton,
                        showHeadStability: $showHeadStability,
                        showSpineAngle: $showSpineAngle,
                        showGrid: $showGrid,
                        onCancelAnalysis: onCancelAnalysis,
                        onSeek: playbackManager.seek,
                        onAdjust: openAdjustment
                    )
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(AnalysisTheme.proTourBackground)
            .animation(.easeInOut(duration: 0.2), value: showsProjectSidebar)
            .animation(.easeInOut(duration: 0.2), value: showsInspector)
            .onChange(of: isRegularLayout) { _, regular in
                if !regular {
                    showsProjectSidebar = false
                    showsInspector = false
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showsResultsSheet) {
            NavigationStack {
                Group {
                    if let simplifiedFeedback {
                        SimplifiedSwingFeedbackView(
                            feedback: simplifiedFeedback,
                            expandedCategory: $expandedFeedbackCategory,
                            onSelectStage: selectStage,
                            onAdjustStage: openAdjustment
                        )
                    } else if practiceCameraView == nil {
                        VStack(spacing: 18) {
                            Spacer()

                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(AnalysisTheme.proTourSignal)

                            Text("选择拍摄视角")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(AnalysisTheme.proTourPrimaryText)

                            Text("选择后将使用对应视角分析视频")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AnalysisTheme.proTourSecondaryText)

                            HStack(spacing: 12) {
                                cameraViewButton(
                                    title: "正后方 DTL",
                                    view: .downTheLine
                                )
                                cameraViewButton(
                                    title: "正面 Face-on",
                                    view: .faceOn
                                )
                            }
                            .padding(.horizontal, 20)

                            Spacer()
                        }
                        .background(AnalysisTheme.proTourBackground)
                    } else {
                        ContentUnavailableView(
                            "暂无动作反馈",
                            systemImage: "figure.golf",
                            description: Text(
                                practiceCameraView == nil
                                    ? "缺少拍摄视角，无法生成可靠的动作结论。"
                                    : "请先完成视频分析。"
                            )
                        )
                        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                        .background(AnalysisTheme.proTourBackground)
                    }
                }
                .navigationTitle("分析结果")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showsResultsSheet = false }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task(id: project.id) {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if SimplifiedFeedbackPreview.isEnabled(arguments) {
                if SimplifiedFeedbackPreview.expandsHandPath(arguments) {
                    expandedFeedbackCategory = .handPath
                }
                try? await Task.sleep(for: .milliseconds(250))
                showsResultsSheet = true
                return
            }

            guard PracticePreviewConfiguration.autoAnalyzes(
                for: arguments
            ) else { return }

            try? await Task.sleep(for: .milliseconds(250))
            requestAnalysis()
            #endif
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func centerWorkbench(isRegularLayout: Bool) -> some View {
        if isRegularLayout {
            regularReplayWorkbench(isRegularLayout: isRegularLayout)
        } else {
            mobileReplayWorkbench
        }
    }

    private func regularReplayWorkbench(isRegularLayout: Bool) -> some View {
        VStack(spacing: 0) {
            WorkspaceHeaderView(
                projectName: project.name,
                saveStatus: saveStatus,
                hasResults: playbackManager.analysisState.hasCompletedResult,
                isRegularLayout: isRegularLayout,
                showsProjectSidebar: showsProjectSidebar,
                showsInspector: showsInspector,
                onBack: onBack,
                onToggleProjectSidebar: { showsProjectSidebar.toggle() },
                onToggleInspector: { showsInspector.toggle() },
                onShowResults: showResults(isRegularLayout: isRegularLayout),
                onCorrectPPoints: onCorrectPPoints,
                onExport: onExport
            )

            ZStack {
                VideoCanvasView(
                    playbackManager: playbackManager,
                    drawings: $drawings,
                    activeTool: $activeTool,
                    selectedColor: $selectedColor,
                    strokeWidth: $strokeWidth,
                    isKeyframeMode: $isKeyframeMode,
                    showPoseSkeleton: showPoseSkeleton,
                    showHeadStability: showHeadStability,
                    showSpineAngle: showSpineAngle,
                    showGrid: showGrid,
                    interactionMode: interactionMode,
                    showsFullscreenButton: false,
                    onEnterFullscreen: {},
                    trajectoryCategory: expandedFeedbackCategory,
                    trajectoryFrames: trajectoryFrames,
                    trajectoryStageTimes: trajectoryStageTimes
                )

                if interactionMode == .idle, !isRegularLayout {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: toggleWorkspacePlayback)
                }

                if !isRegularLayout {
                    mobileReviewChrome
                }

                if interactionMode == .drawing {
                    DrawingToolRail(
                        activeTool: $activeTool,
                        selectedColor: $selectedColor,
                        isKeyframeMode: $isKeyframeMode,
                        onUndo: { if !drawings.isEmpty { drawings.removeLast() } },
                        onClear: { drawings.removeAll() },
                        onDone: { interactionMode = .idle }
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: interactionMode)

            if isRegularLayout {
                StageTimelineView(
                    playbackManager: playbackManager,
                    keyframes: keyframes,
                    presentation: presentation,
                    onStageTap: { stage, marker in
                        if let marker {
                            playbackManager.seek(to: marker.time)
                        } else {
                            openAdjustment(stage)
                        }
                    }
                )

                if let adjustmentStage {
                    StageAdjustmentBar(
                        stage: adjustmentStage,
                        detection: presentation.detection(for: adjustmentStage),
                        playbackManager: playbackManager,
                        onCancel: { self.adjustmentStage = nil },
                        onSetCurrentFrame: {
                            onSetManualStage(adjustmentStage)
                            self.adjustmentStage = nil
                        }
                    )
                } else {
                    PlaybackControlsView(
                        playbackManager: playbackManager,
                        interactionMode: $interactionMode,
                        hasResults: playbackManager.analysisState.hasCompletedResult,
                        onToggleDrawing: toggleDrawingMode,
                        onAnalyze: {
                            interactionMode = .idle
                            requestAnalysis()
                        },
                        onShowResults: showResults(isRegularLayout: isRegularLayout)
                    )
                }
            }
        }
    }

    private var mobileReplayWorkbench: some View {
        ZStack {
            VideoCanvasView(
                playbackManager: playbackManager,
                drawings: $drawings,
                activeTool: $activeTool,
                selectedColor: $selectedColor,
                strokeWidth: $strokeWidth,
                isKeyframeMode: $isKeyframeMode,
                showPoseSkeleton: showPoseSkeleton,
                showHeadStability: showHeadStability,
                showSpineAngle: showSpineAngle,
                showGrid: showGrid,
                interactionMode: interactionMode,
                showsFullscreenButton: false,
                onEnterFullscreen: {},
                trajectoryCategory: expandedFeedbackCategory,
                trajectoryFrames: trajectoryFrames,
                trajectoryStageTimes: trajectoryStageTimes
            )
            .ignoresSafeArea()

            if interactionMode == .idle {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggleWorkspacePlayback)
            }

            mobileReplayHeader
            mobileReviewChrome

            if interactionMode == .drawing {
                DrawingToolRail(
                    activeTool: $activeTool,
                    selectedColor: $selectedColor,
                    isKeyframeMode: $isKeyframeMode,
                    onUndo: { if !drawings.isEmpty { drawings.removeLast() } },
                    onClear: { drawings.removeAll() },
                    onDone: { interactionMode = .idle }
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 10)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color.black)
        .animation(.easeInOut(duration: 0.2), value: interactionMode)
    }

    private var mobileReplayHeader: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 23, weight: .semibold))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回项目库")

            HStack(spacing: 7) {
                Text(project.name)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                if !saveStatus.label.isEmpty {
                    Circle()
                        .fill(saveStatus == .failed ? AnalysisTheme.proTourPaused : AnalysisTheme.proTourSignal)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel(saveStatus.label)
                }
            }

            Spacer(minLength: 0)

            Button(action: onCorrectPPoints) {
                Text("修正 P 点")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 72, minHeight: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("修正 P 点")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.64), .black.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var mobileReviewChrome: some View {
        ZStack {
            VStack {
                mobileAnalysisStatus
                    .padding(.top, 68)
                Spacer()
            }

            VStack {
                Spacer()
                mobileReplayOverlayControls
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var mobileAnalysisStatus: some View {
        if playbackManager.isScanning {
            let presentation = AnalysisProgressPresentation(
                phase: playbackManager.analysisProgressPhase,
                progress: playbackManager.scanProgress
            )

            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                    .tint(AnalysisTheme.proTourSignal)
                Text("AI 分析 · \(presentation.percentage)%")
                    .font(.system(size: 13, weight: .semibold))
                Text(presentation.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
                Button("取消", action: onCancelAnalysis)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AnalysisTheme.proTourSignal)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .background(.black.opacity(0.62), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
            .foregroundStyle(.white)
            .frame(maxWidth: 316)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(presentation.title)，\(presentation.percentage)%")
        } else if let failure = playbackManager.analysisFailure {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AnalysisTheme.proTourPaused)
                Text(mobileFailureMessage(failure))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(AnalysisTheme.proTourPaused.opacity(0.48), lineWidth: 1)
            }
            .frame(maxWidth: 316, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private var mobileReplayOverlayControls: some View {
        VStack(spacing: 14) {
            mobileReplayActionRow

            MobileReplayTimelineView(
                playbackManager: playbackManager,
                keyframes: keyframes
            )
        }
        .padding(.top, 34)
        .padding(.bottom, 10)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.34), .black.opacity(0.84)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.horizontal, -14)
            .padding(.bottom, -8)
        }
    }

    private var mobileReplayActionRow: some View {
        HStack {
            Button {
                interactionMode = .idle
                if playbackManager.analysisState.hasCompletedResult {
                    showResults(isRegularLayout: false)()
                } else {
                    requestAnalysis()
                }
            } label: {
                Image(
                    systemName: playbackManager.analysisState.hasCompletedResult
                        ? "list.bullet"
                        : "sparkles"
                )
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.46), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                playbackManager.isScanning ? .white.opacity(0.58) : .white
            )
            .disabled(playbackManager.isScanning)
            .accessibilityLabel(
                playbackManager.analysisState.hasCompletedResult
                    ? "查看分析结果"
                    : "开始 AI 分析"
            )

            Spacer(minLength: 20)

            Button(action: toggleDrawingMode) {
                HStack(spacing: 7) {
                    Image(systemName: "pencil.tip")
                    Text("画线")
                }
                .font(.system(size: 15, weight: .bold))
                .padding(.horizontal, 20)
                .frame(minHeight: 48)
                .background(
                    interactionMode == .drawing
                        ? AnalysisTheme.proTourSignal
                        : .black.opacity(0.56),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(interactionMode == .drawing ? 0 : 0.20), lineWidth: 1)
                }
                .foregroundStyle(
                    interactionMode == .drawing
                        ? AnalysisTheme.proTourBackground
                        : .white
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(interactionMode == .drawing ? "结束画线" : "开始画线")

            Spacer(minLength: 20)

            Button(action: onExport) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.46), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("导出")
        }
    }

    private func toggleWorkspacePlayback() {
        if playbackManager.isPlaying {
            playbackManager.pause()
        } else {
            interactionMode = WorkspaceModeTransition.beginPlayback.mode
            playbackManager.play()
        }
    }

    private func mobileFailureMessage(_ failure: AnalysisFailure) -> String {
        switch failure {
        case .noVideo:
            return "没有可分析的视频"
        case .invalidDuration, .frameExtractionFailed:
            return "视频读取失败，请重新导入"
        case .insufficientPoseEvidence:
            return "未识别到清晰的人体姿势"
        case .insufficientStageEvidence:
            return "人体已识别，但未能自动确定完整 P1–P8。你可以手动设置 P 点。"
        case .noStableGolfer:
            return "无法持续锁定主球员"
        case .noSwingMotion:
            return "未检测到完整挥杆动作"
        case .ambiguousSwingWindows:
            return "检测到多个挥杆，无法确定目标"
        case .swingWindowTooLong, .incompleteSwingClip:
            return "挥杆片段不完整"
        case .missingAddressBoundary:
            return "未找到准备位到起杆的边界"
        case .missingTopTransition:
            return "未找到上杆顶点转换"
        case .noImpactCorridor:
            return "未找到击球瞬间"
        case .missingPostImpactBoundary:
            return "未找到击球后释放边界"
        case .unsupportedInput:
            return AnalysisFailurePresentation(failure: failure).message
        case .analysisCancelled:
            return "AI 分析已取消"
        }
    }

    private func showResults(isRegularLayout: Bool) -> () -> Void {
        {
            if isRegularLayout {
                showsInspector = true
            }
            showsResultsSheet = true
        }
    }

    private func selectStage(_ stage: SwingStage) {
        playbackManager.pause()
        if let marker = keyframes.first(where: { $0.stage == stage.rawValue }) {
            playbackManager.seek(to: marker.time)
        } else if let time = presentation.detection(for: stage)?.time {
            playbackManager.seek(to: time)
        }
    }

    private func cameraViewButton(
        title: String,
        view: PracticeCameraView
    ) -> some View {
        Button {
            practiceCameraView = view
            showsResultsSheet = false
            onAnalyze()
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(
                    view == .faceOn
                        ? Color.black
                        : AnalysisTheme.proTourPrimaryText
                )
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    view == .faceOn
                        ? AnalysisTheme.proTourSignal
                        : AnalysisTheme.proTourSurface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func requestAnalysis() {
        guard practiceCameraView != nil else {
            showsResultsSheet = true
            return
        }
        onAnalyze()
    }

    private func toggleDrawingMode() {
        if interactionMode == .drawing {
            interactionMode = WorkspaceModeTransition.finishDrawing.mode
        } else {
            let transition = WorkspaceModeTransition.enterDrawing(isPlaying: playbackManager.isPlaying)
            if transition.shouldPausePlayback {
                playbackManager.pause()
            }
            interactionMode = transition.mode
        }
    }

    private func openAdjustment(_ stage: SwingStage) {
        playbackManager.pause()
        interactionMode = .idle
        if let marker = keyframes.first(where: { $0.stage == stage.rawValue }) {
            playbackManager.seek(to: marker.time)
        }
        showsResultsSheet = false
        adjustmentStage = stage
    }

}

struct FullscreenVideoPlaybackView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    @Binding var drawings: [DrawingElement]
    @Binding var isKeyframeMode: Bool
    let showPoseSkeleton: Bool
    let showHeadStability: Bool
    let showSpineAngle: Bool
    let showGrid: Bool
    let keyframes: [KeyframeMarker]
    let practiceCameraView: PracticeCameraView?
    let onAdjustStage: (SwingStage) -> Void
    let onDismiss: () -> Void

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showsFeedback = false
    @State private var expandedFeedbackCategory: SwingFeedbackCategory?
    @State private var inertTool: DrawingTool = .line
    @State private var inertColor: Color = .white
    @State private var inertWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoCanvasView(
                playbackManager: playbackManager,
                drawings: $drawings,
                activeTool: $inertTool,
                selectedColor: $inertColor,
                strokeWidth: $inertWidth,
                isKeyframeMode: $isKeyframeMode,
                showPoseSkeleton: showPoseSkeleton,
                showHeadStability: showHeadStability,
                showSpineAngle: showSpineAngle,
                showGrid: showGrid,
                interactionMode: .idle,
                showsFullscreenButton: false,
                onEnterFullscreen: {}
            )

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: togglePlaybackFromVideo)

            if controlsVisible {
                controls
                    .transition(.opacity)
            }
        }
        .onAppear {
            scheduleAutoHide()
        }
        .onDisappear {
            hideTask?.cancel()
        }
        .sheet(isPresented: $showsFeedback) {
            if let feedback = playbackManager.simplifiedFeedback(
                view: practiceCameraView,
                manualMarkers: keyframes
            ) {
                SimplifiedSwingFeedbackView(
                    feedback: feedback,
                    expandedCategory: $expandedFeedbackCategory,
                    onSelectStage: { stage in
                        if let marker = keyframes.first(where: { $0.stage == stage.rawValue }) {
                            playbackManager.seek(to: marker.time)
                        } else if let time = AnalysisWorkspacePresentation(
                            state: playbackManager.analysisState
                        ).detection(for: stage)?.time {
                            playbackManager.seek(to: time)
                        }
                    },
                    onAdjustStage: onAdjustStage
                )
                .presentationDetents([.large])
            }
        }
        .onChange(of: playbackManager.isPlaying) { _, isPlaying in
            if isPlaying {
                scheduleAutoHide()
            } else {
                hideTask?.cancel()
                setControlsVisible(true, schedulesHide: false)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        VStack {
            HStack {
                chromeButton("xmark", label: "退出全屏", action: onDismiss)
                Spacer()
                chromeButton("questionmark", label: "回放说明", action: {})
            }

            Spacer()

            Button {
                showsFeedback = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.golf")
                    Text("动作反馈")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: FullscreenPlaybackPolicy.minimumTouchTarget)
            }
            .buttonStyle(.plain)
            .background(.black.opacity(0.62), in: Capsule())
            .accessibilityLabel("查看动作反馈")

            SwingPhaseRailView(
                keyframes: keyframes,
                presentation: AnalysisWorkspacePresentation(state: playbackManager.analysisState),
                currentTime: playbackManager.currentTime,
                frameDuration: VideoFramePolicy.frameDuration(sourceFrameRate: playbackManager.sourceFrameRate),
                duration: playbackManager.duration
            ) { time in
                playbackManager.pause()
                playbackManager.seek(to: time)
                setControlsVisible(true, schedulesHide: false)
            } onScrub: { time in
                playbackManager.pause()
                playbackManager.seek(to: time)
                setControlsVisible(true, schedulesHide: false)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func chromeButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .frame(
                    minWidth: FullscreenPlaybackPolicy.minimumTouchTarget,
                    minHeight: FullscreenPlaybackPolicy.minimumTouchTarget
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.black.opacity(0.55), in: Circle())
        .accessibilityLabel(label)
    }

    private func togglePlaybackFromVideo() {
        if playbackManager.isPlaying {
            playbackManager.pause()
            setControlsVisible(true, schedulesHide: false)
        } else {
            playbackManager.play()
            setControlsVisible(true)
        }
    }

    private func setControlsVisible(_ visible: Bool, schedulesHide: Bool = true) {
        withAnimation(.easeInOut(duration: 0.18)) {
            controlsVisible = visible
        }
        hideTask?.cancel()
        if visible && schedulesHide {
            scheduleAutoHide()
        }
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard playbackManager.isPlaying else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(FullscreenPlaybackPolicy.autoHideDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                controlsVisible = false
            }
        }
    }
}

struct VideoCanvasView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    @Binding var drawings: [DrawingElement]
    @Binding var activeTool: DrawingTool
    @Binding var selectedColor: Color
    @Binding var strokeWidth: CGFloat
    @Binding var isKeyframeMode: Bool
    let showPoseSkeleton: Bool
    let showHeadStability: Bool
    let showSpineAngle: Bool
    let showGrid: Bool
    let interactionMode: WorkspaceInteractionMode
    let showsFullscreenButton: Bool
    let onEnterFullscreen: () -> Void
    var trajectoryCategory: SwingFeedbackCategory? = nil
    var trajectoryFrames: [SwingFrameObservation] = []
    var trajectoryStageTimes: [SwingTrajectoryStageTime] = []

    @State private var committedScale: CGFloat = 1
    @State private var renderedVideoRect: CGRect = .zero
    @GestureState private var gestureScale: CGFloat = 1

    private var scale: CGFloat {
        VideoZoomPolicy.clampedScale(committedScale * gestureScale)
    }

    var body: some View {
        ZStack {
            AnalysisTheme.canvasBackground
            if let player = playbackManager.player {
                ZStack {
                    PlayerViewRepresentable(player: player) { rect in
                        renderedVideoRect = rect
                        if showsFullscreenButton {
                            playbackManager.videoRect = rect
                        }
                    }

                    if showGrid {
                        GridView(rect: renderedVideoRect)
                            .allowsHitTesting(false)
                    }

                    DrawingOverlay(
                        playbackManager: playbackManager,
                        drawings: $drawings,
                        activeTool: $activeTool,
                        selectedColor: $selectedColor,
                        strokeWidth: $strokeWidth,
                        isKeyframeMode: $isKeyframeMode,
                        videoRect: renderedVideoRect,
                        isInteractionEnabled: interactionMode == .drawing,
                        showPoseSkeleton: showPoseSkeleton,
                        showHeadStability: showHeadStability,
                        showSpineAngle: showSpineAngle
                    )

                    if let trajectoryCategory,
                       !trajectoryFrames.isEmpty,
                       !renderedVideoRect.isEmpty {
                        SwingTrajectoryOverlay(
                            category: trajectoryCategory,
                            frames: trajectoryFrames,
                            stageTimes: trajectoryStageTimes,
                            videoRect: renderedVideoRect
                        )
                    }
                }
                .scaleEffect(scale)
                .onTapGesture(count: 2) {
                    resetZoom()
                }
            } else if playbackManager.mediaLoadState == .missing {
                ContentUnavailableView(
                    MediaLoadPolicy.missingMessage,
                    systemImage: "video.slash",
                    description: Text("视频文件已被删除或无法恢复，项目标注仍会保留。")
                )
                .foregroundStyle(.white)
            } else {
                ProgressView("正在载入视频")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

        }
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(magnificationGesture, including: .all)
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            committedScale = 1
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                guard interactionMode == .idle else { return }
                state = value
            }
            .onEnded { value in
                guard interactionMode == .idle else { return }
                committedScale = VideoZoomPolicy.adjustedScale(committedScale, multiplier: value)
            }
    }
}

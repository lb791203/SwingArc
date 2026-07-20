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
    @Binding var feedbackConfiguration: FeedbackConfiguration?
    let saveStatus: WorkspaceSaveStatus
    let onBack: () -> Void
    let onSelectProject: (LocalProjectSummary) -> Void
    let onExport: () -> Void
    let onAnalyze: () -> Void
    let onCancelAnalysis: () -> Void
    let onSetManualStage: (SwingStage) -> Void
    let feedback: PriorityFeedback?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var interactionMode: WorkspaceInteractionMode = .idle
    @State private var activeTool: DrawingTool = .line
    @State private var selectedColor: Color = .white
    @State private var strokeWidth: CGFloat = 3
    @State private var showsProjectSidebar = true
    @State private var showsInspector = true
    @State private var showsResultsSheet = false
    @State private var adjustmentStage: SwingStage?
    @State private var showsFullscreenPlayback = false

    private var presentation: AnalysisWorkspacePresentation {
        AnalysisWorkspacePresentation(state: playbackManager.analysisState)
    }

    private var techniquePresentation: TechniqueFeedbackPresentation? {
        guard let feedback, let analysis = playbackManager.analysisResult else { return nil }
        return TechniqueFeedbackPresentation.make(feedback: feedback, analysis: analysis)
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
                StageInspectorView(
                    presentation: presentation,
                    keyframes: keyframes,
                    sourceFrameRate: playbackManager.sourceFrameRate,
                    onSeek: { time in
                        playbackManager.seek(to: time)
                    },
                    onAdjust: openAdjustment
                )
                .padding(16)
                .background(AnalysisTheme.chrome.ignoresSafeArea())
                .navigationTitle("分析结果")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showsResultsSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showsFullscreenPlayback) {
            FullscreenVideoPlaybackView(
                playbackManager: playbackManager,
                drawings: $drawings,
                isKeyframeMode: $isKeyframeMode,
                showPoseSkeleton: showPoseSkeleton,
                showHeadStability: showHeadStability,
                showSpineAngle: showSpineAngle,
                showGrid: showGrid,
                keyframes: keyframes,
                practiceCameraView: $practiceCameraView,
                feedbackConfiguration: $feedbackConfiguration,
                onDismiss: { showsFullscreenPlayback = false }
            )
        }
        .onChange(of: playbackManager.analysisState) { _, state in
            if case .completed = state, horizontalSizeClass != .regular {
                showsResultsSheet = true
            }
        }
        .task(id: project.id) {
            #if DEBUG
            guard PracticePreviewConfiguration.autoAnalyzes(
                for: ProcessInfo.processInfo.arguments
            ) else { return }

            try? await Task.sleep(for: .milliseconds(250))
            onAnalyze()
            #endif
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func centerWorkbench(isRegularLayout: Bool) -> some View {
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
                onExport: onExport
            )

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
                showsFullscreenButton: true,
                onEnterFullscreen: { showsFullscreenPlayback = true }
            )
            .overlay(alignment: .trailing) {
                if interactionMode == .drawing {
                    DrawingToolRail(
                        activeTool: $activeTool,
                        selectedColor: $selectedColor,
                        isKeyframeMode: $isKeyframeMode,
                        onUndo: { if !drawings.isEmpty { drawings.removeLast() } },
                        onClear: { drawings.removeAll() },
                        onDone: { interactionMode = .idle }
                    )
                    .padding(.trailing, 10)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: interactionMode)

            if let techniquePresentation {
                TechniqueFeedbackCard(
                    presentation: techniquePresentation,
                    onSelectEvidence: { stage in
                        if let marker = keyframes.first(where: { $0.stage == stage.rawValue }) {
                            playbackManager.seek(to: marker.time)
                        } else if let time = presentation.detection(for: stage)?.time {
                            playbackManager.seek(to: time)
                        }
                    }
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AnalysisTheme.chrome)
            }

            if !isRegularLayout && playbackManager.isScanning {
                AnalysisProgressCard(
                    phase: playbackManager.analysisProgressPhase,
                    progress: playbackManager.scanProgress,
                    onCancel: onCancelAnalysis
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .background(AnalysisTheme.chrome)
            }

            if !isRegularLayout, let failure = playbackManager.analysisFailure {
                AnalysisFailureBanner(failure: failure)
            }

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
                        onAnalyze()
                    },
                    onShowResults: showResults(isRegularLayout: isRegularLayout)
                )
            }
        }
    }

    private func showResults(isRegularLayout: Bool) -> () -> Void {
        {
            if isRegularLayout {
                showsInspector = true
            } else {
                showsResultsSheet = true
            }
        }
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
    @Binding var practiceCameraView: PracticeCameraView?
    @Binding var feedbackConfiguration: FeedbackConfiguration?
    let onDismiss: () -> Void

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showsFeedbackConfiguration = false
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
        .fullScreenCover(isPresented: $showsFeedbackConfiguration) {
            SwingFeedbackConfigurationView(
                practiceCameraView: $practiceCameraView,
                configuration: $feedbackConfiguration,
                analysisState: playbackManager.analysisState,
                sourceFrameRate: playbackManager.sourceFrameRate,
                onDismiss: { showsFeedbackConfiguration = false }
            )
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
                showsFeedbackConfiguration = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ear.and.waveform")
                    Text(activeMetricTitle)
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: FullscreenPlaybackPolicy.minimumTouchTarget)
            }
            .buttonStyle(.plain)
            .background(.black.opacity(0.62), in: Capsule())
            .accessibilityLabel("选择回放分析参数")

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

    private var activeMetricTitle: String {
        guard let practiceCameraView,
              let feedbackConfiguration,
              SwingFeedbackProfiles.profile(for: practiceCameraView).contains(feedbackConfiguration.activeMetric)
        else {
            return "选择分析视角"
        }
        return feedbackConfiguration.activeMetric.title
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
        .overlay(alignment: .topTrailing) {
            if showsFullscreenButton,
               interactionMode == .idle,
               playbackManager.mediaLoadState == .ready {
                Button(action: onEnterFullscreen) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .foregroundStyle(.white)
                .padding(12)
                .accessibilityLabel("全屏播放")
            }
        }
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

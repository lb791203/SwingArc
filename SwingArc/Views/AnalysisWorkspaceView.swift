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
    let saveStatus: WorkspaceSaveStatus
    let onBack: () -> Void
    let onSelectProject: (LocalProjectSummary) -> Void
    let onExport: () -> Void
    let onAnalyze: () -> Void
    let onCancelAnalysis: () -> Void
    let onSetManualStage: (SwingStage) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var interactionMode: WorkspaceInteractionMode = .idle
    @State private var activeTool: DrawingTool = .line
    @State private var selectedColor: Color = .white
    @State private var strokeWidth: CGFloat = 3
    @State private var showsProjectSidebar = true
    @State private var showsInspector = true
    @State private var showsResultsSheet = false
    @State private var adjustmentStage: SwingStage?

    private var presentation: AnalysisWorkspacePresentation {
        AnalysisWorkspacePresentation(state: playbackManager.analysisState)
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
            .background(AnalysisTheme.canvasBackground)
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
        .onChange(of: playbackManager.analysisState) { _, state in
            if case .completed = state, horizontalSizeClass != .regular {
                showsResultsSheet = true
            }
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
                interactionMode: interactionMode
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

    @State private var committedScale: CGFloat = 1
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
                        playbackManager.videoRect = rect
                    }

                    if showGrid {
                        GridView(rect: playbackManager.videoRect)
                            .allowsHitTesting(false)
                    }

                    DrawingOverlay(
                        playbackManager: playbackManager,
                        drawings: $drawings,
                        activeTool: $activeTool,
                        selectedColor: $selectedColor,
                        strokeWidth: $strokeWidth,
                        isKeyframeMode: $isKeyframeMode,
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

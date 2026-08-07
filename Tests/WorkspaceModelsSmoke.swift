import Foundation

@main
struct WorkspaceModelsSmoke {
    static func main() {
        precondition(WorkspaceLayoutMode.resolve(isRegularWidth: false) == .compact)
        precondition(WorkspaceLayoutMode.resolve(isRegularWidth: true) == .regular)

        let extraction = AnalysisProgressPresentation(phase: .evidence, progress: 0.5)
        precondition(extraction.title == "提取候选证据")
        precondition(extraction.percentage == 50)
        precondition(AnalysisProgressPresentation(phase: .solving, progress: 1.4).percentage == 100)

        let summary = StageResultSummary(statuses: [.confirmed, .confirmed, .review, .unresolved, .manual])
        precondition(summary.confirmed == 3)
        precondition(summary.review == 1)
        precondition(summary.unresolved == 1)

        let gate = AnalysisRunGate()
        let first = gate.begin()
        let second = gate.begin()
        precondition(!gate.isActive(first))
        precondition(gate.isActive(second))
        gate.cancel()
        precondition(!gate.isActive(second))

        let drawing = WorkspaceModeTransition.enterDrawing(isPlaying: true)
        precondition(drawing.mode == .drawing)
        precondition(drawing.showsDrawingRail)
        precondition(drawing.shouldPausePlayback)

        let playback = WorkspaceModeTransition.beginPlayback
        precondition(playback.mode == .idle)
        precondition(!playback.showsDrawingRail)
        precondition(!playback.shouldPausePlayback)

        precondition(WorkspaceAccessoryPolicy.drawingRailMaximumWidth == 56)
        precondition(CameraCaptureLayout.instructionVerticalPosition(containerHeight: 844) <= 664)
        precondition(WorkspaceAccessoryPolicy.stageAdjustmentPlacement == .inline)

        precondition(DrawingRailPolicy.undoIntent(isLongPress: false) == .undoLast)
        precondition(DrawingRailPolicy.undoIntent(isLongPress: true) == .confirmClearAll)

        precondition(StageStripPolicy.buttonHeight == 44)
        precondition(StageStripPolicy.maximumTotalHeight == 80)
        precondition(StageStripPolicy.indicator(for: .confirmed) == .filledCircle)
        precondition(StageStripPolicy.indicator(for: .review) == .filledCircle)
        precondition(StageStripPolicy.indicator(for: .unresolved) == .hollowCircle)
        precondition(StageStripPolicy.indicator(for: .manual) == .lock)
        precondition(MobileReplayStageStripPolicy.stackSpacing == 8)
        precondition(MobileReplayStageStripPolicy.stageSpacing == 4)
        precondition(MobileReplayStageStripPolicy.buttonHeight == 44)
        precondition(MobileReplayStageStripPolicy.glyphWidth == 38)
        precondition(MobileReplayStageStripPolicy.glyphHeight == 34)

        let replayMarkers = [
            KeyframeMarker(time: 0.75, stage: .takeaway),
            KeyframeMarker(time: 1.25, stage: .leadArmParallelBackswing)
        ]
        precondition(
            ReplayStageSelectionPolicy.currentStage(
                at: 1.0,
                keyframes: replayMarkers,
                tolerance: 0.30
            ) == .takeaway
        )
        precondition(
            ReplayStageSelectionPolicy.currentStage(
                at: 1.20,
                keyframes: replayMarkers,
                tolerance: 0.18
            ) == .leadArmParallelBackswing
        )
        precondition(
            ReplayStageSelectionPolicy.currentStage(
                at: 1.5,
                keyframes: replayMarkers,
                tolerance: 0.18
            ) == nil
        )
        precondition(
            ReplayStageSelectionPolicy.currentStage(
                at: -1,
                keyframes: replayMarkers,
                tolerance: 0.18
            ) == nil
        )

        precondition(MediaLoadPolicy.state(fileExists: true) == .ready)
        precondition(MediaLoadPolicy.state(fileExists: false) == .missing)
        precondition(MediaLoadPolicy.missingMessage == "视频文件缺失")

        precondition(FullscreenPlaybackPolicy.autoHideDelay == 2.5)
        precondition(FullscreenPlaybackPolicy.minimumTouchTarget == 44)
        precondition(!FullscreenPlaybackPolicy.allowsDrawing)
        precondition(!FullscreenPlaybackPolicy.showsWorkspaceChrome)

        precondition(abs(VideoFramePolicy.frameDuration(sourceFrameRate: 120) - (1.0 / 120.0)) < 0.000001)
        precondition(VideoFramePolicy.frameDuration(sourceFrameRate: 0) == (1.0 / 60.0))
    }
}

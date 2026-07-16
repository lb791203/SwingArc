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

        precondition(abs(VideoFramePolicy.frameDuration(sourceFrameRate: 120) - (1.0 / 120.0)) < 0.000001)
        precondition(VideoFramePolicy.frameDuration(sourceFrameRate: 0) == (1.0 / 60.0))
    }
}

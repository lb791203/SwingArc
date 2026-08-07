import Foundation

@main
struct CoreAnalysisSurfaceSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try read(root, "SwingArc/Views/AnalysisWorkspaceView.swift")
        let components = try read(root, "SwingArc/Views/WorkspaceComponents.swift")
        let content = try read(root, "SwingArc/Views/ContentView.swift")

        let workspace = prefix(source, before: "struct FullscreenVideoPlaybackView")
        let header = section(
            components,
            from: "struct WorkspaceHeaderView",
            to: "struct StageTimelineView"
        )
        let controls = section(
            components,
            from: "struct PlaybackControlsView",
            to: "struct DrawingToolRail"
        )
        let drawingToolbar = section(
            components,
            from: "struct DrawingToolRail",
            to: "private struct DrawingColorPalette"
        )
        let inspector = section(
            components,
            from: "struct WorkspaceInspectorView",
            to: "struct StageAdjustmentBar"
        )

        precondition(workspace.contains("DrawingToolRail("))
        precondition(workspace.contains("StageTimelineView("))
        precondition(workspace.contains("MobileReplayTimelineView("))
        precondition(workspace.contains("onCorrectPPoints"))
        precondition(workspace.contains("onExport"))
        precondition(workspace.contains("重新分析"))
        precondition(workspace.contains("drawingModeChrome"))
        precondition(workspace.contains("drawingModeHeader"))
        precondition(workspace.contains("Text(\"画线\")"))
        precondition(workspace.contains("Button(\"完成\")"))

        precondition(drawingToolbar.contains("HStack(spacing: WorkspaceAccessoryPolicy.drawingToolbarItemSpacing)"))
        precondition(drawingToolbar.contains("ForEach(DrawingTool.allCases)"))
        precondition(drawingToolbar.contains("Menu {"))
        precondition(drawingToolbar.contains("toolbarItemLabel"))
        precondition(drawingToolbar.contains("AnalysisTheme.proTourSignal"))
        precondition(drawingToolbar.contains("colorButton"))
        precondition(drawingToolbar.contains("选择画线颜色"))
        precondition(drawingToolbar.contains("in: Capsule()"))
        precondition(!drawingToolbar.contains("background(AnalysisTheme.raisedChrome"))

        for forbidden in [
            "SimplifiedSwingFeedbackView(",
            "simplifiedFeedback",
            "SwingTrajectoryOverlay(",
            "trajectoryCategory:",
            "选择拍摄视角",
            "cameraViewButton(",
            "showResults("
        ] {
            precondition(!workspace.contains(forbidden))
        }

        precondition(!header.contains("onShowResults"))
        precondition(!header.contains("hasResults"))
        precondition(!controls.contains("onShowResults"))
        precondition(controls.contains("重新分析"))
        precondition(inspector.contains("StageInspectorView("))
        precondition(!inspector.contains("Toggle("))
        precondition(!inspector.contains("showPoseSkeleton"))
        precondition(!content.contains("showPoseSkeleton: $showPoseSkeleton"))
        precondition(!content.contains("practiceCameraView: $practiceCameraView"))
    }

    private static func read(_ root: URL, _ path: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static func prefix(_ source: String, before marker: String) -> String {
        String(source[..<source.range(of: marker)!.lowerBound])
    }

    private static func section(
        _ source: String,
        from start: String,
        to end: String
    ) -> String {
        let startIndex = source.range(of: start)!.lowerBound
        let tail = source[startIndex...]
        let endIndex = tail.range(of: end)!.lowerBound
        return String(tail[..<endIndex])
    }
}

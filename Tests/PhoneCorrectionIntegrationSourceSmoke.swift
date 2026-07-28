import Foundation

@main
struct PhoneCorrectionIntegrationSourceSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let content = try String(
            contentsOf: root.appendingPathComponent("SwingArc/Views/ContentView.swift"),
            encoding: .utf8
        )
        let workspace = try String(
            contentsOf: root.appendingPathComponent("SwingArc/Views/AnalysisWorkspaceView.swift"),
            encoding: .utf8
        )
        let components = try String(
            contentsOf: root.appendingPathComponent("SwingArc/Views/WorkspaceComponents.swift"),
            encoding: .utf8
        )

        precondition(content.contains("showPPointCorrection"))
        precondition(content.contains("PPointCorrectionWorkspace("))
        precondition(content.contains("refineManualPPoint("))
        precondition(content.contains("refineManualPPoints("))
        precondition(content.contains("manualMarkers: keyframes"))
        precondition(content.contains("sourceFrameIndex: sourceFrameIndex"))
        precondition(!content.contains("AnnotationWorkspaceView("))
        let fullscreenStart = workspace.range(
            of: "struct FullscreenVideoPlaybackView"
        )!.lowerBound
        let publicWorkspace = String(workspace[..<fullscreenStart])

        precondition(publicWorkspace.contains("let onCorrectPPoints: () -> Void"))
        precondition(publicWorkspace.contains("Text(\"修正 P 点\")"))
        precondition(publicWorkspace.contains("Text(\"画线\")"))
        precondition(!publicWorkspace.contains("选择拍摄视角"))
        precondition(!publicWorkspace.contains("title: \"正后方 DTL\""))
        precondition(!publicWorkspace.contains("title: \"正面 Face-on\""))
        precondition(!publicWorkspace.contains("SimplifiedSwingFeedbackView("))
        precondition(!publicWorkspace.contains("trajectoryCategory:"))
        precondition(components.contains("let onCorrectPPoints: () -> Void"))
        precondition(components.contains("Text(\"修正 P 点\")"))
    }
}

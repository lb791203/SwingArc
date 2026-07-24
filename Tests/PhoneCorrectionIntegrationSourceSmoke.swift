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
        precondition(workspace.contains("let onCorrectPPoints: () -> Void"))
        precondition(workspace.contains("Text(\"修正 P 点\")"))
        precondition(workspace.contains("Text(\"画线\")"))
        precondition(workspace.contains("Text(\"选择拍摄视角\")"))
        precondition(workspace.contains("title: \"正后方 DTL\""))
        precondition(workspace.contains("title: \"正面 Face-on\""))
        precondition(workspace.contains("view: .downTheLine"))
        precondition(workspace.contains("view: .faceOn"))
        precondition(workspace.contains("practiceCameraView = view"))
        precondition(components.contains("let onCorrectPPoints: () -> Void"))
        precondition(components.contains("Text(\"修正 P 点\")"))
    }
}

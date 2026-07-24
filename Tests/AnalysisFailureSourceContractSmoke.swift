import Foundation

@main
struct AnalysisFailureSourceContractSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let detector = try String(
            contentsOf: root.appendingPathComponent("SwingArc/Services/SwingStageDetector.swift"),
            encoding: .utf8
        )
        let analyzer = try String(
            contentsOf: root.appendingPathComponent("SwingArc/Services/VisionPoseDetector.swift"),
            encoding: .utf8
        )
        let presentation = try String(
            contentsOf: root.appendingPathComponent("SwingArc/Models/WorkspaceModels.swift"),
            encoding: .utf8
        )
        let workspace = try String(
            contentsOf: root.appendingPathComponent("SwingArc/Views/AnalysisWorkspaceView.swift"),
            encoding: .utf8
        )

        precondition(detector.contains("case insufficientStageEvidence"))
        precondition(
            analyzer.contains(
                "activeFailure(.insufficientStageEvidence, runID: runID, gate: gate)"
            )
        )
        precondition(
            presentation.contains(
                "人体已识别，但未能自动确定完整 P1–P8。你可以手动设置 P 点。"
            )
        )
        precondition(
            workspace.contains(
                "case .insufficientStageEvidence:\n            return \"人体已识别，但未能自动确定完整 P1–P8。你可以手动设置 P 点。\""
            )
        )
    }
}

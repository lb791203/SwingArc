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
            !analyzer.contains(
                "activeFailure(.insufficientStageEvidence, runID: runID, gate: gate)"
            ),
            "Missing strict stage evidence must not discard a usable Vision pose result"
        )
        precondition(
            analyzer.contains("return activeCompletedAnalysis("),
            "Stage validation failures must degrade to an editable completed result"
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
        precondition(detector.contains("case poseDetectionUnavailable"))
        precondition(
            analyzer.contains("activeFailure(.poseDetectionUnavailable, runID: runID, gate: gate)"),
            "Vision failing on every frame must not be reported as an unstable person"
        )
        precondition(
            analyzer.contains("guard !trackedPoseDetector.hasNoUsableVisionResults else {"),
            "A late Vision breakdown must not stop analysis before segmentation"
        )
        precondition(
            workspace.contains("Label(\"手动标 P 点\", systemImage: \"hand.tap\")"),
            "The failure banner must offer manual P-point marking"
        )
    }
}

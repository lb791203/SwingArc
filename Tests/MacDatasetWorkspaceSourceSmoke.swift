import Foundation

@main
struct MacDatasetWorkspaceSourceSmoke {
    static func main() throws {
        let paths = [
            "SwingArcDataset/Views/DatasetWorkspaceView.swift",
            "SwingArcDataset/Views/DatasetClipSidebar.swift",
            "SwingArcDataset/Views/DatasetFrameCanvas.swift",
            "SwingArcDataset/Views/DatasetKeypointInspector.swift",
            "SwingArcDataset/Views/DatasetTimelineView.swift",
            "SwingArcDataset/SwingArcDatasetApp.swift"
        ]
        let source = try paths.map { try String(contentsOfFile: $0, encoding: .utf8) }.joined(separator: "\n")
        for token in [
            "NavigationSplitView", "DatasetClipSidebar", "DatasetFrameCanvas", "DatasetKeypointInspector", "DatasetTimelineView",
            "接受当前帧", "−5", "−1", "+1", "+5", "grip", "shaftStart", "shaftEnd", "clubhead", "ball",
            "onCorrectPoint", "DragGesture", "aspectFitRect", "fullFramePointToROI", "roiPointToFullFrame",
            "predictionPoint", "fullFrameImage", "roiImage", "visionSkeleton", "trailPoints", "timelineStages",
            "无可用帧数据", "选择一段 clip 开始标注"
        ] {
            precondition(source.contains(token), "Missing required source contract: \(token)")
        }
        precondition(!source.contains("[CanvasLandmark:"), "Canvas must use GolfLandmark")
        precondition(!source.contains("pred-run-fixture"), "Production workspace must not use fixture predictions")
        print("All Mac workspace source contracts passed.")
    }
}

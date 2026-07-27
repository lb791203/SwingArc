import Foundation

@main
struct MacDatasetWorkspaceSourceSmoke {
    static func main() throws {
        let paths = [
            "SwingArcDataset/Models/DatasetAnnotationQueueMode.swift",
            "SwingArcDataset/Views/DatasetWorkspaceView.swift",
            "SwingArcDataset/Views/DatasetClipSidebar.swift",
            "SwingArcDataset/Views/DatasetFrameCanvas.swift",
            "SwingArcDataset/Views/DatasetKeypointInspector.swift",
            "SwingArcDataset/Views/DatasetTimelineView.swift",
            "SwingArcDataset/Views/DatasetImportSheet.swift",
            "SwingArcDataset/Services/DatasetWorkspaceController.swift",
            "SwingArcDataset/Services/DatasetSubjectAnchorController.swift",
            "SwingArcDataset/Services/DatasetPredictionRunGenerator.swift",
            "SwingArcDataset/Views/DatasetSubjectAnchorSheet.swift",
            "SwingArcDataset/SwingArcDatasetApp.swift"
        ]
        let source = try paths.map { try String(contentsOfFile: $0, encoding: .utf8) }.joined(separator: "\n")
        for token in [
            "NavigationSplitView", "DatasetClipSidebar", "DatasetFrameCanvas", "DatasetKeypointInspector", "DatasetTimelineView",
            "接受本帧全部预测", "当前无预测，需人工标注",
            "P1–P8 首轮", "扩展训练队列",
            "queueMode", "onQueueModeChange",
            "−5", "−1", "+1", "+5", "grip", "shaftStart", "shaftEnd", "clubhead", "ball",
            "onCorrectPoint", "DragGesture", "aspectFitRect", "fullFramePointToROI", "roiPointToFullFrame",
            "predictionPoint", "fullFrameImage", "roiImage", "visionSkeleton", "trailPoints", "timelineStages",
            "DatasetSkeletonSegment", "displayedImage != nil", "!isLoading",
            "无可用帧数据", "选择一段 clip 开始标注",
            "registerImportedClip", "controller.selectClip", "controller.fullFrameImageSize",
            "onImported(receipt)", "DatasetSubjectAnchorSheet", "DatasetPredictionRunGenerator",
            "主体锚点", "manual-bootstrap"
        ] {
            precondition(source.contains(token), "Missing required source contract: \(token)")
        }
        precondition(!source.contains("[CanvasLandmark:"), "Canvas must use GolfLandmark")
        precondition(!source.contains("visionSkeleton: [GolfNormalizedPoint]"), "Skeleton must use explicit edges")
        precondition(!source.contains("pred-run-fixture"), "Production workspace must not use fixture predictions")
        for token in [
            "DatasetWorkspaceHostView(controller: workspaceController, store: store)",
            "let store: GolfDatasetStore",
            "selectedClipIdentity: controller.selectedClip",
            "store: store",
            "videoURL: controller.selectedVideoURL",
            "allowsPredictionAcceptance: state.allowsPredictionAcceptance",
            "withTaskCancellationHandler",
            "Task.checkCancellation()",
            "generationTask?.cancel()",
            "@MainActor\npublic final class DatasetPredictionRunGenerator",
            "loadPPointTruth", "makeAnnotationQueue",
            "annotationQueueMode", "selectAnnotationQueueMode",
            "DatasetAnnotationQueueFactory.make",
            "controller.annotationQueueMode",
            "controller.selectAnnotationQueueMode",
            "navigateAnnotationQueue", "navigateToNextPendingQueueFrame",
            "queuePosition:", "reviewedQueueCount:",
            "timelineStages: (controller.activePPointTruth"
        ] {
            precondition(source.contains(token), "Production anchor entry is not wired: \(token)")
        }
        precondition(
            !source.contains("registry: nil"),
            "Generator must not fabricate a registry-less validation snapshot"
        )
        precondition(
            !source.contains("queue: []"),
            "Production workspace must not discard the annotation queue"
        )
        print("All Mac workspace source contracts passed.")
    }
}

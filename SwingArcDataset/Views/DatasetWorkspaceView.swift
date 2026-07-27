import SwiftUI

/// Pure, dependency-injected Task 5 workspace. Loading, persistence and autosave
/// remain controller responsibilities for Task 6.
struct DatasetWorkspaceView: View {
    let clips: [DatasetClipRowModel]
    let selectedClipID: String?
    let selectedFilter: DatasetSidebarFilter
    let annotationState: DatasetAnnotationState?
    let fullFrameImage: CGImage?
    let roiImage: CGImage?
    let fullFrameImageSize: CGSize
    let roiImageSize: CGSize
    let visionSkeleton: [DatasetSkeletonSegment]
    let trailPoints: [GolfLandmark: [(delta: Int, point: GolfNormalizedPoint)]]
    let timelineStages: [TimelineStageMarker]
    let isFrameLoading: Bool
    let showsROI: Bool
    let currentSourceTime: Double?
    let workspaceAccess: DatasetWorkspaceAccess
    let queueMode: DatasetAnnotationQueueMode

    let onSelectClip: (String) -> Void
    let onSelectFilter: (DatasetSidebarFilter) -> Void
    let onStep: (Int) -> Void
    let onQueueStep: (Int) -> Void
    let onNextPending: () -> Void
    let onQueueModeChange: (DatasetAnnotationQueueMode) -> Void
    let onToggleROI: () -> Void
    let onAcceptPrediction: (GolfLandmark) -> Void
    let onCorrectPoint: (GolfLandmark, GolfNormalizedPoint) -> Void
    let onSetOccluded: (GolfLandmark) -> Void
    let onSetOutOfFrame: (GolfLandmark) -> Void
    let onSetUnresolved: (GolfLandmark) -> Void
    let onAcceptFrame: () -> Void

    var selectedClipIdentity: GolfClipIdentity? = nil
    var store: GolfDatasetStore? = nil
    var videoURL: URL? = nil

    @StateObject private var defaultAnchorController = DatasetSubjectAnchorController()
    @StateObject private var defaultRunGenerator = DatasetPredictionRunGenerator()

    var anchorController: DatasetSubjectAnchorController? = nil
    var runGenerator: DatasetPredictionRunGenerator? = nil

    @State private var selectedLandmark: GolfLandmark?
    @State private var showsAnchorSheet = false

    private var activeAnchorController: DatasetSubjectAnchorController {
        anchorController ?? defaultAnchorController
    }

    private var activeRunGenerator: DatasetPredictionRunGenerator {
        runGenerator ?? defaultRunGenerator
    }

    var body: some View {
        NavigationSplitView {
            DatasetClipSidebar(
                clips: clips, selectedClipID: selectedClipID, selectedFilter: selectedFilter,
                onSelectClip: onSelectClip, onSelectFilter: onSelectFilter
            )
        } content: {
            VStack(spacing: 0) {
                HStack {
                    if selectedClipID != nil {
                        Button("主体锚点") {
                            showsAnchorSheet = true
                        }
                        .font(.caption)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8).padding(.vertical, 4)

                DatasetFrameCanvas(
                    fullFrameImage: fullFrameImage,
                    roiImage: roiImage,
                    fullFrameImageSize: fullFrameImageSize,
                    roiImageSize: roiImageSize,
                    showsROI: showsROI,
                    landmarkPoints: currentLandmarkPoints,
                    selectedLandmark: selectedLandmark,
                    trailPoints: trailPoints,
                    visionSkeleton: visionSkeleton,
                    roiTransform: annotationState?.currentPredictionFrame?.roiTransform,
                    onCorrectPoint: onCorrectPoint,
                    onToggleROI: onToggleROI,
                    isLoading: isFrameLoading,
                    isEditable: workspaceAccess == .editable,
                    statusMessage: statusMessage
                )
                Divider()
                DatasetTimelineView(
                    totalFrames: annotationState?.frameCount ?? 0,
                    currentFrame: annotationState?.currentSourceFrameIndex ?? 0,
                    stages: timelineStages,
                    queuePosition: annotationState?.currentQueuePosition,
                    queueCount: annotationState?.annotationQueue.count ?? 0,
                    reviewedQueueCount:
                        annotationState?.reviewedQueueFrameCount ?? 0,
                    queueMode: queueMode,
                    onStep: onStep,
                    onQueueStep: onQueueStep,
                    onNextPending: onNextPending,
                    onQueueModeChange: onQueueModeChange
                )
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
        } detail: {
            if let state = annotationState {
                DatasetKeypointInspector(
                    landmarks: inspectorRows(from: state),
                    predictionRunID: state.predictionRun?.predictionRunID ?? state.parentPredictionRunID,
                    revisionID: state.revisionID.isEmpty ? "尚未保存" : state.revisionID,
                    isReviewed: state.currentFrameIsReviewed,
                    isComplete: state.currentFrameIsComplete,
                    canSave: state.canSaveCurrentFrame,
                    canAcceptFrame: state.canAcceptCurrentFrame,
                    isFrameEditable: state.frameCount > 0 && workspaceAccess == .editable,
                    allowsPredictionAcceptance: state.allowsPredictionAcceptance,
                    selectedLandmark: selectedLandmark,
                    onSelectLandmark: { selectedLandmark = $0 },
                    onAcceptPrediction: onAcceptPrediction,
                    onCorrectPoint: { selectedLandmark = $0 },
                    onSetOccluded: onSetOccluded,
                    onSetOutOfFrame: onSetOutOfFrame,
                    onSetUnresolved: onSetUnresolved,
                    onAcceptFrame: onAcceptFrame
                )
            } else {
                Text("选择一段 clip 开始标注").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showsAnchorSheet) {
            if let selectedClipIdentity, let store, let videoURL {
                DatasetSubjectAnchorSheet(
                    anchorController: activeAnchorController,
                    runGenerator: activeRunGenerator,
                    clip: selectedClipIdentity,
                    store: store,
                    videoURL: videoURL,
                    onDismiss: {
                        showsAnchorSheet = false
                        activeAnchorController.resetState()
                    }
                )
            } else {
                VStack(spacing: 16) {
                    Text("主体锚点 — 无视频或 Clip 数据")
                        .font(.headline)
                    Text("请确保选中的 Clip 存在且视频文件正常解析。")
                        .font(.caption).foregroundColor(.secondary)
                    Button("关闭") {
                        showsAnchorSheet = false
                        activeAnchorController.resetState()
                    }
                }
                .padding()
                .frame(width: 400, height: 200)
            }
        }
        .onChange(of: selectedClipID) { _, _ in
            selectedLandmark = nil
            showsAnchorSheet = false
            activeAnchorController.resetState()
        }
        .onChange(of: annotationState == nil) { _, isEmpty in
            if isEmpty {
                selectedLandmark = nil
            }
        }
    }

    private var currentLandmarkPoints: [CanvasLandmarkPoint] {
        guard let state = annotationState else { return [] }
        return GolfLandmark.allCases.compactMap { landmark in
            guard let presentation = state.presentation(for: landmark) else { return nil }
            return CanvasLandmarkPoint(
                id: landmark,
                label: landmark.rawValue,
                fullFramePoint: presentation.point,
                isPrediction: presentation.isPrediction
            )
        }
    }

    private var statusMessage: String? {
        var parts: [String] = []
        if let currentSourceTime { parts.append(String(format: "源时间 %.3fs", currentSourceTime)) }
        if showsROI { parts.append("512 × 512 ROI") }
        if case .readOnly(let reason) = workspaceAccess { parts.append("只读：\(reason)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func inspectorRows(from state: DatasetAnnotationState) -> [LandmarkInspectorRowModel] {
        GolfLandmark.allCases.map { landmark in
            let prediction = state.currentPredictionFrame?.points[landmark]
            let decision = state.decisions[AnnotationDecisionKey(frameIndex: state.currentSourceFrameIndex, landmark: landmark)]
            return LandmarkInspectorRowModel(
                id: landmark,
                label: landmark.rawValue,
                predictionPoint: prediction?.resolvedFullFramePoint,
                predictionConfidence: prediction?.heatmapConfidence,
                decisionPoint: decision?.fullFramePoint,
                decisionKind: decision?.kind
            )
        }
    }
}

#Preview {
    DatasetWorkspaceView(
        clips: [], selectedClipID: nil, selectedFilter: .allClips, annotationState: nil,
        fullFrameImage: nil, roiImage: nil,
        fullFrameImageSize: CGSize(width: 1920, height: 1080), roiImageSize: CGSize(width: 512, height: 512),
        visionSkeleton: [], trailPoints: [:], timelineStages: [], isFrameLoading: false, showsROI: false, currentSourceTime: nil, workspaceAccess: .readOnly(reason: "预览"),
        queueMode: .pPointFirstPass,
        onSelectClip: { _ in }, onSelectFilter: { _ in }, onStep: { _ in },
        onQueueStep: { _ in }, onNextPending: {},
        onQueueModeChange: { _ in }, onToggleROI: {},
        onAcceptPrediction: { _ in },
        onCorrectPoint: { _, _ in }, onSetOccluded: { _ in }, onSetOutOfFrame: { _ in }, onSetUnresolved: { _ in }, onAcceptFrame: {}
    )
    .frame(minWidth: 1000, minHeight: 600)
}

/// Keeps the workspace dependency-injected while binding the production actions
/// to one retained controller instance.
struct DatasetWorkspaceHostView: View {
    @ObservedObject var controller: DatasetWorkspaceController
    let store: GolfDatasetStore

    var body: some View {
        DatasetWorkspaceView(
            clips: controller.clips.map { clip in
                let progress = controller.clipProgress[clip.clipID]
                return DatasetClipRowModel(
                    id: clip.clipID,
                    golferID: clip.golferID,
                    view: clip.view.rawValue,
                    split: controller.split(for: clip).rawValue,
                    completionProgress: progress?.fraction ?? 0,
                    pendingReviewCount: progress?.pending ?? 0,
                    hasP6P8Issues: false,
                    hasTrackingBreaks: false,
                    hasLowConfidence: false,
                    hasROIOOB: false
                )
            }, selectedClipID: controller.selectedClipID, selectedFilter: controller.selectedFilter,
            annotationState: controller.annotationState, fullFrameImage: controller.fullFrameImage, roiImage: nil,
            fullFrameImageSize: controller.fullFrameImageSize, roiImageSize: CGSize(width: 512, height: 512),
            visionSkeleton: [], trailPoints: [:],
            timelineStages: (controller.activePPointTruth?.stages ?? []).map {
                TimelineStageMarker(
                    id: $0.code.rawValue,
                    label: $0.code.rawValue,
                    sourceFrameIndex: $0.sourceFrameIndex,
                    isConfirmed: true
                )
            },
            isFrameLoading: controller.isFrameLoading, showsROI: false,
            currentSourceTime: controller.currentSourceTime,
            workspaceAccess: controller.access,
            queueMode: controller.annotationQueueMode,
            onSelectClip: { clipID in
                Task { await controller.selectClip(clipID) }
            }, onSelectFilter: controller.selectFilter,
            onStep: { controller.dispatch(.step($0)) },
            onQueueStep: controller.navigateAnnotationQueue,
            onNextPending: controller.navigateToNextPendingQueueFrame,
            onQueueModeChange: controller.selectAnnotationQueueMode,
            onToggleROI: {},
            onAcceptPrediction: { controller.dispatch(.acceptPrediction($0, decidedAt: Date())) },
            onCorrectPoint: { controller.dispatch(.correctPoint($0, $1, decidedAt: Date())) },
            onSetOccluded: { controller.dispatch(.setOccluded($0, decidedAt: Date())) },
            onSetOutOfFrame: { controller.dispatch(.setOutOfFrame($0, decidedAt: Date())) },
            onSetUnresolved: { controller.dispatch(.setUnresolved($0, decidedAt: Date())) },
            onAcceptFrame: { controller.dispatch(.acceptUnresolvedFrame(decidedAt: Date())) },
            selectedClipIdentity: controller.selectedClip,
            store: store,
            videoURL: controller.selectedVideoURL
        )
    }
}

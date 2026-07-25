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
    let visionSkeleton: [GolfNormalizedPoint]?
    let trailPoints: [GolfLandmark: [(delta: Int, point: GolfNormalizedPoint)]]
    let timelineStages: [TimelineStageMarker]
    let isFrameLoading: Bool
    let showsROI: Bool
    let currentSourceTime: Double?

    let onSelectClip: (String) -> Void
    let onSelectFilter: (DatasetSidebarFilter) -> Void
    let onStep: (Int) -> Void
    let onToggleROI: () -> Void
    let onAcceptPrediction: (GolfLandmark) -> Void
    let onCorrectPoint: (GolfLandmark, GolfNormalizedPoint) -> Void
    let onSetOccluded: (GolfLandmark) -> Void
    let onSetOutOfFrame: (GolfLandmark) -> Void
    let onSetUnresolved: (GolfLandmark) -> Void
    let onAcceptFrame: () -> Void

    @State private var selectedLandmark: GolfLandmark?

    var body: some View {
        NavigationSplitView {
            DatasetClipSidebar(
                clips: clips, selectedClipID: selectedClipID, selectedFilter: selectedFilter,
                onSelectClip: onSelectClip, onSelectFilter: onSelectFilter
            )
        } content: {
            VStack(spacing: 0) {
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
                    statusMessage: statusMessage
                )
                Divider()
                DatasetTimelineView(
                    totalFrames: annotationState?.frameCount ?? 0,
                    currentFrame: annotationState?.currentSourceFrameIndex ?? 0,
                    stages: timelineStages,
                    onStep: onStep
                )
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
        } detail: {
            if let state = annotationState {
                DatasetKeypointInspector(
                    landmarks: inspectorRows(from: state),
                    predictionRunID: state.predictionRun.predictionRunID,
                    revisionID: state.revisionID,
                    isReviewed: state.currentFrameIsReviewed,
                    isComplete: state.currentFrameIsComplete,
                    canSave: state.canSaveCurrentFrame,
                    canAcceptFrame: canAcceptFrame(state: state),
                    isFrameEditable: state.frameCount > 0,
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
        .navigationSplitViewStyle(.prominentDetail)
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
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func canAcceptFrame(state: DatasetAnnotationState) -> Bool {
        guard state.frameCount > 0, let prediction = state.currentPredictionFrame else { return false }
        return GolfLandmark.allCases.allSatisfy { landmark in
            let key = AnnotationDecisionKey(frameIndex: state.currentSourceFrameIndex, landmark: landmark)
            return state.decisions[key] != nil || prediction.points[landmark]?.resolvedFullFramePoint != nil
        }
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
        visionSkeleton: nil, trailPoints: [:], timelineStages: [], isFrameLoading: false, showsROI: false, currentSourceTime: nil,
        onSelectClip: { _ in }, onSelectFilter: { _ in }, onStep: { _ in }, onToggleROI: {}, onAcceptPrediction: { _ in },
        onCorrectPoint: { _, _ in }, onSetOccluded: { _ in }, onSetOutOfFrame: { _ in }, onSetUnresolved: { _ in }, onAcceptFrame: {}
    )
    .frame(minWidth: 1000, minHeight: 600)
}

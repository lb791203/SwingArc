import SwiftUI

/// The main three-column annotation workspace.
///
/// Layout:
///   - Leading: DatasetClipSidebar (clip list + filters)
///   - Center:  DatasetFrameCanvas + DatasetTimelineView
///   - Trailing: DatasetKeypointInspector
///
/// This view is designed for dependency injection in Task 5.
/// Task 6 will wire it to a real controller for autosave and recovery.
struct DatasetWorkspaceView: View {
    // MARK: - State (injected for Task 5; will move to controller in Task 6)

    let clips: [DatasetClipRowModel]
    let selectedClipID: String?
    let selectedFilter: DatasetSidebarFilter
    let annotationState: DatasetAnnotationState?
    let frameImage: CGImage?
    let isFrameLoading: Bool
    let showsROI: Bool

    // Callbacks
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

    // Optional override for the timestamp display
    let currentSourceTime: Double?

    var body: some View {
        NavigationSplitView {
            // Leading: clip sidebar
            DatasetClipSidebar(
                clips: clips,
                selectedClipID: selectedClipID,
                selectedFilter: selectedFilter,
                onSelectClip: onSelectClip,
                onSelectFilter: onSelectFilter
            )
        } content: {
            // Center: canvas + timeline
            VStack(spacing: 0) {
                DatasetFrameCanvas(
                    frameImage: frameImage,
                    imageSize: imageSize,
                    showsROI: showsROI,
                    landmarkPoints: currentLandmarkPoints,
                    selectedLandmark: nil,
                    trailPoints: [:],
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        } detail: {
            // Trailing: keypoint inspector
            if let state = annotationState {
                DatasetKeypointInspector(
                    landmarks: inspectorRows(from: state),
                    predictionRunID: state.predictionRun.predictionRunID,
                    revisionID: state.revisionID,
                    isReviewed: state.currentFrameIsReviewed,
                    isComplete: state.currentFrameIsComplete,
                    canSave: state.canSaveCurrentFrame,
                    canAcceptFrame: canAcceptFrame(state: state),
                    onAcceptPrediction: onAcceptPrediction,
                    onCorrectPoint: onCorrectPoint,
                    onSetOccluded: onSetOccluded,
                    onSetOutOfFrame: onSetOutOfFrame,
                    onSetUnresolved: onSetUnresolved,
                    onAcceptFrame: onAcceptFrame
                )
            } else {
                Text("选择一段 clip 开始标注")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
    }

    // MARK: - Derived Data

    /// Build landmark point models from the annotation state.
    private var currentLandmarkPoints: [CanvasLandmarkPoint] {
        guard let state = annotationState,
              let predFrame = state.currentPredictionFrame else {
            return []
        }
        return state.decisionsForCurrentFrame.compactMap { decision in
            guard let point = decision.fullFramePoint else { return nil }
            let predPoint = predFrame.points[decision.landmark]
            return CanvasLandmarkPoint(
                id: decision.landmark,
                label: decision.landmark.rawValue,
                normalizedPoint: point,
                isPrediction: decision.kind == .acceptedPrediction,
                isSelected: false
            )
        }
    }

    private var imageSize: CGSize {
        showsROI
            ? CGSize(width: 512, height: 512)
            : CGSize(width: 1920, height: 1080) // default full frame; Task 6 will read from clip metadata
    }

    private var timelineStages: [TimelineStageMarker] {
        // P1–P8 stage markers; in Task 5 these are placeholder positions.
        // Task 6 will load real stage positions from the clip's P-point truth.
        []
    }

    private var statusMessage: String? {
        guard let state = annotationState else {
            return "无标注状态"
        }
        var parts: [String] = []
        if let predFrame = state.currentPredictionFrame {
            let time = predFrame.sourceTime
            parts.append(String(format: "源时间 %.3fs", time))
        }
        if showsROI {
            parts.append("512 × 512 ROI")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The "Accept Current Frame" button is enabled when every undecided
    /// landmark has a prediction available.
    private func canAcceptFrame(state: DatasetAnnotationState) -> Bool {
        guard let predFrame = state.currentPredictionFrame else { return false }
        for landmark in GolfLandmark.allCases {
            let key = AnnotationDecisionKey(
                frameIndex: state.currentSourceFrameIndex,
                landmark: landmark
            )
            if state.decisions[key] != nil { continue } // already decided
            // Must have a prediction with full-frame point
            guard let predPoint = predFrame.points[landmark],
                  predPoint.resolvedFullFramePoint != nil else {
                return false
            }
        }
        return true
    }

    private func inspectorRows(from state: DatasetAnnotationState) -> [LandmarkInspectorRowModel] {
        let predFrame = state.currentPredictionFrame
        let decisions = state.decisionsForCurrentFrame

        return GolfLandmark.allCases.map { landmark in
            let decision = decisions.first(where: { $0.landmark == landmark })
            let predPoint = predFrame?.points[landmark]

            return LandmarkInspectorRowModel(
                id: landmark,
                label: landmark.rawValue,
                coordinate: decision?.fullFramePoint,
                isPredicted: decision?.kind == .acceptedPrediction,
                hasDecision: decision != nil,
                decisionKind: decision?.kind
            )
        }
    }
}

// MARK: - Preview

#Preview {
    DatasetWorkspaceView(
        clips: [],
        selectedClipID: nil,
        selectedFilter: .allClips,
        annotationState: nil,
        frameImage: nil,
        isFrameLoading: false,
        showsROI: false,
        onSelectClip: { _ in },
        onSelectFilter: { _ in },
        onStep: { _ in },
        onToggleROI: {},
        onAcceptPrediction: { _ in },
        onCorrectPoint: { _, _ in },
        onSetOccluded: { _ in },
        onSetOutOfFrame: { _ in },
        onSetUnresolved: { _ in },
        onAcceptFrame: {},
        currentSourceTime: nil
    )
    .frame(minWidth: 1000, minHeight: 600)
}

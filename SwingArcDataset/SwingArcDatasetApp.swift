import SwiftUI

@main
struct SwingArcDatasetApp: App {
    @State private var showsWorkspace = false
    @State private var annotationState: DatasetAnnotationState?

    private let store: GolfDatasetStore

    init() {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "SwingArcDataset/golf-keypoints-v1",
            isDirectory: true
        )
        store = GolfDatasetStore(rootDirectory: root)
    }

    var body: some Scene {
        WindowGroup("SwingArc Dataset") {
            if showsWorkspace, let state = annotationState {
                DatasetWorkspaceView(
                    clips: [],
                    selectedClipID: nil,
                    selectedFilter: .allClips,
                    annotationState: state,
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
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button("返回导入") {
                            showsWorkspace = false
                        }
                    }
                }
            } else {
                DatasetImportSheet(store: store)
                    .frame(minWidth: 760, minHeight: 620)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("标注工作台") {
                                // Show workspace with a minimal fixture state for Task 5
                                // Real data loading will come in Task 6.
                                enterWorkspace()
                            }
                            .disabled(annotationState == nil)
                        }
                    }
            }
        }
    }

    private func enterWorkspace() {
        // For Task 5, we set up a basic annotation state with a fixture prediction run.
        // Task 6 will load real data from the store.
        let roiTransform = GolfROIAffineTransform(
            a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0,
            invA: 1.0, invB: 0.0, invC: 0.0, invD: 1.0, invTx: 0.0, invTy: 0.0
        )
        var frames: [GolfPredictionFrame] = []
        for i in 0..<100 {
            var points: [GolfLandmark: GolfPredictionPoint] = [:]
            for landmark in GolfLandmark.allCases {
                points[landmark] = GolfPredictionPoint(
                    roiX: 0.25, roiY: 0.75,
                    heatmapConfidence: 0.91,
                    heatmapDispersion: 0.04,
                    visibilityProbabilities: [0.9, 0.08, 0.02],
                    preTrackingFullFramePoint: GolfNormalizedPoint(x: 0.4, y: 0.6),
                    postTrackingFullFramePoint: GolfNormalizedPoint(x: 0.401, y: 0.601),
                    trackingStatus: "tracked",
                    anomalyReason: nil
                )
            }
            frames.append(GolfPredictionFrame(
                sourceFrameIndex: i,
                sourceTime: Double(i) / 30.0,
                roiTransform: roiTransform,
                points: points,
                anomalyReason: nil
            ))
        }
        let predictionRun = GolfPredictionRun(
            predictionRunID: "pred-run-fixture",
            clipID: "clip-fixture",
            mediaSHA256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            visionFrameworkVersion: "1.0.0",
            visionRequestVersion: "VNDetectHumanBodyPoseRequest-v1",
            roiAlgorithmVersion: "roi-v1",
            roiConfigSHA256: String(repeating: "c", count: 64),
            modelSHA256: String(repeating: "d", count: 64),
            decoderVersion: "decoder-v1",
            trackerVersion: "tracker-v1",
            createdAt: Date(timeIntervalSince1970: 1000),
            frames: frames,
            provenanceHash: String(repeating: "e", count: 64)
        )
        annotationState = DatasetAnnotationState(
            predictionRun: predictionRun,
            currentSourceFrameIndex: 0,
            decisions: [:],
            annotatorID: "annotator-1",
            revisionID: "rev-001"
        )
        showsWorkspace = true
    }
}

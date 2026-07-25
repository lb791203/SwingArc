import SwiftUI

@main
struct SwingArcDatasetApp: App {
    @State private var showsWorkspace = false

    private let store: GolfDatasetStore

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwingArcDataset/golf-keypoints-v1", isDirectory: true)
        store = GolfDatasetStore(rootDirectory: root)
    }

    var body: some Scene {
        WindowGroup("SwingArc Dataset") {
            if showsWorkspace {
                // Task 5 intentionally opens an honest empty workspace. Task 6 owns
                // loading a real clip, prediction run, images, queue and persistence.
                DatasetWorkspaceView(
                    clips: [], selectedClipID: nil, selectedFilter: .allClips, annotationState: nil,
                    fullFrameImage: nil, roiImage: nil,
                    fullFrameImageSize: CGSize(width: 1920, height: 1080), roiImageSize: CGSize(width: 512, height: 512),
                    visionSkeleton: [], trailPoints: [:], timelineStages: [], isFrameLoading: false, showsROI: false, currentSourceTime: nil,
                    onSelectClip: { _ in }, onSelectFilter: { _ in }, onStep: { _ in }, onToggleROI: {}, onAcceptPrediction: { _ in },
                    onCorrectPoint: { _, _ in }, onSetOccluded: { _ in }, onSetOutOfFrame: { _ in }, onSetUnresolved: { _ in }, onAcceptFrame: {}
                )
                .frame(minWidth: 1000, minHeight: 600)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button("返回导入") { showsWorkspace = false }
                    }
                }
            } else {
                DatasetImportSheet(store: store)
                    .frame(minWidth: 760, minHeight: 620)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("标注工作台") { showsWorkspace = true }
                        }
                    }
            }
        }
    }
}

import SwiftUI

@main
struct SwingArcDatasetApp: App {
    private let store: GolfDatasetStore
    @StateObject private var workspaceController: DatasetWorkspaceController

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwingArcDataset/golf-keypoints-v1", isDirectory: true)
        let datasetStore = GolfDatasetStore(rootDirectory: root)
        store = datasetStore
        _workspaceController = StateObject(wrappedValue: DatasetWorkspaceController(
            store: datasetStore, sessionPersistence: UserDefaultsDatasetWorkspaceSessionPersistence(), annotatorID: "mac-annotator"
        ))
    }

    var body: some Scene {
        WindowGroup("SwingArc Dataset") {
            if workspaceController.selectedClipID != nil || !workspaceController.clips.isEmpty {
                DatasetWorkspaceHostView(controller: workspaceController)
                .frame(minWidth: 1000, minHeight: 600)
                .task { await workspaceController.restore() }
            } else {
                DatasetImportSheet(store: store)
                    .frame(minWidth: 760, minHeight: 620)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("标注工作台") { workspaceController.reloadClipList() }
                        }
                    }
            }
        }
    }
}

import SwiftUI

@main
struct SwingArcDatasetApp: App {
    private let store: GolfDatasetStore
    @StateObject private var workspaceController: DatasetWorkspaceController
    @State private var showsImporter = false

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwingArcDataset/golf-keypoints-v1", isDirectory: true)
        let datasetStore = GolfDatasetStore(rootDirectory: root)
        store = datasetStore
        _workspaceController = StateObject(wrappedValue: DatasetWorkspaceController(
            store: datasetStore,
            sessionPersistence: UserDefaultsDatasetWorkspaceSessionPersistence(),
            bookmarkPersistence: UserDefaultsDatasetWorkspaceBookmarkPersistence(),
            annotatorID: "mac-annotator"
        ))
    }

    var body: some Scene {
        WindowGroup("SwingArc Dataset") {
            if !showsImporter,
               workspaceController.selectedClipID != nil
                    || !workspaceController.clips.isEmpty {
                DatasetWorkspaceHostView(controller: workspaceController, store: store)
                .frame(minWidth: 1000, minHeight: 600)
                .task { await workspaceController.restore() }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("导入视频") {
                            showsImporter = true
                        }
                    }
                }
            } else {
                DatasetImportSheet(store: store) { receipt in
                    Task {
                        await workspaceController.registerImportedClip(
                            clipID: receipt.clip.clipID,
                            securityScopedBookmark: receipt.securityScopedBookmark
                        )
                        showsImporter = false
                    }
                }
                    .frame(minWidth: 760, minHeight: 620)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("标注工作台") {
                                workspaceController.reloadClipList()
                                showsImporter = false
                            }
                        }
                    }
            }
        }
    }
}

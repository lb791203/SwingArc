import SwiftUI

@main
struct SwingArcDatasetApp: App {
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
            DatasetImportSheet(store: store)
                .frame(minWidth: 760, minHeight: 620)
        }
    }
}

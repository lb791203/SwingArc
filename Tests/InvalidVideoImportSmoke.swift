import Foundation

@main
struct InvalidVideoImportSmoke {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            preconditionFailure("Pass one playable audio-only fixture")
        }

        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(
            "invalid-video-import-\(UUID().uuidString)",
            isDirectory: true
        )
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let suiteName = "InvalidVideoImportSmoke-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let existingURL = root.appendingPathComponent("existing.mp4")
        try Data("existing-project-media".utf8).write(to: existingURL)
        let existing = LocalProjectSummary(
            id: UUID(),
            videoURL: existingURL,
            name: "现有项目",
            duration: 2,
            sourceFrameRate: 60,
            modifiedAt: Date(timeIntervalSince1970: 100),
            status: .analyzed
        )
        LocalProjectStore.upsertSummary(
            existing,
            defaults: defaults,
            videoDirectory: root,
            fileManager: manager
        )
        let baselineProjects = LocalProjectStore.projects(
            defaults: defaults,
            videoDirectory: root,
            fileManager: manager
        )
        let baselineFiles = try Set(manager.contentsOfDirectory(atPath: root.path))
        var currentProjectURL: URL? = existingURL

        let corruptData = Data("not a movie".utf8)
        let audioOnlyURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let audioOnlyData = try Data(contentsOf: audioOnlyURL)
        let store = ImportedVideoStore(
            destinationDirectory: root,
            fileManager: manager
        )

        for invalidData in [corruptData, audioOnlyData] {
            do {
                let importedURL = try await store.persist(data: invalidData)
                currentProjectURL = importedURL
                LocalProjectStore.upsertSummary(
                    LocalProjectSummary(
                        videoURL: importedURL,
                        name: "不应创建",
                        duration: 1,
                        sourceFrameRate: 30
                    ),
                    defaults: defaults,
                    videoDirectory: root,
                    fileManager: manager
                )
                preconditionFailure("Invalid media must not validate")
            } catch {
                precondition(currentProjectURL == existingURL)
            }

            precondition(
                LocalProjectStore.projects(
                    defaults: defaults,
                    videoDirectory: root,
                    fileManager: manager
                ) == baselineProjects
            )
            let remainingFiles = try Set(
                manager.contentsOfDirectory(atPath: root.path)
            )
            precondition(
                remainingFiles == baselineFiles,
                "Only a newly copied invalid file may be removed"
            )
            precondition(
                manager.fileExists(atPath: audioOnlyURL.path),
                "The user-owned source fixture must remain untouched"
            )
        }
    }
}

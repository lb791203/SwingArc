import Foundation

@main
struct ProjectLibraryStoreSmoke {
    static func main() {
        let suiteName = "ProjectLibraryStoreSmoke-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let older = LocalProjectSummary(
            id: UUID(),
            videoURL: URL(fileURLWithPath: "/tmp/older.mov"),
            name: "旧项目",
            duration: 8.2,
            sourceFrameRate: 60,
            modifiedAt: Date(timeIntervalSince1970: 100),
            status: .annotated
        )
        let newer = LocalProjectSummary(
            id: UUID(),
            videoURL: URL(fileURLWithPath: "/tmp/newer.mov"),
            name: "新项目",
            duration: 4.6,
            sourceFrameRate: 120,
            modifiedAt: Date(timeIntervalSince1970: 200),
            status: .analyzed
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory

        LocalProjectStore.upsertSummary(older, defaults: defaults, videoDirectory: temporaryDirectory)
        LocalProjectStore.upsertSummary(newer, defaults: defaults, videoDirectory: temporaryDirectory)
        precondition(
            LocalProjectStore.projects(defaults: defaults, videoDirectory: temporaryDirectory).map(\.id)
                == [newer.id, older.id]
        )

        LocalProjectStore.rename(
            newer.id,
            to: "练习一",
            defaults: defaults,
            videoDirectory: temporaryDirectory
        )
        precondition(
            LocalProjectStore.projects(defaults: defaults, videoDirectory: temporaryDirectory)
                .first?.name == "练习一"
        )

        LocalProjectStore.remove(
            older.id,
            defaults: defaults,
            videoDirectory: temporaryDirectory
        )
        let remaining = LocalProjectStore.projects(
            defaults: defaults,
            videoDirectory: temporaryDirectory
        )
        precondition(remaining.count == 1)
        precondition(remaining[0].id == newer.id)

        let migrationSuite = "ProjectLibraryMigrationSmoke-\(UUID().uuidString)"
        guard let migrationDefaults = UserDefaults(suiteName: migrationSuite) else {
            preconditionFailure("Unable to create migration defaults")
        }
        defer { migrationDefaults.removePersistentDomain(forName: migrationSuite) }
        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: legacyURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: legacyURL) }
        _ = LocalProjectStore.save(
            LocalAnalysisProject(
                drawings: [],
                keyframes: [],
                isKeyframeMode: false,
                showPoseSkeleton: false,
                showHeadStability: false,
                showSpineAngle: false,
                showGrid: false
            ),
            for: legacyURL,
            defaults: migrationDefaults
        )
        let migrated = LocalProjectStore.projects(
            defaults: migrationDefaults,
            videoDirectory: legacyURL.deletingLastPathComponent()
        )
        precondition(migrated.count == 1)
        precondition(migrated[0].videoURL == legacyURL)

        let containerSuite = "ProjectContainerMigrationSmoke-\(UUID().uuidString)"
        guard let containerDefaults = UserDefaults(suiteName: containerSuite) else {
            preconditionFailure("Unable to create container migration defaults")
        }
        defer { containerDefaults.removePersistentDomain(forName: containerSuite) }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwingArcContainerMigration-\(UUID().uuidString)", isDirectory: true)
        let oldDirectory = root
            .appendingPathComponent("old-container", isDirectory: true)
            .appendingPathComponent("SwingArcVideos", isDirectory: true)
        let newDirectory = root
            .appendingPathComponent("new-container", isDirectory: true)
            .appendingPathComponent("SwingArcVideos", isDirectory: true)
        try? FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileName = "imported-fixed.mp4"
        let oldURL = oldDirectory.appendingPathComponent(fileName)
        let newURL = newDirectory.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: oldURL.path, contents: Data([0x00, 0x01]))
        try? FileManager.default.moveItem(at: oldURL, to: newURL)

        let legacySummary = LocalProjectSummary(
            id: UUID(),
            videoURL: oldURL,
            name: "更新前项目",
            duration: 6.4,
            sourceFrameRate: 120,
            modifiedAt: Date(timeIntervalSince1970: 300),
            status: .analyzed
        )
        let legacyProject = LocalAnalysisProject(
            drawings: [],
            keyframes: [KeyframeMarker(time: 0.8, stage: .top, source: .automatic)],
            isKeyframeMode: false,
            showPoseSkeleton: true,
            showHeadStability: false,
            showSpineAngle: false,
            showGrid: false
        )
        LocalProjectStore.seedLegacyProjectForTesting(
            legacyProject,
            summary: legacySummary,
            defaults: containerDefaults
        )

        let restored = LocalProjectStore.projects(
            defaults: containerDefaults,
            videoDirectory: newDirectory,
            fileManager: .default
        )
        precondition(restored.count == 1)
        precondition(restored[0].id == legacySummary.id)
        precondition(restored[0].videoURL == newURL)
        precondition(restored[0].name == legacySummary.name)
        precondition(
            LocalProjectStore.load(for: newURL, defaults: containerDefaults)?.keyframes
                == legacyProject.keyframes
        )

        let secondLoad = LocalProjectStore.projects(
            defaults: containerDefaults,
            videoDirectory: newDirectory,
            fileManager: .default
        )
        precondition(secondLoad == restored)
    }
}

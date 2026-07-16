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

        LocalProjectStore.upsertSummary(older, defaults: defaults)
        LocalProjectStore.upsertSummary(newer, defaults: defaults)
        precondition(LocalProjectStore.projects(defaults: defaults).map(\.id) == [newer.id, older.id])

        LocalProjectStore.rename(newer.id, to: "练习一", defaults: defaults)
        precondition(LocalProjectStore.projects(defaults: defaults).first?.name == "练习一")

        LocalProjectStore.remove(older.id, defaults: defaults)
        let remaining = LocalProjectStore.projects(defaults: defaults)
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
        let migrated = LocalProjectStore.projects(defaults: migrationDefaults)
        precondition(migrated.count == 1)
        precondition(migrated[0].videoURL == legacyURL)
    }
}

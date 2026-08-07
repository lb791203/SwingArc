import Foundation

@main
struct AnnotationProjectIsolationSmoke {
    static func main() throws {
        let suiteName = "AnnotationProjectIsolationSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(Data("existing-project".utf8), forKey: "com.liangbo.swingarc.project.fixture")
        defaults.set("fixture.mov", forKey: "com.liangbo.swingarc.last-video-url")
        let before = defaults.persistentDomain(forName: suiteName) ?? [:]

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let package = AnnotationFixture.package()
        let store = AnnotationStore(rootDirectory: root)
        try store.save(package)
        _ = try store.load(mediaSHA256: package.media.sha256)

        let after = defaults.persistentDomain(forName: suiteName) ?? [:]
        precondition(
            NSDictionary(dictionary: before).isEqual(to: after),
            "annotation storage must not mutate ordinary project defaults"
        )
    }
}

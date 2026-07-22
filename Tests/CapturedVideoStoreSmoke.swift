import Foundation

@main
struct CapturedVideoStoreSmoke {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            preconditionFailure("Pass one valid local video fixture")
        }

        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("captured-store-smoke-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let store = CapturedVideoStore(destinationDirectory: root)
        let missing = root.appendingPathComponent("missing.mp4")
        do {
            _ = try await store.persist(
                sourceURL: missing,
                prefix: "manual",
                quality: .complete
            )
            preconditionFailure("Missing media must fail")
        } catch let error as CapturedVideoStoreError {
            precondition(error == .missingSource)
        }

        let empty = root.appendingPathComponent("empty.mp4")
        precondition(manager.createFile(atPath: empty.path, contents: Data()))
        do {
            _ = try await store.persist(
                sourceURL: empty,
                prefix: "manual",
                quality: .complete
            )
            preconditionFailure("Empty media must fail")
        } catch let error as CapturedVideoStoreError {
            precondition(error == .emptyFile)
        }

        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let source = root.appendingPathComponent("valid-source.mp4")
        try manager.copyItem(at: fixture, to: source)
        let persisted = try await store.persist(
            sourceURL: source,
            prefix: "practice",
            quality: .possibleIncomplete
        )
        precondition(persisted.quality == .possibleIncomplete)
        precondition(persisted.url.deletingLastPathComponent() == root)
        precondition(persisted.url.lastPathComponent.hasPrefix("practice-"))
        precondition(manager.fileExists(atPath: persisted.url.path))
        precondition(!manager.fileExists(atPath: source.path))
        precondition(manager.fileExists(atPath: fixture.path))
    }
}

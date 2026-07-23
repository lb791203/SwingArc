import Foundation

@main
struct AnnotationStoreSmoke {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let video = root.appendingPathComponent("sample.mov")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data("video-bytes".utf8).write(to: video)

        let hash = try AnnotationStore.mediaSHA256(url: video)
        precondition(hash.count == 64)

        let package = AnnotationFixture.package(
            mediaSHA256: hash,
            timelineSHA256: String(repeating: "b", count: 64)
        )
        let store = AnnotationStore(
            rootDirectory: root.appendingPathComponent("labels")
        )
        try store.save(package)
        let restored = try store.load(mediaSHA256: hash)
        precondition(restored == package)

        let mismatched = AnnotationFixture.package(
            mediaSHA256: String(repeating: "c", count: 64),
            timelineSHA256: String(repeating: "b", count: 64)
        )
        do {
            try store.save(mismatched, expectedMediaSHA256: hash)
            preconditionFailure("mismatched media identity must be rejected")
        } catch AnnotationStoreError.mediaIdentityMismatch {
        }
    }
}

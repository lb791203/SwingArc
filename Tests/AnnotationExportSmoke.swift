import Foundation

@main
struct AnnotationExportSmoke {
    static func main() throws {
        let directory = CommandLine.arguments.dropFirst().first.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var package = AnnotationFixture.completeReviewedPackage()
        let receipt = try AnnotationExportService.freezeAndExport(
            package: &package,
            destinationDirectory: directory,
            now: Date(timeIntervalSince1970: 100)
        )
        precondition(package.frozenAt == Date(timeIntervalSince1970: 100))
        precondition(receipt.sha256.count == 64)
        precondition(receipt.url.pathExtension == "json")
        precondition(receipt.includesRawVideo == false)
        let restored = try AnnotationCoding.makeDecoder().decode(
            AnnotationPackage.self,
            from: Data(contentsOf: receipt.url)
        )
        precondition(restored == package)
        print("EXPORTED \(receipt.url.path) \(receipt.sha256)")

        var unreviewed = AnnotationFixture.completeReviewedPackage()
        unreviewed.passes[0].frameLabels[0].reviewed = false
        do {
            _ = try AnnotationExportService.freezeAndExport(
                package: &unreviewed,
                destinationDirectory: directory,
                now: Date()
            )
            preconditionFailure("unreviewed training data must not export")
        } catch AnnotationExportError.validationFailed {
        }
        precondition(unreviewed.frozenAt == nil)

        var activeDraft = AnnotationFixture.completeReviewedPackage()
        activeDraft.activeDraft = activeDraft.passes[0]
        do {
            _ = try AnnotationExportService.freezeAndExport(
                package: &activeDraft,
                destinationDirectory: directory,
                now: Date()
            )
            preconditionFailure("active drafts must not freeze")
        } catch AnnotationExportError.validationFailed {
        }
    }
}

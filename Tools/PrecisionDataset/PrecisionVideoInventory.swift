import Foundation

struct InventoryVideoMetadata: Codable, Equatable {
    let fileName: String
    let sourceFrameRate: Double
    let duration: Double
    let width: Int
    let height: Int
}

enum PrecisionVideoInventory {
    static func makeDevelopmentClip(
        metadata: InventoryVideoMetadata
    ) -> PrecisionClipManifest {
        PrecisionClipManifest(
            clipID: "unassigned-\(slug(for: metadata.fileName))",
            golferID: nil,
            fileName: metadata.fileName,
            view: nil,
            handedness: nil,
            split: .development,
            authorization: .internalReview,
            sourceFrameRate: metadata.sourceFrameRate,
            duration: metadata.duration,
            annotationPasses: 0,
            stages: [],
            frameLabels: [],
            sourceWidth: metadata.width,
            sourceHeight: metadata.height
        )
    }

    private static func slug(for fileName: String) -> String {
        let stem = URL(fileURLWithPath: fileName)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()
        let allowed = CharacterSet.alphanumerics
        let parts = stem.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        return parts.joined(separator: "-")
    }
}

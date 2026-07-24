import Foundation

@main
struct GolfDatasetIdentitySmoke {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_721_808_000)
        let empty = GolferRegistry(
            schemaVersion: 1,
            datasetID: "swingarc-local-1",
            golfers: []
        )
        let training = try empty.assign(
            golferID: "golfer-001",
            split: .training,
            at: now
        )
        precondition(training.split(for: "golfer-001") == .training)
        let reassigned = try training.assign(
            golferID: "golfer-001",
            split: .training,
            at: now
        )
        precondition(reassigned == training)
        do {
            _ = try training.assign(
                golferID: "golfer-001",
                split: .validation,
                at: now
            )
            preconditionFailure("a locked golfer cannot cross splits")
        } catch GolfDatasetIdentityError.splitConflict(
            golferID: "golfer-001",
            existing: .training,
            requested: .validation
        ) {}

        let media = GolfMediaIdentity(
            fileName: "clip.mov",
            sha256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            frameCount: 900,
            orientedWidth: 1080,
            orientedHeight: 1920,
            sourceTimescale: 600
        )
        let clip = GolfClipIdentity(
            schemaVersion: 1,
            clipID: "clip-001",
            golferID: "golfer-001",
            media: media,
            view: .downTheLine,
            handedness: .right,
            authorization: .trainingAllowed,
            pPointTruthSHA256: String(repeating: "c", count: 64)
        )
        precondition(clip.media.frameCount == 900)
        let encoded = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(
            GolfClipIdentity.self,
            from: encoded
        )
        precondition(decoded == clip)
    }
}

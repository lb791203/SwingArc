import Foundation

@main
struct GolfDatasetStoreSmoke {
    static func main() throws {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("golf-dataset-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tmpRoot)
        }

        let store = GolfDatasetStore(rootDirectory: tmpRoot)

        // 1. Registry save and load
        let registry = GolferRegistry(datasetID: "test-ds", golfers: [])
        let fixedDate = Date(timeIntervalSince1970: 1_721_808_000)
        let withGolfer = try registry.assign(golferID: "golfer-A", split: .training, at: fixedDate)
        try store.saveRegistry(withGolfer)
        let loadedRegistry = try store.loadRegistry()
        precondition(loadedRegistry == withGolfer, "Registry round-trip failed")

        // 2. Clip save and load
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
            clipID: "clip-001",
            golferID: "golfer-A",
            media: media,
            view: .downTheLine,
            handedness: .right,
            authorization: .trainingAllowed,
            pPointTruthSHA256: String(repeating: "c", count: 64)
        )
        try store.saveClip(clip)
        let loadedClip = try store.loadClip(clipID: "clip-001")
        precondition(loadedClip == clip, "Clip round-trip failed")

        // 3. Prediction append
        let prediction = makePrediction(id: "pred-run-1", clipID: "clip-001")
        try store.appendPrediction(prediction)
        let loadedPred = try store.loadPrediction(clipID: "clip-001", predictionRunID: "pred-run-1")
        precondition(loadedPred == prediction, "Prediction round-trip failed")

        // 4. Duplicate predictionRunID must fail
        let changedPrediction = makePrediction(id: "pred-run-1", clipID: "clip-001")
        do {
            try store.appendPrediction(changedPrediction)
            preconditionFailure("prediction runs are immutable")
        } catch GolfDatasetStoreError.predictionAlreadyExists("pred-run-1") {}
        // Original must be unchanged
        let stillOriginal = try store.loadPrediction(clipID: "clip-001", predictionRunID: "pred-run-1")
        precondition(stillOriginal == prediction, "Original prediction must not change")

        // 5. Revision same ID, same bytes = idempotent
        let revision = makeRevision(id: "rev-1", clipID: "clip-001", predRunID: "pred-run-1")
        try store.saveRevision(revision)
        try store.saveRevision(revision)  // idempotent
        let loadedRev = try store.loadRevision(clipID: "clip-001", revisionID: "rev-1")
        precondition(loadedRev == revision, "Revision round-trip failed")

        // 6. Revision same ID, different bytes = conflict
        do {
            try store.saveRevision(GolfAnnotationRevision(
                schemaVersion: 1,
                revisionID: "rev-1",
                clipID: "clip-001",
                parentPredictionRunID: "pred-run-1",
                annotatorID: "reviewer-2",
                createdAt: Date(timeIntervalSince1970: 2000),
                completedAt: nil,
                frameRevisions: [],
                notes: "different"
            ))
            preconditionFailure("revision conflict must be detected")
        } catch GolfDatasetStoreError.revisionConflict("rev-1") {}

        // 7. Snapshot reads all four record types
        let snapshot = try store.loadSnapshot()
        precondition(snapshot.registry == withGolfer)
        precondition(snapshot.clips.count == 1)
        precondition(snapshot.clips.first?.clipID == "clip-001")
        precondition(snapshot.predictions.count == 1)
        precondition(snapshot.predictions.first?.predictionRunID == "pred-run-1")
        precondition(snapshot.revisions.count == 1)
        precondition(snapshot.revisions.first?.revisionID == "rev-1")

        // 8. Output directory and list order are deterministic
        let snapshot2 = try store.loadSnapshot()
        precondition(snapshot == snapshot2, "Snapshot must be deterministic")

        // 9. No residual .tmp files
        let remaining = try FileManager.default.contentsOfDirectory(
            at: tmpRoot,
            includingPropertiesForKeys: nil
        )
        let tmpFiles = remaining.filter { $0.pathExtension == "tmp" }
        precondition(tmpFiles.isEmpty, "Residual .tmp files found: \(tmpFiles)")

        // 10. Path traversal rejection
        do {
            let evilClip = GolfClipIdentity(
                clipID: "../escape",
                golferID: "golfer-A",
                media: media,
                view: .downTheLine,
                handedness: .right,
                authorization: .trainingAllowed,
                pPointTruthSHA256: String(repeating: "c", count: 64)
            )
            try store.saveClip(evilClip)
            preconditionFailure("path traversal must be rejected")
        } catch GolfDatasetStoreError.pathTraversal {}

        do {
            let evilPred = makePrediction(id: "../../escape", clipID: "clip-001")
            try store.appendPrediction(evilPred)
            preconditionFailure("path traversal must be rejected")
        } catch GolfDatasetStoreError.pathTraversal {}

        do {
            let evilRev = makeRevision(id: "/absolute/path", clipID: "clip-001", predRunID: "pred-run-1")
            try store.saveRevision(evilRev)
            preconditionFailure("path traversal must be rejected")
        } catch GolfDatasetStoreError.pathTraversal {}

        print("All GolfDatasetStore tests passed.")
    }

    private static func makePrediction(id: String, clipID: String) -> GolfPredictionRun {
        GolfPredictionRun(
            predictionRunID: id,
            clipID: clipID,
            mediaSHA256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            visionFrameworkVersion: "1.0",
            visionRequestVersion: "v1",
            roiAlgorithmVersion: "roi-v1",
            roiConfigSHA256: String(repeating: "r", count: 64),
            modelSHA256: String(repeating: "m", count: 64),
            decoderVersion: "dec-v1",
            trackerVersion: "trk-v1",
            createdAt: Date(timeIntervalSince1970: 1000),
            frames: [],
            provenanceHash: String(repeating: "p", count: 64)
        )
    }

    private static func makeRevision(id: String, clipID: String, predRunID: String) -> GolfAnnotationRevision {
        GolfAnnotationRevision(
            revisionID: id,
            clipID: clipID,
            parentPredictionRunID: predRunID,
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: nil,
            frameRevisions: [],
            notes: nil
        )
    }
}

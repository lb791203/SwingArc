import Foundation

@main
struct GolfDatasetStoreSmoke {
    static func main() throws {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("golf-dataset-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let store = GolfDatasetStore(rootDirectory: tmpRoot)
        let fixedDate = Date(timeIntervalSince1970: 1_721_808_000)

        // 1. Registry save and load
        let registry = GolferRegistry(datasetID: "test-ds", golfers: [])
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
        let stillOriginal = try store.loadPrediction(clipID: "clip-001", predictionRunID: "pred-run-1")
        precondition(stillOriginal == prediction, "Original prediction must not change")

        // 5. Revision same ID, same bytes = idempotent
        let revision = makeRevision(id: "rev-1", clipID: "clip-001", predRunID: "pred-run-1")
        try store.saveRevision(revision)
        try store.saveRevision(revision)
        let loadedRev = try store.loadRevision(clipID: "clip-001", revisionID: "rev-1")
        precondition(loadedRev == revision, "Revision round-trip failed")

        // 6. Revision same ID, different bytes = conflict
        do {
            try store.saveRevision(GolfAnnotationRevision(
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

        // 9. No residual .tmp files (recursive)
        var tmpFiles: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: tmpRoot, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                if url.lastPathComponent.hasPrefix(".tmp-") {
                    tmpFiles.append(url)
                }
            }
        }
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

        // 11. Empty ID and whitespace ID rejected
        do {
            let emptyClip = GolfClipIdentity(
                clipID: "",
                golferID: "golfer-A",
                media: media,
                view: .downTheLine,
                handedness: .right,
                authorization: .trainingAllowed,
                pPointTruthSHA256: String(repeating: "c", count: 64)
            )
            try store.saveClip(emptyClip)
            preconditionFailure("empty ID must be rejected")
        } catch GolfDatasetStoreError.pathTraversal {}

        do {
            let spaceClip = GolfClipIdentity(
                clipID: "   ",
                golferID: "golfer-A",
                media: media,
                view: .downTheLine,
                handedness: .right,
                authorization: .trainingAllowed,
                pPointTruthSHA256: String(repeating: "c", count: 64)
            )
            try store.saveClip(spaceClip)
            preconditionFailure("whitespace ID must be rejected")
        } catch GolfDatasetStoreError.pathTraversal {}

        // 12. Concurrent prediction writes: collect both results, exactly one succeeds
        do {
            let concurrentStore = GolfDatasetStore(rootDirectory: tmpRoot)
            let predA = makePrediction(id: "pred-concurrent", clipID: "clip-001")
            let predB = makePrediction(id: "pred-concurrent", clipID: "clip-001")
            let group = DispatchGroup()
            var resultA: Error?
            var resultB: Error?
            let resultLock = NSLock()
            group.enter()
            DispatchQueue.global().async {
                do { try concurrentStore.appendPrediction(predA) } catch { resultLock.lock(); resultA = error; resultLock.unlock() }
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                do { try concurrentStore.appendPrediction(predB) } catch { resultLock.lock(); resultB = error; resultLock.unlock() }
                group.leave()
            }
            group.wait()
            let aSucceeded = resultA == nil
            let bSucceeded = resultB == nil
            precondition(
                (aSucceeded && !bSucceeded) || (!aSucceeded && bSucceeded),
                "Exactly one must succeed: A=\(aSucceeded) B=\(bSucceeded)"
            )
            if let errA = resultA {
                guard case GolfDatasetStoreError.predictionAlreadyExists("pred-concurrent") = errA else {
                    preconditionFailure("Failed prediction must be .predictionAlreadyExists, got \(errA)")
                }
            }
            if let errB = resultB {
                guard case GolfDatasetStoreError.predictionAlreadyExists("pred-concurrent") = errB else {
                    preconditionFailure("Failed prediction must be .predictionAlreadyExists, got \(errB)")
                }
            }
            let loaded = try concurrentStore.loadPrediction(clipID: "clip-001", predictionRunID: "pred-concurrent")
            precondition(loaded == predA || loaded == predB, "Prediction file must be intact")
        }

        // 13. Concurrent revision writes: same content = both succeed, different = conflict
        do {
            let concurrentStore = GolfDatasetStore(rootDirectory: tmpRoot)
            let revSameA = makeRevision(id: "rev-concurrent", clipID: "clip-001", predRunID: "pred-run-1")
            let revSameB = makeRevision(id: "rev-concurrent", clipID: "clip-001", predRunID: "pred-run-1")
            let group = DispatchGroup()
            var resultA: Error?
            var resultB: Error?
            let resultLock = NSLock()
            group.enter()
            DispatchQueue.global().async {
                do { try concurrentStore.saveRevision(revSameA) } catch { resultLock.lock(); resultA = error; resultLock.unlock() }
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                do { try concurrentStore.saveRevision(revSameB) } catch { resultLock.lock(); resultB = error; resultLock.unlock() }
                group.leave()
            }
            group.wait()
            precondition(resultA == nil && resultB == nil, "Same-content revisions must both succeed")
            let loadedRev = try concurrentStore.loadRevision(clipID: "clip-001", revisionID: "rev-concurrent")
            precondition(loadedRev == revSameA, "Revision must be intact")

            // Different content: exactly one succeeds
            let revDiffB = GolfAnnotationRevision(
                revisionID: "rev-conflict",
                clipID: "clip-001",
                parentPredictionRunID: "pred-run-1",
                annotatorID: "reviewer-x",
                createdAt: Date(timeIntervalSince1970: 3000),
                completedAt: nil,
                frameRevisions: [],
                notes: "conflict"
            )
            let group2 = DispatchGroup()
            var result2A: Error?
            var result2B: Error?
            group2.enter()
            DispatchQueue.global().async {
                do { try concurrentStore.saveRevision(GolfAnnotationRevision(
                    revisionID: "rev-conflict",
                    clipID: "clip-001",
                    parentPredictionRunID: "pred-run-1",
                    annotatorID: "reviewer-1",
                    createdAt: Date(timeIntervalSince1970: 1100),
                    completedAt: nil,
                    frameRevisions: [],
                    notes: nil
                )) } catch { resultLock.lock(); result2A = error; resultLock.unlock() }
                group2.leave()
            }
            group2.enter()
            DispatchQueue.global().async {
                do { try concurrentStore.saveRevision(revDiffB) } catch { resultLock.lock(); result2B = error; resultLock.unlock() }
                group2.leave()
            }
            group2.wait()
            let a2OK = result2A == nil
            let b2OK = result2B == nil
            precondition(
                (a2OK && !b2OK) || (!a2OK && b2OK),
                "Different-content revisions: exactly one must succeed"
            )
        }

        // 14. Lock released after error: normal write succeeds after failed write
        do {
            let lockStore = GolfDatasetStore(rootDirectory: tmpRoot)
            // This will fail (duplicate prediction)
            do { try lockStore.appendPrediction(prediction) } catch {}
            // This should succeed (new prediction)
            let newPred = makePrediction(id: "pred-after-error", clipID: "clip-001")
            try lockStore.appendPrediction(newPred)
            let loaded = try lockStore.loadPrediction(clipID: "clip-001", predictionRunID: "pred-after-error")
            precondition(loaded == newPred, "Write after error must succeed")
        }

        // 15. Snapshot with real directory read error
        do {
            // Create a clip directory with unreadable clip.json
            let badClipDir = tmpRoot.appendingPathComponent("clips").appendingPathComponent("bad-clip")
            try FileManager.default.createDirectory(at: badClipDir, withIntermediateDirectories: true)
            // Write garbage data
            try "not json".data(using: .utf8)!.write(to: badClipDir.appendingPathComponent("clip.json"))
            do {
                _ = try store.loadSnapshot()
                preconditionFailure("Corrupt clip.json must cause error")
            } catch {
                // Expected: error must propagate, not be swallowed
            }
        }

        // 13. Subject Anchor save, load, and collision test
        let anchorDecision = GolfSubjectAnchorDecision(
            anchorID: "anchor-001",
            clipID: "clip-001",
            mediaSHA256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            sourceFrameIndex: 10,
            candidateIndex: 1,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.5, y: 0.5),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "user1",
            decidedAt: fixedDate
        )
        try store.appendSubjectAnchor(anchorDecision, clipID: "clip-001")
        let loadedAnchors = try store.loadSubjectAnchors(clipID: "clip-001")
        precondition(loadedAnchors.count == 1)
        precondition(loadedAnchors[0] == anchorDecision)

        let loadedSingle = try store.loadSubjectAnchor(clipID: "clip-001", anchorID: "anchor-001")
        precondition(loadedSingle == anchorDecision)

        do {
            try store.appendSubjectAnchor(anchorDecision, clipID: "clip-001")
            preconditionFailure("Expected anchorID collision exception")
        } catch GolfDatasetStoreError.anchorAlreadyExists {
            // Expected
        }

        // Test anchor.clipID mismatch with directory clipID
        let mismatchAnchor = GolfSubjectAnchorDecision(
            anchorID: "anchor-002",
            clipID: "clip-WRONG",
            mediaSHA256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            sourceFrameIndex: 10,
            candidateIndex: 1,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.5, y: 0.5),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "user1",
            decidedAt: fixedDate
        )
        do {
            try store.appendSubjectAnchor(mismatchAnchor, clipID: "clip-001")
            preconditionFailure("Expected clipID mismatch exception")
        } catch GolfDatasetStoreError.anchorClipMismatch {
            // Expected
        }

        let missingClipAnchor = GolfSubjectAnchorDecision(
            anchorID: "anchor-missing-clip",
            clipID: "clip-missing",
            mediaSHA256: media.sha256,
            timelineSHA256: media.timelineSHA256,
            sourceFrameIndex: 0,
            candidateIndex: 0,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.5, y: 0.5),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "user1",
            decidedAt: fixedDate
        )
        do {
            try store.appendSubjectAnchor(
                missingClipAnchor,
                clipID: "clip-missing"
            )
            preconditionFailure("Anchor writes must require a readable clip")
        } catch {
            // Expected
        }

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

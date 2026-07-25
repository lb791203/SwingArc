import CoreGraphics
import Foundation

private let fixtureDate = Date(timeIntervalSince1970: 1_753_408_123)
private let shaA = String(repeating: "a", count: 64)
private let shaB = String(repeating: "b", count: 64)

private func clip(
    _ id: String = "held-out-clip",
    split: GolfDatasetSplit = .heldOut
) -> GolfClipIdentity {
    GolfClipIdentity(
        clipID: id,
        golferID: "golfer-\(split.rawValue)",
        media: GolfMediaIdentity(
            fileName: "\(id).mov",
            sha256: shaA,
            timelineSHA256: shaB,
            frameCount: 10,
            orientedWidth: 1280,
            orientedHeight: 720,
            sourceTimescale: 600
        ),
        view: .downTheLine,
        handedness: .right,
        authorization: .internalReview,
        pPointTruthSHA256: shaA
    )
}

private func prediction(
    _ clipID: String = "held-out-clip"
) -> GolfPredictionRun {
    let point = GolfPredictionPoint(
        roiX: 0.5,
        roiY: 0.5,
        heatmapConfidence: 0.9,
        heatmapDispersion: 0.1,
        visibilityProbabilities: [0.9, 0.1, 0],
        preTrackingFullFramePoint: GolfNormalizedPoint(x: 0.4, y: 0.6)
    )
    let transform = GolfROIAffineTransform(
        a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0,
        invA: 1, invB: 0, invC: 0, invD: 1, invTx: 0, invTy: 0
    )
    return GolfPredictionRun(
        predictionRunID: "fixture-run",
        clipID: clipID,
        mediaSHA256: shaA,
        timelineSHA256: shaB,
        visionFrameworkVersion: "vision",
        visionRequestVersion: "body",
        roiAlgorithmVersion: "roi",
        roiConfigSHA256: shaA,
        modelSHA256: shaA,
        decoderVersion: "decoder",
        trackerVersion: "tracker",
        createdAt: fixtureDate,
        frames: [
            GolfPredictionFrame(
                sourceFrameIndex: 4,
                sourceTime: 0.16,
                roiTransform: transform,
                points: Dictionary(
                    uniqueKeysWithValues: GolfLandmark.allCases.map {
                        ($0, point)
                    }
                )
            )
        ],
        provenanceHash: shaA
    )
}

private func revision(
    id: String,
    clipID: String = "held-out-clip",
    createdAt: Date,
    landmark: GolfLandmark
) -> GolfAnnotationRevision {
    GolfAnnotationRevision(
        revisionID: id,
        clipID: clipID,
        parentPredictionRunID: "fixture-run",
        annotatorID: "fixture",
        createdAt: createdAt,
        frameRevisions: [
            GolfFrameRevision(
                sourceFrameIndex: 4,
                decisions: [
                    GolfAnnotationDecision(
                        landmark: landmark,
                        kind: .correctedPoint,
                        fullFramePoint: GolfNormalizedPoint(x: 0.2, y: 0.3),
                        annotatorID: "fixture",
                        decidedAt: fixtureDate
                    )
                ]
            )
        ]
    )
}

private final class SpyStore: DatasetWorkspaceStore {
    var clips: [GolfClipIdentity]
    var revisions: [GolfAnnotationRevision] = []
    var predictionRunIDs = ["fixture-run"]
    let prediction: GolfPredictionRun
    var predictionLoads = 0
    var saves: [GolfAnnotationRevision] = []
    var failSave = false

    init(clips: [GolfClipIdentity], prediction: GolfPredictionRun) {
        self.clips = clips
        self.prediction = prediction
    }

    func loadClips() throws -> [GolfClipIdentity] { clips }

    func loadRegistry() throws -> GolferRegistry {
        GolferRegistry(
            datasetID: "test",
            golfers: clips.map { item in
                GolferRecord(
                    golferID: item.golferID,
                    split: item.golferID.contains("held-out")
                        ? .heldOut : .training,
                    splitLockedAt: fixtureDate
                )
            }
        )
    }

    func loadRevisions(clipID: String) throws -> [GolfAnnotationRevision] {
        revisions.filter { $0.clipID == clipID }
    }

    func listPredictionRunIDs(clipID: String) throws -> [String] {
        predictionRunIDs
    }

    func loadPrediction(
        clipID: String,
        predictionRunID: String
    ) throws -> GolfPredictionRun {
        predictionLoads += 1
        return prediction
    }

    func saveRevision(_ revision: GolfAnnotationRevision) throws {
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        saves.append(revision)
        revisions.append(revision)
    }
}

@MainActor
private final class StubMediaAccess: DatasetWorkspaceMediaAccessing {
    var metadata = DatasetWorkspaceMediaMetadata(
        mediaSHA256: shaA,
        frameCount: 10,
        timelineSHA256: shaB,
        orientedWidth: 1280,
        orientedHeight: 720
    )
    var openedBookmarks: [Data] = []
    var closeCount = 0
    var requestedFrames: [Int] = []

    func open(bookmark: Data) async throws -> DatasetWorkspaceMediaMetadata {
        openedBookmarks.append(bookmark)
        return metadata
    }

    func frame(
        at sourceFrameIndex: Int
    ) async throws -> DatasetWorkspaceDecodedFrame {
        requestedFrames.append(sourceFrameIndex)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 2,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return DatasetWorkspaceDecodedFrame(
            image: context.makeImage()!,
            sourceTime: Double(sourceFrameIndex) / 30
        )
    }

    func close() {
        closeCount += 1
    }
}

private func metadata(
    _ media: String = shaA,
    _ timeline: String = shaB,
    _ count: Int = 10
) -> DatasetWorkspaceMediaMetadata {
    DatasetWorkspaceMediaMetadata(
        mediaSHA256: media,
        frameCount: count,
        timelineSHA256: timeline,
        orientedWidth: 1280,
        orientedHeight: 720
    )
}

@main
@MainActor
struct MacDatasetBlindModeSmoke {
    static func main() async throws {
        let heldPresentation = DatasetAnnotationPresentation(
            split: .heldOut,
            reviewMode: .blindIndependentPass,
            prediction: prediction()
        )
        precondition(heldPresentation.visiblePredictionPoints.isEmpty)
        precondition(!heldPresentation.showsConfidence)
        precondition(!heldPresentation.allowsAcceptPrediction)

        let trainingPresentation = DatasetAnnotationPresentation(
            split: .training,
            reviewMode: .predictionFirst,
            prediction: prediction()
        )
        precondition(trainingPresentation.visiblePredictionPoints.count == 5)
        precondition(trainingPresentation.allowsAcceptPrediction)

        let held = clip()
        let training = clip("training-clip", split: .training)
        let store = SpyStore(
            clips: [held, training],
            prediction: prediction()
        )
        let sessions = InMemoryDatasetWorkspaceSessionPersistence()
        let bookmarks = InMemoryDatasetWorkspaceBookmarkPersistence()
        let media = StubMediaAccess()
        let controller = DatasetWorkspaceController(
            store: store,
            sessionPersistence: sessions,
            bookmarkPersistence: bookmarks,
            mediaAccess: media,
            annotatorID: "smoke"
        )

        try controller.openVerifiedClip(
            clip: held,
            split: .heldOut,
            parentPredictionRunID: "fixture-run",
            metadata: metadata(),
            queue: []
        )
        precondition(
            store.predictionLoads == 0,
            "held-out verified open must not load predictions"
        )
        controller.dispatch(
            .correctPoint(
                .grip,
                GolfNormalizedPoint(x: 0.2, y: 0.3),
                decidedAt: fixtureDate
            )
        )
        controller.dispatch(.setOccluded(.ball, decidedAt: fixtureDate))
        precondition(store.saves.count == 2)
        precondition(store.saves[0].revisionID != store.saves[1].revisionID)
        precondition(
            store.saves[1].frameRevisions.flatMap(\.decisions).count == 2,
            "each append-only save must contain the complete decision snapshot"
        )
        controller.dispatch(.step(1))
        precondition(store.saves.count == 2)
        precondition(sessions.load()?.currentSourceFrameIndex == 1)

        controller.rememberBookmark(Data([1]), for: held.clipID)
        controller.rememberBookmark(Data([2]), for: training.clipID)
        precondition(bookmarks.loadBookmark(for: held.clipID) == Data([1]))
        precondition(bookmarks.loadBookmark(for: training.clipID) == Data([2]))

        for bad in [
            metadata("wrong-media"),
            metadata(shaA, "wrong-timeline"),
            metadata(shaA, shaB, 9)
        ] {
            try controller.openVerifiedClip(
                clip: held,
                split: .heldOut,
                parentPredictionRunID: "fixture-run",
                metadata: bad,
                queue: []
            )
            if case .readOnly = controller.access {
                // Expected.
            } else {
                preconditionFailure("identity mismatch must be read-only")
            }
        }

        store.failSave = true
        try controller.openVerifiedClip(
            clip: held,
            split: .heldOut,
            parentPredictionRunID: "fixture-run",
            metadata: metadata(),
            queue: []
        )
        controller.dispatch(
            .setOutOfFrame(.shaftEnd, decidedAt: fixtureDate)
        )
        if case .readOnly = controller.access {
            // Expected.
        } else {
            preconditionFailure("save failure must be read-only")
        }
        store.failSave = false

        let sameTime = fixtureDate.addingTimeInterval(20)
        store.revisions = [
            revision(id: "revision-a", createdAt: sameTime, landmark: .grip),
            revision(id: "revision-z", createdAt: sameTime, landmark: .ball)
        ]
        sessions.save(
            DatasetWorkspaceSessionRecord(
                clipID: held.clipID,
                currentSourceFrameIndex: 4,
                filter: .p6p8,
                activeRevisionID: "revision-a"
            )
        )
        let restoredMedia = StubMediaAccess()
        let restored = DatasetWorkspaceController(
            store: store,
            sessionPersistence: sessions,
            bookmarkPersistence: bookmarks,
            mediaAccess: restoredMedia,
            annotatorID: "restore"
        )
        await restored.restore()
        precondition(restored.selectedClipID == held.clipID)
        precondition(restored.annotationState?.currentSourceFrameIndex == 4)
        precondition(restored.selectedFilter == .p6p8)
        precondition(restored.activeRevisionID == "revision-a")
        precondition(restoredMedia.requestedFrames == [4])
        precondition(
            store.predictionLoads == 0,
            "held-out restore must not load prediction content"
        )

        sessions.save(
            DatasetWorkspaceSessionRecord(
                clipID: held.clipID,
                currentSourceFrameIndex: 4,
                filter: .allClips,
                activeRevisionID: nil
            )
        )
        let latest = DatasetWorkspaceController(
            store: store,
            sessionPersistence: sessions,
            bookmarkPersistence: bookmarks,
            mediaAccess: StubMediaAccess(),
            annotatorID: "latest"
        )
        await latest.restore()
        precondition(
            latest.activeRevisionID == "revision-z",
            "latest revision uses createdAt then revisionID"
        )

        await restored.selectClip(training.clipID)
        precondition(store.predictionLoads == 1)
        await restored.selectClip(held.clipID)
        precondition(
            store.predictionLoads == 1,
            "switching back to held-out must not load predictions"
        )
        precondition(restoredMedia.openedBookmarks == [Data([1]), Data([2]), Data([1])])
        precondition(restoredMedia.closeCount >= 3)

        store.predictionRunIDs = []
        store.revisions = []
        await restored.selectClip(held.clipID)
        if case .readOnly(let reason) = restored.access {
            precondition(reason.contains("预测运行 ID"))
        } else {
            preconditionFailure("missing provenance must be read-only")
        }

        print("All Mac dataset blind-mode/controller tests passed.")
    }
}

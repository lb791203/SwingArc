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
    var failRevisionLoad = false

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

    func loadPPointTruth(
        clipID: String
    ) throws -> GolfPPointTruthDocument {
        GolfPPointTruthDocument(
            media: GolfPPointTruthMedia(
                sha256: shaA,
                timelineSHA256: shaB,
                frameCount: 10
            ),
            view: .downTheLine,
            stages: GolfPPointStageCode.allCases.enumerated().map {
                GolfPPointTruthStage(
                    code: $0.element,
                    sourceFrameIndex: $0.offset
                )
            }
        )
    }

    func loadRevisions(clipID: String) throws -> [GolfAnnotationRevision] {
        if failRevisionLoad { throw CocoaError(.fileReadCorruptFile) }
        return revisions.filter { $0.clipID == clipID }
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
private final class StubMediaRecorder {
    var openedBookmarks: [Data] = []
    var closeCount = 0
    var requestedFrames: [Int] = []
}

@MainActor
private final class StubMediaAccess: DatasetWorkspaceMediaAccessing {
    let recorder: StubMediaRecorder
    let activeURL: URL? = URL(fileURLWithPath: "/tmp/fixture-video.mov")
    var metadata = DatasetWorkspaceMediaMetadata(
        mediaSHA256: shaA,
        frameCount: 10,
        timelineSHA256: shaB,
        orientedWidth: 1280,
        orientedHeight: 720
    )

    init(recorder: StubMediaRecorder) {
        self.recorder = recorder
    }

    func open(bookmark: Data) async throws -> DatasetWorkspaceMediaMetadata {
        recorder.openedBookmarks.append(bookmark)
        return metadata
    }

    func frame(
        at sourceFrameIndex: Int
    ) async throws -> DatasetWorkspaceDecodedFrame {
        recorder.requestedFrames.append(sourceFrameIndex)
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
        recorder.closeCount += 1
    }
}

@MainActor
private final class StubMediaFactory: DatasetWorkspaceMediaAccessFactory {
    let recorder = StubMediaRecorder()
    var queued: [DatasetWorkspaceMediaAccessing] = []

    func makeMediaAccess() -> DatasetWorkspaceMediaAccessing {
        if !queued.isEmpty {
            return queued.removeFirst()
        }
        return StubMediaAccess(recorder: recorder)
    }
}

@MainActor
private final class SuspendingMediaAccess: DatasetWorkspaceMediaAccessing {
    let recorder: StubMediaRecorder
    let imageWidth: Int
    var activeURL: URL? { nil }
    var suspendOpen = false
    var suspendFrame = false
    private(set) var openStarted = false
    private(set) var frameStarted = false
    private(set) var closeCount = 0
    private var openContinuation: CheckedContinuation<Void, Never>?
    private var frameContinuation: CheckedContinuation<Void, Never>?

    init(recorder: StubMediaRecorder, imageWidth: Int) {
        self.recorder = recorder
        self.imageWidth = imageWidth
    }

    func open(bookmark: Data) async throws -> DatasetWorkspaceMediaMetadata {
        recorder.openedBookmarks.append(bookmark)
        openStarted = true
        if suspendOpen {
            await withCheckedContinuation { continuation in
                openContinuation = continuation
            }
        }
        return metadata()
    }

    func frame(
        at sourceFrameIndex: Int
    ) async throws -> DatasetWorkspaceDecodedFrame {
        recorder.requestedFrames.append(sourceFrameIndex)
        frameStarted = true
        if suspendFrame {
            await withCheckedContinuation { continuation in
                frameContinuation = continuation
            }
        }
        let context = CGContext(
            data: nil,
            width: imageWidth,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: imageWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return DatasetWorkspaceDecodedFrame(
            image: context.makeImage()!,
            sourceTime: Double(sourceFrameIndex) / 30
        )
    }

    func close() {
        closeCount += 1
        recorder.closeCount += 1
    }

    func resumeOpen() {
        suspendOpen = false
        openContinuation?.resume()
        openContinuation = nil
    }

    func resumeFrame() {
        suspendFrame = false
        frameContinuation?.resume()
        frameContinuation = nil
    }
}

@MainActor
private func waitUntil(
    _ description: String,
    condition: @MainActor () -> Bool
) async {
    for _ in 0..<1_000 {
        if condition() { return }
        await Task.yield()
    }
    preconditionFailure("Timed out waiting for \(description)")
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
        let mediaFactory = StubMediaFactory()
        let controller = DatasetWorkspaceController(
            store: store,
            sessionPersistence: sessions,
            bookmarkPersistence: bookmarks,
            mediaAccessFactory: mediaFactory,
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
        let restoredMediaFactory = StubMediaFactory()
        let restored = DatasetWorkspaceController(
            store: store,
            sessionPersistence: sessions,
            bookmarkPersistence: bookmarks,
            mediaAccessFactory: restoredMediaFactory,
            annotatorID: "restore"
        )
        await restored.restore()
        precondition(restored.selectedClipID == held.clipID)
        precondition(restored.annotationState?.currentSourceFrameIndex == 4)
        precondition(restored.selectedFilter == .p6p8)
        precondition(restored.activeRevisionID == "revision-a")
        precondition(
            restored.selectedVideoURL ==
                URL(fileURLWithPath: "/tmp/fixture-video.mov"),
            "Expected active video URL, got \(String(describing: restored.selectedVideoURL))"
        )
        precondition(restoredMediaFactory.recorder.requestedFrames == [4])
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
        let latestMediaFactory = StubMediaFactory()
        let latest = DatasetWorkspaceController(
            store: store,
            sessionPersistence: sessions,
            bookmarkPersistence: bookmarks,
            mediaAccessFactory: latestMediaFactory,
            annotatorID: "latest"
        )
        await latest.restore()
        precondition(
            latest.activeRevisionID == "revision-z",
            "latest revision uses createdAt then revisionID"
        )

        sessions.save(
            DatasetWorkspaceSessionRecord(
                clipID: held.clipID,
                currentSourceFrameIndex: 4,
                filter: .allClips,
                activeRevisionID: "revision-missing"
            )
        )
        let missingRevision = DatasetWorkspaceController(
            store: store,
            sessionPersistence: sessions,
            bookmarkPersistence: bookmarks,
            mediaAccessFactory: StubMediaFactory(),
            annotatorID: "missing-revision"
        )
        await missingRevision.restore()
        if case .readOnly(let reason) = missingRevision.access {
            precondition(reason.contains("已不存在"))
        } else {
            preconditionFailure("missing persisted revision must be read-only")
        }
        precondition(missingRevision.activeRevisionID == nil)
        precondition(
            sessions.load()?.activeRevisionID == "revision-missing",
            "failed exact restore must not erase the requested revision ID"
        )

        await restored.selectClip(training.clipID)
        precondition(store.predictionLoads == 1)
        await restored.selectClip(held.clipID)
        precondition(
            store.predictionLoads == 1,
            "switching back to held-out must not load predictions"
        )
        precondition(
            restoredMediaFactory.recorder.openedBookmarks
                == [Data([1]), Data([2]), Data([1])]
        )
        precondition(restoredMediaFactory.recorder.closeCount >= 2)

        store.failRevisionLoad = true
        await restored.selectClip(held.clipID)
        if case .readOnly(let reason) = restored.access {
            precondition(reason.contains("标注修订历史"))
        } else {
            preconditionFailure("revision read failure must be read-only")
        }
        precondition(restored.selectedVideoURL == nil)
        store.failRevisionLoad = false

        store.revisions = []
        store.predictionRunIDs = ["run-a", "run-b"]
        let loadsBeforeMultipleRunCheck = store.predictionLoads
        await restored.selectClip(held.clipID)
        if case .readOnly(let reason) = restored.access {
            precondition(reason.contains("多个预测运行"))
        } else {
            preconditionFailure("ambiguous prediction runs must be read-only")
        }
        precondition(store.predictionLoads == loadsBeforeMultipleRunCheck)
        await restored.selectClip(
            held.clipID,
            predictionRunID: "run-a"
        )
        precondition(restored.activePredictionRunID == "run-a")
        precondition(sessions.load()?.activePredictionRunID == "run-a")
        precondition(
            store.predictionLoads == loadsBeforeMultipleRunCheck,
            "explicit held-out provenance must not decode prediction content"
        )

        store.predictionRunIDs = ["fixture-run"]
        let openRaceFactory = StubMediaFactory()
        let slowOpen = SuspendingMediaAccess(
            recorder: openRaceFactory.recorder,
            imageWidth: 7
        )
        slowOpen.suspendOpen = true
        let fastOpen = SuspendingMediaAccess(
            recorder: openRaceFactory.recorder,
            imageWidth: 2
        )
        openRaceFactory.queued = [slowOpen, fastOpen]
        let openRace = DatasetWorkspaceController(
            store: store,
            sessionPersistence: InMemoryDatasetWorkspaceSessionPersistence(),
            bookmarkPersistence: bookmarks,
            mediaAccessFactory: openRaceFactory,
            annotatorID: "open-race"
        )
        let slowOpenTask = Task {
            await openRace.selectClip(held.clipID)
        }
        await waitUntil("slow media open") { slowOpen.openStarted }
        await openRace.selectClip(training.clipID)
        slowOpen.resumeOpen()
        await slowOpenTask.value
        precondition(openRace.selectedClipID == training.clipID)
        precondition(openRace.fullFrameImage?.width == 2)
        precondition(slowOpen.closeCount >= 1)

        let frameRaceFactory = StubMediaFactory()
        let slowFrame = SuspendingMediaAccess(
            recorder: frameRaceFactory.recorder,
            imageWidth: 9
        )
        slowFrame.suspendFrame = true
        let fastFrame = SuspendingMediaAccess(
            recorder: frameRaceFactory.recorder,
            imageWidth: 3
        )
        frameRaceFactory.queued = [slowFrame, fastFrame]
        let frameRace = DatasetWorkspaceController(
            store: store,
            sessionPersistence: InMemoryDatasetWorkspaceSessionPersistence(),
            bookmarkPersistence: bookmarks,
            mediaAccessFactory: frameRaceFactory,
            annotatorID: "frame-race"
        )
        let slowFrameTask = Task {
            await frameRace.selectClip(held.clipID)
        }
        await waitUntil("slow frame decode") { slowFrame.frameStarted }
        await frameRace.selectClip(training.clipID)
        slowFrame.resumeFrame()
        await slowFrameTask.value
        precondition(frameRace.selectedClipID == training.clipID)
        precondition(
            frameRace.fullFrameImage?.width == 3,
            "stale frame from prior clip must not overwrite active clip"
        )

        store.predictionRunIDs = []
        store.revisions = []
        await restored.selectClip(held.clipID)
        if case .readOnly(let reason) = restored.access {
            precondition(reason.contains("预测运行 ID"))
        } else {
            preconditionFailure("missing provenance must be read-only")
        }
        precondition(
            restored.selectedVideoURL ==
                URL(fileURLWithPath: "/tmp/fixture-video.mov"),
            "verified media must remain available for subject-anchor bootstrap"
        )
        precondition(
            restored.annotationState == nil,
            "missing provenance must not create an editable annotation state"
        )

        print("All Mac dataset blind-mode/controller tests passed.")
    }
}

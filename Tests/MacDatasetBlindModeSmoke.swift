import Foundation

private let fixtureDate = Date(timeIntervalSince1970: 1_753_408_123)

private func fixturePrediction() -> GolfPredictionRun {
    let point = GolfPredictionPoint(
        roiX: 0.5, roiY: 0.5, heatmapConfidence: 0.9, heatmapDispersion: 0.1,
        visibilityProbabilities: [0.9, 0.1, 0],
        preTrackingFullFramePoint: GolfNormalizedPoint(x: 0.4, y: 0.6),
        postTrackingFullFramePoint: GolfNormalizedPoint(x: 0.4, y: 0.6)
    )
    let transform = GolfROIAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0,
                                           invA: 1, invB: 0, invC: 0, invD: 1, invTx: 0, invTy: 0)
    return GolfPredictionRun(
        predictionRunID: "fixture-run", clipID: "held-out-clip",
        mediaSHA256: String(repeating: "a", count: 64), timelineSHA256: String(repeating: "b", count: 64),
        visionFrameworkVersion: "vision", visionRequestVersion: "body-pose", roiAlgorithmVersion: "roi",
        roiConfigSHA256: String(repeating: "c", count: 64), modelSHA256: String(repeating: "d", count: 64),
        decoderVersion: "decoder", trackerVersion: "tracker", createdAt: fixtureDate,
        frames: [GolfPredictionFrame(sourceFrameIndex: 4, sourceTime: 0.16, roiTransform: transform,
                                     points: Dictionary(uniqueKeysWithValues: GolfLandmark.allCases.map { ($0, point) }))],
        provenanceHash: String(repeating: "e", count: 64)
    )
}

private final class SpyStore: DatasetWorkspaceStore {
    let snapshot: GolfDatasetSnapshot
    let prediction: GolfPredictionRun
    private(set) var predictionLoads = 0
    private(set) var savedRevisions: [GolfAnnotationRevision] = []

    init(clip: GolfClipIdentity, prediction: GolfPredictionRun) {
        snapshot = GolfDatasetSnapshot(registry: nil, clips: [clip], predictions: [prediction], revisions: [])
        self.prediction = prediction
    }

    func loadSnapshot() throws -> GolfDatasetSnapshot { snapshot }
    func loadPrediction(clipID: String, predictionRunID: String) throws -> GolfPredictionRun {
        predictionLoads += 1
        return prediction
    }
    func saveRevision(_ revision: GolfAnnotationRevision) throws { savedRevisions.append(revision) }
}

private func fixtureClip() -> GolfClipIdentity {
    GolfClipIdentity(
        clipID: "held-out-clip", golferID: "golfer-held-out",
        media: GolfMediaIdentity(fileName: "fixture.mov", sha256: String(repeating: "a", count: 64),
                                 timelineSHA256: String(repeating: "b", count: 64), frameCount: 10,
                                 orientedWidth: 1920, orientedHeight: 1080, sourceTimescale: 600),
        view: .downTheLine, handedness: .right, authorization: .internalReview,
        pPointTruthSHA256: String(repeating: "c", count: 64)
    )
}

@main
struct MacDatasetBlindModeSmoke {
    static func main() throws {
        let prediction = fixturePrediction()
        let heldOut = DatasetAnnotationPresentation(split: .heldOut, reviewMode: .blindIndependentPass, prediction: prediction)
        precondition(heldOut.visiblePredictionPoints.isEmpty)
        precondition(!heldOut.showsConfidence)
        precondition(!heldOut.allowsAcceptPrediction)

        let training = DatasetAnnotationPresentation(split: .training, reviewMode: .predictionFirst, prediction: prediction)
        precondition(training.visiblePredictionPoints.count == 5)
        precondition(training.allowsAcceptPrediction)

        let store = SpyStore(clip: fixtureClip(), prediction: prediction)
        let sessions = InMemoryDatasetWorkspaceSessionPersistence()
        let controller = DatasetWorkspaceController(store: store, sessionPersistence: sessions, annotatorID: "smoke")
        try controller.openVerifiedClip(clip: fixtureClip(), split: .heldOut, parentPredictionRunID: prediction.predictionRunID,
                                       metadata: DatasetWorkspaceMediaMetadata(frameCount: 10, timelineSHA256: String(repeating: "b", count: 64)),
                                       queue: [], securityScopedBookmark: Data([1]))
        precondition(store.predictionLoads == 0, "Blind held-out open must not load a prediction run")
        controller.dispatch(.correctPoint(.grip, GolfNormalizedPoint(x: 0.2, y: 0.3), decidedAt: fixtureDate))
        precondition(store.savedRevisions.count == 1, "Every decision must save one revision")
        controller.dispatch(.step(1))
        precondition(store.savedRevisions.count == 1, "Stepping saves cursor session, not a revision")
        print("All Mac dataset blind-mode tests passed.")
    }
}

import Foundation

@main
struct GolfDatasetValidatorSmoke {
    static func main() throws {
        let registry = makeRegistry()
        let clip = makeClip(clipID: "clip-001", golferID: "golfer-A", auth: .trainingAllowed)
        let prediction = makePrediction(id: "pred-1", clipID: "clip-001")
        let revision = makeRevision(id: "rev-1", clipID: "clip-001", predRunID: "pred-1")

        // 1. Valid snapshot passes
        let valid = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction],
            revisions: [revision]
        )
        let errors = GolfDatasetValidator.validate(snapshot: valid)
        precondition(errors.isEmpty, "Valid snapshot should pass, got \(errors)")

        // 2. Duplicate clip ID
        let dupSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip, clip],
            predictions: [prediction],
            revisions: [revision]
        )
        let dupErrors = GolfDatasetValidator.validate(snapshot: dupSnap)
        precondition(
            dupErrors.contains(.duplicateClipID("clip-001")),
            "Must detect duplicate clip ID, got \(dupErrors)"
        )

        // 3. Golfer split conflict: clip says trainingAllowed but registry says validation
        let registryVal = GolferRegistry(datasetID: "test-ds", golfers: [
            GolferRecord(golferID: "golfer-A", split: .validation, splitLockedAt: Date(timeIntervalSince1970: 1_721_808_000))
        ])
        let splitSnap = GolfDatasetSnapshot(
            registry: registryVal,
            clips: [clip],
            predictions: [],
            revisions: []
        )
        let splitErrors = GolfDatasetValidator.validate(snapshot: splitSnap)
        precondition(
            splitErrors.contains(.golferSplitConflict(golferID: "golfer-A", registry: .validation, clip: .training)),
            "Must detect split conflict, got \(splitErrors)"
        )

        // 4. Training not authorized
        let noAuthClip = GolfClipIdentity(
            clipID: "clip-noauth",
            golferID: "golfer-A",
            media: makeMedia(),
            view: .downTheLine,
            handedness: .right,
            authorization: .internalReview,
            pPointTruthSHA256: String(repeating: "c", count: 64)
        )
        let noAuthSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [noAuthClip],
            predictions: [],
            revisions: []
        )
        let noAuthErrors = GolfDatasetValidator.validate(snapshot: noAuthSnap)
        precondition(
            noAuthErrors.contains(.trainingNotAuthorized("clip-noauth")),
            "Must detect unauthorized training clip, got \(noAuthErrors)"
        )

        // 5. Missing prediction run
        let missingPredSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [],
            revisions: [revision]
        )
        let missingPredErrors = GolfDatasetValidator.validate(snapshot: missingPredSnap)
        precondition(
            missingPredErrors.contains(.missingPredictionRun("pred-1")),
            "Must detect missing prediction, got \(missingPredErrors)"
        )

        // 6. Frame out of range
        let oorRev = makeRevision(id: "rev-oor", clipID: "clip-001", predRunID: "pred-1", frameIndex: 900)
        let oorSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction],
            revisions: [oorRev]
        )
        let oorErrors = GolfDatasetValidator.validate(snapshot: oorSnap)
        precondition(
            oorErrors.contains(.frameOutOfRange(clipID: "clip-001", sourceFrameIndex: 900)),
            "Must detect out-of-range frame, got \(oorErrors)"
        )

        // 7. Media SHA mismatch
        let badMediaClipObj = GolfClipIdentity(
            clipID: "clip-001",
            golferID: "golfer-A",
            media: GolfMediaIdentity(
                fileName: "clip.mov",
                sha256: String(repeating: "x", count: 64),
                timelineSHA256: String(repeating: "b", count: 64),
                frameCount: 900,
                orientedWidth: 1080,
                orientedHeight: 1920,
                sourceTimescale: 600
            ),
            view: .downTheLine,
            handedness: .right,
            authorization: .trainingAllowed,
            pPointTruthSHA256: String(repeating: "c", count: 64)
        )
        let badMediaSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [badMediaClipObj],
            predictions: [prediction],
            revisions: []
        )
        let badMediaErrors = GolfDatasetValidator.validate(snapshot: badMediaSnap)
        precondition(
            badMediaErrors.contains(.mediaHashMismatch("clip-001")),
            "Must detect media hash mismatch, got \(badMediaErrors)"
        )

        // 8. Timeline SHA mismatch
        let badTimelineClip = GolfClipIdentity(
            clipID: "clip-001",
            golferID: "golfer-A",
            media: GolfMediaIdentity(
                fileName: "clip.mov",
                sha256: String(repeating: "a", count: 64),
                timelineSHA256: String(repeating: "x", count: 64),
                frameCount: 900,
                orientedWidth: 1080,
                orientedHeight: 1920,
                sourceTimescale: 600
            ),
            view: .downTheLine,
            handedness: .right,
            authorization: .trainingAllowed,
            pPointTruthSHA256: String(repeating: "c", count: 64)
        )
        let badTimelineSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [badTimelineClip],
            predictions: [prediction],
            revisions: []
        )
        let badTimelineErrors = GolfDatasetValidator.validate(snapshot: badTimelineSnap)
        precondition(
            badTimelineErrors.contains(.timelineHashMismatch("clip-001")),
            "Must detect timeline hash mismatch, got \(badTimelineErrors)"
        )

        // 9. Revision references different clip
        let wrongClipRev = GolfAnnotationRevision(
            revisionID: "rev-wrong",
            clipID: "clip-other",
            parentPredictionRunID: "pred-1",
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [],
            notes: nil
        )
        let wrongClipSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction],
            revisions: [wrongClipRev]
        )
        let wrongClipErrors = GolfDatasetValidator.validate(snapshot: wrongClipSnap)
        precondition(
            wrongClipErrors.contains(.missingClip("clip-other")),
            "Must detect missing clip reference, got \(wrongClipErrors)"
        )

        // 10. Revision completedAt nil
        let incompleteRev = GolfAnnotationRevision(
            revisionID: "rev-incomplete",
            clipID: "clip-001",
            parentPredictionRunID: "pred-1",
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: nil,
            frameRevisions: [],
            notes: nil
        )
        let incompleteSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction],
            revisions: [incompleteRev]
        )
        let incompleteErrors = GolfDatasetValidator.validate(snapshot: incompleteSnap)
        precondition(
            incompleteErrors.contains(.revisionNotCompleted("rev-incomplete")),
            "Must detect incomplete revision, got \(incompleteErrors)"
        )

        // 11. Duplicate landmark decisions
        let dupLandRev = GolfAnnotationRevision(
            revisionID: "rev-dupland",
            clipID: "clip-001",
            parentPredictionRunID: "pred-1",
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [
                GolfFrameRevision(sourceFrameIndex: 10, decisions: [
                    makeDecision(landmark: .grip, kind: .correctedPoint),
                    makeDecision(landmark: .grip, kind: .occluded),
                    makeDecision(landmark: .shaftStart, kind: .correctedPoint),
                    makeDecision(landmark: .shaftEnd, kind: .correctedPoint),
                    makeDecision(landmark: .clubhead, kind: .correctedPoint),
                    makeDecision(landmark: .ball, kind: .correctedPoint),
                ])
            ],
            notes: nil
        )
        let dupLandSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction],
            revisions: [dupLandRev]
        )
        let dupLandErrors = GolfDatasetValidator.validate(snapshot: dupLandSnap)
        precondition(
            dupLandErrors.contains(.duplicateLandmarkDecision(clipID: "clip-001", sourceFrameIndex: 10, landmark: .grip)),
            "Must detect duplicate landmark, got \(dupLandErrors)"
        )

        // 12. Visible decision without coordinate
        let noCoordRev = GolfAnnotationRevision(
            revisionID: "rev-nocoord",
            clipID: "clip-001",
            parentPredictionRunID: "pred-1",
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [
                GolfFrameRevision(sourceFrameIndex: 10, decisions: [
                    GolfAnnotationDecision(landmark: .grip, kind: .correctedPoint, fullFramePoint: nil, annotatorID: "reviewer-1", decidedAt: Date()),
                    makeDecision(landmark: .shaftStart, kind: .correctedPoint),
                    makeDecision(landmark: .shaftEnd, kind: .correctedPoint),
                    makeDecision(landmark: .clubhead, kind: .correctedPoint),
                    makeDecision(landmark: .ball, kind: .correctedPoint),
                ])
            ],
            notes: nil
        )
        let noCoordSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction],
            revisions: [noCoordRev]
        )
        let noCoordErrors = GolfDatasetValidator.validate(snapshot: noCoordSnap)
        precondition(
            noCoordErrors.contains(.decisionValidationError(clipID: "clip-001", sourceFrameIndex: 10, landmark: .grip)),
            "Must detect missing coordinate, got \(noCoordErrors)"
        )

        // 13. Hidden decision with coordinate
        let hiddenCoordRev = GolfAnnotationRevision(
            revisionID: "rev-hidden",
            clipID: "clip-001",
            parentPredictionRunID: "pred-1",
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [
                GolfFrameRevision(sourceFrameIndex: 10, decisions: [
                    GolfAnnotationDecision(landmark: .grip, kind: .occluded, fullFramePoint: GolfNormalizedPoint(x: 0.5, y: 0.5), annotatorID: "reviewer-1", decidedAt: Date()),
                    makeDecision(landmark: .shaftStart, kind: .correctedPoint),
                    makeDecision(landmark: .shaftEnd, kind: .correctedPoint),
                    makeDecision(landmark: .clubhead, kind: .correctedPoint),
                    makeDecision(landmark: .ball, kind: .correctedPoint),
                ])
            ],
            notes: nil
        )
        let hiddenCoordSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction],
            revisions: [hiddenCoordRev]
        )
        let hiddenCoordErrors = GolfDatasetValidator.validate(snapshot: hiddenCoordSnap)
        precondition(
            hiddenCoordErrors.contains(.decisionValidationError(clipID: "clip-001", sourceFrameIndex: 10, landmark: .grip)),
            "Must detect hidden decision with coordinate, got \(hiddenCoordErrors)"
        )

        // 14. acceptedPrediction without matching prediction point
        let noBallPrediction = GolfPredictionRun(
            predictionRunID: "pred-noball",
            clipID: "clip-001",
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
            frames: [
                GolfPredictionFrame(
                    sourceFrameIndex: 10,
                    sourceTime: 0.333,
                    roiTransform: GolfROIAffineTransform(
                        a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0,
                        invA: 1, invB: 0, invC: 0, invD: 1, invTx: 0, invTy: 0
                    ),
                    points: [
                        .grip: GolfPredictionPoint(roiX: 0.5, roiY: 0.6, heatmapConfidence: 0.9, heatmapDispersion: 0.04, visibilityProbabilities: [0.9, 0.08, 0.02]),
                        .shaftStart: GolfPredictionPoint(roiX: 0.5, roiY: 0.55, heatmapConfidence: 0.85, heatmapDispersion: 0.05, visibilityProbabilities: [0.85, 0.1, 0.05]),
                        .shaftEnd: GolfPredictionPoint(roiX: 0.5, roiY: 0.45, heatmapConfidence: 0.8, heatmapDispersion: 0.06, visibilityProbabilities: [0.8, 0.15, 0.05]),
                        .clubhead: GolfPredictionPoint(roiX: 0.5, roiY: 0.4, heatmapConfidence: 0.95, heatmapDispersion: 0.02, visibilityProbabilities: [0.95, 0.03, 0.02]),
                        // .ball intentionally missing
                    ]
                )
            ],
            provenanceHash: String(repeating: "p", count: 64)
        )
        let noPredPointRev = GolfAnnotationRevision(
            revisionID: "rev-nopred",
            clipID: "clip-001",
            parentPredictionRunID: "pred-noball",
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [
                GolfFrameRevision(sourceFrameIndex: 10, decisions: [
                    GolfAnnotationDecision(landmark: .ball, kind: .acceptedPrediction, fullFramePoint: GolfNormalizedPoint(x: 0.5, y: 0.5), annotatorID: "reviewer-1", decidedAt: Date()),
                    makeDecision(landmark: .grip, kind: .correctedPoint),
                    makeDecision(landmark: .shaftStart, kind: .correctedPoint),
                    makeDecision(landmark: .shaftEnd, kind: .correctedPoint),
                    makeDecision(landmark: .clubhead, kind: .correctedPoint),
                ])
            ],
            notes: nil
        )
        let noPredPointSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction, noBallPrediction],
            revisions: [noPredPointRev]
        )
        let noPredPointErrors = GolfDatasetValidator.validate(snapshot: noPredPointSnap)
        precondition(
            noPredPointErrors.contains(.missingPredictionPoint(clipID: "clip-001", sourceFrameIndex: 10, landmark: .ball)),
            "Must detect missing prediction point, got \(noPredPointErrors)"
        )

        // 15. Deterministic ordering
        let multiErrorSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip, clip],
            predictions: [prediction],
            revisions: [revision, oorRev]
        )
        let run1 = GolfDatasetValidator.validate(snapshot: multiErrorSnap)
        let run2 = GolfDatasetValidator.validate(snapshot: multiErrorSnap)
        precondition(run1 == run2, "Validation must be deterministic")
        precondition(run1.count >= 2, "Multiple errors should be collected")

        // 16. Golfer not in registry
        let orphanClip = GolfClipIdentity(
            clipID: "clip-orphan",
            golferID: "golfer-NONE",
            media: makeMedia(),
            view: .downTheLine,
            handedness: .right,
            authorization: .trainingAllowed,
            pPointTruthSHA256: String(repeating: "c", count: 64)
        )
        let orphanSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [orphanClip],
            predictions: [],
            revisions: []
        )
        let orphanErrors = GolfDatasetValidator.validate(snapshot: orphanSnap)
        precondition(
            orphanErrors.contains(.golferNotInRegistry("golfer-NONE")),
            "Must detect golfer not in registry, got \(orphanErrors)"
        )

        print("All GolfDatasetValidator tests passed.")
    }

    // MARK: - Helpers

    static func makeRegistry() -> GolferRegistry {
        let registry = GolferRegistry(datasetID: "test-ds", golfers: [])
        return try! registry.assign(golferID: "golfer-A", split: .training, at: Date(timeIntervalSince1970: 1_721_808_000))
    }

    static func makeMedia() -> GolfMediaIdentity {
        GolfMediaIdentity(
            fileName: "clip.mov",
            sha256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            frameCount: 900,
            orientedWidth: 1080,
            orientedHeight: 1920,
            sourceTimescale: 600
        )
    }

    static func makeClip(clipID: String, golferID: String, auth: GolfDatasetAuthorization) -> GolfClipIdentity {
        GolfClipIdentity(
            clipID: clipID,
            golferID: golferID,
            media: makeMedia(),
            view: .downTheLine,
            handedness: .right,
            authorization: auth,
            pPointTruthSHA256: String(repeating: "c", count: 64)
        )
    }

    static func makePrediction(id: String, clipID: String) -> GolfPredictionRun {
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
            frames: [
                GolfPredictionFrame(
                    sourceFrameIndex: 10,
                    sourceTime: 0.333,
                    roiTransform: GolfROIAffineTransform(
                        a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0,
                        invA: 1, invB: 0, invC: 0, invD: 1, invTx: 0, invTy: 0
                    ),
                    points: [
                        .grip: GolfPredictionPoint(roiX: 0.5, roiY: 0.6, heatmapConfidence: 0.9, heatmapDispersion: 0.04, visibilityProbabilities: [0.9, 0.08, 0.02]),
                        .shaftStart: GolfPredictionPoint(roiX: 0.5, roiY: 0.55, heatmapConfidence: 0.85, heatmapDispersion: 0.05, visibilityProbabilities: [0.85, 0.1, 0.05]),
                        .shaftEnd: GolfPredictionPoint(roiX: 0.5, roiY: 0.45, heatmapConfidence: 0.8, heatmapDispersion: 0.06, visibilityProbabilities: [0.8, 0.15, 0.05]),
                        .clubhead: GolfPredictionPoint(roiX: 0.5, roiY: 0.4, heatmapConfidence: 0.95, heatmapDispersion: 0.02, visibilityProbabilities: [0.95, 0.03, 0.02]),
                        .ball: GolfPredictionPoint(roiX: 0.52, roiY: 0.7, heatmapConfidence: 0.92, heatmapDispersion: 0.03, visibilityProbabilities: [0.92, 0.05, 0.03]),
                    ]
                )
            ],
            provenanceHash: String(repeating: "p", count: 64)
        )
    }

    static func makeDecision(landmark: GolfLandmark, kind: GolfAnnotationDecisionKind, point: GolfNormalizedPoint? = nil) -> GolfAnnotationDecision {
        let actualPoint: GolfNormalizedPoint?
        switch kind {
        case .acceptedPrediction, .correctedPoint:
            actualPoint = point ?? GolfNormalizedPoint(x: 0.5, y: 0.5)
        case .occluded, .outOfFrame, .unresolved:
            actualPoint = nil
        }
        return GolfAnnotationDecision(
            landmark: landmark,
            kind: kind,
            fullFramePoint: actualPoint,
            annotatorID: "reviewer-1",
            decidedAt: Date(timeIntervalSince1970: 1100)
        )
    }

    static func makeRevision(id: String, clipID: String, predRunID: String, frameIndex: Int = 10) -> GolfAnnotationRevision {
        GolfAnnotationRevision(
            revisionID: id,
            clipID: clipID,
            parentPredictionRunID: predRunID,
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [
                GolfFrameRevision(sourceFrameIndex: frameIndex, decisions: [
                    makeDecision(landmark: .grip, kind: .correctedPoint),
                    makeDecision(landmark: .shaftStart, kind: .correctedPoint),
                    makeDecision(landmark: .shaftEnd, kind: .correctedPoint),
                    makeDecision(landmark: .clubhead, kind: .correctedPoint),
                    makeDecision(landmark: .ball, kind: .correctedPoint),
                ])
            ],
            notes: nil
        )
    }
}

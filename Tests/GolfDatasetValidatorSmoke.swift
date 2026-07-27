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

        testManualBootstrapAndModelInferenceValidation(registry: registry, clip: clip)

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

        // 3. Golfer split conflict: registry says validation, clip says internalReview
        // Split is golfer-level (owned by registry), authorization is independent.
        // The validator checks that each clip's golfer is in the registry with a consistent split.
        // Here we verify that a clip with authorization=internalReview triggers trainingNotAuthorized.
        let registryVal = GolferRegistry(datasetID: "test-ds", golfers: [
            GolferRecord(golferID: "golfer-A", split: .validation, splitLockedAt: Date(timeIntervalSince1970: 1_721_808_000))
        ])
        let validationInternalReviewClip = GolfClipIdentity(
            clipID: "clip-noauth-2",
            golferID: "golfer-A",
            media: makeMedia(),
            view: .downTheLine,
            handedness: .right,
            authorization: .internalReview,
            pPointTruthSHA256: String(repeating: "c", count: 64)
        )
        let splitSnap = GolfDatasetSnapshot(
            registry: registryVal,
            clips: [validationInternalReviewClip],
            predictions: [],
            revisions: []
        )
        let splitErrors = GolfDatasetValidator.validate(snapshot: splitSnap)
        precondition(
            splitErrors.contains(.trainingNotAuthorized("clip-noauth-2")),
            "Must detect unauthorized clip, got \(splitErrors)"
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

        // 17. Duplicate prediction run ID
        let dupPredSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction, prediction],
            revisions: []
        )
        let dupPredErrors = GolfDatasetValidator.validate(snapshot: dupPredSnap)
        precondition(
            dupPredErrors.contains(.duplicatePredictionRunID("pred-1")),
            "Must detect duplicate prediction run ID, got \(dupPredErrors)"
        )

        // 18. Prediction frame out of range
        let oorPred = GolfPredictionRun(
            predictionRunID: "pred-oor",
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
                    sourceFrameIndex: 999,
                    sourceTime: 33.3,
                    roiTransform: GolfROIAffineTransform(
                        a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0,
                        invA: 1, invB: 0, invC: 0, invD: 1, invTx: 0, invTy: 0
                    ),
                    points: [:]
                )
            ],
            provenanceHash: String(repeating: "p", count: 64)
        )
        let oorPredSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [oorPred],
            revisions: []
        )
        let oorPredErrors = GolfDatasetValidator.validate(snapshot: oorPredSnap)
        precondition(
            oorPredErrors.contains(.predictionFrameOutOfRange(clipID: "clip-001", sourceFrameIndex: 999)),
            "Must detect prediction frame out of range, got \(oorPredErrors)"
        )

        // 19. acceptedPrediction coordinate mismatch
        // Decision says (0.1, 0.1) but prediction resolves to (0.5, 0.5)
        let mismatchPred = GolfPredictionRun(
            predictionRunID: "pred-mismatch",
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
                        .grip: GolfPredictionPoint(
                            roiX: 0.5, roiY: 0.5,
                            heatmapConfidence: 0.9, heatmapDispersion: 0.04,
                            visibilityProbabilities: [0.9, 0.08, 0.02],
                            preTrackingFullFramePoint: GolfNormalizedPoint(x: 0.5, y: 0.5)
                        ),
                        .shaftStart: GolfPredictionPoint(roiX: 0.5, roiY: 0.55, heatmapConfidence: 0.85, heatmapDispersion: 0.05, visibilityProbabilities: [0.85, 0.1, 0.05]),
                        .shaftEnd: GolfPredictionPoint(roiX: 0.5, roiY: 0.45, heatmapConfidence: 0.8, heatmapDispersion: 0.06, visibilityProbabilities: [0.8, 0.15, 0.05]),
                        .clubhead: GolfPredictionPoint(roiX: 0.5, roiY: 0.4, heatmapConfidence: 0.95, heatmapDispersion: 0.02, visibilityProbabilities: [0.95, 0.03, 0.02]),
                        .ball: GolfPredictionPoint(roiX: 0.52, roiY: 0.7, heatmapConfidence: 0.92, heatmapDispersion: 0.03, visibilityProbabilities: [0.92, 0.05, 0.03]),
                    ]
                )
            ],
            provenanceHash: String(repeating: "p", count: 64)
        )
        let mismatchRev = GolfAnnotationRevision(
            revisionID: "rev-mismatch",
            clipID: "clip-001",
            parentPredictionRunID: "pred-mismatch",
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [
                GolfFrameRevision(sourceFrameIndex: 10, decisions: [
                    // Decision coordinate (0.1, 0.1) does not match prediction resolved point (0.5, 0.5)
                    GolfAnnotationDecision(landmark: .grip, kind: .acceptedPrediction, fullFramePoint: GolfNormalizedPoint(x: 0.1, y: 0.1), annotatorID: "reviewer-1", decidedAt: Date()),
                    makeDecision(landmark: .shaftStart, kind: .correctedPoint),
                    makeDecision(landmark: .shaftEnd, kind: .correctedPoint),
                    makeDecision(landmark: .clubhead, kind: .correctedPoint),
                    makeDecision(landmark: .ball, kind: .correctedPoint),
                ])
            ],
            notes: nil
        )
        let mismatchSnap = GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [mismatchPred],
            revisions: [mismatchRev]
        )
        let mismatchErrors = GolfDatasetValidator.validate(snapshot: mismatchSnap)
        precondition(
            mismatchErrors.contains(.acceptedPredictionCoordinateMismatch(clipID: "clip-001", sourceFrameIndex: 10, landmark: .grip)),
            "Must detect acceptedPrediction coordinate mismatch, got \(mismatchErrors)"
        )

        // 20. Missing decisions produce one frame-level error, not one per landmark
        let missingBallRevision = GolfAnnotationRevision(
            revisionID: "rev-missing-ball",
            clipID: "clip-001",
            parentPredictionRunID: "pred-1",
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [
                GolfFrameRevision(sourceFrameIndex: 542, decisions: [
                    makeDecision(landmark: .grip, kind: .correctedPoint),
                    makeDecision(landmark: .shaftStart, kind: .correctedPoint),
                    makeDecision(landmark: .shaftEnd, kind: .correctedPoint),
                    makeDecision(landmark: .clubhead, kind: .correctedPoint),
                ])
            ],
            notes: nil
        )
        let missingBallErrors = GolfDatasetValidator.validate(snapshot: GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction],
            revisions: [missingBallRevision]
        ))
        precondition(
            missingBallErrors.filter {
                $0 == .incompleteFrameDecisions(clipID: "clip-001", sourceFrameIndex: 542)
            }.count == 1,
            "A frame with missing decisions must produce exactly one incomplete-frame error: \(missingBallErrors)"
        )

        // 21. Public ordering is clipID, frame index, then enum order
        let ordered = [
            GolfDatasetValidationError.frameOutOfRange(clipID: "clip-001", sourceFrameIndex: 20),
            GolfDatasetValidationError.incompleteFrameDecisions(clipID: "clip-001", sourceFrameIndex: 10),
        ].sorted()
        precondition(
            ordered.first == .incompleteFrameDecisions(clipID: "clip-001", sourceFrameIndex: 10),
            "Frame index must sort before enum order: \(ordered)"
        )

        // 22. A missing registry never silently validates clips
        let missingRegistryErrors = GolfDatasetValidator.validate(snapshot: GolfDatasetSnapshot(
            registry: nil,
            clips: [clip],
            predictions: [],
            revisions: []
        ))
        precondition(
            missingRegistryErrors.contains(.golferNotInRegistry("golfer-A")),
            "A clip without a golfer registry must fail: \(missingRegistryErrors)"
        )

        // 23. One golfer recorded in two splits is rejected
        let conflictingRegistry = GolferRegistry(datasetID: "test-ds", golfers: [
            GolferRecord(golferID: "golfer-A", split: .training, splitLockedAt: Date(timeIntervalSince1970: 1)),
            GolferRecord(golferID: "golfer-A", split: .validation, splitLockedAt: Date(timeIntervalSince1970: 2)),
        ])
        let registryConflictErrors = GolfDatasetValidator.validate(snapshot: GolfDatasetSnapshot(
            registry: conflictingRegistry,
            clips: [clip],
            predictions: [],
            revisions: []
        ))
        precondition(
            registryConflictErrors.contains(.golferSplitConflict(
                golferID: "golfer-A",
                registry: .training,
                clip: .validation
            )),
            "Conflicting golfer-level splits must fail: \(registryConflictErrors)"
        )

        // 24. An accepted prediction without a resolved full-frame point is missing evidence
        let unresolvedPredictionRevision = GolfAnnotationRevision(
            revisionID: "rev-unresolved-prediction",
            clipID: "clip-001",
            parentPredictionRunID: "pred-1",
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [
                GolfFrameRevision(sourceFrameIndex: 10, decisions: [
                    makeDecision(landmark: .grip, kind: .acceptedPrediction),
                    makeDecision(landmark: .shaftStart, kind: .correctedPoint),
                    makeDecision(landmark: .shaftEnd, kind: .correctedPoint),
                    makeDecision(landmark: .clubhead, kind: .correctedPoint),
                    makeDecision(landmark: .ball, kind: .correctedPoint),
                ])
            ],
            notes: nil
        )
        let unresolvedPredictionErrors = GolfDatasetValidator.validate(snapshot: GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction],
            revisions: [unresolvedPredictionRevision]
        ))
        precondition(
            unresolvedPredictionErrors.contains(.missingPredictionPoint(
                clipID: "clip-001",
                sourceFrameIndex: 10,
                landmark: .grip
            )),
            "Accepted predictions need resolved full-frame coordinates: \(unresolvedPredictionErrors)"
        )

        // 25. Duplicate prediction frames never get silently selected with first(where:)
        let duplicateFramePrediction = GolfPredictionRun(
            predictionRunID: "pred-duplicate-frame",
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
            frames: [prediction.frames[0], prediction.frames[0]],
            provenanceHash: String(repeating: "p", count: 64)
        )
        let duplicatePredictionFrameErrors = GolfDatasetValidator.validate(snapshot: GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [duplicateFramePrediction],
            revisions: []
        ))
        precondition(
            duplicatePredictionFrameErrors.contains(.duplicatePredictionFrame(
                clipID: "clip-001",
                sourceFrameIndex: 10
            )),
            "Duplicate prediction frames must fail: \(duplicatePredictionFrameErrors)"
        )

        // 26. A revision cannot use a prediction run owned by a different clip
        let otherClipPrediction = makePrediction(id: "pred-other-clip", clipID: "clip-other")
        let mismatchedParentRevision = makeRevision(
            id: "rev-wrong-parent-clip",
            clipID: "clip-001",
            predRunID: "pred-other-clip"
        )
        let predictionClipMismatchErrors = GolfDatasetValidator.validate(snapshot: GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [otherClipPrediction],
            revisions: [mismatchedParentRevision]
        ))
        precondition(
            predictionClipMismatchErrors.contains(.predictionClipMismatch(
                clipID: "clip-001",
                predictionRunID: "pred-other-clip"
            )),
            "Revision/prediction clip linkage must fail: \(predictionClipMismatchErrors)"
        )

        // 27. A reviewed source frame appears only once in a revision
        let duplicateRevisionFrame = GolfAnnotationRevision(
            revisionID: "rev-duplicate-frame",
            clipID: "clip-001",
            parentPredictionRunID: "pred-1",
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [
                makeRevision(id: "unused-a", clipID: "clip-001", predRunID: "pred-1").frameRevisions[0],
                makeRevision(id: "unused-b", clipID: "clip-001", predRunID: "pred-1").frameRevisions[0],
            ],
            notes: nil
        )
        let duplicateRevisionFrameErrors = GolfDatasetValidator.validate(snapshot: GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction],
            revisions: [duplicateRevisionFrame]
        ))
        precondition(
            duplicateRevisionFrameErrors.contains(.duplicateRevisionFrame(
                clipID: "clip-001",
                sourceFrameIndex: 10
            )),
            "Duplicate revision frames must fail: \(duplicateRevisionFrameErrors)"
        )

        // 28. Completed revisions still require valid top-level provenance
        let invalidRevisionMetadata = GolfAnnotationRevision(
            revisionID: "rev-invalid-metadata",
            clipID: "clip-001",
            parentPredictionRunID: "pred-1",
            annotatorID: "   ",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [],
            notes: nil
        )
        let invalidRevisionMetadataErrors = GolfDatasetValidator.validate(snapshot: GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction],
            revisions: [invalidRevisionMetadata]
        ))
        precondition(
            invalidRevisionMetadataErrors.contains(.revisionValidationError("rev-invalid-metadata")),
            "Invalid revision provenance must fail: \(invalidRevisionMetadataErrors)"
        )

        // 29. Validator ordering uses owning clipID even when the public error stores another ID
        let clipA = makeClip(clipID: "clip-a", golferID: "golfer-A", auth: .trainingAllowed)
        let clipB = makeClip(clipID: "clip-b", golferID: "golfer-A", auth: .trainingAllowed)
        let missingForA = GolfAnnotationRevision(
            revisionID: "rev-a",
            clipID: "clip-a",
            parentPredictionRunID: "z-prediction",
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [],
            notes: nil
        )
        let missingForB = GolfAnnotationRevision(
            revisionID: "rev-b",
            clipID: "clip-b",
            parentPredictionRunID: "a-prediction",
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [],
            notes: nil
        )
        let owningClipOrder = GolfDatasetValidator.validate(snapshot: GolfDatasetSnapshot(
            registry: registry,
            clips: [clipB, clipA],
            predictions: [],
            revisions: [missingForB, missingForA]
        ))
        precondition(
            owningClipOrder == [
                .missingPredictionRun("z-prediction"),
                .missingPredictionRun("a-prediction"),
            ],
            "Owning clipID must sort before referenced prediction ID: \(owningClipOrder)"
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
            modelSHA256: String(repeating: "a", count: 64),
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
            provenanceHash: String(repeating: "f", count: 64)
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

    static func testManualBootstrapAndModelInferenceValidation(registry: GolferRegistry, clip: GolfClipIdentity) {
        // modelInference missing modelSHA256
        let badModelInfRun = GolfPredictionRun(
            schemaVersion: 2,
            runKind: .modelInference,
            predictionRunID: "bad-model-run",
            clipID: clip.clipID,
            mediaSHA256: clip.media.sha256,
            timelineSHA256: clip.media.timelineSHA256,
            visionFrameworkVersion: "v1",
            visionRequestVersion: "r1",
            roiAlgorithmVersion: "roi-v1",
            roiConfigSHA256: String(repeating: "r", count: 64),
            modelSHA256: nil, // FAIL: modelInference requires 64-hex modelSHA256
            decoderVersion: "dec-v1",
            trackerVersion: "trk-v1",
            createdAt: Date(),
            frames: [],
            provenanceHash: String(repeating: "f", count: 64)
        )
        let snap1 = GolfDatasetSnapshot(registry: registry, clips: [clip], predictions: [badModelInfRun], revisions: [])
        let errs1 = GolfDatasetValidator.validate(snapshot: snap1)
        precondition(errs1.contains(.invalidModelSHA256(predictionRunID: "bad-model-run")), "Must reject modelInference with missing modelSHA256, got \(errs1)")

        // manualBootstrap with modelSHA256
        let badBootstrapRun = GolfPredictionRun(
            schemaVersion: 2,
            runKind: .manualBootstrap,
            predictionRunID: "bad-bootstrap-run",
            clipID: clip.clipID,
            mediaSHA256: clip.media.sha256,
            timelineSHA256: clip.media.timelineSHA256,
            visionFrameworkVersion: "v1",
            visionRequestVersion: "r1",
            roiAlgorithmVersion: "roi-v1",
            roiConfigSHA256: String(repeating: "r", count: 64),
            modelSHA256: String(repeating: "m", count: 64), // FAIL: manualBootstrap must have nil modelSHA256
            decoderVersion: "dec-v1",
            trackerVersion: "trk-v1",
            createdAt: Date(),
            frames: [],
            provenanceHash: String(repeating: "f", count: 64)
        )
        let snap2 = GolfDatasetSnapshot(registry: registry, clips: [clip], predictions: [badBootstrapRun], revisions: [])
        let errs2 = GolfDatasetValidator.validate(snapshot: snap2)
        precondition(errs2.contains(.manualBootstrapHasModelSHA(predictionRunID: "bad-bootstrap-run")), "Must reject manualBootstrap with modelSHA256, got \(errs2)")

        testManualBootstrapValidationWithMissingFrames(registry: registry, clip: clip)
        testManualBootstrapValidationWithInvalidInverseTransform(registry: registry, clip: clip)
        testManualBootstrapValidationWithInvalidInverseTranslation(registry: registry, clip: clip)
        testManualBootstrapValidationWithTamperedProvenanceHash(registry: registry, clip: clip)
    }

    static func testManualBootstrapValidationWithMissingFrames(registry: GolferRegistry, clip: GolfClipIdentity) {
        // Frame count mismatch (clip frameCount is 60, but run only has 1 frame)
        let incompleteRun = GolfPredictionRun(
            schemaVersion: 2,
            runKind: .manualBootstrap,
            predictionRunID: "incomplete-run",
            clipID: clip.clipID,
            mediaSHA256: clip.media.sha256,
            timelineSHA256: clip.media.timelineSHA256,
            visionFrameworkVersion: "v1",
            visionRequestVersion: "r1",
            roiAlgorithmVersion: "roi-v1",
            roiConfigSHA256: String(repeating: "r", count: 64),
            modelSHA256: nil,
            decoderVersion: "dec-v1",
            trackerVersion: "trk-v1",
            createdAt: Date(),
            frames: [
                GolfPredictionFrame(
                    sourceFrameIndex: 0,
                    sourceTime: 0.0,
                    roiTransform: GolfROIAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0, invA: 1, invB: 0, invC: 0, invD: 1, invTx: 0, invTy: 0),
                    points: [:]
                )
            ],
            provenanceHash: String(repeating: "f", count: 64)
        )
        let snap = GolfDatasetSnapshot(registry: registry, clips: [clip], predictions: [incompleteRun], revisions: [])
        let errs = GolfDatasetValidator.validate(snapshot: snap)
        precondition(errs.contains(.emptyPredictionRunFrames(predictionRunID: "incomplete-run")), "Must reject incomplete manualBootstrap frames, got \(errs)")
    }

    static func testManualBootstrapValidationWithInvalidInverseTransform(registry: GolferRegistry, clip: GolfClipIdentity) {
        // Transform forward x inverse does not equal identity matrix
        let badTransformRun = GolfPredictionRun(
            schemaVersion: 2,
            runKind: .manualBootstrap,
            predictionRunID: "bad-transform-run",
            clipID: clip.clipID,
            mediaSHA256: clip.media.sha256,
            timelineSHA256: clip.media.timelineSHA256,
            visionFrameworkVersion: "v1",
            visionRequestVersion: "r1",
            roiAlgorithmVersion: "roi-v1",
            roiConfigSHA256: String(repeating: "r", count: 64),
            modelSHA256: nil,
            decoderVersion: "dec-v1",
            trackerVersion: "trk-v1",
            createdAt: Date(),
            frames: [
                GolfPredictionFrame(
                    sourceFrameIndex: 0,
                    sourceTime: 0.0,
                    roiTransform: GolfROIAffineTransform(
                        a: 2, b: 0, c: 0, d: 2, tx: 0, ty: 0,
                        invA: 1, invB: 0, invC: 0, invD: 1, invTx: 0, invTy: 0 // invA * a = 2 != 1 -> INVALID
                    ),
                    points: [:]
                )
            ],
            provenanceHash: String(repeating: "f", count: 64)
        )
        let snap = GolfDatasetSnapshot(registry: registry, clips: [clip], predictions: [badTransformRun], revisions: [])
        let errs = GolfDatasetValidator.validate(snapshot: snap)
        precondition(errs.contains(.invalidPredictionROITransform(predictionRunID: "bad-transform-run", sourceFrameIndex: 0)), "Must reject invalid inverse transform, got \(errs)")
    }

    static func testManualBootstrapValidationWithTamperedProvenanceHash(registry: GolferRegistry, clip: GolfClipIdentity) {
        let formatValidButIncorrectHash = String(repeating: "e", count: 64)
        let tamperedRun = GolfPredictionRun(
            schemaVersion: 2,
            runKind: .manualBootstrap,
            predictionRunID: formatValidButIncorrectHash,
            clipID: clip.clipID,
            mediaSHA256: clip.media.sha256,
            timelineSHA256: clip.media.timelineSHA256,
            visionFrameworkVersion: "v1",
            visionRequestVersion: "r1",
            roiAlgorithmVersion: "roi-v1",
            roiConfigSHA256: String(repeating: "r", count: 64),
            modelSHA256: nil,
            decoderVersion: "dec-v1",
            trackerVersion: "trk-v1",
            createdAt: Date(),
            frames: [
                GolfPredictionFrame(
                    sourceFrameIndex: 0,
                    sourceTime: 0.0,
                    roiTransform: GolfROIAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0, invA: 1, invB: 0, invC: 0, invD: 1, invTx: 0, invTy: 0),
                    points: [:]
                )
            ],
            provenanceHash: formatValidButIncorrectHash
        )
        let snap = GolfDatasetSnapshot(registry: registry, clips: [clip], predictions: [tamperedRun], revisions: [])
        let errs = GolfDatasetValidator.validate(snapshot: snap)
        precondition(
            errs.contains(.provenanceHashMismatch(predictionRunID: formatValidButIncorrectHash)),
            "Must recompute and reject a format-valid but incorrect provenanceHash, got \(errs)"
        )
    }

    static func testManualBootstrapValidationWithInvalidInverseTranslation(
        registry: GolferRegistry,
        clip: GolfClipIdentity
    ) {
        let runID = String(repeating: "d", count: 64)
        let badTranslationRun = GolfPredictionRun(
            schemaVersion: 2,
            runKind: .manualBootstrap,
            predictionRunID: runID,
            clipID: clip.clipID,
            mediaSHA256: clip.media.sha256,
            timelineSHA256: clip.media.timelineSHA256,
            visionFrameworkVersion: "v1",
            visionRequestVersion: "r1",
            roiAlgorithmVersion: "roi-v1",
            roiConfigSHA256: String(repeating: "r", count: 64),
            modelSHA256: nil,
            decoderVersion: "dec-v1",
            trackerVersion: "trk-v1",
            createdAt: Date(),
            frames: [
                GolfPredictionFrame(
                    sourceFrameIndex: 0,
                    sourceTime: 0,
                    roiTransform: GolfROIAffineTransform(
                        a: 1, b: 0, c: 0, d: 1, tx: 0.25, ty: -0.1,
                        invA: 1, invB: 0, invC: 0, invD: 1,
                        invTx: 0, invTy: 0
                    ),
                    points: [:]
                )
            ],
            provenanceHash: runID
        )
        let errors = GolfDatasetValidator.validate(
            snapshot: GolfDatasetSnapshot(
                registry: registry,
                clips: [clip],
                predictions: [badTranslationRun],
                revisions: []
            )
        )
        precondition(
            errors.contains(
                .invalidPredictionROITransform(
                    predictionRunID: runID,
                    sourceFrameIndex: 0
                )
            ),
            "Must reject an inverse transform with incorrect translation, got \(errors)"
        )
    }
}

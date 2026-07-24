import Foundation

@main
struct GolfKeypointAnnotationContractSmoke {
    static func main() throws {
        // 1. Verify fixed order of GolfLandmark
        precondition(GolfLandmark.allCases == [.grip, .shaftStart, .shaftEnd, .clubhead, .ball])

        // 2. Accepted prediction binding to actual prediction
        let predictedWithPoint = GolfPredictionPoint(
            roiX: 0.25,
            roiY: 0.75,
            heatmapConfidence: 0.91,
            heatmapDispersion: 0.04,
            visibilityProbabilities: [0.9, 0.08, 0.02],
            preTrackingFullFramePoint: NormalizedPoint(x: 0.4, y: 0.6),
            postTrackingFullFramePoint: NormalizedPoint(x: 0.401, y: 0.601),
            trackingStatus: "tracked",
            anomalyReason: nil
        )
        let predictedWithoutPoint = GolfPredictionPoint(
            roiX: 0.1,
            roiY: 0.1,
            heatmapConfidence: 0.1,
            heatmapDispersion: 0.5,
            visibilityProbabilities: [0.1, 0.8, 0.1],
            preTrackingFullFramePoint: nil,
            postTrackingFullFramePoint: nil,
            trackingStatus: "untracked",
            anomalyReason: "low-confidence"
        )

        let accepted = GolfAnnotationDecision(
            landmark: .clubhead,
            kind: .acceptedPrediction,
            fullFramePoint: NormalizedPoint(x: 0.401, y: 0.601),
            annotatorID: "reviewer-1",
            decidedAt: Date(timeIntervalSince1970: 10)
        )
        let validatedAccepted = try accepted.validated()

        // 2a. Accepted prediction with valid prediction
        let resolvedAccepted = try validatedAccepted.resolvedLandmark(prediction: predictedWithPoint)
        precondition(resolvedAccepted?.visibility == .visible)
        precondition(resolvedAccepted?.source == .acceptedPrediction)
        precondition(resolvedAccepted?.point == NormalizedPoint(x: 0.401, y: 0.601))

        // 2b. Accepted prediction with nil prediction must fail
        do {
            _ = try validatedAccepted.resolvedLandmark(prediction: nil)
            preconditionFailure("acceptedPrediction with nil prediction must throw error")
        } catch GolfAnnotationContractError.acceptedPredictionRequiresPrediction {}

        // 2c. Accepted prediction with missing prediction coordinate must fail
        do {
            _ = try validatedAccepted.resolvedLandmark(prediction: predictedWithoutPoint)
            preconditionFailure("acceptedPrediction with prediction missing coordinate must throw error")
        } catch GolfAnnotationContractError.acceptedPredictionMissingCoordinate {}

        // 2d. Accepted prediction with mismatched coordinate must fail
        let mismatchedAccepted = GolfAnnotationDecision(
            landmark: .clubhead,
            kind: .acceptedPrediction,
            fullFramePoint: NormalizedPoint(x: 0.99, y: 0.99),
            annotatorID: "reviewer-1",
            decidedAt: Date(timeIntervalSince1970: 10)
        )
        do {
            _ = try mismatchedAccepted.validated().resolvedLandmark(prediction: predictedWithPoint)
            preconditionFailure("acceptedPrediction with mismatched coordinate must throw error")
        } catch GolfAnnotationContractError.acceptedPredictionCoordinateMismatch {}

        // 3. Corrected point uses manual point independently of prediction
        let corrected = GolfAnnotationDecision(
            landmark: .grip,
            kind: .correctedPoint,
            fullFramePoint: NormalizedPoint(x: 0.45, y: 0.55),
            annotatorID: "reviewer-1",
            decidedAt: Date(timeIntervalSince1970: 10)
        )
        let validatedCorrected = try corrected.validated()
        let resolvedCorrected = try validatedCorrected.resolvedLandmark(prediction: predictedWithoutPoint)
        precondition(resolvedCorrected?.visibility == .visible)
        precondition(resolvedCorrected?.source == .correctedPoint)
        precondition(resolvedCorrected?.point == NormalizedPoint(x: 0.45, y: 0.55))

        // 4. Occluded point
        let occluded = GolfAnnotationDecision(
            landmark: .shaftEnd,
            kind: .occluded,
            fullFramePoint: nil,
            annotatorID: "reviewer-1",
            decidedAt: Date(timeIntervalSince1970: 11)
        )
        let validatedOccluded = try occluded.validated()
        let resolvedOccluded = try validatedOccluded.resolvedLandmark(prediction: predictedWithPoint)
        precondition(resolvedOccluded?.visibility == .occluded)
        precondition(resolvedOccluded?.point == nil)
        precondition(resolvedOccluded?.source == .occluded)

        // 5. Out of frame point
        let outOfFrame = GolfAnnotationDecision(
            landmark: .ball,
            kind: .outOfFrame,
            fullFramePoint: nil,
            annotatorID: "reviewer-1",
            decidedAt: Date(timeIntervalSince1970: 12)
        )
        let validatedOutOfFrame = try outOfFrame.validated()
        let resolvedOutOfFrame = try validatedOutOfFrame.resolvedLandmark(prediction: predictedWithPoint)
        precondition(resolvedOutOfFrame?.visibility == .outOfFrame)
        precondition(resolvedOutOfFrame?.point == nil)
        precondition(resolvedOutOfFrame?.source == .outOfFrame)

        // 6. Unresolved point
        let unresolved = GolfAnnotationDecision(
            landmark: .shaftStart,
            kind: .unresolved,
            fullFramePoint: nil,
            annotatorID: "reviewer-1",
            decidedAt: Date(timeIntervalSince1970: 13)
        )
        let validatedUnresolved = try unresolved.validated()
        let resolvedUnresolved = try validatedUnresolved.resolvedLandmark(prediction: predictedWithPoint)
        precondition(resolvedUnresolved == nil)

        // 7. Validation error checks
        // 7a. Visible decision missing coordinate
        do {
            _ = try GolfAnnotationDecision(
                landmark: .grip,
                kind: .correctedPoint,
                fullFramePoint: nil,
                annotatorID: "reviewer-1",
                decidedAt: Date()
            ).validated()
            preconditionFailure("visible decisions require coordinates")
        } catch GolfAnnotationContractError.visiblePointMissingCoordinate {}

        // 7b. Hidden decision carrying coordinate
        do {
            _ = try GolfAnnotationDecision(
                landmark: .ball,
                kind: .outOfFrame,
                fullFramePoint: NormalizedPoint(x: 0.5, y: 0.5),
                annotatorID: "reviewer-1",
                decidedAt: Date()
            ).validated()
            preconditionFailure("out-of-frame decisions cannot carry coordinates")
        } catch GolfAnnotationContractError.hiddenPointHasCoordinate {}

        // 7c. Coordinate out of range
        do {
            _ = try GolfAnnotationDecision(
                landmark: .grip,
                kind: .correctedPoint,
                fullFramePoint: NormalizedPoint(x: 1.5, y: 0.5),
                annotatorID: "reviewer-1",
                decidedAt: Date()
            ).validated()
            preconditionFailure("coordinates outside [0, 1] must fail validation")
        } catch GolfAnnotationContractError.coordinateOutOfRange {}

        // 7d. NaN coordinate
        do {
            _ = try GolfAnnotationDecision(
                landmark: .grip,
                kind: .correctedPoint,
                fullFramePoint: NormalizedPoint(x: Double.nan, y: 0.5),
                annotatorID: "reviewer-1",
                decidedAt: Date()
            ).validated()
            preconditionFailure("NaN coordinates must fail validation")
        } catch GolfAnnotationContractError.coordinateOutOfRange {}

        // 7e. Empty annotator ID in decision
        do {
            _ = try GolfAnnotationDecision(
                landmark: .grip,
                kind: .correctedPoint,
                fullFramePoint: NormalizedPoint(x: 0.5, y: 0.5),
                annotatorID: "   ",
                decidedAt: Date()
            ).validated()
            preconditionFailure("empty annotator ID must fail validation")
        } catch GolfAnnotationContractError.missingAnnotator {}

        // 8. GolfAnnotationRevision validation checks
        let validFrameRev = GolfFrameRevision(
            sourceFrameIndex: 100,
            decisions: [validatedAccepted, validatedOccluded]
        )
        // 8a. Revision missing parent prediction run ID
        do {
            _ = try GolfAnnotationRevision(
                schemaVersion: 1,
                revisionID: "rev-001",
                clipID: "clip-001",
                parentPredictionRunID: "   ",
                annotatorID: "reviewer-1",
                createdAt: Date(),
                frameRevisions: [validFrameRev]
            ).validated()
            preconditionFailure("revision missing parentPredictionRunID must fail validation")
        } catch GolfAnnotationContractError.missingParentPredictionRun {}

        // 8b. Revision missing annotator ID
        do {
            _ = try GolfAnnotationRevision(
                schemaVersion: 1,
                revisionID: "rev-001",
                clipID: "clip-001",
                parentPredictionRunID: "pred-run-001",
                annotatorID: "",
                createdAt: Date(),
                frameRevisions: [validFrameRev]
            ).validated()
            preconditionFailure("revision missing annotatorID must fail validation")
        } catch GolfAnnotationContractError.missingAnnotator {}

        // 9. GolfPredictionRun JSON Round-trip with new immutable fields
        let roiTransform = GolfROIAffineTransform(
            a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0,
            invA: 1.0, invB: 0.0, invC: 0.0, invD: 1.0, invTx: 0.0, invTy: 0.0
        )
        let predictionFrame = GolfPredictionFrame(
            sourceFrameIndex: 100,
            sourceTime: 3.333,
            roiTransform: roiTransform,
            points: [.clubhead: predictedWithPoint, .ball: predictedWithoutPoint],
            anomalyReason: "motion-blur"
        )
        let predictionRun = GolfPredictionRun(
            schemaVersion: 1,
            predictionRunID: "pred-run-001",
            clipID: "clip-001",
            mediaSHA256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            visionFrameworkVersion: "1.0.0",
            visionRequestVersion: "VNDetectHumanBodyPoseRequest-v1",
            roiAlgorithmVersion: "roi-v1",
            roiConfigSHA256: String(repeating: "r", count: 64),
            modelSHA256: String(repeating: "m", count: 64),
            decoderVersion: "decoder-v1",
            trackerVersion: "tracker-v1",
            createdAt: Date(timeIntervalSince1970: 1000),
            frames: [predictionFrame],
            provenanceHash: String(repeating: "p", count: 64)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedRun = try encoder.encode(predictionRun)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedRun = try decoder.decode(GolfPredictionRun.self, from: encodedRun)

        precondition(decodedRun == predictionRun)
        precondition(decodedRun.visionFrameworkVersion == "1.0.0")
        precondition(decodedRun.visionRequestVersion == "VNDetectHumanBodyPoseRequest-v1")
        precondition(decodedRun.frames[0].anomalyReason == "motion-blur")
        precondition(decodedRun.frames[0].points[.clubhead]?.preTrackingFullFramePoint == NormalizedPoint(x: 0.4, y: 0.6))
        precondition(decodedRun.frames[0].points[.clubhead]?.postTrackingFullFramePoint == NormalizedPoint(x: 0.401, y: 0.601))
        precondition(decodedRun.frames[0].points[.clubhead]?.trackingStatus == "tracked")
        precondition(decodedRun.frames[0].points[.ball]?.anomalyReason == "low-confidence")

        // 10. Valid GolfAnnotationRevision JSON Round-trip
        let validRevision = try GolfAnnotationRevision(
            schemaVersion: 1,
            revisionID: "rev-001",
            clipID: "clip-001",
            parentPredictionRunID: predictionRun.predictionRunID,
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [validFrameRev],
            notes: "Provenanced review"
        ).validated()

        let encodedRev = try encoder.encode(validRevision)
        let decodedRev = try decoder.decode(GolfAnnotationRevision.self, from: encodedRev)
        precondition(decodedRev == validRevision)
    }
}

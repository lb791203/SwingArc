import Foundation

@main
struct GolfKeypointAnnotationContractSmoke {
    static func main() throws {
        // 1. Verify fixed order of GolfLandmark
        precondition(GolfLandmark.allCases == [.grip, .shaftStart, .shaftEnd, .clubhead, .ball])

        // 2. Accepted prediction
        let predicted = GolfPredictionPoint(
            roiX: 0.25,
            roiY: 0.75,
            heatmapConfidence: 0.91,
            heatmapDispersion: 0.04,
            visibilityProbabilities: [0.9, 0.08, 0.02],
            fullFramePoint: NormalizedPoint(x: 0.4, y: 0.6)
        )
        let accepted = GolfAnnotationDecision(
            landmark: .clubhead,
            kind: .acceptedPrediction,
            fullFramePoint: NormalizedPoint(x: 0.4, y: 0.6),
            annotatorID: "reviewer-1",
            decidedAt: Date(timeIntervalSince1970: 10)
        )
        let validatedAccepted = try accepted.validated()
        let resolvedAccepted = try validatedAccepted.resolvedLandmark(prediction: predicted)
        precondition(resolvedAccepted?.visibility == .visible)
        precondition(resolvedAccepted?.source == .acceptedPrediction)
        precondition(resolvedAccepted?.point == NormalizedPoint(x: 0.4, y: 0.6))

        // 3. Corrected point
        let corrected = GolfAnnotationDecision(
            landmark: .grip,
            kind: .correctedPoint,
            fullFramePoint: NormalizedPoint(x: 0.45, y: 0.55),
            annotatorID: "reviewer-1",
            decidedAt: Date(timeIntervalSince1970: 10)
        )
        let validatedCorrected = try corrected.validated()
        let resolvedCorrected = try validatedCorrected.resolvedLandmark(prediction: predicted)
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
        let resolvedOccluded = try validatedOccluded.resolvedLandmark(prediction: predicted)
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
        let resolvedOutOfFrame = try validatedOutOfFrame.resolvedLandmark(prediction: predicted)
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
        let resolvedUnresolved = try validatedUnresolved.resolvedLandmark(prediction: predicted)
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

        // 7d. NaN or Infinity coordinate
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

        // 7e. Empty annotator ID
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

        // 8. GolfPredictionRun & GolfAnnotationRevision JSON Round-trip
        let roiTransform = GolfROIAffineTransform(
            a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0,
            invA: 1.0, invB: 0.0, invC: 0.0, invD: 1.0, invTx: 0.0, invTy: 0.0
        )
        let predictionFrame = GolfPredictionFrame(
            sourceFrameIndex: 100,
            sourceTime: 3.333,
            roiTransform: roiTransform,
            points: [.clubhead: predicted]
        )
        let predictionRun = GolfPredictionRun(
            schemaVersion: 1,
            predictionRunID: "pred-run-001",
            clipID: "clip-001",
            mediaSHA256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            visionFrameworkVersion: "1.0.0",
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
        precondition(decodedRun.modelSHA256 == String(repeating: "m", count: 64))
        precondition(decodedRun.roiAlgorithmVersion == "roi-v1")
        precondition(decodedRun.decoderVersion == "decoder-v1")
        precondition(decodedRun.trackerVersion == "tracker-v1")
        precondition(decodedRun.mediaSHA256 == String(repeating: "a", count: 64))
        precondition(decodedRun.provenanceHash == String(repeating: "p", count: 64))

        // 9. Linkage between GolfAnnotationRevision and GolfPredictionRun
        let frameRevision = GolfFrameRevision(
            sourceFrameIndex: 100,
            decisions: [validatedAccepted, validatedOccluded]
        )
        let revision = GolfAnnotationRevision(
            schemaVersion: 1,
            revisionID: "rev-001",
            clipID: "clip-001",
            parentPredictionRunID: predictionRun.predictionRunID,
            annotatorID: "reviewer-1",
            createdAt: Date(timeIntervalSince1970: 1100),
            completedAt: Date(timeIntervalSince1970: 1200),
            frameRevisions: [frameRevision],
            notes: "Initial review"
        )

        precondition(revision.parentPredictionRunID == predictionRun.predictionRunID)
        let encodedRev = try encoder.encode(revision)
        let decodedRev = try decoder.decode(GolfAnnotationRevision.self, from: encodedRev)
        precondition(decodedRev == revision)
    }
}

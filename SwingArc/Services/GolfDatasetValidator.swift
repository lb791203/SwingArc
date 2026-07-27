import Foundation

public enum GolfDatasetValidationError: Equatable, CustomStringConvertible, Comparable {
    case duplicateClipID(String)
    case golferNotInRegistry(String)
    case golferSplitConflict(golferID: String, registry: GolfDatasetSplit, clip: GolfDatasetSplit)
    case trainingNotAuthorized(String)
    case missingClip(String)
    case missingPredictionRun(String)
    case mediaHashMismatch(String)
    case timelineHashMismatch(String)
    case revisionNotCompleted(String)
    case frameOutOfRange(clipID: String, sourceFrameIndex: Int)
    case incompleteFrameDecisions(clipID: String, sourceFrameIndex: Int)
    case duplicateLandmarkDecision(clipID: String, sourceFrameIndex: Int, landmark: GolfLandmark)
    case decisionValidationError(clipID: String, sourceFrameIndex: Int, landmark: GolfLandmark)
    case missingPredictionPoint(clipID: String, sourceFrameIndex: Int, landmark: GolfLandmark)
    case predictionFrameOutOfRange(clipID: String, sourceFrameIndex: Int)
    case duplicatePredictionRunID(String)
    case acceptedPredictionCoordinateMismatch(clipID: String, sourceFrameIndex: Int, landmark: GolfLandmark)
    case duplicatePredictionFrame(clipID: String, sourceFrameIndex: Int)
    case predictionClipMismatch(clipID: String, predictionRunID: String)
    case duplicateRevisionFrame(clipID: String, sourceFrameIndex: Int)
    case revisionValidationError(String)
    case invalidModelSHA256(predictionRunID: String)
    case manualBootstrapContainsPredictionPoints(predictionRunID: String)
    case manualBootstrapHasModelSHA(predictionRunID: String)
    case emptyPredictionRunFrames(predictionRunID: String)
    case invalidPredictionFrameTime(predictionRunID: String, sourceFrameIndex: Int)
    case invalidPredictionROITransform(predictionRunID: String, sourceFrameIndex: Int)
    case provenanceHashMismatch(predictionRunID: String)
    case anchorMismatch(clipID: String, anchorID: String)

    public var description: String {
        switch self {
        case .duplicateClipID(let id):
            return "Duplicate clip ID: \(id)"
        case .golferNotInRegistry(let id):
            return "Golfer '\(id)' not in registry"
        case .golferSplitConflict(let golferID, let registry, let requested):
            return "Golfer '\(golferID)' split conflict: registry=\(registry.rawValue) requested=\(requested.rawValue)"
        case .trainingNotAuthorized(let id):
            return "Clip '\(id)' requires training-allowed authorization"
        case .missingClip(let id):
            return "Missing clip: \(id)"
        case .missingPredictionRun(let id):
            return "Missing prediction run: \(id)"
        case .mediaHashMismatch(let id):
            return "Media hash mismatch for clip: \(id)"
        case .timelineHashMismatch(let id):
            return "Timeline hash mismatch for clip: \(id)"
        case .revisionNotCompleted(let id):
            return "Revision not completed: \(id)"
        case .frameOutOfRange(let clipID, let index):
            return "Frame \(index) out of range in clip \(clipID)"
        case .incompleteFrameDecisions(let clipID, let index):
            return "Incomplete decisions for frame \(index) in clip \(clipID)"
        case .duplicateLandmarkDecision(let clipID, let index, let landmark):
            return "Duplicate \(landmark.rawValue) decision at frame \(index) in clip \(clipID)"
        case .decisionValidationError(let clipID, let index, let landmark):
            return "Invalid decision for \(landmark.rawValue) at frame \(index) in clip \(clipID)"
        case .missingPredictionPoint(let clipID, let index, let landmark):
            return "Missing prediction point for \(landmark.rawValue) at frame \(index) in clip \(clipID)"
        case .predictionFrameOutOfRange(let clipID, let index):
            return "Prediction frame \(index) out of range in clip \(clipID)"
        case .duplicatePredictionRunID(let id):
            return "Duplicate prediction run ID: \(id)"
        case .acceptedPredictionCoordinateMismatch(let clipID, let index, let landmark):
            return "Accepted prediction coordinate mismatch for \(landmark.rawValue) at frame \(index) in clip \(clipID)"
        case .duplicatePredictionFrame(let clipID, let index):
            return "Duplicate prediction frame \(index) in clip \(clipID)"
        case .predictionClipMismatch(let clipID, let predictionRunID):
            return "Prediction run \(predictionRunID) does not belong to clip \(clipID)"
        case .duplicateRevisionFrame(let clipID, let index):
            return "Duplicate revision frame \(index) in clip \(clipID)"
        case .revisionValidationError(let revisionID):
            return "Invalid revision metadata: \(revisionID)"
        case .invalidModelSHA256(let id):
            return "Invalid modelSHA256 for prediction run: \(id)"
        case .manualBootstrapContainsPredictionPoints(let id):
            return "Manual bootstrap run contains prediction points: \(id)"
        case .manualBootstrapHasModelSHA(let id):
            return "Manual bootstrap run contains modelSHA256: \(id)"
        case .emptyPredictionRunFrames(let id):
            return "Prediction run frames empty: \(id)"
        case .invalidPredictionFrameTime(let id, let index):
            return "Invalid frame time for prediction run \(id) frame \(index)"
        case .invalidPredictionROITransform(let id, let index):
            return "Invalid ROI transform for prediction run \(id) frame \(index)"
        case .provenanceHashMismatch(let id):
            return "Provenance hash mismatch for prediction run: \(id)"
        case .anchorMismatch(let clipID, let anchorID):
            return "Anchor \(anchorID) mismatch for clip: \(clipID)"
        }
    }

    public static func < (
        lhs: GolfDatasetValidationError,
        rhs: GolfDatasetValidationError
    ) -> Bool {
        let left = lhs.sortComponents
        let right = rhs.sortComponents
        if left.scope != right.scope { return left.scope < right.scope }
        if left.frameIndex != right.frameIndex { return left.frameIndex < right.frameIndex }
        if left.enumOrder != right.enumOrder { return left.enumOrder < right.enumOrder }
        return left.detail < right.detail
    }

    fileprivate var sortComponents: (
        scope: String,
        frameIndex: Int,
        enumOrder: Int,
        detail: String
    ) {
        let noFrame = Int.min
        switch self {
        case .duplicateClipID(let id):
            return (id, noFrame, 0, description)
        case .golferNotInRegistry(let id):
            return (id, noFrame, 1, description)
        case .golferSplitConflict(let golferID, _, _):
            return (golferID, noFrame, 2, description)
        case .trainingNotAuthorized(let id):
            return (id, noFrame, 3, description)
        case .missingClip(let id):
            return (id, noFrame, 4, description)
        case .missingPredictionRun(let id):
            return (id, noFrame, 5, description)
        case .duplicatePredictionRunID(let id):
            return (id, noFrame, 6, description)
        case .mediaHashMismatch(let id):
            return (id, noFrame, 7, description)
        case .timelineHashMismatch(let id):
            return (id, noFrame, 8, description)
        case .revisionNotCompleted(let id):
            return (id, noFrame, 9, description)
        case .revisionValidationError(let id):
            return (id, noFrame, 10, description)
        case .predictionClipMismatch(let clipID, _):
            return (clipID, noFrame, 11, description)
        case .predictionFrameOutOfRange(let clipID, let index):
            return (clipID, index, 12, description)
        case .frameOutOfRange(let clipID, let index):
            return (clipID, index, 13, description)
        case .duplicatePredictionFrame(let clipID, let index):
            return (clipID, index, 14, description)
        case .duplicateRevisionFrame(let clipID, let index):
            return (clipID, index, 15, description)
        case .incompleteFrameDecisions(let clipID, let index):
            return (clipID, index, 16, description)
        case .duplicateLandmarkDecision(let clipID, let index, _):
            return (clipID, index, 17, description)
        case .decisionValidationError(let clipID, let index, _):
            return (clipID, index, 18, description)
        case .missingPredictionPoint(let clipID, let index, _):
            return (clipID, index, 19, description)
        case .acceptedPredictionCoordinateMismatch(let clipID, let index, _):
            return (clipID, index, 20, description)
        case .invalidModelSHA256(let id):
            return (id, noFrame, 21, description)
        case .manualBootstrapContainsPredictionPoints(let id):
            return (id, noFrame, 22, description)
        case .manualBootstrapHasModelSHA(let id):
            return (id, noFrame, 23, description)
        case .emptyPredictionRunFrames(let id):
            return (id, noFrame, 24, description)
        case .invalidPredictionFrameTime(let id, let index):
            return (id, index, 25, description)
        case .invalidPredictionROITransform(let id, let index):
            return (id, index, 26, description)
        case .provenanceHashMismatch(let id):
            return (id, noFrame, 27, description)
        case .anchorMismatch(let clipID, _):
            return (clipID, noFrame, 28, description)
        }
    }
}

public enum GolfDatasetValidator {
    public static func validate(
        snapshot: GolfDatasetSnapshot
    ) -> [GolfDatasetValidationError] {
        var errors: [GolfDatasetValidationError] = []

        let clipGroups = Dictionary(grouping: snapshot.clips, by: \GolfClipIdentity.clipID)
        for clipID in clipGroups.keys.sorted() where (clipGroups[clipID]?.count ?? 0) > 1 {
            errors.append(.duplicateClipID(clipID))
        }

        let registryRecords = snapshot.registry?.golfers ?? []
        let registryGroups = Dictionary(grouping: registryRecords, by: \GolferRecord.golferID)
        if snapshot.registry == nil {
            for golferID in Set(snapshot.clips.map(\GolfClipIdentity.golferID)).sorted() {
                errors.append(.golferNotInRegistry(golferID))
            }
        } else {
            for golferID in registryGroups.keys.sorted() {
                let records = registryGroups[golferID] ?? []
                let splits = GolfDatasetSplit.allCases.filter { split in
                    records.contains(where: { $0.split == split })
                }
                if let locked = splits.first {
                    for conflicting in splits.dropFirst() {
                        errors.append(.golferSplitConflict(
                            golferID: golferID,
                            registry: locked,
                            clip: conflicting
                        ))
                    }
                }
            }
            for clip in snapshot.clips where registryGroups[clip.golferID] == nil {
                errors.append(.golferNotInRegistry(clip.golferID))
            }
        }

        for clip in snapshot.clips where clip.authorization != .trainingAllowed {
            errors.append(.trainingNotAuthorized(clip.clipID))
        }

        var clipsByID: [String: GolfClipIdentity] = [:]
        for clip in snapshot.clips where clipsByID[clip.clipID] == nil {
            clipsByID[clip.clipID] = clip
        }

        let predictionGroups = Dictionary(
            grouping: snapshot.predictions,
            by: \GolfPredictionRun.predictionRunID
        )
        for predictionRunID in predictionGroups.keys.sorted()
        where (predictionGroups[predictionRunID]?.count ?? 0) > 1 {
            errors.append(.duplicatePredictionRunID(predictionRunID))
        }

        var predictionsByID: [String: GolfPredictionRun] = [:]
        for prediction in snapshot.predictions
        where predictionsByID[prediction.predictionRunID] == nil {
            predictionsByID[prediction.predictionRunID] = prediction
        }

        for prediction in snapshot.predictions {
            guard let clip = clipsByID[prediction.clipID] else {
                errors.append(.missingClip(prediction.clipID))
                continue
            }
            if prediction.mediaSHA256 != clip.media.sha256 {
                errors.append(.mediaHashMismatch(prediction.clipID))
            }
            if prediction.timelineSHA256 != clip.media.timelineSHA256 {
                errors.append(.timelineHashMismatch(prediction.clipID))
            }

            switch prediction.runKind {
            case .modelInference:
                if let modelSHA = prediction.modelSHA256 {
                    let is64Hex = modelSHA.count == 64 && modelSHA.allSatisfy({ $0.isHexDigit })
                    if !is64Hex {
                        errors.append(.invalidModelSHA256(predictionRunID: prediction.predictionRunID))
                    }
                } else {
                    errors.append(.invalidModelSHA256(predictionRunID: prediction.predictionRunID))
                }
            case .manualBootstrap:
                if prediction.modelSHA256 != nil {
                    errors.append(.manualBootstrapHasModelSHA(predictionRunID: prediction.predictionRunID))
                }
                if prediction.frames.count != clip.media.frameCount {
                    errors.append(.emptyPredictionRunFrames(predictionRunID: prediction.predictionRunID))
                }
                for frame in prediction.frames {
                    if !frame.points.isEmpty {
                        errors.append(.manualBootstrapContainsPredictionPoints(predictionRunID: prediction.predictionRunID))
                        break
                    }
                }
            }

            let provHash = prediction.provenanceHash
            let isLowercaseSHA256 = provHash.count == 64 &&
                provHash.unicodeScalars.allSatisfy {
                    (48...57).contains($0.value) ||
                        (97...102).contains($0.value)
                }
            var provenanceMatches = isLowercaseSHA256
            if prediction.runKind == .manualBootstrap {
                let canonical = GolfManualBootstrapProvenance.canonicalString(
                    clipID: prediction.clipID,
                    mediaSHA256: prediction.mediaSHA256,
                    timelineSHA256: prediction.timelineSHA256,
                    anchors: prediction.manualBootstrapAnchors,
                    visionFrameworkVersion: prediction.visionFrameworkVersion,
                    visionRequestVersion: prediction.visionRequestVersion,
                    roiAlgorithmVersion: prediction.roiAlgorithmVersion,
                    roiConfigSHA256: prediction.roiConfigSHA256,
                    decoderVersion: prediction.decoderVersion,
                    trackerVersion: prediction.trackerVersion,
                    frames: prediction.frames
                )
                provenanceMatches = provenanceMatches &&
                    StableSwingROIBuilder.sha256Hex(canonical) == provHash &&
                    prediction.predictionRunID == provHash
            }
            if !provenanceMatches {
                errors.append(.provenanceHashMismatch(predictionRunID: prediction.predictionRunID))
            }

            var prevTime: Double?
            let frameGroups = Dictionary(
                grouping: prediction.frames,
                by: \GolfPredictionFrame.sourceFrameIndex
            )
            for frameIndex in frameGroups.keys.sorted() {
                if (frameGroups[frameIndex]?.count ?? 0) > 1 {
                    errors.append(.duplicatePredictionFrame(
                        clipID: prediction.clipID,
                        sourceFrameIndex: frameIndex
                    ))
                }
                if frameIndex < 0 || frameIndex >= clip.media.frameCount {
                    errors.append(.predictionFrameOutOfRange(
                        clipID: prediction.clipID,
                        sourceFrameIndex: frameIndex
                    ))
                }
            }

            for frame in prediction.frames.sorted(by: { $0.sourceFrameIndex < $1.sourceFrameIndex }) {
                if !frame.sourceTime.isFinite || (prevTime != nil && frame.sourceTime <= prevTime!) {
                    errors.append(.invalidPredictionFrameTime(predictionRunID: prediction.predictionRunID, sourceFrameIndex: frame.sourceFrameIndex))
                }
                prevTime = frame.sourceTime

                let t = frame.roiTransform
                let det = t.a * t.d - t.b * t.c
                let valuesFinite = t.a.isFinite && t.b.isFinite && t.c.isFinite && t.d.isFinite && t.tx.isFinite && t.ty.isFinite &&
                    t.invA.isFinite && t.invB.isFinite && t.invC.isFinite && t.invD.isFinite && t.invTx.isFinite && t.invTy.isFinite
                let invertible = abs(det) > 1e-12
                let identityCheck: Bool
                if valuesFinite && invertible {
                    let probes = [
                        GolfNormalizedPoint(x: 0, y: 0),
                        GolfNormalizedPoint(x: 1, y: 0),
                        GolfNormalizedPoint(x: 0, y: 1),
                        GolfNormalizedPoint(x: 1, y: 1)
                    ]
                    identityCheck = probes.allSatisfy { point in
                        let forwardRoundTrip = t.roiPointToFullFrame(
                            t.fullFramePointToROI(point)
                        )
                        let inverseRoundTrip = t.fullFramePointToROI(
                            t.roiPointToFullFrame(point)
                        )
                        return abs(forwardRoundTrip.x - point.x) < 1e-4 &&
                            abs(forwardRoundTrip.y - point.y) < 1e-4 &&
                            abs(inverseRoundTrip.x - point.x) < 1e-4 &&
                            abs(inverseRoundTrip.y - point.y) < 1e-4
                    }
                } else {
                    identityCheck = false
                }

                if !valuesFinite || !invertible || !identityCheck {
                    errors.append(.invalidPredictionROITransform(predictionRunID: prediction.predictionRunID, sourceFrameIndex: frame.sourceFrameIndex))
                }
            }
        }

        for revision in snapshot.revisions {
            if revision.completedAt == nil {
                errors.append(.revisionNotCompleted(revision.revisionID))
            }
            if revision.annotatorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.revisionValidationError(revision.revisionID))
            }

            let clip = clipsByID[revision.clipID]
            if clip == nil {
                errors.append(.missingClip(revision.clipID))
            }

            let parentPrediction = predictionsByID[revision.parentPredictionRunID]
            if parentPrediction == nil {
                errors.append(.missingPredictionRun(revision.parentPredictionRunID))
            } else if parentPrediction?.clipID != revision.clipID {
                errors.append(.predictionClipMismatch(
                    clipID: revision.clipID,
                    predictionRunID: revision.parentPredictionRunID
                ))
            }

            let revisionFrameGroups = Dictionary(
                grouping: revision.frameRevisions,
                by: \GolfFrameRevision.sourceFrameIndex
            )
            for frameIndex in revisionFrameGroups.keys.sorted()
            where (revisionFrameGroups[frameIndex]?.count ?? 0) > 1 {
                errors.append(.duplicateRevisionFrame(
                    clipID: revision.clipID,
                    sourceFrameIndex: frameIndex
                ))
            }

            for frameRevision in revision.frameRevisions {
                let frameIndex = frameRevision.sourceFrameIndex
                if let clip, frameIndex < 0 || frameIndex >= clip.media.frameCount {
                    errors.append(.frameOutOfRange(
                        clipID: revision.clipID,
                        sourceFrameIndex: frameIndex
                    ))
                }

                let decisionGroups = Dictionary(
                    grouping: frameRevision.decisions,
                    by: \GolfAnnotationDecision.landmark
                )
                if GolfLandmark.allCases.contains(where: {
                    (decisionGroups[$0]?.count ?? 0) == 0
                }) {
                    errors.append(.incompleteFrameDecisions(
                        clipID: revision.clipID,
                        sourceFrameIndex: frameIndex
                    ))
                }
                for landmark in GolfLandmark.allCases
                where (decisionGroups[landmark]?.count ?? 0) > 1 {
                    errors.append(.duplicateLandmarkDecision(
                        clipID: revision.clipID,
                        sourceFrameIndex: frameIndex,
                        landmark: landmark
                    ))
                }

                for decision in frameRevision.decisions {
                    do {
                        _ = try decision.validated()
                    } catch {
                        errors.append(.decisionValidationError(
                            clipID: revision.clipID,
                            sourceFrameIndex: frameIndex,
                            landmark: decision.landmark
                        ))
                    }

                    guard decision.kind == .acceptedPrediction,
                          let parentPrediction,
                          parentPrediction.clipID == revision.clipID else {
                        continue
                    }
                    let matchingFrames = parentPrediction.frames.filter {
                        $0.sourceFrameIndex == frameIndex
                    }
                    guard matchingFrames.count == 1,
                          let predictionPoint = matchingFrames[0].points[decision.landmark],
                          predictionPoint.resolvedFullFramePoint != nil else {
                        errors.append(.missingPredictionPoint(
                            clipID: revision.clipID,
                            sourceFrameIndex: frameIndex,
                            landmark: decision.landmark
                        ))
                        continue
                    }
                    do {
                        _ = try decision.resolvedLandmark(prediction: predictionPoint)
                    } catch GolfAnnotationContractError.acceptedPredictionCoordinateMismatch {
                        errors.append(.acceptedPredictionCoordinateMismatch(
                            clipID: revision.clipID,
                            sourceFrameIndex: frameIndex,
                            landmark: decision.landmark
                        ))
                    } catch {
                        errors.append(.decisionValidationError(
                            clipID: revision.clipID,
                            sourceFrameIndex: frameIndex,
                            landmark: decision.landmark
                        ))
                    }
                }
            }
        }

        return errors.sorted { lhs, rhs in
            let leftContext = sortContext(for: lhs, snapshot: snapshot)
            let rightContext = sortContext(for: rhs, snapshot: snapshot)
            if leftContext.clipID != rightContext.clipID {
                return leftContext.clipID < rightContext.clipID
            }
            if leftContext.frameIndex != rightContext.frameIndex {
                return leftContext.frameIndex < rightContext.frameIndex
            }
            if lhs.sortComponents.enumOrder != rhs.sortComponents.enumOrder {
                return lhs.sortComponents.enumOrder < rhs.sortComponents.enumOrder
            }
            return lhs.sortComponents.detail < rhs.sortComponents.detail
        }
    }

    private static func sortContext(
        for error: GolfDatasetValidationError,
        snapshot: GolfDatasetSnapshot
    ) -> (clipID: String, frameIndex: Int) {
        let noFrame = Int.min
        switch error {
        case .duplicateClipID(let clipID),
             .trainingNotAuthorized(let clipID),
             .missingClip(let clipID),
             .mediaHashMismatch(let clipID),
             .timelineHashMismatch(let clipID):
            return (clipID, noFrame)
        case .golferNotInRegistry(let golferID),
             .golferSplitConflict(let golferID, _, _):
            let clipID = snapshot.clips
                .filter { $0.golferID == golferID }
                .map(\GolfClipIdentity.clipID)
                .min() ?? golferID
            return (clipID, noFrame)
        case .missingPredictionRun(let predictionRunID),
             .duplicatePredictionRunID(let predictionRunID),
             .invalidModelSHA256(let predictionRunID),
             .manualBootstrapContainsPredictionPoints(let predictionRunID),
             .manualBootstrapHasModelSHA(let predictionRunID),
             .emptyPredictionRunFrames(let predictionRunID),
             .provenanceHashMismatch(let predictionRunID):
            let revisionClip = snapshot.revisions
                .filter { $0.parentPredictionRunID == predictionRunID }
                .map(\GolfAnnotationRevision.clipID)
                .min()
            let predictionClip = snapshot.predictions
                .filter { $0.predictionRunID == predictionRunID }
                .map(\GolfPredictionRun.clipID)
                .min()
            return (revisionClip ?? predictionClip ?? predictionRunID, noFrame)
        case .invalidPredictionFrameTime(let predictionRunID, let index),
             .invalidPredictionROITransform(let predictionRunID, let index):
            let clipID = snapshot.predictions
                .first(where: { $0.predictionRunID == predictionRunID })?.clipID
                ?? predictionRunID
            return (clipID, index)
        case .anchorMismatch(let clipID, _):
            return (clipID, noFrame)
        case .revisionNotCompleted(let revisionID),
             .revisionValidationError(let revisionID):
            let clipID = snapshot.revisions
                .first(where: { $0.revisionID == revisionID })?.clipID
                ?? revisionID
            return (clipID, noFrame)
        case .predictionClipMismatch(let clipID, _):
            return (clipID, noFrame)
        case .frameOutOfRange(let clipID, let index),
             .incompleteFrameDecisions(let clipID, let index),
             .predictionFrameOutOfRange(let clipID, let index),
             .duplicatePredictionFrame(let clipID, let index),
             .duplicateRevisionFrame(let clipID, let index):
            return (clipID, index)
        case .duplicateLandmarkDecision(let clipID, let index, _),
             .decisionValidationError(let clipID, let index, _),
             .missingPredictionPoint(let clipID, let index, _),
             .acceptedPredictionCoordinateMismatch(let clipID, let index, _):
            return (clipID, index)
        }
    }
}

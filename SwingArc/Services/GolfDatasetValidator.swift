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

    public var description: String {
        switch self {
        case .duplicateClipID(let id): return "Duplicate clip ID: \(id)"
        case .golferNotInRegistry(let id): return "Golfer '\(id)' not in registry"
        case .golferSplitConflict(let golferID, let reg, let clip):
            return "Golfer '\(golferID)' split conflict: registry=\(reg.rawValue) clip=\(clip.rawValue)"
        case .trainingNotAuthorized(let id): return "Clip '\(id)' requires training-allowed authorization"
        case .missingClip(let id): return "Missing clip: \(id)"
        case .missingPredictionRun(let id): return "Missing prediction run: \(id)"
        case .mediaHashMismatch(let id): return "Media hash mismatch for clip: \(id)"
        case .timelineHashMismatch(let id): return "Timeline hash mismatch for clip: \(id)"
        case .revisionNotCompleted(let id): return "Revision not completed: \(id)"
        case .frameOutOfRange(let clipID, let idx):
            return "Frame \(idx) out of range in clip \(clipID)"
        case .incompleteFrameDecisions(let clipID, let idx):
            return "Incomplete decisions for frame \(idx) in clip \(clipID)"
        case .duplicateLandmarkDecision(let clipID, let idx, let lm):
            return "Duplicate \(lm.rawValue) decision at frame \(idx) in clip \(clipID)"
        case .decisionValidationError(let clipID, let idx, let lm):
            return "Invalid decision for \(lm.rawValue) at frame \(idx) in clip \(clipID)"
        case .missingPredictionPoint(let clipID, let idx, let lm):
            return "Missing prediction point for \(lm.rawValue) at frame \(idx) in clip \(clipID)"
        }
    }

    public static func < (lhs: GolfDatasetValidationError, rhs: GolfDatasetValidationError) -> Bool {
        let lhsKey = sortKey(lhs)
        let rhsKey = sortKey(rhs)
        return lhsKey < rhsKey
    }

    private static func sortKey(_ e: GolfDatasetValidationError) -> (String, Int, Int) {
        switch e {
        case .duplicateClipID(let id): return (id, -2, 0)
        case .golferNotInRegistry(let id): return (id, -1, 0)
        case .golferSplitConflict(_, _, _): return ("", 0, 0)
        case .trainingNotAuthorized(let id): return (id, 1, 0)
        case .missingClip(let id): return (id, 2, 0)
        case .missingPredictionRun(let id): return (id, 3, 0)
        case .mediaHashMismatch(let id): return (id, 4, 0)
        case .timelineHashMismatch(let id): return (id, 5, 0)
        case .revisionNotCompleted(let id): return (id, 6, 0)
        case .frameOutOfRange(let clipID, let idx): return (clipID, 10, idx)
        case .incompleteFrameDecisions(let clipID, let idx): return (clipID, 11, idx)
        case .duplicateLandmarkDecision(let clipID, let idx, _): return (clipID, 12, idx)
        case .decisionValidationError(let clipID, let idx, _): return (clipID, 13, idx)
        case .missingPredictionPoint(let clipID, let idx, _): return (clipID, 14, idx)
        }
    }
}

public enum GolfDatasetValidator {
    public static func validate(snapshot: GolfDatasetSnapshot) -> [GolfDatasetValidationError] {
        var errors: [GolfDatasetValidationError] = []

        // 1. Duplicate clip IDs
        var seenClips: [String: Int] = [:]
        for clip in snapshot.clips {
            seenClips[clip.clipID, default: 0] += 1
        }
        for (clipID, count) in seenClips where count > 1 {
            errors.append(.duplicateClipID(clipID))
        }

        // 2. Golfer in registry
        for clip in snapshot.clips {
            if let registry = snapshot.registry {
                if !registry.golfers.contains(where: { $0.golferID == clip.golferID }) {
                    errors.append(.golferNotInRegistry(clip.golferID))
                }
            }
        }

        // 3. Golfer split conflicts: all clips for a golfer must agree with registry split
        if let registry = snapshot.registry {
            for clip in snapshot.clips {
                if let regSplit = registry.split(for: clip.golferID) {
                    // Infer clip split from authorization
                    let clipSplit: GolfDatasetSplit = clip.authorization == .trainingAllowed ? .training : .validation
                    if regSplit != clipSplit {
                        errors.append(.golferSplitConflict(
                            golferID: clip.golferID,
                            registry: regSplit,
                            clip: clipSplit
                        ))
                    }
                }
            }
        }

        // 4. Cross-clip consistency: all clips for same golfer must have same inferred split
        var golferClipSplits: [String: (split: GolfDatasetSplit, clipID: String)] = [:]
        for clip in snapshot.clips {
            let clipSplit: GolfDatasetSplit = clip.authorization == .trainingAllowed ? .training : .validation
            if let existing = golferClipSplits[clip.golferID] {
                if existing.split != clipSplit {
                    errors.append(.golferSplitConflict(
                        golferID: clip.golferID,
                        registry: existing.split,
                        clip: clipSplit
                    ))
                }
            } else {
                golferClipSplits[clip.golferID] = (clipSplit, clip.clipID)
            }
        }

        // 5. Authorization check
        for clip in snapshot.clips {
            if clip.authorization != .trainingAllowed {
                errors.append(.trainingNotAuthorized(clip.clipID))
            }
        }

        // Build lookups
        var clipDict: [String: GolfClipIdentity] = [:]
        for clip in snapshot.clips {
            clipDict[clip.clipID] = clip
        }
        let predDict = Dictionary(uniqueKeysWithValues: snapshot.predictions.map { ($0.predictionRunID, $0) })

        // 6-8. Prediction checks
        for pred in snapshot.predictions {
            guard let clip = clipDict[pred.clipID] else {
                errors.append(.missingClip(pred.clipID))
                continue
            }
            if pred.mediaSHA256 != clip.media.sha256 {
                errors.append(.mediaHashMismatch(pred.clipID))
            }
            if pred.timelineSHA256 != clip.media.timelineSHA256 {
                errors.append(.timelineHashMismatch(pred.clipID))
            }
        }

        // 9-15. Revision checks
        for rev in snapshot.revisions {
            guard let clip = clipDict[rev.clipID] else {
                errors.append(.missingClip(rev.clipID))
                continue
            }

            guard rev.completedAt != nil else {
                errors.append(.revisionNotCompleted(rev.revisionID))
                continue
            }

            guard predDict[rev.parentPredictionRunID] != nil else {
                errors.append(.missingPredictionRun(rev.parentPredictionRunID))
                continue
            }

            if let pred = predDict[rev.parentPredictionRunID], pred.clipID != rev.clipID {
                errors.append(.missingClip(rev.clipID))
            }

            for frameRev in rev.frameRevisions {
                let idx = frameRev.sourceFrameIndex

                guard idx >= 0 && idx < clip.media.frameCount else {
                    errors.append(.frameOutOfRange(clipID: rev.clipID, sourceFrameIndex: idx))
                    continue
                }

                var seenLandmarks: [GolfLandmark: Int] = [:]
                for decision in frameRev.decisions {
                    seenLandmarks[decision.landmark, default: 0] += 1
                }
                for lm in GolfLandmark.allCases {
                    let count = seenLandmarks[lm] ?? 0
                    if count == 0 {
                        errors.append(.incompleteFrameDecisions(clipID: rev.clipID, sourceFrameIndex: idx))
                    } else if count > 1 {
                        errors.append(.duplicateLandmarkDecision(clipID: rev.clipID, sourceFrameIndex: idx, landmark: lm))
                    }
                }

                for decision in frameRev.decisions {
                    if let err = validateDecision(decision, clipID: rev.clipID, frameIndex: idx) {
                        errors.append(err)
                    }
                }

                if let pred = predDict[rev.parentPredictionRunID] {
                    let predFrame = pred.frames.first { $0.sourceFrameIndex == idx }
                    for decision in frameRev.decisions where decision.kind == .acceptedPrediction {
                        if predFrame == nil || predFrame!.points[decision.landmark] == nil {
                            errors.append(.missingPredictionPoint(clipID: rev.clipID, sourceFrameIndex: idx, landmark: decision.landmark))
                        }
                    }
                }
            }
        }

        return errors.sorted()
    }

    private static func validateDecision(
        _ decision: GolfAnnotationDecision,
        clipID: String,
        frameIndex: Int
    ) -> GolfDatasetValidationError? {
        switch decision.kind {
        case .acceptedPrediction, .correctedPoint:
            guard let point = decision.fullFramePoint,
                  point.x.isFinite, point.y.isFinite,
                  (0...1).contains(point.x), (0...1).contains(point.y) else {
                return .decisionValidationError(clipID: clipID, sourceFrameIndex: frameIndex, landmark: decision.landmark)
            }
            guard !decision.annotatorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .decisionValidationError(clipID: clipID, sourceFrameIndex: frameIndex, landmark: decision.landmark)
            }
        case .occluded, .outOfFrame, .unresolved:
            if decision.fullFramePoint != nil {
                return .decisionValidationError(clipID: clipID, sourceFrameIndex: frameIndex, landmark: decision.landmark)
            }
            guard !decision.annotatorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .decisionValidationError(clipID: clipID, sourceFrameIndex: frameIndex, landmark: decision.landmark)
            }
        }
        return nil
    }
}

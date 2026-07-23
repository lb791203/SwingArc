import Foundation

enum PrecisionManifestValidator {
    static func errors(in clips: [PrecisionClipManifest]) -> [PrecisionManifestError] {
        var errors: [PrecisionManifestError] = []

        let duplicateIDs = Dictionary(grouping: clips, by: \.clipID)
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
        errors.append(contentsOf: duplicateIDs.map(PrecisionManifestError.duplicateClipID))

        let clipsByGolfer = clips.reduce(into: [String: [PrecisionClipManifest]]()) {
            result, clip in
            guard let golferID = clip.golferID else { return }
            result[golferID, default: []].append(clip)
        }
        let leakingGolfers = clipsByGolfer
            .filter { Set($0.value.map(\.split)).count > 1 }
            .map(\.key)
            .sorted()
        errors.append(contentsOf: leakingGolfers.map(PrecisionManifestError.golferSplitLeak))

        for clip in clips.sorted(by: { $0.clipID < $1.clipID }) {
            if clip.annotationPasses < 2 {
                errors.append(.missingDoublePass(clip.clipID))
            }
            if clip.split == .training || clip.split == .validation,
               clip.authorization != .trainingAllowed {
                errors.append(.trainingNotAuthorized(clip.clipID))
            }
            if clip.split != .development {
                if clip.golferID == nil {
                    errors.append(.missingRequiredMetadata(
                        clipID: clip.clipID,
                        field: "golferID"
                    ))
                }
                if clip.view == nil {
                    errors.append(.missingRequiredMetadata(
                        clipID: clip.clipID,
                        field: "view"
                    ))
                }
                if clip.handedness == nil {
                    errors.append(.missingRequiredMetadata(
                        clipID: clip.clipID,
                        field: "handedness"
                    ))
                }
            }

            var resolvedStages: [(code: String, frame: Int)] = []
            var hasInvalidStageLabel = false
            for stage in clip.stages {
                let frames = stage.annotatorFrames.values.sorted()
                guard frames.count >= 2 else {
                    errors.append(.stageMissingDoublePass(
                        clipID: clip.clipID,
                        stage: stage.stage
                    ))
                    hasInvalidStageLabel = true
                    continue
                }
                if let adjudicated = stage.adjudicatedSourceFrameIndex {
                    resolvedStages.append((stage.stage, adjudicated))
                } else if let first = frames.first,
                          let last = frames.last,
                          last - first <= 2 {
                    resolvedStages.append((stage.stage, (first + last) / 2))
                } else {
                    errors.append(.stageNeedsAdjudication(
                        clipID: clip.clipID,
                        stage: stage.stage
                    ))
                    hasInvalidStageLabel = true
                }
            }

            if !hasInvalidStageLabel,
               !resolvedStages.isEmpty,
               !hasCanonicalOrder(resolvedStages) {
                errors.append(.invalidStageOrder(clip.clipID))
            }

            if clip.split == .training || clip.split == .validation {
                for frame in clip.frameLabels where !isReviewed(frame) {
                    errors.append(.unreviewedTrainingLabel(
                        clipID: clip.clipID,
                        sourceFrameIndex: frame.sourceFrameIndex
                    ))
                }
            }
        }
        return errors
    }

    private static func hasCanonicalOrder(_ stages: [(code: String, frame: Int)]) -> Bool {
        let canonicalRanks = Dictionary(uniqueKeysWithValues: (1...8).map { ("P\($0)", $0) })
        let ranks = stages.compactMap { canonicalRanks[$0.code] }
        let frames = stages.map(\.frame)
        guard ranks.count == stages.count else { return false }
        return zip(ranks, ranks.dropFirst()).allSatisfy(<)
            && zip(frames, frames.dropFirst()).allSatisfy(<)
    }

    private static func isReviewed(_ frame: PrecisionFrameLabel) -> Bool {
        frame.reviewed && !frame.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

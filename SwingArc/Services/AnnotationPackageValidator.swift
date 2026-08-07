import Foundation

enum AnnotationValidationError: Equatable {
    case unsupportedSchema(Int)
    case invalidStageSystem(String)
    case invalidMediaIdentity
    case invalidSubmittedPassCount
    case duplicateAnnotator(String)
    case invalidStageSet(annotatorID: String)
    case invalidStageOrder(annotatorID: String)
    case trainingWithoutAuthorization
    case missingReviewedFrames(annotatorID: String)
    case unreviewedTrainingFrame(sourceFrameIndex: Int)
    case unresolvedTrainingStage(stage: String)
    case activeDraftPresent
    case invalidFrameQueue
    case missingAdjudication(stage: String)
    case incompleteAdjudication(stage: String)
}

enum AnnotationPackageValidator {
    static let stageCodes = (1...8).map { "P\($0)" }

    static func validate(
        _ package: AnnotationPackage
    ) -> [AnnotationValidationError] {
        var errors: [AnnotationValidationError] = []
        if package.schemaVersion != 1 {
            errors.append(.unsupportedSchema(package.schemaVersion))
        }
        if package.stageSystem != "p-system-v1" {
            errors.append(.invalidStageSystem(package.stageSystem))
        }
        if package.media.sha256.count != 64
            || package.media.timelineSHA256.count != 64
            || package.media.frameCount <= 0
            || package.media.width <= 0
            || package.media.height <= 0 {
            errors.append(.invalidMediaIdentity)
        }

        let groups = Dictionary(grouping: package.passes, by: \.annotatorID)
        if package.passes.count != 2
            || package.passes.contains(where: { $0.submittedAt == nil }) {
            errors.append(.invalidSubmittedPassCount)
        }
        for (annotator, passes) in groups where passes.count > 1 {
            errors.append(.duplicateAnnotator(annotator))
        }
        for pass in package.passes {
            let groupedStages = Dictionary(grouping: pass.stages, by: \.stage)
            if Set(groupedStages.keys) != Set(stageCodes)
                || groupedStages.values.contains(where: { $0.count != 1 }) {
                errors.append(.invalidStageSet(annotatorID: pass.annotatorID))
                continue
            }
            let stageMap = groupedStages.compactMapValues { $0.first }
            let frames = stageCodes.compactMap {
                stageMap[$0]?.sourceFrameIndex
            }
            if !zip(frames, frames.dropFirst()).allSatisfy(<) {
                errors.append(.invalidStageOrder(annotatorID: pass.annotatorID))
            }
        }

        if package.metadata.split != .development
            && package.metadata.authorization != .trainingAllowed {
            errors.append(.trainingWithoutAuthorization)
        }
        if package.metadata.split != .development {
            for pass in package.passes {
                if pass.frameLabels.isEmpty {
                    errors.append(.missingReviewedFrames(
                        annotatorID: pass.annotatorID
                    ))
                }
                for frame in pass.frameLabels
                    where !frame.reviewed || frame.reviewerID?.isEmpty != false {
                    errors.append(.unreviewedTrainingFrame(
                        sourceFrameIndex: frame.sourceFrameIndex
                    ))
                }
            }
            for resolved in AnnotationConsensusResolver.resolve(package)
                where resolved.sourceFrameIndex == nil {
                errors.append(.unresolvedTrainingStage(stage: resolved.stage))
            }
        }
        if package.frozenAt != nil, package.activeDraft != nil {
            errors.append(.activeDraftPresent)
        }
        if package.frameQueue.contains(where: {
            !(0..<package.media.frameCount).contains($0)
        }) || package.frameQueue != Array(Set(package.frameQueue)).sorted() {
            errors.append(.invalidFrameQueue)
        }
        if package.frozenAt != nil,
           package.metadata.split != .development,
           package.frameQueue.isEmpty {
            errors.append(.invalidFrameQueue)
        }

        if package.passes.count == 2 {
            for stage in stageCodes {
                let selections = package.passes.compactMap {
                    $0.stages.first(where: { $0.stage == stage })
                }
                let frames = selections.compactMap(\.sourceFrameIndex)
                let needsDecision = frames.count != 2
                    || abs(frames[0] - frames[1]) > 2
                if needsDecision
                    && !package.adjudications.contains(where: {
                        $0.stage == stage
                    }) {
                    errors.append(.missingAdjudication(stage: stage))
                }
                if let decision = package.adjudications.first(where: {
                    $0.stage == stage
                }), decision.originalSelections.count != 2 {
                    errors.append(.incompleteAdjudication(stage: stage))
                }
            }
        }
        return errors
    }
}

enum AnnotationConsensusResolver {
    static func resolve(
        _ package: AnnotationPackage
    ) -> [AnnotationStageSelection] {
        AnnotationPackageValidator.stageCodes.map { stage in
            if let decision = package.adjudications.first(where: {
                $0.stage == stage
            }) {
                return .init(
                    stage: stage,
                    sourceFrameIndex: decision.sourceFrameIndex,
                    status: decision.sourceFrameIndex == nil
                        ? .unresolved
                        : .manual,
                    note: "adjudicated"
                )
            }
            let originals = package.passes.prefix(2).compactMap {
                $0.stages.first(where: { $0.stage == stage })
            }
            let frames = originals.compactMap(\.sourceFrameIndex)
            guard frames.count == 2, abs(frames[0] - frames[1]) <= 2 else {
                return .init(
                    stage: stage,
                    sourceFrameIndex: nil,
                    status: .unresolved,
                    note: "requires-adjudication"
                )
            }
            return .init(
                stage: stage,
                sourceFrameIndex: Int(
                    (Double(frames[0] + frames[1]) / 2).rounded()
                ),
                status: .manual,
                note: "two-pass-midpoint"
            )
        }
    }
}

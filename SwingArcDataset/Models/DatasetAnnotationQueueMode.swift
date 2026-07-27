import Foundation

public enum DatasetAnnotationQueueMode:
    String,
    CaseIterable,
    Equatable,
    Hashable,
    Sendable
{
    case pPointFirstPass
    case expandedTraining

    public var displayName: String {
        switch self {
        case .pPointFirstPass:
            return "P1–P8 首轮"
        case .expandedTraining:
            return "扩展训练队列"
        }
    }
}

public enum DatasetAnnotationQueueFactory {
    public static func make(
        mode: DatasetAnnotationQueueMode,
        truth: GolfPPointTruthDocument,
        split: GolfDatasetSplit,
        totalFrames: Int
    ) -> [GolfAnnotationQueueItem] {
        switch mode {
        case .pPointFirstPass:
            return makePPointFirstPass(
                truth: truth,
                totalFrames: totalFrames
            )
        case .expandedTraining:
            return GolfAnnotationFrameQueueBuilder.build(
                input: GolfAnnotationQueueInput(
                    split: split,
                    p1: truth.frame(for: .p1),
                    p5: truth.frame(for: .p5),
                    p6: truth.frame(for: .p6),
                    p8: truth.frame(for: .p8),
                    totalFrames: totalFrames,
                    anomalyFrames: [],
                    preSwingNegativeSamples: [],
                    postSwingNegativeSamples: []
                )
            )
        }
    }

    private static func makePPointFirstPass(
        truth: GolfPPointTruthDocument,
        totalFrames: Int
    ) -> [GolfAnnotationQueueItem] {
        guard totalFrames > 0,
              truth.stages.count == GolfPPointStageCode.allCases.count else {
            return []
        }

        let grouped = Dictionary(grouping: truth.stages, by: \.code)
        guard Set(grouped.keys) == Set(GolfPPointStageCode.allCases),
              grouped.values.allSatisfy({ $0.count == 1 }) else {
            return []
        }

        let orderedStages = GolfPPointStageCode.allCases.compactMap {
            grouped[$0]?.first
        }
        let frames = orderedStages.map(\.sourceFrameIndex)
        guard frames.allSatisfy({ (0..<totalFrames).contains($0) }),
              zip(frames, frames.dropFirst()).allSatisfy(<) else {
            return []
        }

        return orderedStages.map { stage in
            GolfAnnotationQueueItem(
                sourceFrameIndex: stage.sourceFrameIndex,
                reasons: [reason(for: stage.code)],
                isProtected: true
            )
        }
    }

    private static func reason(
        for code: GolfPPointStageCode
    ) -> GolfAnnotationQueueReason {
        switch code {
        case .p1: return .p1Stage
        case .p2: return .p2Stage
        case .p3: return .p3Stage
        case .p4: return .p4Stage
        case .p5: return .p5Stage
        case .p6: return .p6Stage
        case .p7: return .p7Stage
        case .p8: return .p8Stage
        }
    }
}

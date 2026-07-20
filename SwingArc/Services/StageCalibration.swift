import Foundation

/// One human-confirmed P-stage frame. Frame indices are always source-video
/// indices so reports remain comparable across source frame rates.
struct StageGroundTruthFrame: Equatable {
    let stage: SwingStage
    let sourceFrameIndex: Int
}

struct StageGroundTruthSet: Equatable {
    let maximumAcceptedFrameError: Int
    let frames: [StageGroundTruthFrame]

    init(maximumAcceptedFrameError: Int, frames: [StageGroundTruthFrame]) {
        self.maximumAcceptedFrameError = max(0, maximumAcceptedFrameError)
        self.frames = frames
    }
}

struct StageCalibrationMetric: Equatable {
    let stage: SwingStage
    let evaluatedCount: Int
    let resolvedCount: Int
    let unresolvedCount: Int
    let falseConfirmationCount: Int
    let absoluteFrameErrors: [Int]
    let inToleranceCount: Int

    var medianFrameError: Double? {
        guard !absoluteFrameErrors.isEmpty else { return nil }
        let sorted = absoluteFrameErrors.sorted()
        let midpoint = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Double(sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return Double(sorted[midpoint])
    }
}

struct StageCalibrationReport: Equatable {
    let metrics: [SwingStage: StageCalibrationMetric]

    static func evaluate(
        truth: StageGroundTruthSet,
        result: SwingAnalysisResult
    ) -> StageCalibrationReport {
        let metrics = Dictionary(uniqueKeysWithValues: truth.frames.map { expected in
            let matches = result.detections.filter { $0.stage == expected.stage }
            let resolved = matches.filter {
                $0.status != .unresolved && $0.sourceFrameIndex != nil
            }
            let errors = resolved.compactMap { detection in
                detection.sourceFrameIndex.map { abs($0 - expected.sourceFrameIndex) }
            }
            let invalidConfirmedCount = matches.filter {
                $0.status != .unresolved && $0.sourceFrameIndex == nil
            }.count
            let falseConfirmations = max(0, matches.count - 1) + invalidConfirmedCount
            let metric = StageCalibrationMetric(
                stage: expected.stage,
                evaluatedCount: 1,
                resolvedCount: resolved.isEmpty ? 0 : 1,
                unresolvedCount: resolved.isEmpty ? 1 : 0,
                falseConfirmationCount: falseConfirmations,
                absoluteFrameErrors: errors,
                inToleranceCount: errors.filter {
                    $0 <= truth.maximumAcceptedFrameError
                }.count
            )
            return (expected.stage, metric)
        })
        return StageCalibrationReport(metrics: metrics)
    }
}

/// A candidate detector can replace a baseline only when it has not worsened
/// stage availability, false confirmations, or median source-frame error.
enum StageBaselineComparator {
    static func canPromote(
        candidate: StageCalibrationReport,
        baseline: StageCalibrationReport
    ) -> Bool {
        SwingStage.allCases.allSatisfy { stage in
            guard let baselineMetric = baseline.metrics[stage],
                  let candidateMetric = candidate.metrics[stage] else {
                return false
            }
            guard candidateMetric.unresolvedCount <= baselineMetric.unresolvedCount,
                  candidateMetric.falseConfirmationCount <= baselineMetric.falseConfirmationCount else {
                return false
            }
            switch (candidateMetric.medianFrameError, baselineMetric.medianFrameError) {
            case let (candidateError?, baselineError?):
                return candidateError <= baselineError
            case (nil, nil):
                return true
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }
}

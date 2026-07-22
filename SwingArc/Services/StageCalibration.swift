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

enum PracticeCameraView: String, Codable, Equatable, Identifiable {
    case downTheLine
    case faceOn

    var id: String { rawValue }
}

/// A user-confirmed replacement for an automatically selected source frame.
/// Corrections are deliberately compact: they store frame deltas, not video
/// pixels or Vision model data.
struct StageCorrection: Codable, Equatable {
    let stage: SwingStage
    let view: PracticeCameraView
    let automaticFrameIndex: Int
    let manualFrameIndex: Int

    init(
        stage: SwingStage,
        view: PracticeCameraView,
        automaticFrameIndex: Int,
        manualFrameIndex: Int
    ) {
        self.stage = stage
        self.view = view
        self.automaticFrameIndex = automaticFrameIndex
        self.manualFrameIndex = manualFrameIndex
    }

    var frameDelta: Int {
        manualFrameIndex - automaticFrameIndex
    }

    private enum CodingKeys: String, CodingKey {
        case stage
        case view
        case automaticFrameIndex
        case manualFrameIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stageValue = try container.decode(String.self, forKey: .stage)
        guard let stage = SwingStage(rawValue: stageValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .stage,
                in: container,
                debugDescription: "Unknown SwingStage raw value"
            )
        }
        self.init(
            stage: stage,
            view: try container.decode(PracticeCameraView.self, forKey: .view),
            automaticFrameIndex: try container.decode(Int.self, forKey: .automaticFrameIndex),
            manualFrameIndex: try container.decode(Int.self, forKey: .manualFrameIndex)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stage.rawValue, forKey: .stage)
        try container.encode(view, forKey: .view)
        try container.encode(automaticFrameIndex, forKey: .automaticFrameIndex)
        try container.encode(manualFrameIndex, forKey: .manualFrameIndex)
    }
}

struct PersonalStageCalibration: Codable, Equatable {
    private let offsetsByStageRawValue: [String: Int]

    init(offsetFrames: [SwingStage: Int]) {
        offsetsByStageRawValue = Dictionary(
            uniqueKeysWithValues: offsetFrames.map { ($0.key.rawValue, $0.value) }
        )
    }

    var offsetFrames: [SwingStage: Int] {
        Dictionary(uniqueKeysWithValues: offsetsByStageRawValue.compactMap { rawValue, offset in
            SwingStage(rawValue: rawValue).map { ($0, offset) }
        })
    }

    static let empty = PersonalStageCalibration(offsetFrames: [:])
}

enum PersonalCalibrationPolicy {
    static let minimumCorrectionCount = 8
    static let maximumAbsoluteOffsetFrames = 6

    static func update(
        current: PersonalStageCalibration,
        corrections: [StageCorrection],
        view: PracticeCameraView
    ) -> PersonalStageCalibration {
        var offsets = current.offsetFrames
        for stage in SwingStage.allCases {
            let deltas = corrections
                .filter { $0.view == view && $0.stage == stage }
                .map(\.frameDelta)
                .sorted()
            guard deltas.count >= minimumCorrectionCount else { continue }
            let middle = deltas.count / 2
            let median = deltas.count.isMultiple(of: 2)
                ? Int((Double(deltas[middle - 1] + deltas[middle]) / 2).rounded())
                : deltas[middle]
            offsets[stage] = min(
                maximumAbsoluteOffsetFrames,
                max(-maximumAbsoluteOffsetFrames, median)
            )
        }
        return PersonalStageCalibration(offsetFrames: offsets)
    }
}

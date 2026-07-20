import Foundation

@main
struct StageCalibrationSmoke {
    static func main() {
        let truth = StageGroundTruthSet(
            maximumAcceptedFrameError: 1,
            frames: SwingStage.allCases.enumerated().map { offset, stage in
                StageGroundTruthFrame(stage: stage, sourceFrameIndex: 100 + offset * 10)
            }
        )

        let baseline = StageCalibrationReport.evaluate(
            truth: truth,
            result: result(overrides: [:])
        )
        precondition(baseline.metrics[.top]?.absoluteFrameErrors == [0])
        precondition(baseline.metrics[.followThrough]?.unresolvedCount == 0)
        precondition(StageBaselineComparator.canPromote(candidate: baseline, baseline: baseline))

        let regressed = StageCalibrationReport.evaluate(
            truth: truth,
            result: result(overrides: [
                .top: .confirmed(frame: 132),
                .followThrough: .unresolved
            ])
        )
        precondition(regressed.metrics[.top]?.absoluteFrameErrors == [2])
        precondition(regressed.metrics[.top]?.inToleranceCount == 0)
        precondition(regressed.metrics[.followThrough]?.unresolvedCount == 1)
        precondition(!StageBaselineComparator.canPromote(candidate: regressed, baseline: baseline))

        let duplicateImpact = result(overrides: [:], duplicate: .impact)
        let duplicateReport = StageCalibrationReport.evaluate(truth: truth, result: duplicateImpact)
        precondition(duplicateReport.metrics[.impact]?.falseConfirmationCount == 1)
        precondition(!StageBaselineComparator.canPromote(candidate: duplicateReport, baseline: baseline))
    }

    private enum Override {
        case confirmed(frame: Int)
        case unresolved
    }

    private static func result(
        overrides: [SwingStage: Override],
        duplicate: SwingStage? = nil
    ) -> SwingAnalysisResult {
        var detections = SwingStage.allCases.enumerated().map { offset, stage -> SwingStageDetection in
            let defaultFrame = 100 + offset * 10
            switch overrides[stage] {
            case let .confirmed(frame):
                return detection(stage: stage, frame: frame)
            case .unresolved:
                return SwingStageDetection(
                    stage: stage,
                    time: nil,
                    sourceFrameIndex: nil,
                    confidence: 0,
                    status: .unresolved
                )
            case nil:
                return detection(stage: stage, frame: defaultFrame)
            }
        }
        if let duplicate, let original = detections.first(where: { $0.stage == duplicate }) {
            detections.append(original)
        }
        return SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: Set(detections.filter { $0.status == .unresolved }.map(\.stage)),
            detections: detections
        )
    }

    private static func detection(stage: SwingStage, frame: Int) -> SwingStageDetection {
        SwingStageDetection(
            stage: stage,
            time: Double(frame) / 30,
            sourceFrameIndex: frame,
            confidence: 0.9,
            status: .confirmed,
            hasClubEvidence: stage == .impact,
            hasBallEvidence: stage == .impact
        )
    }
}

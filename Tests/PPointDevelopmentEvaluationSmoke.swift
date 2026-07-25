import Foundation

@main
struct PPointDevelopmentEvaluationSmoke {
    static func main() throws {
        let dtlTruth = makeTruth(
            identity: "dtl-media",
            timeline: "dtl-timeline",
            view: .downTheLine
        )
        let faceOnTruth = makeTruth(
            identity: "fo-media",
            timeline: "fo-timeline",
            view: .faceOn
        )
        precondition(
            PPointDevelopmentCoveragePolicy.missingViews(
                in: [dtlTruth]
            ) == [.faceOn]
        )
        precondition(
            PPointDevelopmentCoveragePolicy.missingViews(
                in: [dtlTruth, faceOnTruth]
            ).isEmpty
        )
        let dtlPrediction = makePrediction(
            truth: dtlTruth,
            overrides: [
                .p2: PPointAutomaticStageResult(
                    code: .p2,
                    sourceFrameIndex: 23,
                    status: .confirmed
                )
            ]
        )
        let faceOnPrediction = makePrediction(
            truth: faceOnTruth,
            overrides: [
                .p2: PPointAutomaticStageResult(
                    code: .p2,
                    sourceFrameIndex: nil,
                    status: .unresolved
                )
            ]
        )

        let report = try PPointDevelopmentEvaluationBuilder.makeReport(
            pairs: [
                .init(truth: dtlTruth, prediction: dtlPrediction),
                .init(truth: faceOnTruth, prediction: faceOnPrediction)
            ]
        )

        precondition(report.maximumAcceptedFrameError == 2)
        precondition(report.clipCount == 2)
        precondition(report.decision == .developmentOnly)
        precondition(report.views.map(\.view) == [.downTheLine, .faceOn])
        let dtlClipP2 = report.clips[0].stages.first {
            $0.code == .p2
        }
        precondition(dtlClipP2?.referenceFrame == 20)
        precondition(dtlClipP2?.predictedFrame == 23)
        precondition(dtlClipP2?.signedFrameDelta == 3)
        precondition(dtlClipP2?.absoluteFrameError == 3)
        precondition(dtlClipP2?.withinTolerance == false)

        let faceOnClipP2 = report.clips[1].stages.first {
            $0.code == .p2
        }
        precondition(faceOnClipP2?.predictedFrame == nil)
        precondition(faceOnClipP2?.signedFrameDelta == nil)
        precondition(faceOnClipP2?.status == .unresolved)

        let dtlP1 = require(report, view: .downTheLine, code: .p1)
        precondition(dtlP1.referenceCount == 1)
        precondition(dtlP1.hitRate == 1)
        precondition(dtlP1.medianAbsoluteFrameError == 0)

        let dtlP2 = require(report, view: .downTheLine, code: .p2)
        precondition(dtlP2.hitRate == 0)
        precondition(dtlP2.unresolvedRate == 0)
        precondition(dtlP2.outOfToleranceRate == 1)
        precondition(dtlP2.medianAbsoluteFrameError == 3)

        let faceOnP2 = require(report, view: .faceOn, code: .p2)
        precondition(faceOnP2.hitRate == 0)
        precondition(faceOnP2.unresolvedRate == 1)
        precondition(faceOnP2.outOfToleranceRate == 0)
        precondition(faceOnP2.medianAbsoluteFrameError == nil)

        let markdown = PPointDevelopmentEvaluationRenderer.markdown(report)
        precondition(markdown.contains("## DTL"))
        precondition(markdown.contains("## Face-on"))
        precondition(markdown.contains("| P2 | 1 | 0.0% | 0.0% | 100.0% | 3.00 |"))
        precondition(markdown.contains("| dtl-media.mov | DTL | P2 | 20 | 23 | +3 |"))
        precondition(markdown.contains("仅用于开发评估"))

        var mismatched = dtlPrediction
        mismatched = PPointAutomaticClipResult(
            mediaSHA256: mismatched.mediaSHA256,
            timelineSHA256: "wrong-timeline",
            view: mismatched.view,
            elapsedSeconds: mismatched.elapsedSeconds,
            stages: mismatched.stages
        )
        do {
            _ = try PPointDevelopmentEvaluationBuilder.makeReport(
                pairs: [.init(truth: dtlTruth, prediction: mismatched)]
            )
            preconditionFailure("Mismatched media identity must fail")
        } catch let error as PPointDevelopmentEvaluationError {
            precondition(error == .mediaIdentityMismatch("dtl-media"))
        }

        do {
            _ = try PPointDevelopmentEvaluationBuilder.makeReport(
                pairs: [.init(truth: dtlTruth, prediction: dtlPrediction)]
            )
            preconditionFailure("A single-view report must not claim split-view accuracy")
        } catch let error as PPointDevelopmentEvaluationError {
            precondition(error == .missingViewCoverage([.faceOn]))
        }
    }

    private static func makeTruth(
        identity: String,
        timeline: String,
        view: PPointGroundTruthView
    ) -> PPointGroundTruthPackage {
        PPointGroundTruthPackage(
            schemaVersion: 1,
            stageSystem: "p-system-v1",
            reviewLevel: .singlePassDevelopment,
            media: PPointGroundTruthMedia(
                fileName: "\(identity).mov",
                sha256: identity,
                timelineSHA256: timeline,
                frameCount: 200,
                width: 1920,
                height: 1080
            ),
            view: view,
            createdAt: Date(timeIntervalSince1970: 100),
            stages: PPointCode.allCases.enumerated().map { index, code in
                PPointGroundTruthStage(
                    code: code,
                    sourceFrameIndex: (index + 1) * 10,
                    time: Double(index + 1) / 3
                )
            }
        )
    }

    private static func makePrediction(
        truth: PPointGroundTruthPackage,
        overrides: [PPointCode: PPointAutomaticStageResult]
    ) -> PPointAutomaticClipResult {
        PPointAutomaticClipResult(
            mediaSHA256: truth.media.sha256,
            timelineSHA256: truth.media.timelineSHA256,
            view: truth.view,
            elapsedSeconds: 1.5,
            stages: truth.stages.map {
                overrides[$0.code] ?? PPointAutomaticStageResult(
                    code: $0.code,
                    sourceFrameIndex: $0.sourceFrameIndex,
                    status: .confirmed
                )
            }
        )
    }

    private static func require(
        _ report: PPointDevelopmentEvaluationReport,
        view: PPointGroundTruthView,
        code: PPointCode
    ) -> PPointStageDevelopmentSummary {
        guard let value = report.views
            .first(where: { $0.view == view })?
            .stages.first(where: { $0.code == code }) else {
            preconditionFailure("Missing \(view) \(code)")
        }
        return value
    }
}

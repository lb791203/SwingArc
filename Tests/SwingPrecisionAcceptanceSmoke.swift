import Foundation

@main
struct SwingPrecisionAcceptanceSmoke {
    static func main() {
        verifyExactlyNinetyPercentPasses()
        verifyBelowNinetyPercentFails()
        verifyViewsAndStagesAreEvaluatedSeparately()
    }

    private static func verifyExactlyNinetyPercentPasses() {
        let records = (0..<10).map { index in
            PrecisionStageRecord(
                view: .downTheLine,
                stage: "P6",
                expectedFrame: 100,
                actualFrame: index == 9 ? nil : 102,
                status: index == 9 ? "unresolved" : "confirmed"
            )
        }

        let summary = SwingPrecisionAcceptance.summarize(records: records)
        let key = PrecisionStageKey(view: .downTheLine, stage: "P6")
        precondition(summary.stageRates[key] == 0.9)
        precondition(summary.passed)
    }

    private static func verifyBelowNinetyPercentFails() {
        var records = (0..<10).map { _ in
            PrecisionStageRecord(
                view: .downTheLine,
                stage: "P6",
                expectedFrame: 100,
                actualFrame: 102,
                status: "confirmed"
            )
        }
        records[8] = PrecisionStageRecord(
            view: .downTheLine,
            stage: "P6",
            expectedFrame: 100,
            actualFrame: 103,
            status: "confirmed"
        )
        records[9] = PrecisionStageRecord(
            view: .downTheLine,
            stage: "P6",
            expectedFrame: 100,
            actualFrame: nil,
            status: "unresolved"
        )

        precondition(!SwingPrecisionAcceptance.summarize(records: records).passed)
    }

    private static func verifyViewsAndStagesAreEvaluatedSeparately() {
        let dtlP1 = passingRecords(view: .downTheLine, stage: "P1")
        let faceOnP1 = passingRecords(view: .faceOn, stage: "P1")
        var faceOnP8 = passingRecords(view: .faceOn, stage: "P8")
        faceOnP8[0] = PrecisionStageRecord(
            view: .faceOn,
            stage: "P8",
            expectedFrame: 200,
            actualFrame: 203,
            status: "confirmed"
        )
        faceOnP8[1] = PrecisionStageRecord(
            view: .faceOn,
            stage: "P8",
            expectedFrame: 200,
            actualFrame: nil,
            status: "unresolved"
        )

        let summary = SwingPrecisionAcceptance.summarize(
            records: dtlP1 + faceOnP1 + faceOnP8
        )
        precondition(summary.stageRates.count == 3)
        precondition(!summary.passed)
    }

    private static func passingRecords(
        view: PrecisionCameraView,
        stage: String
    ) -> [PrecisionStageRecord] {
        (0..<10).map { _ in
            PrecisionStageRecord(
                view: view,
                stage: stage,
                expectedFrame: stage == "P8" ? 200 : 20,
                actualFrame: stage == "P8" ? 202 : 22,
                status: "confirmed"
            )
        }
    }
}

import Foundation

@main
struct TwoStageAnalysisPolicySmoke {
    static func main() {
        let locating = AnalysisProgressPresentation(phase: .locating, progress: 0.25)
        precondition(locating.title == "定位挥杆段")
        precondition(locating.detail.contains("粗扫"))

        let failures: [AnalysisFailure] = [
            .noStableGolfer,
            .noSwingMotion,
            .ambiguousSwingWindows,
            .swingWindowTooLong
        ]
        precondition(failures.count == 4)
    }
}

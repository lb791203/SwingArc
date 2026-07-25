import Foundation

@main
struct AutomaticAnalysisLaunchSmoke {
    static func main() {
        precondition(
            !AutomaticAnalysisPolicy.shouldAnalyze(
                event: .importCompleted,
                view: nil
            )
        )
        precondition(
            AutomaticAnalysisPolicy.shouldAnalyze(
                event: .importCompleted,
                view: .faceOn
            )
        )
        precondition(
            AutomaticAnalysisPolicy.shouldAnalyze(
                event: .capturedClipSaved,
                view: .downTheLine
            )
        )
        precondition(
            !AutomaticAnalysisPolicy.shouldAnalyze(
                event: .projectReopened,
                view: .faceOn
            )
        )
    }
}

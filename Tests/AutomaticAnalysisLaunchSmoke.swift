import Foundation

@main
struct AutomaticAnalysisLaunchSmoke {
    static func main() {
        precondition(AutomaticAnalysisPolicy.shouldAnalyze(event: .importCompleted))
        precondition(AutomaticAnalysisPolicy.shouldAnalyze(event: .capturedClipSaved))
        precondition(!AutomaticAnalysisPolicy.shouldAnalyze(event: .projectReopened))
    }
}

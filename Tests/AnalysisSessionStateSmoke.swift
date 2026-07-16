import Foundation

@main
struct AnalysisSessionStateSmoke {
    static func main() {
        precondition(!SwingAnalysisState.idle.hasCompletedResult)
        precondition(!SwingAnalysisState.scanning(progress: 0.5).hasCompletedResult)

        let result = SwingAnalysisResult(
            detectedMarkers: [KeyframeMarker(time: 0.3, stage: .top)],
            unresolvedStages: Set(SwingStage.allCases).subtracting([.top])
        )
        precondition(SwingAnalysisState.completed(result).hasCompletedResult)
        precondition(!SwingAnalysisState.failed(.insufficientPoseEvidence).hasCompletedResult)
    }
}

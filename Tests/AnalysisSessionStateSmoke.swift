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

        let gate = AnalysisRunGate()
        let supersededRun = gate.begin()
        let activeRun = gate.begin()
        precondition(!gate.isActive(supersededRun))
        precondition(gate.isActive(activeRun))
        gate.cancel(supersededRun)
        precondition(gate.isActive(activeRun), "An obsolete run must not cancel its replacement")
        gate.cancel(activeRun)
        precondition(!gate.isActive(activeRun))

        precondition(
            SwingVideoAnalysisProgressPolicy.expansionProgress(
                cachedFrameCount: 0,
                maximumFrameBudget: 480
            ) == 0.20
        )
        precondition(
            SwingVideoAnalysisProgressPolicy.expansionProgress(
                cachedFrameCount: 240,
                maximumFrameBudget: 480
            ) == 0.45
        )
        precondition(
            SwingVideoAnalysisProgressPolicy.expansionProgress(
                cachedFrameCount: 960,
                maximumFrameBudget: 480
            ) == 0.70
        )
        precondition(
            SwingVideoAnalysisProgressPolicy.evidenceProgress(
                processedReferenceCount: 16,
                totalReferenceCount: 32
            ) == 0.825
        )
        precondition(
            SwingVideoAnalysisProgressPolicy.evidenceProgress(
                processedReferenceCount: 64,
                totalReferenceCount: 32
            ) == 0.95
        )

        precondition(
            SwingVideoAnalysisValidationPolicy.transitionFailure(
                hasTopTransition: false,
                hasImpactCandidates: false
            ) == .missingTopTransition
        )
        precondition(
            SwingVideoAnalysisValidationPolicy.transitionFailure(
                hasTopTransition: true,
                hasImpactCandidates: false
            ) == .noImpactCorridor
        )
        precondition(
            SwingVideoAnalysisValidationPolicy.transitionFailure(
                hasTopTransition: true,
                hasImpactCandidates: true
            ) == nil
        )
    }
}

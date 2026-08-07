import Foundation

@main
struct AnalysisWorkspacePresentationSmoke {
    static func main() {
        let idle = AnalysisWorkspacePresentation(state: .idle)
        precondition(idle.markers.isEmpty)
        precondition(!idle.allowsPoseOverlays)

        let result = SwingAnalysisResult(
            detectedMarkers: [KeyframeMarker(time: 0.3, stage: .top)],
            unresolvedStages: Set(SwingStage.allCases).subtracting([.top])
        )
        let completed = AnalysisWorkspacePresentation(state: .completed(result))
        precondition(completed.markers.count == 1)
        precondition(completed.allowsPoseOverlays)
        precondition(completed.unresolvedStages.contains(.impact))

        precondition(SwingFeedbackCategory.allCases == [
            .setup,
            .bodyStability,
            .handPath,
            .swingPlane,
            .impactAndRelease
        ])
    }
}

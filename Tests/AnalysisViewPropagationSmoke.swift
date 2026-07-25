import Foundation

@main
struct AnalysisViewPropagationSmoke {
    static func main() {
        let output = SwingVideoAnalysisOutput(
            view: .faceOn,
            result: SwingAnalysisResult(
                detectedMarkers: [],
                unresolvedStages: Set(SwingStage.pStages),
                detections: []
            ),
            poseSamples: [],
            leadArm: .unknown,
            adaptiveWindow: SwingWindow(startTime: 0, endTime: 1),
            sourceFrameRate: 240,
            elapsedSeconds: 0.1
        )

        precondition(output.view == .faceOn)
        guard let result = SwingFeedbackPipeline.make(
            output: output,
            manualMarkers: []
        ) else {
            preconditionFailure("The completed analysis must own its camera view")
        }
        precondition(result.artifact.view == PracticeCameraView.faceOn.rawValue)
    }
}

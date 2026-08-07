import Foundation

struct SwingFeedbackPipelineResult: Equatable {
    let artifact: SwingAnalysisArtifact
    let detections: [SwingStageDetection]
    let feedback: SimplifiedSwingFeedback
}

enum SwingFeedbackPipeline {
    static func make(
        output: SwingVideoAnalysisOutput,
        view: PracticeCameraView?,
        manualMarkers: [KeyframeMarker]
    ) -> SwingFeedbackPipelineResult? {
        guard let view else { return nil }
        let detections = ManualStageDetectionPolicy.applying(
            manualMarkers: manualMarkers,
            sourceFrameRate: output.sourceFrameRate,
            automatic: output.result.detections,
            availablePoseSamples: output.poseSamples
        )
        let personHeight = SwingMetricEvidence.personHeight(
            frames: output.observationFrames,
            detections: detections
        )
        let metrics = SwingMetricEngine.motionMeasurements(
            frames: output.observationFrames,
            stages: detections,
            personHeight: personHeight
        )
        let artifact = SwingAnalysisArtifactBuilder.make(
            view: view,
            sourceFrameRate: output.sourceFrameRate,
            frames: output.observationFrames,
            detections: detections,
            metrics: metrics
        )
        let findings = SwingTechniqueEvaluator.evaluate(
            samples: output.poseSamples,
            stages: detections,
            view: view,
            leadArm: output.leadArm
        )
        return SwingFeedbackPipelineResult(
            artifact: artifact,
            detections: detections,
            feedback: SwingFeedbackAssembler.make(
                artifact: artifact,
                detections: detections,
                findings: findings
            )
        )
    }
}

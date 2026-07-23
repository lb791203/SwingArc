import Foundation

enum SwingAnalysisArtifactBuilder {
    static let modelVersion = "vision-p-system-v1"

    static func make(
        view: PracticeCameraView,
        sourceFrameRate: Double,
        qualityIssues: [String] = [],
        frames: [SwingFrameObservation],
        detections: [SwingStageDetection],
        metrics: [SwingMetricValue]
    ) -> SwingAnalysisArtifact {
        SwingAnalysisArtifact(
            schemaVersion: SwingAnalysisArtifact.currentSchemaVersion,
            modelVersion: modelVersion,
            view: view.rawValue,
            sourceFrameRate: sourceFrameRate,
            qualityIssues: qualityIssues,
            frames: frames,
            stages: detections.map { detection in
                SwingStageArtifact(
                    code: detection.stage.evidenceCode,
                    sourceFrameIndex: detection.sourceFrameIndex,
                    time: detection.time,
                    confidence: detection.confidence,
                    status: detection.status.rawValue,
                    evidenceSources: detection.evidence.sources
                        .map(\.rawValue)
                        .sorted(),
                    manuallyLocked: detection.evidence.sources
                        .contains(.manual)
                )
            },
            metrics: metrics.filter {
                $0.id.isMotionAnalysisOutput
            }
        )
    }
}

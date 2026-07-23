import Foundation

@main
struct SwingAnalysisArtifactBuilderSmoke {
    static func main() {
        let manual = SwingStageDetection(
            stage: .impact,
            time: 1.4,
            sourceFrameIndex: 84,
            confidence: 1,
            status: .confirmed,
            evidence: StageEvidenceSummary(
                sources: [.manual],
                detectedPointCount: 0,
                estimatedPointCount: 0
            )
        )
        let artifact = SwingAnalysisArtifactBuilder.make(
            view: .downTheLine,
            sourceFrameRate: 60,
            frames: [],
            detections: [manual],
            metrics: [
                SwingMetricValue(
                    id: .handPathLength,
                    value: 1.2,
                    unit: "person-height",
                    confidence: 0.9,
                    stage: "P2-P7",
                    availability: .measured
                ),
                SwingMetricValue(
                    id: .attackAngle,
                    value: -4,
                    unit: "deg",
                    confidence: 0.9,
                    stage: "P7",
                    availability: .measured
                )
            ]
        )

        precondition(
            artifact.schemaVersion
                == SwingAnalysisArtifact.currentSchemaVersion
        )
        precondition(artifact.metrics.map(\.id) == [.handPathLength])
        precondition(artifact.stages.first?.manuallyLocked == true)
        precondition(artifact.stages.first?.sourceFrameIndex == 84)
        precondition(
            artifact.view == PracticeCameraView.downTheLine.rawValue
        )
    }
}

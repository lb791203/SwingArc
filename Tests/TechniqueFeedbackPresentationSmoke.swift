import Foundation

@main
struct TechniqueFeedbackPresentationSmoke {
    static func main() {
        let finding = TechniqueFinding(
            kind: .overTheTop,
            severity: .attention,
            evidence: TechniqueEvidence(
                stages: [.takeaway, .top, .impact],
                normalizedMagnitude: 0.21
            )
        )
        let confirmed = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: [.takeaway, .top, .impact].enumerated().map { index, stage in
                SwingStageDetection(
                    stage: stage,
                    time: Double(index) / 30,
                    sourceFrameIndex: index,
                    confidence: 0.9,
                    status: .confirmed
                )
            }
        )
        let model = TechniqueFeedbackPresentation.make(
            feedback: .finding(finding),
            analysis: confirmed
        )
        precondition(model.title == "下杆略偏外")
        precondition(model.showsEvidence)
        precondition(model.drill?.identifier == "path-towel")

        let unresolved = TechniqueFeedbackPresentation.make(
            feedback: .unresolved,
            analysis: SwingAnalysisResult(
                detectedMarkers: [],
                unresolvedStages: [.impact]
            )
        )
        precondition(unresolved.title == "本球未能判定")
        precondition(!unresolved.showsEvidence)
        precondition(unresolved.drill == nil)

        let incompleteFinding = TechniqueFeedbackPresentation.make(
            feedback: .finding(finding),
            analysis: SwingAnalysisResult(
                detectedMarkers: [],
                unresolvedStages: [.top],
                detections: [
                    SwingStageDetection(
                        stage: .takeaway,
                        time: 0,
                        sourceFrameIndex: 0,
                        confidence: 0.9,
                        status: .confirmed
                    ),
                    SwingStageDetection(
                        stage: .top,
                        time: 1.0 / 30,
                        sourceFrameIndex: nil,
                        confidence: 0,
                        status: .lowConfidence
                    ),
                    SwingStageDetection(
                        stage: .impact,
                        time: 2.0 / 30,
                        sourceFrameIndex: 2,
                        confidence: 0.9,
                        status: .confirmed
                    )
                ]
            )
        )
        precondition(!incompleteFinding.showsEvidence)
        precondition(incompleteFinding.drill == nil)

        let automaticTop = SwingStageDetection(
            stage: .top,
            time: 10.0 / 240.0,
            sourceFrameIndex: 10,
            confidence: 0.9,
            status: .confirmed
        )
        let manualTop = KeyframeMarker(
            time: 14.0 / 240.0,
            stage: .top,
            source: .manual
        )
        let corrected = ManualStageDetectionPolicy.applying(
            manualMarkers: [manualTop],
            sourceFrameRate: 240,
            automatic: [automaticTop],
            availablePoseSamples: [sample(frame: 14)]
        )
        precondition(corrected[0].sourceFrameIndex == 14)
        precondition(corrected[0].status == .confirmed)
        precondition(corrected[0].evidence.sources == [.manual])
        let unsupportedCorrection = ManualStageDetectionPolicy.applying(
            manualMarkers: [manualTop],
            sourceFrameRate: 240,
            automatic: [automaticTop],
            availablePoseSamples: []
        )
        precondition(unsupportedCorrection[0].status == .lowConfidence)
        precondition(
            unsupportedCorrection[0].evidence.sources == [.manual]
        )
    }

    private static func sample(frame: Int) -> SwingPoseSample {
        SwingPoseSample(
            time: Double(frame) / 240,
            leftWrist: nil,
            rightWrist: nil,
            leftElbow: nil,
            rightElbow: nil,
            leftShoulder: nil,
            rightShoulder: nil,
            leftHip: nil,
            rightHip: nil,
            head: nil,
            spineAngle: nil,
            aggregateConfidence: 1,
            sourceFrameIndex: frame
        )
    }
}

import Foundation

@main
struct PracticeFeedbackPolicySmoke {
    static func main() {
        var samples = baseSamples()
        samples[3] = sample(
            frame: 3,
            leftWrist: CGPoint(x: 0.50, y: 0.30),
            rightWrist: CGPoint(x: 0.54, y: 0.30)
        )
        samples[5] = sample(
            frame: 5,
            leftWrist: CGPoint(x: 0.80, y: 0.52),
            rightWrist: CGPoint(x: 0.84, y: 0.52)
        )
        let output = SwingVideoAnalysisOutput(
            result: SwingAnalysisResult(
                detectedMarkers: [],
                unresolvedStages: [],
                detections: confirmedStages()
            ),
            poseSamples: samples,
            leadArm: .left,
            adaptiveWindow: SwingWindow(startTime: 0, endTime: 3),
            sourceFrameRate: 240,
            elapsedSeconds: 0.4
        )
        guard case let .finding(finding) = PracticeFeedbackPolicy.make(
            output: output,
            view: .downTheLine
        ) else {
            preconditionFailure("Expected evidence-backed finding")
        }
        precondition(finding.kind == .overTheTop)

        let lowEvidence = SwingVideoAnalysisOutput(
            result: SwingAnalysisResult(
                detectedMarkers: [],
                unresolvedStages: Set(SwingStage.allCases),
                detections: []
            ),
            poseSamples: samples,
            leadArm: .left,
            adaptiveWindow: SwingWindow(startTime: 0, endTime: 3),
            sourceFrameRate: 240,
            elapsedSeconds: 0.4
        )
        precondition(PracticeFeedbackPolicy.make(output: lowEvidence, view: .downTheLine) == .unresolved)
    }

    private static func confirmedStages() -> [SwingStageDetection] {
        SwingStage.allCases.enumerated().map { offset, stage in
            SwingStageDetection(
                stage: stage,
                time: Double(offset) / 30,
                sourceFrameIndex: offset,
                confidence: 0.9,
                status: .confirmed
            )
        }
    }

    private static func baseSamples() -> [SwingPoseSample] {
        (0..<8).map { sample(frame: $0) }
    }

    private static func sample(
        frame: Int,
        leftWrist: CGPoint = CGPoint(x: 0.42, y: 0.58),
        rightWrist: CGPoint = CGPoint(x: 0.58, y: 0.58)
    ) -> SwingPoseSample {
        SwingPoseSample(
            time: Double(frame) / 30,
            leftWrist: leftWrist,
            rightWrist: rightWrist,
            leftElbow: CGPoint(x: 0.44, y: 0.46),
            rightElbow: CGPoint(x: 0.56, y: 0.46),
            leftShoulder: CGPoint(x: 0.40, y: 0.32),
            rightShoulder: CGPoint(x: 0.60, y: 0.32),
            leftHip: CGPoint(x: 0.42, y: 0.62),
            rightHip: CGPoint(x: 0.58, y: 0.62),
            head: CGPoint(x: 0.50, y: 0.12),
            spineAngle: 10,
            aggregateConfidence: 0.9,
            sourceFrameIndex: frame
        )
    }
}

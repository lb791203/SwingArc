import Foundation

@main
struct SwingTechniqueEvaluatorSmoke {
    static func main() {
        let stages = confirmedStages()

        var postureSamples = baseSamples()
        postureSamples[3] = sample(
            frame: 3,
            head: CGPoint(x: 0.72, y: 0.12),
            spineAngle: 18
        )
        let posture = SwingTechniqueEvaluator.evaluate(
            samples: postureSamples,
            stages: stages,
            view: .downTheLine,
            leadArm: .left
        )
        precondition(posture.contains { $0.kind == .postureLoss })

        var ottSamples = baseSamples()
        ottSamples[3] = sample(frame: 3, leftWrist: CGPoint(x: 0.50, y: 0.30), rightWrist: CGPoint(x: 0.54, y: 0.30))
        ottSamples[5] = sample(frame: 5, leftWrist: CGPoint(x: 0.80, y: 0.52), rightWrist: CGPoint(x: 0.84, y: 0.52))
        let overTheTop = SwingTechniqueEvaluator.evaluate(
            samples: ottSamples,
            stages: stages,
            view: .downTheLine,
            leadArm: .left
        )
        precondition(overTheTop.contains { $0.kind == .overTheTop })
        precondition(!SwingTechniqueEvaluator.evaluate(
            samples: ottSamples,
            stages: stages,
            view: .faceOn,
            leadArm: .left
        ).contains { $0.kind == .overTheTop })

        var chickenSamples = baseSamples()
        chickenSamples[5] = sample(
            frame: 5,
            leftShoulder: CGPoint(x: 0.40, y: 0.32),
            leftWrist: CGPoint(x: 0.82, y: 0.31),
            leftElbow: CGPoint(x: 0.69, y: 0.42)
        )
        chickenSamples[6] = sample(
            frame: 6,
            leftShoulder: CGPoint(x: 0.40, y: 0.32),
            leftWrist: CGPoint(x: 0.82, y: 0.31),
            leftElbow: CGPoint(x: 0.69, y: 0.42)
        )
        let chickenWing = SwingTechniqueEvaluator.evaluate(
            samples: chickenSamples,
            stages: stages,
            view: .faceOn,
            leadArm: .left
        )
        precondition(chickenWing.contains { $0.kind == .chickenWing })

        let lowConfidence = baseSamples(confidence: 0.5)
        precondition(SwingTechniqueEvaluator.evaluate(
            samples: lowConfidence,
            stages: stages,
            view: .downTheLine,
            leadArm: .left
        ).isEmpty)
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

    private static func baseSamples(confidence: Float = 0.9) -> [SwingPoseSample] {
        (0..<8).map { sample(frame: $0, confidence: confidence) }
    }

    private static func sample(
        frame: Int,
        leftShoulder: CGPoint = CGPoint(x: 0.40, y: 0.32),
        rightShoulder: CGPoint = CGPoint(x: 0.60, y: 0.32),
        leftWrist: CGPoint = CGPoint(x: 0.42, y: 0.58),
        rightWrist: CGPoint = CGPoint(x: 0.58, y: 0.58),
        leftElbow: CGPoint = CGPoint(x: 0.44, y: 0.46),
        rightElbow: CGPoint = CGPoint(x: 0.56, y: 0.46),
        head: CGPoint = CGPoint(x: 0.50, y: 0.12),
        spineAngle: Double = 10,
        confidence: Float = 0.9
    ) -> SwingPoseSample {
        SwingPoseSample(
            time: Double(frame) / 30,
            leftWrist: leftWrist,
            rightWrist: rightWrist,
            leftElbow: leftElbow,
            rightElbow: rightElbow,
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftHip: CGPoint(x: 0.42, y: 0.62),
            rightHip: CGPoint(x: 0.58, y: 0.62),
            head: head,
            spineAngle: spineAngle,
            aggregateConfidence: confidence,
            sourceFrameIndex: frame
        )
    }
}

import Foundation

@main
struct SwingAttemptSelectionPolicySmoke {
    static func main() {
        let swing = SwingAttempt(ordinal: 1, startTime: 1, endTime: 4)
        let walking = SwingAttempt(ordinal: 2, startTime: 5, endTime: 9)
        let samples = [
            sample(time: 1.0, handY: 0.62),
            sample(time: 2.0, handY: 0.25),
            sample(time: 3.0, handY: 0.58),
            sample(time: 5.0, handY: 0.57),
            sample(time: 6.0, handY: 0.48),
            sample(time: 7.0, handY: 0.55),
            sample(time: 8.0, handY: 0.50)
        ]

        precondition(
            SwingAttemptSelectionPolicy.preferredAttempt(
                in: [walking, swing],
                samples: samples
            )?.id == swing.id,
            "A full vertical hand arc must outrank later walking or ball-retrieval motion"
        )
        precondition(
            SwingAttemptSelectionPolicy.rankedAttempts(
                in: [walking, swing],
                samples: samples
            ).map(\.id) == [swing.id, walking.id],
            "Coarse scan must retain every candidate in evidence order for serial fine validation"
        )
        precondition(
            SwingAttemptSelectionPolicy.preferredAttempt(in: [], samples: samples) == nil
        )
    }

    private static func sample(time: Double, handY: CGFloat) -> CoarseSwingSample {
        CoarseSwingSample(
            time: time,
            pose: SwingPoseSample(
                time: time,
                leftWrist: CGPoint(x: 0.47, y: handY),
                rightWrist: CGPoint(x: 0.53, y: handY),
                leftElbow: nil,
                rightElbow: nil,
                leftShoulder: CGPoint(x: 0.42, y: 0.34),
                rightShoulder: CGPoint(x: 0.58, y: 0.34),
                leftHip: CGPoint(x: 0.44, y: 0.64),
                rightHip: CGPoint(x: 0.56, y: 0.64),
                head: nil,
                spineAngle: nil,
                aggregateConfidence: 0.9
            )
        )
    }
}

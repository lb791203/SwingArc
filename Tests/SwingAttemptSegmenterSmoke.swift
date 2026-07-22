import Foundation

@main
struct SwingAttemptSegmenterSmoke {
    static func main() {
        let samples = (0...48).map { index in
            let time = Double(index) * 0.25
            let handX: CGFloat
            switch index {
            case 8...12:
                handX = 0.24 + CGFloat(index - 8) * 0.12
            case 28...32:
                handX = 0.22 + CGFloat(index - 28) * 0.13
            default:
                handX = 0.50
            }
            return CoarseSwingSample(time: time, pose: pose(time: time, handX: handX))
        }

        let attempts = SwingAttemptSegmenter.segment(samples: samples, sourceDuration: 12)
        precondition(attempts.map(\.ordinal) == [1, 2])
        precondition(attempts[0].endTime < attempts[1].startTime)
        precondition(attempts.allSatisfy { $0.duration >= 0.8 && $0.duration <= 8 })
    }

    private static func pose(time: Double, handX: CGFloat) -> SwingPoseSample {
        SwingPoseSample(
            time: time,
            leftWrist: CGPoint(x: handX - 0.03, y: 0.52),
            rightWrist: CGPoint(x: handX + 0.03, y: 0.52),
            leftElbow: nil, rightElbow: nil,
            leftShoulder: CGPoint(x: 0.42, y: 0.32),
            rightShoulder: CGPoint(x: 0.58, y: 0.32),
            leftHip: CGPoint(x: 0.43, y: 0.62),
            rightHip: CGPoint(x: 0.57, y: 0.62),
            head: nil, spineAngle: nil, aggregateConfidence: 0.9
        )
    }
}

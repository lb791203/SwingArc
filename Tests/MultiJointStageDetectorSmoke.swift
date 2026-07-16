import Foundation

@main
struct MultiJointStageDetectorSmoke {
    static func main() {
        let samples = [
            sample(0.00, 0.82), sample(0.08, 0.82), sample(0.16, 0.74),
            sample(0.24, 0.58), sample(0.32, 0.40), sample(0.40, 0.22),
            sample(0.48, 0.30), sample(0.56, 0.58), sample(0.64, 0.82),
            sample(0.72, 0.61), sample(0.80, 0.47), sample(0.88, 0.45),
            sample(0.96, 0.45)
        ]

        let result = SwingStageDetector.detect(samples: samples)
        precondition(result.detections.map(\.stage) == SwingStage.allCases)
        precondition(result.detections.allSatisfy { $0.status == .confirmed })
        let times = result.detections.compactMap(\.time)
        precondition(zip(times, times.dropFirst()).allSatisfy(<))

        let occluded = samples.map { sample in
            SwingPoseSample(
                time: sample.time,
                leftWrist: nil, rightWrist: sample.rightWrist,
                leftElbow: nil, rightElbow: nil,
                leftShoulder: nil, rightShoulder: nil,
                leftHip: nil, rightHip: nil,
                head: nil, spineAngle: nil, aggregateConfidence: 0.8
            )
        }
        precondition(SwingStageDetector.detect(samples: occluded).detections.allSatisfy { $0.status != .confirmed })
    }

    private static func sample(_ time: Double, _ wristY: CGFloat) -> SwingPoseSample {
        SwingPoseSample(
            time: time,
            leftWrist: CGPoint(x: 0.42, y: wristY), rightWrist: CGPoint(x: 0.58, y: wristY),
            leftElbow: CGPoint(x: 0.40, y: min(0.95, wristY + 0.10)), rightElbow: CGPoint(x: 0.60, y: min(0.95, wristY + 0.10)),
            leftShoulder: CGPoint(x: 0.40, y: 0.34), rightShoulder: CGPoint(x: 0.60, y: 0.34),
            leftHip: CGPoint(x: 0.43, y: 0.58), rightHip: CGPoint(x: 0.57, y: 0.58),
            head: CGPoint(x: 0.50, y: 0.16), spineAngle: 18, aggregateConfidence: 0.92
        )
    }
}

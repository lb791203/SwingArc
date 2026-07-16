import Foundation

@main
struct SwingStageDetectorSmoke {
    static func main() {
        let samples = [
            SwingPoseSample(time: 0.0, wristY: 0.82),
            SwingPoseSample(time: 0.1, wristY: 0.70),
            SwingPoseSample(time: 0.2, wristY: 0.54),
            SwingPoseSample(time: 0.3, wristY: 0.25),
            SwingPoseSample(time: 0.45, wristY: 0.48),
            SwingPoseSample(time: 0.55, wristY: 0.83),
            SwingPoseSample(time: 0.7, wristY: 0.56),
            SwingPoseSample(time: 0.8, wristY: 0.47),
            SwingPoseSample(time: 0.9, wristY: 0.46)
        ]

        let result = SwingStageDetector.detect(samples: samples)
        precondition(result.detectedMarkers.isEmpty)
        precondition(result.unresolvedStages == Set(SwingStage.allCases))
        precondition(SwingStage.allCases.count == 8)
        precondition(SwingStage.allCases.contains(.leadArmParallelBackswing))

        // Real videos commonly contain several near-identical frames at
        // address and at the top of the backswing.  Those plateaus must not
        // prevent the eight real, observed stage samples from being resolved.
        let plateauedSwing = [
            SwingPoseSample(time: 0.00, wristY: 0.82),
            SwingPoseSample(time: 0.08, wristY: 0.82),
            SwingPoseSample(time: 0.16, wristY: 0.82),
            SwingPoseSample(time: 0.24, wristY: 0.76),
            SwingPoseSample(time: 0.32, wristY: 0.62),
            SwingPoseSample(time: 0.40, wristY: 0.42),
            SwingPoseSample(time: 0.48, wristY: 0.25),
            SwingPoseSample(time: 0.56, wristY: 0.25),
            SwingPoseSample(time: 0.64, wristY: 0.31),
            SwingPoseSample(time: 0.72, wristY: 0.55),
            SwingPoseSample(time: 0.80, wristY: 0.82),
            SwingPoseSample(time: 0.88, wristY: 0.60),
            SwingPoseSample(time: 0.96, wristY: 0.48),
            SwingPoseSample(time: 1.04, wristY: 0.46),
            SwingPoseSample(time: 1.12, wristY: 0.46)
        ]
        precondition(SwingStageDetector.detect(samples: plateauedSwing).unresolvedStages == Set(SwingStage.allCases))

        // P4 is the first backswing apex that reverses into the downswing.
        // A later follow-through/finish height must never replace it merely
        // because that later wrist position is higher in the whole video.
        let followThroughHigherThanTop = [
            (0.00, 0.84), (0.08, 0.76), (0.16, 0.51), (0.24, 0.22),
            (0.32, 0.38), (0.40, 0.66), (0.48, 0.86), (0.56, 0.52),
            (0.64, 0.30), (0.72, 0.12), (0.80, 0.12)
        ].map { completeSample(time: $0.0, wristY: $0.1) }
        let topDetection = SwingStageDetector.detect(samples: followThroughHigherThanTop)
            .detections.first(where: { $0.stage == .top })
        precondition(topDetection?.time == 0.24)

        let empty = SwingStageDetector.detect(samples: [])
        precondition(empty.detectedMarkers.isEmpty)
        precondition(empty.unresolvedStages == Set(SwingStage.allCases))
    }

    private static func completeSample(time: Double, wristY: CGFloat) -> SwingPoseSample {
        SwingPoseSample(
            time: time,
            leftWrist: CGPoint(x: 0.42, y: wristY), rightWrist: CGPoint(x: 0.58, y: wristY),
            leftElbow: CGPoint(x: 0.40, y: min(0.95, wristY + 0.08)), rightElbow: CGPoint(x: 0.60, y: min(0.95, wristY + 0.08)),
            leftShoulder: CGPoint(x: 0.40, y: 0.34), rightShoulder: CGPoint(x: 0.60, y: 0.34),
            leftHip: CGPoint(x: 0.43, y: 0.58), rightHip: CGPoint(x: 0.57, y: 0.58),
            head: CGPoint(x: 0.50, y: 0.16), spineAngle: 18, aggregateConfidence: 0.92
        )
    }
}

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
        precondition(result.detectedMarkers.map(\.stage) == SwingStage.allCases.map(\.rawValue))
        precondition(result.unresolvedStages.isEmpty)
        precondition(SwingStage.allCases.count == 8)
        precondition(SwingStage.allCases.contains(.leadArmParallelBackswing))

        let empty = SwingStageDetector.detect(samples: [])
        precondition(empty.detectedMarkers.isEmpty)
        precondition(empty.unresolvedStages == Set(SwingStage.allCases))
    }
}

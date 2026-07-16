import Foundation

@main
struct SwingPhaseTransitionSmoke {
    static func main() {
        let samples = [
            make(0.00, 0.82), make(0.08, 0.72), make(0.16, 0.48), make(0.24, 0.22),
            make(0.32, 0.23), make(0.40, 0.21), // P4 jitter, not P5.
            make(0.48, 0.38), make(0.56, 0.62), // sustained downswing; P6 is fast.
            make(0.64, 0.67), // lower hand position but slower, not impact.
            make(0.72, 0.50), make(0.80, 0.44), make(0.88, 0.44),
            make(0.96, 0.65), make(1.04, 0.65) // later clip tail, not P8.
        ]

        let detections = SwingStageDetector.detect(samples: samples).detections
        precondition(detections.first(where: { $0.stage == .leadArmParallelDownswing })?.time == 0.48)
        precondition(detections.first(where: { $0.stage == .impact })?.time == 0.56)
        precondition(detections.first(where: { $0.stage == .followThrough })?.time == 0.72)
        precondition(detections.first(where: { $0.stage == .finish })?.time == 0.88)
    }

    private static func make(_ time: Double, _ wristY: CGFloat) -> SwingPoseSample {
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

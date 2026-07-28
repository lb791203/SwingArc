import Foundation

@main
struct LeadArmResolutionSmoke {
    static func main() {
        let frames = (0..<9).map { index -> SwingFrameSample in
            let observesLeadArmCrossing = (3...5).contains(index)
            let pose = SwingPoseSample(
                time: Double(index) / 30,
                leftWrist: observesLeadArmCrossing
                    ? CGPoint(x: 0.10, y: 0.40)
                    : CGPoint(x: 0.38, y: 0.52),
                rightWrist: CGPoint(x: 0.60, y: 0.75),
                leftElbow: observesLeadArmCrossing
                    ? CGPoint(x: 0.25, y: 0.40)
                    : nil,
                rightElbow: CGPoint(x: 0.60, y: 0.58),
                leftShoulder: CGPoint(x: 0.40, y: 0.40),
                rightShoulder: CGPoint(x: 0.60, y: 0.40),
                leftHip: CGPoint(x: 0.43, y: 0.65),
                rightHip: CGPoint(x: 0.57, y: 0.65),
                head: CGPoint(x: 0.50, y: 0.20),
                spineAngle: 0,
                aggregateConfidence: 0.95
            )
            return SwingFrameSample(
                sourceFrameIndex: 1_000 + index,
                time: pose.time,
                pose: pose,
                objectEvidence: .empty
            )
        }

        let evidence = SwingFeatureExtractor.extract(frames: frames)
        precondition(
            evidence.allSatisfy { $0.leadArm == .left },
            "A long horizontal shoulder-to-wrist crossing must identify the lead arm even when the trailing arm is visible for more frames"
        )
    }
}

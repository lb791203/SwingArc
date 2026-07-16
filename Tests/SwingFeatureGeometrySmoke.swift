import Foundation

@main
struct SwingFeatureGeometrySmoke {
    static func main() {
        let pose = SwingPoseSample(
            time: 0,
            leftWrist: CGPoint(x: 0.20, y: 0.40),
            rightWrist: CGPoint(x: 0.58, y: 0.62),
            leftElbow: CGPoint(x: 0.35, y: 0.40),
            rightElbow: CGPoint(x: 0.63, y: 0.50),
            leftShoulder: CGPoint(x: 0.50, y: 0.40),
            rightShoulder: CGPoint(x: 0.65, y: 0.40),
            leftHip: CGPoint(x: 0.48, y: 0.62),
            rightHip: CGPoint(x: 0.62, y: 0.62),
            head: CGPoint(x: 0.55, y: 0.18),
            spineAngle: 0,
            aggregateConfidence: 0.95
        )

        precondition(abs(SwingGeometry.angleFromHorizontal(from: pose.leftShoulder!, to: pose.leftWrist!)) < 0.001)
        precondition(abs(SwingGeometry.jointAngle(a: pose.leftShoulder!, vertex: pose.leftElbow!, c: pose.leftWrist!) - 180) < 0.001)
        precondition(abs(SwingGeometry.lineAngle(from: pose.leftShoulder!, to: pose.rightShoulder!)) < 0.001)
        precondition(abs(SwingGeometry.lineAngle(from: pose.leftHip!, to: pose.rightHip!)) < 0.001)

        let object = SwingObjectEvidence(
            shaft: nil,
            ball: BallEvidence(center: CGPoint(x: 0.25, y: 0.80), radius: 0.012, confidence: 0.9),
            stableBall: CGPoint(x: 0.25, y: 0.80),
            ballLocalChange: 0
        )
        let frames = (0..<5).map { index in
            SwingFrameSample(
                sourceFrameIndex: index,
                time: Double(index) / 60,
                pose: pose,
                objectEvidence: object
            )
        }
        let evidence = SwingFeatureExtractor.extract(frames: frames)
        precondition(evidence.count == frames.count)
        precondition(evidence.allSatisfy { $0.leadArm == .left })
        precondition(evidence.allSatisfy { abs(($0.leadArmAngle ?? 90)) < 0.001 })
        precondition(evidence.allSatisfy { ($0.leadArmExtension ?? 0) > 179.9 })
    }
}

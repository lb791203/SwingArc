import Foundation

@main
struct PoseSampleFactorySmoke {
    static func main() {
        var pose = PoseEstimationResult()
        pose.keypoints["leftWrist"] = JointKeypoint(
            name: "leftWrist",
            position: CGPoint(x: 0.2, y: 0.7),
            confidence: 0.9
        )
        pose.keypoints["rightShoulder"] = JointKeypoint(
            name: "rightShoulder",
            position: CGPoint(x: 0.7, y: 0.3),
            confidence: 0.8
        )

        let sample = SwingPoseSample(time: 0.5, pose: pose)
        precondition(sample.leftWrist?.x == 0.2)
        precondition(sample.rightShoulder?.y == 0.3)
        precondition(sample.aggregateConfidence > 0.8)
    }
}

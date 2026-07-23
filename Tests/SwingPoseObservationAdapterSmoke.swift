import CoreGraphics
import Foundation

@main
struct SwingPoseObservationAdapterSmoke {
    static func main() {
        var pose = PoseEstimationResult()
        pose.keypoints["leftWrist"] = JointKeypoint(
            name: "leftWrist",
            position: CGPoint(x: 0.2, y: 0.4),
            confidence: 0.9
        )
        pose.keypoints["rightShoulder"] = JointKeypoint(
            name: "rightShoulder",
            position: CGPoint(x: 0.7, y: 0.3),
            confidence: 0.8
        )
        pose.headCenter = CGPoint(x: 0.5, y: 0.1)

        let frame = SwingPoseObservationAdapter.frame(
            pose: pose,
            sourceFrameIndex: 12,
            time: 0.4
        )
        precondition(frame.sourceFrameIndex == 12)
        precondition(frame.time == 0.4)
        precondition(frame.landmarks[.leftWrist]?.source == .visionPose)
        precondition(abs((frame.landmarks[.leftWrist]?.confidence ?? 0) - 0.9) < 0.000_001)
        precondition(frame.landmarks[.rightShoulder]?.point == .init(x: 0.7, y: 0.3))
        precondition(frame.landmarks[.head]?.point == .init(x: 0.5, y: 0.1))
        precondition(frame.landmarks[.handCenter]?.point == .init(x: 0.2, y: 0.4))
        precondition(frame.rawLandmarks[.handCenter] == nil)
        let poseSample = SwingPoseObservationAdapter.poseSample(from: frame)
        precondition(poseSample?.sourceFrameIndex == 12)
        precondition(poseSample?.leftWrist == CGPoint(x: 0.2, y: 0.4))
        precondition(poseSample?.rightShoulder == CGPoint(x: 0.7, y: 0.3))
        precondition(poseSample?.head == CGPoint(x: 0.5, y: 0.1))

        let absent = SwingPoseObservationAdapter.frame(
            pose: nil,
            sourceFrameIndex: 13,
            time: 0.433
        )
        precondition(absent.sourceFrameIndex == 13)
        precondition(absent.landmarks.isEmpty)
        precondition(absent.rawLandmarks.isEmpty)
        precondition(SwingPoseObservationAdapter.poseSample(from: absent) == nil)
    }
}

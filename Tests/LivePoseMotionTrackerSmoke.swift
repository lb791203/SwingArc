import Foundation
import CoreGraphics

@main
struct LivePoseMotionTrackerSmoke {
    static func main() {
        var tracker = LivePoseMotionTracker()
        let address = LivePoseLandmarks(
            leftShoulder: CGPoint(x: 0.4, y: 0.7),
            rightShoulder: CGPoint(x: 0.6, y: 0.7),
            leftHip: CGPoint(x: 0.44, y: 0.4),
            rightHip: CGPoint(x: 0.56, y: 0.4),
            leftWrist: CGPoint(x: 0.48, y: 0.35),
            rightWrist: CGPoint(x: 0.52, y: 0.35)
        )
        let first = tracker.ingest(landmarks: address, at: 0)
        precondition(first.personVisible)
        precondition(first.normalizedWristSpeed == 0)

        let moving = LivePoseLandmarks(
            leftShoulder: CGPoint(x: 0.4, y: 0.7),
            rightShoulder: CGPoint(x: 0.6, y: 0.7),
            leftHip: CGPoint(x: 0.44, y: 0.4),
            rightHip: CGPoint(x: 0.56, y: 0.4),
            leftWrist: CGPoint(x: 0.38, y: 0.62),
            rightWrist: CGPoint(x: 0.42, y: 0.62)
        )
        let second = tracker.ingest(landmarks: moving, at: 1.0 / 12.0)
        precondition(second.normalizedWristSpeed > 0.8)
        precondition(second.normalizedTorsoSpeed < 0.01)
        precondition(second.backswingDirectionScore > 0.5)

        var rotationTracker = LivePoseMotionTracker()
        _ = rotationTracker.ingest(landmarks: address, at: 0)
        let rotated = LivePoseLandmarks(
            leftShoulder: CGPoint(x: 0.46, y: 0.72),
            rightShoulder: CGPoint(x: 0.54, y: 0.68),
            leftHip: CGPoint(x: 0.46, y: 0.4),
            rightHip: CGPoint(x: 0.54, y: 0.4),
            leftWrist: CGPoint(x: 0.38, y: 0.62),
            rightWrist: CGPoint(x: 0.42, y: 0.62)
        )
        let rotation = rotationTracker.ingest(landmarks: rotated, at: 1.0 / 12.0)
        precondition(rotation.normalizedTorsoSpeed > 0.15)

        var translationTracker = LivePoseMotionTracker()
        _ = translationTracker.ingest(landmarks: address, at: 0)
        let translated = LivePoseLandmarks(
            leftShoulder: CGPoint(x: 0.5, y: 0.7),
            rightShoulder: CGPoint(x: 0.7, y: 0.7),
            leftHip: CGPoint(x: 0.54, y: 0.4),
            rightHip: CGPoint(x: 0.66, y: 0.4),
            leftWrist: CGPoint(x: 0.58, y: 0.35),
            rightWrist: CGPoint(x: 0.62, y: 0.35)
        )
        let translation = translationTracker.ingest(
            landmarks: translated,
            at: 1.0 / 12.0
        )
        precondition(translation.normalizedWristSpeed < 0.01)
        precondition(translation.normalizedTorsoSpeed < 0.01)

        let aboveShoulders = LivePoseLandmarks(
            leftShoulder: CGPoint(x: 0.4, y: 0.7),
            rightShoulder: CGPoint(x: 0.6, y: 0.7),
            leftHip: CGPoint(x: 0.44, y: 0.4),
            rightHip: CGPoint(x: 0.56, y: 0.4),
            leftWrist: CGPoint(x: 0.56, y: 0.82),
            rightWrist: CGPoint(x: 0.60, y: 0.82)
        )
        let third = tracker.ingest(landmarks: aboveShoulders, at: 2.0 / 12.0)
        precondition(third.followThroughScore > 0.5)

        let missing = tracker.ingestMissing(at: 3.0 / 12.0)
        precondition(!missing.personVisible)
        let afterMissing = tracker.ingest(landmarks: address, at: 4.0 / 12.0)
        precondition(afterMissing.normalizedWristSpeed == 0)

        let regressed = tracker.ingest(landmarks: moving, at: 0.1)
        precondition(regressed.normalizedWristSpeed == 0)
    }
}

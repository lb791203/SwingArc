import Foundation

@main
struct SwingTrajectoryTrackerSmoke {
    static func main() {
        var tracker = SwingTrajectoryTracker(maximumPredictionFrames: 2)
        let first = frame(index: 12, time: 0.4, wristX: 0.20)
        let second = frame(index: 13, time: 0.433, wristX: 0.23)
        _ = tracker.update(first)
        _ = tracker.update(second)

        let missing = SwingFrameObservation(
            sourceFrameIndex: 14,
            time: 0.466,
            landmarks: [:]
        )
        let predicted = tracker.update(missing)
        let predictedWrist = predicted.landmarks[.leftWrist]
        precondition(predictedWrist?.state == .estimated)
        precondition(predictedWrist?.source == .temporalPrediction)
        precondition(abs((predictedWrist?.point?.x ?? 0) - 0.26) < 0.001)
        precondition(predicted.rawLandmarks.isEmpty)

        let secondMissing = tracker.update(.init(
            sourceFrameIndex: 15,
            time: 0.5,
            landmarks: [:]
        ))
        precondition(secondMissing.landmarks[.leftWrist]?.state == .estimated)

        let beyondBound = tracker.update(.init(
            sourceFrameIndex: 16,
            time: 0.533,
            landmarks: [:]
        ))
        precondition(beyondBound.landmarks[.leftWrist]?.state == .missing)
        precondition(beyondBound.landmarks[.leftWrist]?.point == nil)

        let detectedAgain = tracker.update(frame(index: 17, time: 0.566, wristX: 0.41))
        precondition(detectedAgain.landmarks[.leftWrist]?.state == .detected)
        precondition(detectedAgain.landmarks[.leftWrist]?.source == .visionPose)

        var singlePointTracker = SwingTrajectoryTracker(maximumPredictionFrames: 2)
        _ = singlePointTracker.update(first)
        let zeroVelocityPrediction = singlePointTracker.update(.init(
            sourceFrameIndex: 13,
            time: 0.433,
            landmarks: [:]
        ))
        precondition(zeroVelocityPrediction.landmarks[.leftWrist]?.state == .estimated)
        precondition(zeroVelocityPrediction.landmarks[.leftWrist]?.point == .init(x: 0.20, y: 0.4))

        let batch = SwingTrajectoryTracker.track(
            [missing, second, first],
            maximumPredictionFrames: 2
        )
        precondition(batch.map(\.sourceFrameIndex) == [12, 13, 14])
        precondition(batch.map(\.time) == [0.4, 0.433, 0.466])
        precondition(batch.last?.landmarks[.leftWrist]?.state == .estimated)
    }

    private static func frame(index: Int, time: Double, wristX: Double) -> SwingFrameObservation {
        SwingFrameObservation(
            sourceFrameIndex: index,
            time: time,
            landmarks: [
                .leftWrist: TrackedSwingPoint(
                    point: .init(x: wristX, y: 0.4),
                    confidence: 0.9,
                    state: .detected,
                    source: .visionPose
                )
            ]
        )
    }
}

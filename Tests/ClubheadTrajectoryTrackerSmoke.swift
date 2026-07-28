import Foundation

@main
struct ClubheadTrajectoryTrackerSmoke {
    static func main() {
        var tracker = GolfObjectTrajectoryTracker(maximumPredictionFrames: 2)
        _ = tracker.update(
            observation: observation(clubheadX: 0.60, includesBodyPoint: true),
            sourceFrameIndex: 10,
            time: 0.333
        )
        let second = tracker.update(
            observation: observation(clubheadX: 0.65),
            sourceFrameIndex: 11,
            time: 0.366
        )
        precondition(second.landmarks[.clubhead]?.state == .detected)
        precondition(second.landmarks[.leftWrist] == nil)

        let predicted = tracker.update(
            observation: .empty,
            sourceFrameIndex: 12,
            time: 0.399
        )
        precondition(predicted.landmarks[.clubhead]?.state == .estimated)
        precondition(predicted.landmarks[.clubhead]?.source == .temporalPrediction)
        precondition(abs((predicted.landmarks[.clubhead]?.point?.x ?? 0) - 0.70) < 0.001)
        let evidence = TrackedGolfObjectEvidenceAdapter.evidence(
            from: predicted,
            stableBall: CGPoint(x: 0.8, y: 0.9),
            ballLocalChange: 0.2
        )
        precondition(evidence.trackedPoints[.clubhead]?.state == .estimated)
        precondition(evidence.stableBall == CGPoint(x: 0.8, y: 0.9))
        precondition(evidence.ballLocalChange == 0.2)

        let missing = tracker.update(
            observation: .empty,
            sourceFrameIndex: 14,
            time: 0.466
        )
        precondition(missing.landmarks[.clubhead]?.state == .missing)
        precondition(missing.rawLandmarks.isEmpty)
    }

    private static func observation(
        clubheadX: Double,
        includesBodyPoint: Bool = false
    ) -> GolfObjectObservation {
        var points: [SwingLandmark: TrackedSwingPoint] = [
            .clubhead: TrackedSwingPoint(
                point: .init(x: clubheadX, y: 0.6),
                confidence: 0.9,
                state: .detected,
                source: .coreMLGolf
            )
        ]
        if includesBodyPoint {
            points[.leftWrist] = TrackedSwingPoint(
                point: .init(x: 0.2, y: 0.3),
                confidence: 0.9,
                state: .detected,
                source: .visionPose
            )
        }
        return GolfObjectObservation(points: points)
    }
}

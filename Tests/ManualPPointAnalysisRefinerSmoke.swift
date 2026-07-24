import Foundation

@main
struct ManualPPointAnalysisRefinerSmoke {
    static func main() {
        let oldBody = frame(index: 8, x: 0.40)
        let oldClub = TrackedSwingPoint(
            point: NormalizedPoint(x: 0.72, y: 0.60),
            confidence: 0.80,
            state: .detected,
            source: .coreMLGolf
        )
        let existingAtTen = SwingFrameObservation(
            sourceFrameIndex: 10,
            time: 1.0,
            landmarks: [.clubhead: oldClub]
        )
        let exactBody = frame(index: 10, x: 0.55)

        let result = ManualPPointAnalysisRefiner.merging(
            exactBodyFrame: exactBody,
            intoFrames: [oldBody, existingAtTen],
            poseSamples: [SwingPoseObservationAdapter.poseSample(from: oldBody)!]
        )

        precondition(result.frames.map(\.sourceFrameIndex) == [8, 10])
        let refined = result.frames[1]
        precondition(refined.landmarks[.leftWrist]?.point?.x == 0.55)
        precondition(refined.landmarks[.clubhead] == oldClub)
        precondition(result.poseSamples.map(\.sourceFrameIndex) == [8, 10])
        precondition(result.poseSamples[1].leftWrist?.x == 0.55)
    }

    private static func frame(
        index: Int,
        x: Double
    ) -> SwingFrameObservation {
        let point = TrackedSwingPoint(
            point: NormalizedPoint(x: x, y: 0.50),
            confidence: 0.95,
            state: .detected,
            source: .visionPose
        )
        return SwingFrameObservation(
            sourceFrameIndex: index,
            time: Double(index) / 10,
            landmarks: [
                .leftWrist: point,
                .rightWrist: point,
                .leftShoulder: point,
                .rightShoulder: point,
                .leftHip: point,
                .rightHip: point
            ]
        )
    }
}

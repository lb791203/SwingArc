import Foundation

@main
struct SwingTrajectoryPresentationSmoke {
    static func main() {
        precondition(
            SwingTrajectoryPresentationPolicy.landmarks(for: .setup) == [
                .head,
                .leftShoulder,
                .rightShoulder,
                .leftHip,
                .rightHip,
                .leftKnee,
                .rightKnee,
                .leftAnkle,
                .rightAnkle,
                .handCenter
            ]
        )
        precondition(
            SwingTrajectoryPresentationPolicy.landmarks(for: .handPath)
                == [.handCenter]
        )
        precondition(
            SwingTrajectoryPresentationPolicy.style(
                for: TrackedSwingPoint(
                    point: NormalizedPoint(x: 0.5, y: 0.5),
                    confidence: 0.9,
                    state: .detected,
                    source: .visionPose
                )
            ) == .measured
        )
        precondition(
            SwingTrajectoryPresentationPolicy.style(
                for: TrackedSwingPoint(
                    point: NormalizedPoint(x: 0.5, y: 0.5),
                    confidence: 0.8,
                    state: .estimated,
                    source: .temporalPrediction
                )
            ) == .estimated
        )
        precondition(
            SwingTrajectoryPresentationPolicy.style(
                for: TrackedSwingPoint(
                    point: nil,
                    confidence: 0,
                    state: .missing,
                    source: .visionPose
                )
            ) == .hidden
        )
    }
}

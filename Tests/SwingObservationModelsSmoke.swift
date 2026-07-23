import Foundation

@main
struct SwingObservationModelsSmoke {
    static func main() throws {
        try verifyTrackedPointRoundTrip()
        try verifyRawAndTrackedValuesRemainDistinct()
        try verifyArtifactRoundTripAndUnsupportedMetrics()
    }

    private static func verifyTrackedPointRoundTrip() throws {
        let point = TrackedSwingPoint(
            point: NormalizedPoint(x: 0.25, y: 0.5),
            confidence: 0.92,
            state: .detected,
            source: .visionPose
        )
        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(TrackedSwingPoint.self, from: data)
        precondition(decoded == point)
        precondition(!point.isEstimated)

        let prediction = TrackedSwingPoint(
            point: NormalizedPoint(x: 0.27, y: 0.51),
            confidence: 0.55,
            state: .estimated,
            source: .temporalPrediction
        )
        precondition(prediction.isEstimated)
        precondition(!prediction.isMeasured)
    }

    private static func verifyRawAndTrackedValuesRemainDistinct() throws {
        let raw = TrackedSwingPoint(
            point: NormalizedPoint(x: 0.2, y: 0.4),
            confidence: 0.8,
            state: .detected,
            source: .visionPose
        )
        let tracked = TrackedSwingPoint(
            point: NormalizedPoint(x: 0.21, y: 0.39),
            confidence: 0.8,
            state: .detected,
            source: .visionPose
        )
        let frame = SwingFrameObservation(
            sourceFrameIndex: 12,
            time: 0.4,
            landmarks: [.leftWrist: tracked],
            rawLandmarks: [.leftWrist: raw]
        )
        precondition(frame.rawLandmarks[.leftWrist] == raw)
        precondition(frame.landmarks[.leftWrist] == tracked)

        let trajectory = SwingTrajectory.make(
            landmark: .leftWrist,
            frames: [frame]
        )
        precondition(trajectory.samples.count == 1)
        precondition(trajectory.samples[0].sourceFrameIndex == 12)
        precondition(trajectory.samples[0].value == tracked)
    }

    private static func verifyArtifactRoundTripAndUnsupportedMetrics() throws {
        precondition(!SwingMetricID.trueClubheadSpeed.isSupportedBySingleCamera)
        precondition(SwingMetricID.clubheadRelativeSpeed2D.isSupportedBySingleCamera)

        let unsupported = SwingMetricValue(
            id: .trueClubheadSpeed,
            value: nil,
            unit: "mph",
            confidence: 0,
            stage: nil,
            availability: .unavailable(reason: .requiresCalibrated3DOrSensor)
        )
        let artifact = SwingAnalysisArtifact(
            schemaVersion: SwingAnalysisArtifact.currentSchemaVersion,
            modelVersion: "baseline-vision-v1",
            view: "dtl",
            sourceFrameRate: 30,
            qualityIssues: [],
            frames: [],
            stages: [
                SwingStageArtifact(
                    code: "P6",
                    sourceFrameIndex: nil,
                    time: nil,
                    confidence: 0,
                    status: "unresolved",
                    evidenceSources: [],
                    manuallyLocked: false
                )
            ],
            metrics: [unsupported]
        )
        let data = try JSONEncoder().encode(artifact)
        let decoded = try JSONDecoder().decode(SwingAnalysisArtifact.self, from: data)
        precondition(decoded == artifact)
        precondition(decoded.metrics[0].value == nil)
    }
}

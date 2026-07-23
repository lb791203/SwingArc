import Foundation

@main
struct SwingMetricEngineSmoke {
    static func main() {
        testMotionOnlyOutputs()
        testEstimatedEvidenceIsUnavailable()
    }

    private static func testMotionOnlyOutputs() {
        let stages = [
            detection(.address, frame: 10, time: 1.0),
            detection(.takeaway, frame: 11, time: 1.1),
            detection(.leadArmParallelBackswing, frame: 12, time: 1.2),
            detection(.top, frame: 13, time: 1.3),
            detection(.leadArmParallelDownswing, frame: 14, time: 1.4),
            detection(.shaftParallelDownswing, frame: 15, time: 1.5),
            detection(.impact, frame: 16, time: 1.6)
        ]
        let frames = (10...16).map { index in
            bodyFrame(
                index: index,
                time: Double(index) / 10,
                handX: 0.30 + Double(index - 10) * 0.05,
                headX: 0.50 + Double(index - 10) * 0.005
            )
        }

        let measurements = SwingMetricEngine.motionMeasurements(
            frames: frames,
            stages: stages,
            personHeight: 0.8
        )

        precondition(!measurements.isEmpty)
        precondition(measurements.allSatisfy { $0.id.isMotionAnalysisOutput })
        precondition(measurements.allSatisfy { $0.id.userFacingTitle != nil })
        precondition(measurements.contains { $0.id == .tempoRatio })
        precondition(measurements.contains { $0.id == .handPathLength })
        precondition(!measurements.contains { forbiddenMetricIDs.contains($0.id) })
        precondition(SwingMetricID.trueClubheadSpeed.userFacingTitle == nil)
    }

    private static func testEstimatedEvidenceIsUnavailable() {
        let measured = bodyFrame(index: 20, time: 2.0, handX: 0.3, headX: 0.5)
        let estimated = bodyFrame(
            index: 21,
            time: 2.1,
            handX: 0.4,
            headX: 0.5,
            estimatedHand: true
        )

        let value = SwingMetricEngine.pathLength(
            landmark: .handCenter,
            frames: [measured, estimated],
            personHeight: 0.8,
            id: .handPathLength
        )

        precondition(value.availability == .unavailable(reason: .estimatedInput))
    }

    private static let forbiddenMetricIDs: Set<SwingMetricID> = [
        .trueClubheadSpeed,
        .attackAngle,
        .faceAngle,
        .dynamicLoft,
        .ballSpeed,
        .launchAngle,
        .spinRate,
        .carryDistance
    ]

    private static func detection(
        _ stage: SwingStage,
        frame: Int,
        time: Double
    ) -> SwingStageDetection {
        SwingStageDetection(
            stage: stage,
            time: time,
            sourceFrameIndex: frame,
            confidence: 0.9,
            status: .confirmed
        )
    }

    private static func bodyFrame(
        index: Int,
        time: Double,
        handX: Double,
        headX: Double,
        estimatedHand: Bool = false
    ) -> SwingFrameObservation {
        func point(
            _ x: Double,
            _ y: Double,
            state: SwingPointState = .detected,
            source: SwingPointSource = .visionPose
        ) -> TrackedSwingPoint {
            TrackedSwingPoint(
                point: NormalizedPoint(x: x, y: y),
                confidence: 0.9,
                state: state,
                source: source
            )
        }

        return SwingFrameObservation(
            sourceFrameIndex: index,
            time: time,
            landmarks: [
                .head: point(headX, 0.86),
                .leftShoulder: point(0.43, 0.72),
                .rightShoulder: point(0.57, 0.72),
                .leftHip: point(0.45, 0.50),
                .rightHip: point(0.55, 0.50),
                .leftKnee: point(0.45, 0.28),
                .rightKnee: point(0.55, 0.28),
                .leftAnkle: point(0.44, 0.06),
                .rightAnkle: point(0.56, 0.06),
                .handCenter: estimatedHand
                    ? point(
                        handX,
                        0.58,
                        state: .estimated,
                        source: .temporalPrediction
                    )
                    : point(handX, 0.58)
            ]
        )
    }
}

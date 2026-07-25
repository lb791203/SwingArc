import Foundation

@main
struct SwingFeedbackPipelineSmoke {
    static func main() {
        let output = fixtureOutput()
        precondition(
            SwingFeedbackPipeline.make(
                output: output,
                manualMarkers: []
            ) != nil
        )

        let manualTop = KeyframeMarker(
            time: 4.0 / 60.0,
            stage: .top,
            source: .manual,
            sourceFrameIndex: 6
        )
        guard let result = SwingFeedbackPipeline.make(
            output: output,
            manualMarkers: [manualTop]
        ) else {
            preconditionFailure("Expected simplified feedback pipeline result")
        }

        precondition(result.feedback.cards.count == 5)
        precondition(
            result.detections.first(where: { $0.stage == .top })?
                .sourceFrameIndex == 6
        )
        precondition(
            result.artifact.stages.first(where: { $0.code == "P4" })?
                .manuallyLocked == true
        )
        precondition(result.artifact.metrics.allSatisfy {
            $0.id.isMotionAnalysisOutput
        })
    }

    private static func fixtureOutput() -> SwingVideoAnalysisOutput {
        let detections = SwingStage.pStages.enumerated().map {
            offset,
            stage in
            SwingStageDetection(
                stage: stage,
                time: Double(offset) / 60,
                sourceFrameIndex: offset,
                confidence: 0.9,
                status: .confirmed,
                hasClubEvidence: [
                    SwingStage.takeaway,
                    .shaftParallelDownswing,
                    .followThrough
                ].contains(stage),
                hasBallEvidence: stage == .impact,
                hasBallChangeEvidence: stage == .impact
            )
        }
        let frames = SwingStage.pStages.enumerated().map {
            offset,
            stage in
            frame(index: offset, stage: stage)
        }
        return SwingVideoAnalysisOutput(
            view: .downTheLine,
            result: SwingAnalysisResult(
                detectedMarkers: detections.compactMap(\.marker),
                unresolvedStages: [],
                detections: detections
            ),
            poseSamples: frames.compactMap(
                SwingPoseObservationAdapter.poseSample(from:)
            ),
            leadArm: .left,
            adaptiveWindow: SwingWindow(startTime: 0, endTime: 1),
            sourceFrameRate: 60,
            elapsedSeconds: 0.1,
            observationFrames: frames
        )
    }

    private static func frame(
        index: Int,
        stage: SwingStage
    ) -> SwingFrameObservation {
        func point(
            _ x: Double,
            _ y: Double,
            source: SwingPointSource = .visionPose
        ) -> TrackedSwingPoint {
            TrackedSwingPoint(
                point: NormalizedPoint(x: x, y: y),
                confidence: 0.9,
                state: .detected,
                source: source
            )
        }

        var landmarks: [SwingLandmark: TrackedSwingPoint] = [
            .head: point(0.50, 0.86),
            .leftShoulder: point(0.43, 0.72),
            .rightShoulder: point(0.57, 0.72),
            .leftElbow: point(0.42, 0.62),
            .rightElbow: point(0.58, 0.62),
            .leftWrist: point(0.36, 0.58),
            .rightWrist: point(0.40, 0.58),
            .leftHip: point(0.45, 0.50),
            .rightHip: point(0.55, 0.50),
            .leftKnee: point(0.45, 0.28),
            .rightKnee: point(0.55, 0.28),
            .leftAnkle: point(0.44, 0.06),
            .rightAnkle: point(0.56, 0.06),
            .handCenter: point(0.38, 0.58)
        ]
        if [
            SwingStage.takeaway,
            .shaftParallelDownswing,
            .followThrough
        ].contains(stage) {
            landmarks[.shaftStart] = point(
                0.38,
                0.58,
                source: .coreMLGolf
            )
            landmarks[.shaftEnd] = point(
                0.62,
                0.42,
                source: .coreMLGolf
            )
        }
        if stage == .impact {
            landmarks[.clubhead] = point(
                0.68,
                0.10,
                source: .coreMLGolf
            )
            landmarks[.ball] = point(
                0.70,
                0.08,
                source: .coreMLGolf
            )
        }
        return SwingFrameObservation(
            sourceFrameIndex: index,
            time: Double(index) / 60,
            landmarks: landmarks
        )
    }
}

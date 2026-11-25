import Foundation
import CoreMedia

@main
struct TechniqueFeedbackPresentationSmoke {
    static func main() {
        let finding = TechniqueFinding(
            kind: .overTheTop,
            severity: .attention,
            evidence: TechniqueEvidence(
                stages: [.takeaway, .top, .impact],
                normalizedMagnitude: 0.21
            )
        )
        let confirmed = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: [.takeaway, .top, .impact].enumerated().map { index, stage in
                SwingStageDetection(
                    stage: stage,
                    time: Double(index) / 30,
                    sourceFrameIndex: index,
                    confidence: 0.9,
                    status: .confirmed
                )
            }
        )
        let model = TechniqueFeedbackPresentation.make(
            feedback: .finding(finding),
            analysis: confirmed
        )
        precondition(model.title == "下杆略偏外")
        precondition(model.showsEvidence)
        precondition(model.drill?.identifier == "path-towel")

        let unresolved = TechniqueFeedbackPresentation.make(
            feedback: .unresolved,
            analysis: SwingAnalysisResult(
                detectedMarkers: [],
                unresolvedStages: [.impact]
            )
        )
        precondition(unresolved.title == "本球未能判定")
        precondition(!unresolved.showsEvidence)
        precondition(unresolved.drill == nil)

        let incompleteFinding = TechniqueFeedbackPresentation.make(
            feedback: .finding(finding),
            analysis: SwingAnalysisResult(
                detectedMarkers: [],
                unresolvedStages: [.top],
                detections: [
                    SwingStageDetection(
                        stage: .takeaway,
                        time: 0,
                        sourceFrameIndex: 0,
                        confidence: 0.9,
                        status: .confirmed
                    ),
                    SwingStageDetection(
                        stage: .top,
                        time: 1.0 / 30,
                        sourceFrameIndex: nil,
                        confidence: 0,
                        status: .lowConfidence
                    ),
                    SwingStageDetection(
                        stage: .impact,
                        time: 2.0 / 30,
                        sourceFrameIndex: 2,
                        confidence: 0.9,
                        status: .confirmed
                    )
                ]
            )
        )
        precondition(!incompleteFinding.showsEvidence)
        precondition(incompleteFinding.drill == nil)

        let automaticTop = SwingStageDetection(
            stage: .top,
            time: 10.0 / 240.0,
            sourceFrameIndex: 10,
            confidence: 0.9,
            status: .confirmed
        )
        let manualTop = KeyframeMarker(
            time: 14.0 / 240.0,
            stage: .top,
            source: .manual
        )
        let corrected = ManualStageDetectionPolicy.applying(
            manualMarkers: [manualTop],
            sourceFrameRate: 240,
            automatic: [automaticTop],
            availablePoseSamples: [sample(frame: 14)]
        )
        precondition(corrected[0].sourceFrameIndex == 14)
        precondition(corrected[0].status == .confirmed)
        precondition(corrected[0].evidence.sources == [.manual])
        let unsupportedCorrection = ManualStageDetectionPolicy.applying(
            manualMarkers: [manualTop],
            sourceFrameRate: 240,
            automatic: [automaticTop],
            availablePoseSamples: []
        )
        precondition(unsupportedCorrection[0].status == .lowConfidence)
        precondition(
            unsupportedCorrection[0].evidence.sources == [.manual]
        )

        // Older project: P4 stored as frame 100 but its time is frame 102.
        let legacyTop = KeyframeMarker(
            time: 102.0 / 240.0,
            stage: .top,
            source: .manual,
            sourceFrameIndex: 100
        )
        let legacy = ManualStageDetectionPolicy.applying(
            manualMarkers: [legacyTop],
            sourceFrameRate: 240,
            automatic: [automaticTop],
            availablePoseSamples: [sample(frame: 102)]
        )
        precondition(legacy[0].sourceFrameIndex == 102 && legacy[0].status == .confirmed,
                     "A stale stored frame must follow the marker time to the pose at 102")
        let staleOnly = ManualStageDetectionPolicy.applying(
            manualMarkers: [legacyTop],
            sourceFrameRate: 240,
            automatic: [automaticTop],
            availablePoseSamples: [sample(frame: 100)]
        )
        precondition(staleOnly[0].sourceFrameIndex != 100 && staleOnly[0].status == .lowConfidence,
                     "A pose at the stale index must not be used for feedback")

        // Variable frame rate: frame 3 at 0.300 s, frame 5 at 0.308 s (the
        // average half frame at 30 fps is 16.7 ms). A marker at 0.308 s
        // stored as frame 3 must use frame 5.
        func vfrSample(frame: Int, time: Double) -> SwingPoseSample {
            let base = sample(frame: frame)
            return SwingPoseSample(
                time: time,
                leftWrist: nil, rightWrist: nil, leftElbow: nil, rightElbow: nil,
                leftShoulder: nil, rightShoulder: nil, leftHip: nil, rightHip: nil,
                head: nil, spineAngle: nil, aggregateConfidence: base.aggregateConfidence,
                sourceFrameIndex: frame
            )
        }
        let vfrMarker = KeyframeMarker(time: 0.308, stage: .top, source: .manual, sourceFrameIndex: 3)
        let vfrTimeline = SourceFrameTimeline(
            presentationTimes: [0, 0.10, 0.20, 0.300, 0.304, 0.308, 0.312, 0.40].map {
                CMTime(seconds: $0, preferredTimescale: 60_000)
            }
        )!
        let staleVFRPose = vfrSample(frame: 3, time: 0.300)
        let vfr = ManualStageDetectionPolicy.applying(
            manualMarkers: [vfrMarker],
            sourceFrameRate: vfrTimeline.averageFrameRate!,
            automatic: [automaticTop],
            availablePoseSamples: [staleVFRPose, vfrSample(frame: 5, time: 0.308)],
            sourceFrameTimeline: vfrTimeline
        )
        precondition(vfr[0].sourceFrameIndex == 5 && vfr[0].status == .confirmed,
                     "VFR: the pose nearest the marker time (frame 5) must be used, got \(String(describing: vfr[0].sourceFrameIndex))")

        let vfrMissingTarget = ManualStageDetectionPolicy.applying(
            manualMarkers: [vfrMarker],
            sourceFrameRate: vfrTimeline.averageFrameRate!,
            automatic: [automaticTop],
            availablePoseSamples: [staleVFRPose, vfrSample(frame: 4, time: 0.304)],
            sourceFrameTimeline: vfrTimeline
        )
        precondition(
            vfrMissingTarget[0].sourceFrameIndex == 5 && vfrMissingTarget[0].status == .lowConfidence,
            "VFR: missing target pose must keep the correct frame without promoting a neighbour"
        )
    }

    private static func sample(frame: Int) -> SwingPoseSample {
        SwingPoseSample(
            time: Double(frame) / 240,
            leftWrist: nil,
            rightWrist: nil,
            leftElbow: nil,
            rightElbow: nil,
            leftShoulder: nil,
            rightShoulder: nil,
            leftHip: nil,
            rightHip: nil,
            head: nil,
            spineAngle: nil,
            aggregateConfidence: 1,
            sourceFrameIndex: frame
        )
    }
}

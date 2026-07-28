import Foundation
import SwiftUI

@main
struct ConservativeStagePersistenceSmoke {
    static func main() throws {
        let suiteName = "ConservativeStagePersistenceSmoke-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let videoURL = URL(fileURLWithPath: "/tmp/conservative-stage.mp4")
        let evidence = KeyframeEvidenceSnapshot(
            sources: [.bodyPose, .temporalTransition],
            detectedPointCount: 2,
            estimatedPointCount: 1,
            hasClubEvidence: false,
            hasBallEvidence: false,
            hasBallChangeEvidence: false
        )
        let lowConfidence = KeyframeMarker(
            time: 1.25,
            stage: .takeaway,
            source: .automatic,
            sourceFrameIndex: 75,
            automaticStatus: .lowConfidence,
            automaticConfidence: 0.48,
            automaticEvidence: evidence
        )
        let confirmed = KeyframeMarker(
            time: 0.75,
            stage: .address,
            source: .automatic,
            sourceFrameIndex: 45,
            automaticStatus: .confirmed,
            automaticConfidence: 0.91,
            automaticEvidence: evidence
        )
        let persistedManual = KeyframeMarker(
            time: 1.75,
            stage: .leadArmParallelBackswing,
            source: .manual,
            sourceFrameIndex: 105
        )
        let project = LocalAnalysisProject(
            drawings: [],
            keyframes: [lowConfidence, confirmed, persistedManual],
            isKeyframeMode: false,
            showPoseSkeleton: false,
            showHeadStability: false,
            showSpineAngle: false,
            showGrid: false
        )

        precondition(LocalProjectStore.save(project, for: videoURL, defaults: defaults))
        guard let reopened = LocalProjectStore.load(for: videoURL, defaults: defaults),
              let reopenedMarker = reopened.keyframes.first else {
            preconditionFailure("Saved automatic marker must reopen")
        }
        precondition(reopenedMarker.automaticStatus == .lowConfidence)
        precondition(reopenedMarker.automaticConfidence == 0.48)
        precondition(reopenedMarker.automaticEvidence == evidence)
        precondition(StageResultPolicy.state(for: reopenedMarker) == .review)
        precondition(StageResultPresentation.label(for: .review) == "待核对")
        precondition(
            !AutomaticAnalysisPolicy.shouldAnalyze(event: .projectReopened),
            "Reopening a persisted project must not trigger automatic reanalysis"
        )

        var predictedFrames: [PPointCode: Int] = [:]
        var suggestedFrames: [PPointCode: Int] = [:]
        var manualFrames: [PPointCode: Int] = [:]
        for marker in reopened.keyframes {
            guard let stage = SwingStage(rawValue: marker.stage),
                  let stageIndex = SwingStage.pStages.firstIndex(of: stage),
                  let frame = marker.sourceFrameIndex else {
                preconditionFailure("Persisted correction markers need exact frames")
            }
            let kind = PPointCorrectionMarkerPolicy.kind(
                isManual: marker.source == .manual,
                automaticIsConfirmed: marker.automaticStatus == .confirmed
            )
            PPointCorrectionMarkerPolicy.apply(
                code: PPointCode.allCases[stageIndex],
                frame: frame,
                kind: kind,
                predictedFrames: &predictedFrames,
                suggestedFrames: &suggestedFrames,
                manualFrames: &manualFrames
            )
        }
        let correction = PPointCorrectionState(
            frameCount: 180,
            predictedFrames: predictedFrames,
            suggestedFrames: suggestedFrames,
            manualFrames: manualFrames
        )
        precondition(correction.selection(for: .p1).source == .automatic)
        precondition(correction.selection(for: .p1).sourceFrameIndex == 45)
        precondition(correction.selection(for: .p2).source == .review)
        precondition(correction.selection(for: .p2).sourceFrameIndex == nil)
        precondition(
            correction.selection(for: .p2).suggestedSourceFrameIndex == 75
        )
        precondition(
            PPointSelectionPresentation.label(
                for: correction.selection(for: .p2).source
            ) == "待核对"
        )
        precondition(correction.selection(for: .p3).source == .manual)
        precondition(correction.selection(for: .p3).sourceFrameIndex == 105)

        let legacyAutomaticJSON = """
        {
          "id": "\(UUID().uuidString)",
          "time": 0.75,
          "stage": "起杆 (Takeaway)",
          "source": "automatic",
          "sourceFrameIndex": 45
        }
        """.data(using: .utf8)!
        let legacyAutomatic = try JSONDecoder().decode(
            KeyframeMarker.self,
            from: legacyAutomaticJSON
        )
        precondition(
            legacyAutomatic.automaticStatus == .lowConfidence,
            "Status-less legacy automatic markers must migrate to review"
        )
        precondition(StageResultPolicy.state(for: legacyAutomatic) == .review)

        let manual = KeyframeMarker(
            time: 0.8,
            stage: .takeaway,
            source: .manual,
            sourceFrameIndex: 48
        )
        precondition(manual.isLocked)
        precondition(manual.automaticStatus == nil)
        precondition(StageResultPolicy.state(for: manual) == .manual)
        precondition(StageResultPresentation.label(for: .manual) == "已识别")
        precondition(StageResultPolicy.state(for: nil) == .unresolved)
        precondition(StageResultPresentation.label(for: .unresolved) == "未识别")

        let detection = SwingStageDetection(
            stage: .impact,
            time: 1.4,
            sourceFrameIndex: 84,
            confidence: 0.91,
            status: .confirmed,
            hasClubEvidence: true,
            hasBallEvidence: true,
            hasBallChangeEvidence: true,
            evidence: StageEvidenceSummary(
                sources: [.bodyPose, .shaft, .ball],
                detectedPointCount: 3,
                estimatedPointCount: 0
            )
        )
        guard let detectedMarker = detection.marker else {
            preconditionFailure("Resolved detector output must produce a marker")
        }
        precondition(detectedMarker.sourceFrameIndex == 84)
        precondition(detectedMarker.automaticStatus == .confirmed)
        precondition(detectedMarker.automaticConfidence == 0.91)
        precondition(
            detectedMarker.automaticEvidence?.sources
                == [.bodyPose, .shaft, .ball]
        )
        precondition(detectedMarker.automaticEvidence?.hasClubEvidence == true)
        precondition(detectedMarker.automaticEvidence?.hasBallEvidence == true)
        precondition(
            detectedMarker.automaticEvidence?.hasBallChangeEvidence == true
        )
    }
}

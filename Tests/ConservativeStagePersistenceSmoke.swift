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
            stage: .followThrough,
            source: .automatic,
            sourceFrameIndex: 75,
            automaticStatus: .lowConfidence,
            automaticConfidence: 0.48,
            automaticEvidence: evidence
        )
        let project = LocalAnalysisProject(
            drawings: [],
            keyframes: [lowConfidence],
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

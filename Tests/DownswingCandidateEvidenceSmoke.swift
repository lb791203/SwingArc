import Foundation

@main
struct DownswingCandidateEvidenceSmoke {
    static func main() {
        let skippedCrossingEvidence = ParallelStageEvidence.downswingArmHorizontalEvidence(
            angle: 23.9
        )
        precondition(
            skippedCrossingEvidence > 0.20,
            "A 30 FPS clip may skip the exact horizontal frame; the nearest observed arm position must remain a low-confidence P5 candidate"
        )
        precondition(
            ParallelStageEvidence.downswingArmHorizontalEvidence(angle: 31) == 0
        )
        let occludedElbowScore = ParallelStageEvidence.downswingScore(
            armHorizontal: 0.522,
            armExtension: 0,
            downward: 1,
            hipOpen: 0.105,
            coverage: 1
        )
        precondition(occludedElbowScore > 0.30 && occludedElbowScore < 0.32)
        precondition(
            ParallelStageEvidence.shouldRetainDownswingCandidate(
                score: occludedElbowScore
            ),
            "Observed horizontal-arm and downswing evidence must survive as a low-confidence P5 candidate when only the elbow is occluded"
        )
        precondition(
            !ParallelStageEvidence.shouldRetainDownswingCandidate(score: 0.249)
        )
    }
}

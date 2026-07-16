import Foundation

@main
struct TwoStageScanBudgetSmoke {
    static func main() {
        precondition(
            !TwoStageScanPolicy.extractsObjectEvidence(during: .coarse),
            "Full-video coarse scanning must not run contour-based club/ball detection"
        )
        precondition(
            TwoStageScanPolicy.extractsObjectEvidence(during: .fine),
            "Club and ball evidence is required only inside the located swing window"
        )

        let coarseFrameCount = SwingWindowLocator.sampleTimes(duration: 25.19).count
        precondition(coarseFrameCount >= 200)
    }
}

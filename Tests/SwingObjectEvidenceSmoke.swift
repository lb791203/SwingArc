import Foundation

@main
struct SwingObjectEvidenceSmoke {
    static func main() {
        let hands = CGPoint(x: 0.50, y: 0.60)
        let ball = CGPoint(x: 0.70, y: 0.80)
        let connected = ClubShaftEvidence(
            start: hands,
            end: CGPoint(x: 0.60, y: 0.70),
            confidence: 0.9
        )
        precondition(connected.isConnected(to: hands, tolerance: 0.03))
        precondition(connected.distanceFromExtendedLine(to: ball) < 0.001)
        precondition(abs(connected.length - sqrt(0.02)) < 0.001)

        let disconnected = ClubShaftEvidence(
            start: CGPoint(x: 0.05, y: 0.10),
            end: CGPoint(x: 0.15, y: 0.20),
            confidence: 0.9
        )
        precondition(!disconnected.isConnected(to: hands, tolerance: 0.08))

        var tracker = BallPositionTracker(requiredHits: 3, maximumMisses: 2)
        for (frame, offset) in zip(100...102, [-0.002, 0, 0.002]) {
            _ = tracker.update(
                BallEvidence(
                    center: CGPoint(x: 0.70 + offset, y: 0.80),
                    radius: 0.012,
                    confidence: 0.9
                ),
                sourceFrameIndex: frame
            )
        }
        precondition(tracker.stableBall != nil)

        let firstMiss = tracker.update(nil, sourceFrameIndex: 103)
        precondition(firstMiss.stableBall != nil)
        precondition(
            firstMiss.localChange == 0,
            "One contour miss must not become impact evidence"
        )
        let lockedCenter = firstMiss.stableBall?.center
        let secondMiss = tracker.update(nil, sourceFrameIndex: 104)
        precondition(secondMiss.stableBall != nil)
        precondition(secondMiss.localChange == 0)
        let sustainedLoss = tracker.update(nil, sourceFrameIndex: 105)
        precondition(sustainedLoss.localChange == 1)
        precondition(
            sustainedLoss.stableBall?.center == lockedCenter,
            "The address ball location must remain locked after the ball leaves at impact"
        )

        verifySparseMissesDoNotAccumulateIntoImpactEvidence()
    }

    private static func verifySparseMissesDoNotAccumulateIntoImpactEvidence() {
        let ball = BallEvidence(
            center: CGPoint(x: 0.70, y: 0.80),
            radius: 0.012,
            confidence: 0.9
        )
        var tracker = BallPositionTracker(requiredHits: 3, maximumMisses: 2)
        for frame in 10...12 {
            _ = tracker.update(ball, sourceFrameIndex: frame)
        }

        // Sparse P1/P2/P6/P8 neighborhoods are independent observations. A miss
        // in each neighborhood must never add up to a false impact event.
        for frame in [100, 200, 300] {
            let isolatedMiss = tracker.update(nil, sourceFrameIndex: frame)
            precondition(isolatedMiss.localChange == 0)
        }

        precondition(tracker.update(nil, sourceFrameIndex: 400).localChange == 0)
        precondition(tracker.update(nil, sourceFrameIndex: 401).localChange == 0)
        precondition(
            tracker.update(nil, sourceFrameIndex: 402).localChange == 1,
            "Only a contiguous source-frame loss may become impact evidence"
        )
    }
}

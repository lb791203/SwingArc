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

        let coarseFrameCount = SwingCoreLocator.sampleTimes(duration: 25.19).count
        precondition(coarseFrameCount >= 200)

        let windows = [
            SwingWindow(startTime: 13.5, endTime: 16.5),
            SwingWindow(startTime: 13.0, endTime: 16.5),
            SwingWindow(startTime: 12.5, endTime: 16.5),
            SwingWindow(startTime: 12.0, endTime: 16.5),
            SwingWindow(startTime: 12.0, endTime: 17.0),
            SwingWindow(startTime: 12.0, endTime: 17.5)
        ]
        var cached = Set<Int>()
        var requestedInOrder: [Int] = []
        var priorCachedCount = 0
        for window in windows {
            let references = FineSwingSamplingPlan.frames(
                window: window,
                sourceFrameRate: 60,
                duration: 25.19
            )
            let missing = references.filter { !cached.contains($0.sourceFrameIndex) }
            let missingIndices = missing.map(\.sourceFrameIndex)
            precondition(Set(missingIndices).count == missingIndices.count)
            precondition(cached.isDisjoint(with: missingIndices), "A source frame was requested twice")
            cached.formUnion(missingIndices)
            requestedInOrder.append(contentsOf: missingIndices)
            precondition(cached.count >= priorCachedCount, "Adaptive expansion must add frames monotonically")
            priorCachedCount = cached.count
        }

        precondition(Set(requestedInOrder).count == requestedInOrder.count)
        let sortedUnion = cached.sorted()
        precondition(sortedUnion == Array(sortedUnion.first!...sortedUnion.last!))
        let finalPlan = FineSwingSamplingPlan.frames(
            window: windows.last!,
            sourceFrameRate: 60,
            duration: 25.19
        )
        precondition(sortedUnion == finalPlan.map(\.sourceFrameIndex))
    }
}

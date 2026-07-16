import Foundation

@main
struct AdaptiveSwingWindowPlannerSmoke {
    static func main() {
        let duration = 25.23
        let core = SwingCore(startTime: 14.0, endTime: 16.0, peakTime: 15.5)
        let initial = AdaptiveSwingWindowPlanner.initialWindow(core: core, duration: duration)
        precondition(initial == SwingWindow(startTime: 13.5, endTime: 16.5))

        let earlier = AdaptiveSwingWindowPlanner.nextAction(
            current: initial,
            duration: duration,
            evidence: AdaptiveBoundaryEvidence(
                hasAddressBoundary: false,
                hasFinishBoundary: true
            )
        )
        precondition(earlier == .expand(SwingWindow(startTime: 13.0, endTime: 16.5)))

        let later = AdaptiveSwingWindowPlanner.nextAction(
            current: initial,
            duration: duration,
            evidence: AdaptiveBoundaryEvidence(
                hasAddressBoundary: true,
                hasFinishBoundary: false
            )
        )
        precondition(later == .expand(SwingWindow(startTime: 13.5, endTime: 17.0)))

        precondition(
            AdaptiveSwingWindowPlanner.nextAction(
                current: initial,
                duration: duration,
                evidence: AdaptiveBoundaryEvidence(
                    hasAddressBoundary: true,
                    hasFinishBoundary: true
                )
            ) == .ready(initial)
        )

        precondition(
            AdaptiveSwingWindowPlanner.nextAction(
                current: SwingWindow(startTime: 0, endTime: 3),
                duration: duration,
                evidence: AdaptiveBoundaryEvidence(
                    hasAddressBoundary: false,
                    hasFinishBoundary: true
                )
            ) == .failed(.incompleteSwingClip)
        )
        precondition(
            AdaptiveSwingWindowPlanner.nextAction(
                current: SwingWindow(startTime: 22, endTime: duration),
                duration: duration,
                evidence: AdaptiveBoundaryEvidence(
                    hasAddressBoundary: true,
                    hasFinishBoundary: false
                )
            ) == .failed(.incompleteSwingClip)
        )

        let maximumSpan = SwingWindow(startTime: 5, endTime: 13)
        precondition(
            AdaptiveSwingWindowPlanner.nextAction(
                current: maximumSpan,
                duration: duration,
                evidence: AdaptiveBoundaryEvidence(
                    hasAddressBoundary: false,
                    hasFinishBoundary: true
                )
            ) == .failed(.missingAddressBoundary)
        )
        precondition(
            AdaptiveSwingWindowPlanner.nextAction(
                current: maximumSpan,
                duration: duration,
                evidence: AdaptiveBoundaryEvidence(
                    hasAddressBoundary: true,
                    hasFinishBoundary: false
                )
            ) == .failed(.missingFinishBoundary)
        )
    }
}

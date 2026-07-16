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

        let justBelowLimit = SwingWindow(startTime: 5, endTime: 12.9)
        precondition(
            AdaptiveSwingWindowPlanner.nextAction(
                current: justBelowLimit,
                duration: duration,
                evidence: AdaptiveBoundaryEvidence(
                    hasAddressBoundary: true,
                    hasFinishBoundary: false
                )
            ) == .expand(SwingWindow(startTime: 5.4, endTime: 13.4)),
            "The final growth step must cap at exactly eight seconds and shift toward the missing finish"
        )
        precondition(
            AdaptiveSwingWindowPlanner.nextAction(
                current: SwingWindow(startTime: 5, endTime: 13.01),
                duration: duration,
                evidence: AdaptiveBoundaryEvidence(
                    hasAddressBoundary: true,
                    hasFinishBoundary: true
                )
            ) != .ready(SwingWindow(startTime: 5, endTime: 13.01)),
            "A window above the eight-second contract must never become ready"
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
            ) == .expand(SwingWindow(startTime: 4.5, endTime: 12.5)),
            "At maximum width the planner must shift left toward a missing address"
        )
        precondition(
            AdaptiveSwingWindowPlanner.nextAction(
                current: maximumSpan,
                duration: duration,
                evidence: AdaptiveBoundaryEvidence(
                    hasAddressBoundary: true,
                    hasFinishBoundary: false
                )
            ) == .expand(SwingWindow(startTime: 5.5, endTime: 13.5)),
            "At maximum width the planner must shift right toward a missing finish"
        )

        let nearEnd = SwingWindow(startTime: 17.23, endTime: 25.23)
        precondition(
            AdaptiveSwingWindowPlanner.nextAction(
                current: nearEnd,
                duration: duration,
                evidence: AdaptiveBoundaryEvidence(
                    hasAddressBoundary: true,
                    hasFinishBoundary: false
                )
            ) == .failed(.incompleteSwingClip)
        )

        var earlierSearch = AdaptiveWindowSearchState()
        let earlierFirst = earlierSearch.nextAction(
            current: SwingWindow(startTime: 5, endTime: 13),
            duration: duration,
            evidence: AdaptiveBoundaryEvidence(
                hasAddressBoundary: false,
                hasFinishBoundary: true
            )
        )
        precondition(earlierFirst == .expand(SwingWindow(startTime: 4.5, endTime: 12.5)))
        precondition(earlierSearch.shiftDirection == .earlier)
        precondition(
            earlierSearch.nextAction(
                current: SwingWindow(startTime: 4.5, endTime: 12.5),
                duration: duration,
                evidence: AdaptiveBoundaryEvidence(
                    hasAddressBoundary: true,
                    hasFinishBoundary: false
                )
            ) == .failed(.missingFinishBoundary),
            "A left-shifting full window must report the newly missing finish instead of reversing"
        )

        var laterSearch = AdaptiveWindowSearchState()
        let laterFirst = laterSearch.nextAction(
            current: SwingWindow(startTime: 5, endTime: 13),
            duration: duration,
            evidence: AdaptiveBoundaryEvidence(
                hasAddressBoundary: true,
                hasFinishBoundary: false
            )
        )
        precondition(laterFirst == .expand(SwingWindow(startTime: 5.5, endTime: 13.5)))
        precondition(laterSearch.shiftDirection == .later)
        precondition(
            laterSearch.nextAction(
                current: SwingWindow(startTime: 5.5, endTime: 13.5),
                duration: duration,
                evidence: AdaptiveBoundaryEvidence(
                    hasAddressBoundary: false,
                    hasFinishBoundary: true
                )
            ) == .failed(.missingAddressBoundary),
            "A right-shifting full window must report the newly missing address instead of reversing"
        )

        var monotonicSearch = AdaptiveWindowSearchState()
        var monotonicWindow = SwingWindow(startTime: 5, endTime: 13)
        for expectedStart in [4.5, 4.0, 3.5] {
            let action = monotonicSearch.nextAction(
                current: monotonicWindow,
                duration: duration,
                evidence: AdaptiveBoundaryEvidence(
                    hasAddressBoundary: false,
                    hasFinishBoundary: true
                )
            )
            guard case let .expand(next) = action else {
                preconditionFailure("Repeated fixed-width search must remain monotonic")
            }
            precondition(next.startTime == expectedStart)
            precondition(next.duration == AdaptiveSwingWindowPlanner.maximumSpan)
            monotonicWindow = next
        }
    }
}

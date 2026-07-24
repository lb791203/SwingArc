import CoreMedia
import Foundation

@main
struct FineSwingSamplingPlanSmoke {
    static func main() {
        precondition(SourceFrameTimelineLoadingPolicy.canUseConstantTimeline(
            metadataFrameRate: 30
        ))
        precondition(SourceFrameTimelineLoadingPolicy.canUseConstantTimeline(
            metadataFrameRate: 60
        ))
        precondition(!SourceFrameTimelineLoadingPolicy.canUseConstantTimeline(
            metadataFrameRate: 240
        ))

        let window = SwingWindow(startTime: 3.2, endTime: 4.2)
        let frames = FineSwingSamplingPlan.frames(
            window: window,
            sourceFrameRate: 59.94,
            duration: 25.19
        )

        precondition(!frames.isEmpty)
        precondition(zip(frames, frames.dropFirst()).allSatisfy { $0.sourceFrameIndex < $1.sourceFrameIndex })
        precondition(frames.allSatisfy { abs($0.time - Double($0.sourceFrameIndex) / 59.94) < 0.000_001 })
        precondition(zip(frames, frames.dropFirst()).allSatisfy { $1.time - $0.time >= (1.0 / 59.94) - 0.000_001 })

        let highRate = FineSwingSamplingPlan.frames(
            window: SwingWindow(startTime: 0, endTime: 1),
            sourceFrameRate: 240,
            duration: 1
        )
        precondition(highRate.count <= 121)
        precondition(zip(highRate, highRate.dropFirst()).allSatisfy {
            $1.sourceFrameIndex - $0.sourceFrameIndex >= 2
        })

        let longSlowMotion = FineSwingSamplingPlan.frames(
            window: SwingWindow(startTime: 10, endTime: 18),
            sourceFrameRate: 240,
            duration: 30
        )
        precondition(
            longSlowMotion.count <= 97,
            "An eight-second slow-motion window must have a bounded Vision frame budget"
        )
        precondition(longSlowMotion.first?.sourceFrameIndex == 2_400)
        precondition((longSlowMotion.last?.sourceFrameIndex ?? .max) <= 4_320)

        let lowRate = FineSwingSamplingPlan.frames(
            window: SwingWindow(startTime: 0, endTime: 1),
            sourceFrameRate: 30,
            duration: 1
        )
        precondition(lowRate.count == 10)
        precondition(lowRate.last?.sourceFrameIndex == 27)
        precondition(zip(lowRate, lowRate.dropFirst()).allSatisfy {
            $1.sourceFrameIndex - $0.sourceFrameIndex == 3
        })

        let explicitBound = FineSwingSamplingPlan.frames(
            window: SwingWindow(startTime: 0.8, endTime: 1.0),
            sourceFrameRate: 30,
            duration: 1,
            maximumSourceFrameIndex: 28
        )
        precondition(explicitBound.last?.sourceFrameIndex == 27)
        precondition(explicitBound.allSatisfy { $0.sourceFrameIndex <= 28 })

        precondition(
            SourceFrameBounds.maximumSourceFrameIndex(duration: 1, sourceFrameRate: 30) == 29
        )

        let variableTimeline = SourceFrameTimeline(presentationTimes: [
            CMTime(seconds: 0.000, preferredTimescale: 60_000),
            CMTime(seconds: 0.004, preferredTimescale: 60_000),
            CMTime(seconds: 0.008, preferredTimescale: 60_000),
            CMTime(seconds: 0.016, preferredTimescale: 60_000),
            CMTime(seconds: 0.020, preferredTimescale: 60_000)
        ])!
        let variableFrames = FineSwingSamplingPlan.frames(
            window: SwingWindow(startTime: 0, endTime: 0.020),
            sourceFrameTimeline: variableTimeline
        )
        precondition(!variableFrames.isEmpty)
        precondition(variableFrames.first?.sourceFrameIndex == 0)
        precondition(variableFrames.last?.sourceFrameIndex == 0)
        precondition(variableFrames.allSatisfy {
            variableTimeline.presentationTime(
                sourceFrameIndex: $0.sourceFrameIndex
            )?.seconds == $0.time
        })
        precondition(zip(variableFrames, variableFrames.dropFirst()).allSatisfy {
            $0.sourceFrameIndex < $1.sourceFrameIndex
        })

        let expandingTimeline = SourceFrameTimeline(presentationTimes: (0..<360).map {
            CMTime(
                seconds: Double($0) / 60 + ($0.isMultiple(of: 7) ? 0.000_2 : 0),
                preferredTimescale: 60_000
            )
        })!
        let innerVariableFrames = FineSwingSamplingPlan.frames(
            window: SwingWindow(startTime: 1.03, endTime: 3.47),
            sourceFrameTimeline: expandingTimeline
        )
        let expandedVariableFrames = FineSwingSamplingPlan.frames(
            window: SwingWindow(startTime: 0.53, endTime: 3.97),
            sourceFrameTimeline: expandingTimeline
        )
        precondition(
            Set(innerVariableFrames.map(\.sourceFrameIndex)).isSubset(
                of: Set(expandedVariableFrames.map(\.sourceFrameIndex))
            ),
            "Adaptive expansion must use one global sampling grid without re-entry"
        )
    }
}

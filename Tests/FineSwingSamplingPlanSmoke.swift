import Foundation

@main
struct FineSwingSamplingPlanSmoke {
    static func main() {
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

        let lowRate = FineSwingSamplingPlan.frames(
            window: SwingWindow(startTime: 0, endTime: 1),
            sourceFrameRate: 30,
            duration: 1
        )
        precondition(lowRate.count == 31)
        precondition(zip(lowRate, lowRate.dropFirst()).allSatisfy {
            $1.sourceFrameIndex - $0.sourceFrameIndex == 1
        })
    }
}

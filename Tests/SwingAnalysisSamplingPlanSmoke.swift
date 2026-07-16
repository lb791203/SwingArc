import Foundation

@main
struct SwingAnalysisSamplingPlanSmoke {
    static func main() {
        let times = SwingAnalysisSamplingPlan.sampleTimes(duration: 25.19)

        precondition(times.first == 0)
        precondition(abs((times.last ?? 0) - 25.19) < 0.0001)
        precondition(SwingAnalysisSamplingPlan.samplesPerSecond == 8.0)
        precondition(zip(times, times.dropFirst()).allSatisfy { $1 - $0 <= (1.0 / 8.0) + 0.0001 })
    }
}

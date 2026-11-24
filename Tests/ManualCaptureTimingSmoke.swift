import Foundation

@main
struct ManualCaptureTimingSmoke {
    static func main() throws {
        precondition(ManualCaptureTiming.maximumDuration == 15)
        precondition(ManualCaptureDelay.options == [0, 3, 5, 10])
        precondition(ManualCaptureDelay.sanitized(7) == ManualCaptureDelay.defaultSeconds)
        precondition(ManualCaptureDelay.sanitized(0) == 0)
        precondition(ManualCaptureDelay.label(for: 0) == "立即")
        precondition(ManualCaptureDelay.label(for: 10) == "10 秒")

        let source = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )
        precondition(!source.contains("startCountdown"))
        precondition(!source.contains("isCountingDown"))
        precondition(!source.contains("countdownValue"))
        precondition(!source.contains("3 秒后自动录制"))
        precondition(source.contains("ManualCaptureDelay.options"))
        precondition(source.contains("cancelDelayedStart()"))
        precondition(source.contains("ManualCaptureTiming.maximumDuration"))
        precondition(source.contains("pendingAutomaticStop"))
    }
}

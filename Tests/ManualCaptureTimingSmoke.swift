import Foundation

@main
struct ManualCaptureTimingSmoke {
    static func main() throws {
        precondition(ManualCaptureTiming.maximumDuration == 15)

        let source = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )
        precondition(!source.contains("startCountdown"))
        precondition(!source.contains("isCountingDown"))
        precondition(!source.contains("countdownValue"))
        precondition(!source.contains("3 秒后自动录制"))
        precondition(source.contains("ManualCaptureTiming.maximumDuration"))
        precondition(source.contains("pendingAutomaticStop"))
    }
}

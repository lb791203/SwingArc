import Foundation

@main
struct CameraRecordingLifecycleSmoke {
    static func main() {
        var lifecycle = ManualCaptureLifecycle()
        precondition(lifecycle.state == .idle)
        precondition(!lifecycle.shouldScheduleAutomaticStop)

        precondition(lifecycle.requestStart())
        precondition(lifecycle.state == .starting)
        precondition(!lifecycle.shouldScheduleAutomaticStop)
        precondition(!lifecycle.requestStart())

        lifecycle.didStart()
        precondition(lifecycle.state == .recording)
        precondition(lifecycle.shouldScheduleAutomaticStop)

        lifecycle.didFinish()
        precondition(lifecycle.state == .idle)
        precondition(!lifecycle.shouldScheduleAutomaticStop)

        precondition(lifecycle.requestStart())
        lifecycle.didFail()
        precondition(lifecycle.state == .failed)
        precondition(!lifecycle.shouldScheduleAutomaticStop)
        precondition(lifecycle.requestStart(), "A surfaced failure must be retryable")

        var abandonedStart = ManualCaptureLifecycle()
        precondition(abandonedStart.requestStart())
        abandonedStart.didFinish()
        abandonedStart.didStart()
        precondition(abandonedStart.state == .idle)
        precondition(
            !abandonedStart.shouldScheduleAutomaticStop,
            "A dismissed start must not arm the 15-second timer later"
        )
    }
}

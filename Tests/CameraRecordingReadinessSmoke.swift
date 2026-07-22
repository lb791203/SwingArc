import Foundation

@main
struct CameraRecordingReadinessSmoke {
    static func main() {
        precondition(CameraRecordingReadiness.canStart(
            sessionIsRunning: true,
            hasActiveVideoConnection: true,
            isAlreadyRecording: false
        ))
        precondition(!CameraRecordingReadiness.canStart(
            sessionIsRunning: false,
            hasActiveVideoConnection: true,
            isAlreadyRecording: false
        ))
        precondition(!CameraRecordingReadiness.canStart(
            sessionIsRunning: true,
            hasActiveVideoConnection: false,
            isAlreadyRecording: false
        ))
        precondition(!CameraRecordingReadiness.canStart(
            sessionIsRunning: true,
            hasActiveVideoConnection: true,
            isAlreadyRecording: true
        ))
    }
}

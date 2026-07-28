import Foundation

@main
struct CameraRecordingReadinessSmoke {
    static func main() {
        precondition(CameraRecordingReadiness.isRecordable(
            sessionIsRunning: true,
            hasActiveVideoConnection: true
        ))
        precondition(!CameraRecordingReadiness.isRecordable(
            sessionIsRunning: false,
            hasActiveVideoConnection: true
        ))
        precondition(!CameraRecordingReadiness.isRecordable(
            sessionIsRunning: true,
            hasActiveVideoConnection: false
        ))
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

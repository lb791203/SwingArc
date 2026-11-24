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
        let storageFull = NSError(domain: "AVFoundationErrorDomain", code: -11807)
        let message = CameraErrorPresentation.message(prefix: "录像中断", error: storageFull)
        precondition(message.hasPrefix("录像中断：手机存储空间不足"), message)
        precondition(
            CameraErrorPresentation.message(prefix: "x", error: CameraRecordingStartError.notReady)
                == "相机尚未准备好，请稍候后重试。"
        )
    }
}

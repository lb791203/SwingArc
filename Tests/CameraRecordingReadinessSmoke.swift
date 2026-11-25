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
        let disconnected = CameraErrorPresentation.message(
            prefix: "x",
            error: NSError(domain: "AVFoundationErrorDomain", code: -11808)
        )
        precondition(disconnected.contains("相机已断开"), disconnected)
        let reset = CameraErrorPresentation.message(
            prefix: "x",
            error: NSError(domain: "AVFoundationErrorDomain", code: -11819)
        )
        precondition(reset.contains("媒体服务已重置"), reset)
        let occupied = CameraErrorPresentation.message(
            prefix: "x",
            error: NSError(domain: "AVFoundationErrorDomain", code: -11818)
        )
        precondition(occupied.contains("占用"), occupied)
        precondition(CaptureCountdownPolicy.shouldContinue(
            appIsActive: true, canRecord: true, cameraIsReady: true
        ))
        precondition(!CaptureCountdownPolicy.shouldContinue(
            appIsActive: false, canRecord: true, cameraIsReady: true
        ), "Leaving the app must cancel the countdown")
        precondition(!CaptureCountdownPolicy.shouldContinue(
            appIsActive: true, canRecord: true, cameraIsReady: false
        ), "An interrupted camera must cancel the countdown before the go tone")
        precondition(
            CameraErrorPresentation.message(prefix: "x", error: CameraRecordingStartError.notReady)
                == "相机尚未准备好，请稍候后重试。"
        )
    }
}

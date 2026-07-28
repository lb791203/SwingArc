import Foundation

/// Prevents `AVCaptureMovieFileOutput` from receiving a recording request
/// before its session and video connection are ready. AVFoundation raises an
/// Objective-C exception for that invalid transition, so it cannot be handled
/// by Swift's `do` / `catch`.
enum CameraRecordingReadiness {
    static func canStart(
        sessionIsRunning: Bool,
        hasActiveVideoConnection: Bool,
        isAlreadyRecording: Bool
    ) -> Bool {
        sessionIsRunning && hasActiveVideoConnection && !isAlreadyRecording
    }
}

enum CameraAccessState: Equatable {
    case checking
    case ready
    case denied
    case unavailable
}

enum CameraAccessPresentation {
    static func canRecord(_ state: CameraAccessState) -> Bool {
        state == .ready
    }

    static func title(for state: CameraAccessState) -> String {
        switch state {
        case .checking:
            return "正在检查相机权限"
        case .ready:
            return "相机已就绪"
        case .denied:
            return "需要相机权限"
        case .unavailable:
            return "无法使用相机"
        }
    }

    static func detail(for state: CameraAccessState) -> String {
        switch state {
        case .checking:
            return "请稍候"
        case .ready:
            return "可以开始录像"
        case .denied:
            return "请前往 iOS 设置允许 SwingArc 使用相机。"
        case .unavailable:
            return "此设备没有可用于录像的相机。"
        }
    }
}

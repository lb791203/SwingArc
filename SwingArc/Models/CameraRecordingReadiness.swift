import Foundation

/// Prevents `AVCaptureMovieFileOutput` from receiving a recording request
/// before its session and video connection are ready. AVFoundation raises an
/// Objective-C exception for that invalid transition, so it cannot be handled
/// by Swift's `do` / `catch`.
enum CameraRecordingReadiness {
    static func isRecordable(
        sessionIsRunning: Bool,
        hasActiveVideoConnection: Bool
    ) -> Bool {
        sessionIsRunning && hasActiveVideoConnection
    }

    static func canStart(
        sessionIsRunning: Bool,
        hasActiveVideoConnection: Bool,
        isAlreadyRecording: Bool
    ) -> Bool {
        isRecordable(
            sessionIsRunning: sessionIsRunning,
            hasActiveVideoConnection: hasActiveVideoConnection
        ) && !isAlreadyRecording
    }
}

enum ManualCaptureLifecycleState: Equatable {
    case idle
    case starting
    case recording
    case failed
}

struct ManualCaptureLifecycle: Equatable {
    private(set) var state: ManualCaptureLifecycleState = .idle

    var shouldScheduleAutomaticStop: Bool {
        state == .recording
    }

    @discardableResult
    mutating func requestStart() -> Bool {
        guard state == .idle || state == .failed else { return false }
        state = .starting
        return true
    }

    mutating func didStart() {
        guard state == .starting else { return }
        state = .recording
    }

    mutating func didFail() {
        state = .failed
    }

    mutating func didFinish() {
        state = .idle
    }
}

enum CameraRecordingStartError: LocalizedError, Equatable {
    case notReady
    case rejected
    case interrupted

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "相机尚未准备好，请稍候后重试。"
        case .rejected:
            return "录像未能开始，请重试。"
        case .interrupted:
            return "录像被系统中断，请确认相机可用后重试。"
        }
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

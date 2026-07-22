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

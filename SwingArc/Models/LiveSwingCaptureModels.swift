import Foundation

enum PracticeCaptureQuality: Equatable {
    case complete
    case possibleIncomplete
}

struct PracticeCaptureBoundary: Equatable {
    let swingStartTime: TimeInterval
    let swingEndTime: TimeInterval
    let quality: PracticeCaptureQuality
}

struct RecordedPracticeClip: Equatable {
    let url: URL
    let quality: PracticeCaptureQuality
}

enum PracticeCaptureStatus: Equatable {
    case searchingForPerson
    case readyForSwing
    case capturingSwing
    case finalizing
    case captureFrameRateChanged(Double)
    case visualUnavailable(message: String)
}

enum LiveSwingTriggerState: Equatable {
    case searchingForPerson
    case ready
    case swingInProgress
    case finishing
    case cooldown
}

struct LivePoseMotionSample: Equatable {
    let time: TimeInterval
    let personVisible: Bool
    let normalizedWristSpeed: Double
    let normalizedTorsoSpeed: Double
    let backswingDirectionScore: Double
    let followThroughScore: Double
}

struct LiveSwingTriggerConfiguration: Equatable {
    let sampleRate: Double
    let personStableDuration: TimeInterval
    let onsetConfirmationSamples: Int
    let minimumSwingDuration: TimeInterval
    let maximumSwingDuration: TimeInterval
    let finishSettledDuration: TimeInterval
    let cooldownDuration: TimeInterval
    let wristOnsetSpeed: Double
    let torsoCoordinationSpeed: Double
    let settledSpeed: Double

    static let standard = LiveSwingTriggerConfiguration(
        sampleRate: 12,
        personStableDuration: 0.5,
        onsetConfirmationSamples: 3,
        minimumSwingDuration: 0.7,
        maximumSwingDuration: 5.0,
        finishSettledDuration: 0.35,
        cooldownDuration: 0.75,
        wristOnsetSpeed: 0.8,
        torsoCoordinationSpeed: 0.15,
        settledSpeed: 0.25
    )
}

struct LiveSwingTriggerUpdate: Equatable {
    let state: LiveSwingTriggerState
    let boundary: PracticeCaptureBoundary?
}

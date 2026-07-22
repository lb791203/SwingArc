import Foundation
import Combine

struct PracticeClipWindow: Equatable {
    let preImpact: TimeInterval
    let postImpact: TimeInterval

    static let standard = PracticeClipWindow(preImpact: 2, postImpact: 1)
}

struct PracticeClipRange: Equatable {
    let start: TimeInterval
    let duration: TimeInterval
}

enum PracticeClipRangePolicy {
    static func resolve(
        impactTime: TimeInterval,
        sourceDuration: TimeInterval,
        window: PracticeClipWindow
    ) -> PracticeClipRange? {
        guard impactTime.isFinite,
              sourceDuration.isFinite,
              window.preImpact >= 0,
              window.postImpact >= 0 else {
            return nil
        }
        let start = impactTime - window.preImpact
        let end = impactTime + window.postImpact
        guard start >= 0, end <= sourceDuration else { return nil }
        return PracticeClipRange(start: start, duration: end - start)
    }
}

enum PracticeSessionError: Error, Equatable {
    case recordingFailed
    case analysisFailed
}

/// A captured clip has one Vision-analysis owner. Practice feedback stays in
/// the camera session, while a workspace handoff defers the same work to the
/// replay screen that is about to open.
enum PracticeAnalysisDestination: Equatable {
    case practiceFeedback
    case workspaceHandoff
}

protocol PracticeClipRecording: AnyObject {
    func requestClip(
        status: @escaping (PracticeCaptureStatus) -> Void,
        completion: @escaping (Result<RecordedPracticeClip, PracticeSessionError>) -> Void
    )

    func cancelPendingClip()
}

extension PracticeClipRecording {
    func cancelPendingClip() {}
}

protocol PracticeAnalyzing: AnyObject {
    func analyze(
        clipURL: URL,
        view: PracticeCameraView,
        completion: @escaping (Result<PriorityFeedback, PracticeSessionError>) -> Void
    )
}

/// Serializes one visually detected swing at a time. Camera and Vision
/// implementations are injected so this stateful policy can be tested without
/// hardware.
final class PracticeSessionEngine: ObservableObject {
    private let recorder: PracticeClipRecording
    private let analyzer: PracticeAnalyzing?
    private let analysisDestination: PracticeAnalysisDestination
    @Published private(set) var state: PracticeSessionState = .failed(
        view: .downTheLine,
        message: "练习尚未开始"
    )
    @Published private(set) var lastClip: RecordedPracticeClip?
    @Published private(set) var captureFrameRate: Double?
    private var isCaptureArmed = false
    private var clipPersistenceRetry: (view: PracticeCameraView, swingCount: Int)?

    var canRetryAfterClipPersistenceFailure: Bool {
        clipPersistenceRetry != nil
    }

    init(
        recorder: PracticeClipRecording,
        analyzer: PracticeAnalyzing? = nil,
        analysisDestination: PracticeAnalysisDestination = .practiceFeedback
    ) {
        self.recorder = recorder
        self.analyzer = analyzer
        self.analysisDestination = analysisDestination
    }

    func begin(view: PracticeCameraView) {
        lastClip = nil
        captureFrameRate = nil
        state = .aligning(view: view)
    }

    func confirmAlignment() {
        state = PracticeSessionReducer.reduce(state: state, event: .alignmentConfirmed)
    }

    func start() {
        state = PracticeSessionReducer.reduce(state: state, event: .startTapped)
    }

    func pause() {
        recorder.cancelPendingClip()
        isCaptureArmed = false
        state = PracticeSessionReducer.reduce(state: state, event: .pauseTapped)
    }

    func resume() {
        state = PracticeSessionReducer.reduce(state: state, event: .resumeTapped)
    }

    func advanceResultRibbon() {
        state = PracticeSessionReducer.reduce(state: state, event: .resultRibbonElapsed)
    }

    /// Arms one visual capture while the state remains visibly in the person
    /// search / swing-ready flow. Analysis begins only when the recorder
    /// returns an actual trimmed local clip.
    func armNextCapture() {
        guard activeCaptureIdentity != nil, !isCaptureArmed else { return }
        isCaptureArmed = true
        recorder.requestClip(status: { [weak self] status in
            self?.publish(status)
        }) { [weak self] recordingResult in
            guard let self else { return }
            self.isCaptureArmed = false
            guard let (view, _) = self.activeCaptureIdentity else { return }
            switch recordingResult {
            case let .success(clip):
                self.acceptRecordedClip(clip, view: view)
            case .failure:
                self.state = .degraded(view: view, message: "本球录制失败，请检查储存空间或相机权限")
            }
        }
    }

    /// The file was captured but the private, stable copy required by the
    /// analysis workspace could not be made. Keep the camera session visible
    /// and offer a deliberate retry instead of leaving it in `processing`.
    func reportClipPersistenceFailure() {
        guard analysisDestination == .workspaceHandoff,
              case let .processing(view, swingCount) = state else {
            return
        }
        clipPersistenceRetry = (view, swingCount)
        state = .degraded(
            view: view,
            message: "录制已完成，但无法保存用于 AI 分析的视频。请释放储存空间后重新录制。"
        )
    }

    func retryAfterClipPersistenceFailure() {
        guard let retry = clipPersistenceRetry else { return }
        clipPersistenceRetry = nil
        state = .searchingForPerson(view: retry.view, swingCount: retry.swingCount)
        armNextCapture()
    }

    private func acceptRecordedClip(_ clip: RecordedPracticeClip, view: PracticeCameraView) {
        lastClip = clip
        state = PracticeSessionReducer.reduce(state: state, event: .clipCaptured)

        guard analysisDestination == .practiceFeedback else { return }
        guard analyzer != nil else {
            state = .degraded(view: view, message: "本球未能分析，影片已保留")
            return
        }
        analyze(clipURL: clip.url, view: view)
    }

    private func analyze(clipURL: URL, view: PracticeCameraView) {
        analyzer?.analyze(clipURL: clipURL, view: view) { [weak self] analysisResult in
            guard let self else { return }
            switch analysisResult {
            case let .success(feedback):
                self.state = PracticeSessionReducer.reduce(
                    state: self.state,
                    event: .analysisFinished(feedback)
                )
                self.returnToWaitingAfterResult()
            case .failure:
                self.state = .degraded(view: view, message: "本球未能分析，影片已保留")
            }
        }
    }

    private func returnToWaitingAfterResult() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, case .resultRibbon = self.state else { return }
            self.advanceResultRibbon()
            self.armNextCapture()
        }
    }

    private func publish(_ status: PracticeCaptureStatus) {
        guard let (view, _) = activeCaptureIdentity else { return }
        switch status {
        case .searchingForPerson:
            state = PracticeSessionReducer.reduce(state: state, event: .captureSearching)
        case .readyForSwing:
            state = PracticeSessionReducer.reduce(state: state, event: .captureReady)
        case .capturingSwing:
            state = PracticeSessionReducer.reduce(state: state, event: .swingStarted)
        case .finalizing:
            state = PracticeSessionReducer.reduce(state: state, event: .clipFinalizing)
        case let .captureFrameRateChanged(rate):
            captureFrameRate = rate
        case let .visualUnavailable(message):
            isCaptureArmed = false
            state = .degraded(view: view, message: message)
        }
    }

    private var activeCaptureIdentity: (PracticeCameraView, Int)? {
        switch state {
        case let .searchingForPerson(view, swingCount),
             let .readyForSwing(view, swingCount),
             let .capturingSwing(view, swingCount),
             let .finalizingCapture(view, swingCount):
            return (view, swingCount)
        default:
            return nil
        }
    }
}

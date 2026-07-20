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

protocol PracticeClipRecording: AnyObject {
    func requestClip(
        window: PracticeClipWindow,
        completion: @escaping (Result<URL, PracticeSessionError>) -> Void
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

/// Serializes one impact at a time. Camera and audio implementations are
/// injected so this stateful policy can be tested without hardware.
final class PracticeSessionEngine: ObservableObject {
    private let recorder: PracticeClipRecording
    private let analyzer: PracticeAnalyzing
    @Published private(set) var state: PracticeSessionState = .failed(
        view: .downTheLine,
        message: "练习尚未开始"
    )
    @Published private(set) var lastClipURL: URL?
    private var isCaptureArmed = false

    init(recorder: PracticeClipRecording, analyzer: PracticeAnalyzing) {
        self.recorder = recorder
        self.analyzer = analyzer
    }

    func begin(view: PracticeCameraView) {
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

    /// Arms one microphone-triggered capture while the state remains visibly
    /// in waiting mode. The recorder owns the pre/post-impact buffering;
    /// analysis begins only when it returns an actual trimmed local clip.
    func armNextCapture() {
        guard case .waitingForImpact = state, !isCaptureArmed else { return }
        isCaptureArmed = true
        recorder.requestClip(window: .standard) { [weak self] recordingResult in
            guard let self else { return }
            self.isCaptureArmed = false
            guard case let .waitingForImpact(view, _) = self.state else { return }
            switch recordingResult {
            case let .success(clipURL):
                self.lastClipURL = clipURL
                self.state = PracticeSessionReducer.reduce(
                    state: self.state,
                    event: .impactDetected
                )
                self.analyze(clipURL: clipURL, view: view)
            case .failure:
                self.state = .degraded(view: view, message: "本球录制失败，请检查储存空间或相机权限")
            }
        }
    }

    func ingestImpact(time _: TimeInterval) {
        guard case let .waitingForImpact(view, _) = state, !isCaptureArmed else { return }
        isCaptureArmed = true
        state = PracticeSessionReducer.reduce(state: state, event: .impactDetected)
        recorder.requestClip(window: .standard) { [weak self] recordingResult in
            guard let self else { return }
            self.isCaptureArmed = false
            switch recordingResult {
            case let .success(clipURL):
                self.lastClipURL = clipURL
                self.analyze(clipURL: clipURL, view: view)
            case .failure:
                self.state = .degraded(view: view, message: "本球录制失败，请检查储存空间或相机权限")
            }
        }
    }

    private func analyze(clipURL: URL, view: PracticeCameraView) {
        analyzer.analyze(clipURL: clipURL, view: view) { [weak self] analysisResult in
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
}

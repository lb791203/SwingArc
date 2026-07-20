import Foundation

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
final class PracticeSessionEngine {
    private let recorder: PracticeClipRecording
    private let analyzer: PracticeAnalyzing
    private(set) var state: PracticeSessionState = .failed(
        view: .downTheLine,
        message: "练习尚未开始"
    )

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
        state = PracticeSessionReducer.reduce(state: state, event: .pauseTapped)
    }

    func resume() {
        state = PracticeSessionReducer.reduce(state: state, event: .resumeTapped)
    }

    func advanceResultRibbon() {
        state = PracticeSessionReducer.reduce(state: state, event: .resultRibbonElapsed)
    }

    func ingestImpact(time _: TimeInterval) {
        guard case let .waitingForImpact(view, _) = state else { return }
        state = PracticeSessionReducer.reduce(state: state, event: .impactDetected)
        recorder.requestClip(window: .standard) { [weak self] recordingResult in
            guard let self else { return }
            switch recordingResult {
            case let .success(clipURL):
                self.analyzer.analyze(clipURL: clipURL, view: view) { [weak self] analysisResult in
                    guard let self else { return }
                    switch analysisResult {
                    case let .success(feedback):
                        self.state = PracticeSessionReducer.reduce(
                            state: self.state,
                            event: .analysisFinished(feedback)
                        )
                    case .failure:
                        self.state = .degraded(view: view, message: "本球未能分析，影片已保留")
                    }
                }
            case .failure:
                self.state = .degraded(view: view, message: "本球录制失败，请检查储存空间或相机权限")
            }
        }
    }
}

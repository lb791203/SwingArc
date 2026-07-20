import Foundation

@main
struct PracticeSessionEngineSmoke {
    static func main() {
        let recorder = Recorder()
        let analyzer = Analyzer()
        let engine = PracticeSessionEngine(recorder: recorder, analyzer: analyzer)

        engine.begin(view: .faceOn)
        engine.confirmAlignment()
        engine.start()
        precondition(engine.state == .waitingForImpact(view: .faceOn, swingCount: 0))

        engine.armNextCapture()
        precondition(recorder.requestedWindows == [PracticeClipWindow(preImpact: 2, postImpact: 1)])
        precondition(engine.state == .waitingForImpact(view: .faceOn, swingCount: 0))

        recorder.complete(url: URL(fileURLWithPath: "/tmp/swing.mp4"))
        precondition(analyzer.urls == [URL(fileURLWithPath: "/tmp/swing.mp4")])
        precondition(engine.state == .processing(view: .faceOn, swingCount: 1))
        analyzer.complete(feedback: .unresolved)
        precondition(engine.state == .resultRibbon(view: .faceOn, swingCount: 1, feedback: .unresolved))

        engine.advanceResultRibbon()
        precondition(engine.state == .waitingForImpact(view: .faceOn, swingCount: 1))
    }

    private final class Recorder: PracticeClipRecording {
        var requestedWindows: [PracticeClipWindow] = []
        private var completion: ((Result<URL, PracticeSessionError>) -> Void)?

        func requestClip(
            window: PracticeClipWindow,
            completion: @escaping (Result<URL, PracticeSessionError>) -> Void
        ) {
            requestedWindows.append(window)
            self.completion = completion
        }

        func complete(url: URL) {
            completion?(.success(url))
        }
    }

    private final class Analyzer: PracticeAnalyzing {
        var urls: [URL] = []
        private var completion: ((Result<PriorityFeedback, PracticeSessionError>) -> Void)?

        func analyze(
            clipURL: URL,
            view: PracticeCameraView,
            completion: @escaping (Result<PriorityFeedback, PracticeSessionError>) -> Void
        ) {
            urls.append(clipURL)
            self.completion = completion
        }

        func complete(feedback: PriorityFeedback) {
            completion?(.success(feedback))
        }
    }
}

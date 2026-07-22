import Foundation

@main
struct PracticeSessionEngineSmoke {
    static func main() {
        verifyFeedbackFlow()
        verifyWorkspaceHandoffAndRetry()
        verifyVisualFailureAndFrameRate()
    }

    private static func verifyFeedbackFlow() {
        let recorder = Recorder()
        let analyzer = Analyzer()
        let engine = PracticeSessionEngine(recorder: recorder, analyzer: analyzer)

        engine.begin(view: .faceOn)
        engine.confirmAlignment()
        engine.start()
        precondition(engine.state == .searchingForPerson(view: .faceOn, swingCount: 0))

        engine.armNextCapture()
        precondition(recorder.requestCount == 1)
        recorder.publish(.readyForSwing)
        precondition(engine.state == .readyForSwing(view: .faceOn, swingCount: 0))
        recorder.publish(.capturingSwing)
        precondition(engine.state == .capturingSwing(view: .faceOn, swingCount: 0))
        recorder.publish(.finalizing)
        precondition(engine.state == .finalizingCapture(view: .faceOn, swingCount: 0))

        let clip = RecordedPracticeClip(
            url: URL(fileURLWithPath: "/tmp/swing.mp4"),
            quality: .complete
        )
        recorder.complete(clip: clip)
        precondition(engine.lastClip == clip)
        precondition(analyzer.urls == [clip.url])
        precondition(engine.state == .processing(view: .faceOn, swingCount: 1))

        analyzer.complete(feedback: .unresolved)
        precondition(
            engine.state == .resultRibbon(
                view: .faceOn,
                swingCount: 1,
                feedback: .unresolved
            )
        )
        engine.advanceResultRibbon()
        precondition(engine.state == .searchingForPerson(view: .faceOn, swingCount: 1))
    }

    private static func verifyWorkspaceHandoffAndRetry() {
        let recorder = Recorder()
        let analyzer = Analyzer()
        let engine = PracticeSessionEngine(
            recorder: recorder,
            analyzer: analyzer,
            analysisDestination: .workspaceHandoff
        )
        let clip = RecordedPracticeClip(
            url: URL(fileURLWithPath: "/tmp/handoff-swing.mp4"),
            quality: .possibleIncomplete
        )

        engine.begin(view: .downTheLine)
        engine.confirmAlignment()
        engine.start()
        engine.armNextCapture()
        recorder.publish(.capturingSwing)
        recorder.complete(clip: clip)

        precondition(engine.lastClip == clip)
        precondition(analyzer.urls.isEmpty)
        precondition(engine.state == .processing(view: .downTheLine, swingCount: 1))

        engine.reportClipPersistenceFailure()
        precondition(engine.canRetryAfterClipPersistenceFailure)
        precondition(
            engine.state == .degraded(
                view: .downTheLine,
                message: "录制已完成，但无法保存用于 AI 分析的视频。请释放储存空间后重新录制。"
            )
        )

        engine.retryAfterClipPersistenceFailure()
        precondition(recorder.requestCount == 2)
        precondition(engine.state == .searchingForPerson(view: .downTheLine, swingCount: 1))
    }

    private static func verifyVisualFailureAndFrameRate() {
        let recorder = Recorder()
        let engine = PracticeSessionEngine(
            recorder: recorder,
            analysisDestination: .workspaceHandoff
        )
        engine.begin(view: .faceOn)
        engine.confirmAlignment()
        engine.start()
        engine.armNextCapture()

        recorder.publish(.captureFrameRateChanged(120))
        precondition(engine.captureFrameRate == 120)

        recorder.publish(.visualUnavailable(message: "视觉检测不可用"))
        precondition(
            engine.state == .degraded(view: .faceOn, message: "视觉检测不可用")
        )
    }

    private final class Recorder: PracticeClipRecording {
        private(set) var requestCount = 0
        private var status: ((PracticeCaptureStatus) -> Void)?
        private var completion: ((Result<RecordedPracticeClip, PracticeSessionError>) -> Void)?

        func requestClip(
            status: @escaping (PracticeCaptureStatus) -> Void,
            completion: @escaping (Result<RecordedPracticeClip, PracticeSessionError>) -> Void
        ) {
            requestCount += 1
            self.status = status
            self.completion = completion
        }

        func publish(_ value: PracticeCaptureStatus) {
            status?(value)
        }

        func complete(clip: RecordedPracticeClip) {
            completion?(.success(clip))
        }
    }

    private final class Analyzer: PracticeAnalyzing {
        private(set) var urls: [URL] = []
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

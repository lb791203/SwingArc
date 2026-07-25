import Foundation

/// Converts one captured practice clip into truthful, local-only feedback.
/// The video analysis engine remains the sole Vision pass; technique checks
/// consume its solved stages and the pose samples from that same pass.
enum PracticeFeedbackPolicy {
    static func make(
        output: SwingVideoAnalysisOutput
    ) -> PriorityFeedback {
        let findings = SwingTechniqueEvaluator.evaluate(
            samples: output.poseSamples,
            stages: output.result.detections,
            view: output.view,
            leadArm: output.leadArm
        )
        return .select(from: findings)
    }
}

/// Production adapter for automatic practice. Every invocation owns a fresh
/// analysis gate, runs Vision away from the UI thread, and publishes exactly
/// one local result on the main queue.
final class OnDevicePracticeAnalyzer: PracticeAnalyzing {
    private let analysisQueue = DispatchQueue(
        label: "com.swingarc.practice-analysis",
        qos: .userInitiated
    )

    func analyze(
        clipURL: URL,
        view: PracticeCameraView,
        completion: @escaping (Result<PriorityFeedback, PracticeSessionError>) -> Void
    ) {
        let gate = AnalysisRunGate()
        let runID = gate.begin()
        analysisQueue.async {
            let outcome = SwingVideoAnalysisEngine().analyze(
                url: clipURL,
                view: view,
                runID: runID,
                gate: gate,
                progress: { _ in }
            )
            DispatchQueue.main.async {
                switch outcome {
                case let .completed(output):
                    completion(.success(PracticeFeedbackPolicy.make(output: output)))
                case .failed, .cancelled:
                    completion(.failure(.analysisFailed))
                }
            }
        }
    }
}

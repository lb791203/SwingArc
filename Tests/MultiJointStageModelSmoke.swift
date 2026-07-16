import Foundation

@main
struct MultiJointStageModelSmoke {
    static func main() {
        let detection = SwingStageDetection(
            stage: .impact,
            time: 0.72,
            confidence: 0.88,
            status: .confirmed
        )
        precondition(detection.marker?.stage == SwingStage.impact.rawValue)
        precondition(SwingStageDetection(stage: .top, time: nil, confidence: 0, status: .unresolved).marker == nil)

        let manual = KeyframeMarker(time: 0.72, stage: .impact, source: .manual)
        precondition(manual.isLocked)
    }
}

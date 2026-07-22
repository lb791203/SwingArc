import Foundation

@main
struct PracticePresentationSmoke {
    static func main() {
        precondition(
            PracticePresentationPolicy.primaryControl(
                for: .readyToStart(view: .downTheLine)
            ) == .start
        )
        precondition(
            PracticePresentationPolicy.primaryControl(
                for: .readyForSwing(view: .downTheLine, swingCount: 0)
            ) == .pause
        )
        precondition(
            PracticePresentationPolicy.remoteStatus(
                for: .processing(view: .faceOn, swingCount: 4)
            ) == "ANALYSING · SHOT 04"
        )
        precondition(
            PracticePresentationPolicy.remoteStatus(
                for: .aligning(view: .faceOn)
            ) == "ALIGNMENT"
        )
    }
}

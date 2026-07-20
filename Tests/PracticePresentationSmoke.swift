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
                for: .waitingForImpact(view: .downTheLine, swingCount: 0)
            ) == .pause
        )
        precondition(
            PracticePresentationPolicy.remoteStatus(
                for: .processing(view: .faceOn, swingCount: 4)
            ) == "第 4 球分析中"
        )
        precondition(
            PracticePresentationPolicy.remoteStatus(
                for: .aligning(view: .faceOn)
            ) == "请站入取景框"
        )
    }
}

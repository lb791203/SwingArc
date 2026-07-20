import Foundation

@main
struct ProTourPresentationSmoke {
    static func main() {
        precondition(PracticeHomePresentation.modeOrder == [.downTheLine, .faceOn])
        precondition(PracticeHomePresentation.secondaryActions == [.importVideo, .history])
        precondition(
            PracticePresentationPolicy.primaryControl(
                for: .waitingForImpact(view: .downTheLine, swingCount: 0)
            ) == .pause
        )
    }
}

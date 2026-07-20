import Foundation

@main
struct FeedbackProfileSmoke {
    static func main() {
        let dtl = SwingFeedbackProfiles.profile(for: .downTheLine)
        precondition(dtl.groups[0].title == "准备姿势")
        precondition(dtl.metric(.swingPlane)?.title == "挥杆平面")
        precondition(dtl.metric(.swingPlane)?.stages == [
            .takeaway,
            .leadArmParallelBackswing,
            .leadArmParallelDownswing,
            .followThrough
        ])
        precondition(dtl.metric(.spineStability)?.title == "脊柱稳定")

        let faceOn = SwingFeedbackProfiles.profile(for: .faceOn)
        precondition(faceOn.metric(.spineTilt)?.title == "脊柱侧倾")
        precondition(faceOn.metric(.leadShoulder)?.stages == [.top, .impact])
        precondition(faceOn.metric(.clubRelease)?.title == "释放")

        let configuration = FeedbackConfiguration.defaultValue(for: .faceOn)
        precondition(configuration.activeMetric == .spineTilt)
        precondition(configuration.enabledCheckpoints.contains(
            .init(metric: .spineTilt, stage: .top)
        ))
        precondition(
            FeedbackAvailability.resolve(
                metric: .clubRelease,
                analysis: .idle,
                sourceFrameRate: 240
            ) == .unavailable("需要可靠的杆头与击球证据")
        )
    }
}

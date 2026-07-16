import Foundation

@main
struct VideoZoomPolicySmoke {
    static func main() {
        precondition(VideoZoomPolicy.clampedScale(0.4) == 1)
        precondition(VideoZoomPolicy.clampedScale(2.5) == 2.5)
        precondition(VideoZoomPolicy.clampedScale(8) == 4)
    }
}

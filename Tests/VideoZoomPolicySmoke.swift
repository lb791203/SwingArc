import Foundation

@main
struct VideoZoomPolicySmoke {
    static func main() {
        precondition(VideoZoomPolicy.clampedScale(0.4) == 1)
        precondition(VideoZoomPolicy.clampedScale(2.5) == 2.5)
        precondition(VideoZoomPolicy.clampedScale(8) == 4)
        precondition(VideoZoomPolicy.adjustedScale(1, multiplier: 1.25) == 1.25)
        precondition(VideoZoomPolicy.adjustedScale(3.8, multiplier: 1.25) == 4)
    }
}

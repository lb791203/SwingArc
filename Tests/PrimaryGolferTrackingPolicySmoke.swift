import Foundation
import CoreGraphics

@main
struct PrimaryGolferTrackingPolicySmoke {
    static func main() {
        var history = ContinuityHistory()
        history.insert(time: 1.00, center: CGPoint(x: 0.5, y: 0.5))
        history.insert(time: 2.00, center: CGPoint(x: 0.6, y: 0.5))
        history.insert(time: 1.50, center: CGPoint(x: 0.55, y: 0.5))
        precondition(history.times == [1.00, 1.50, 2.00], "History must stay time-sorted")
        precondition(history.center(before: 1.60) == CGPoint(x: 0.55, y: 0.5))
        precondition(history.center(before: 0.90) == nil, "No earlier pose must not borrow a later one")
        precondition(history.center(before: 1.90) == nil, "A pose more than 0.25 s earlier is too old")
        precondition(history.center(before: 2.00) == CGPoint(x: 0.6, y: 0.5))
        history.insert(time: 2.10, center: nil)
        precondition(
            history.center(before: 2.15) == nil,
            "A centre cleared by consecutive misses must not be revived"
        )
        let anchor = PrimaryGolferIdentity(
            center: CGPoint(x: 0.50, y: 0.56),
            scale: 0.54
        )
        let movingGolfer = PrimaryGolferIdentity(
            center: CGPoint(x: 0.78, y: 0.55),
            scale: 0.53
        )
        let bystander = PrimaryGolferIdentity(
            center: CGPoint(x: 0.88, y: 0.55),
            scale: 0.53
        )

        precondition(PrimaryGolferTrackingPolicy.matches(candidate: movingGolfer, anchor: anchor))
        precondition(!PrimaryGolferTrackingPolicy.matches(candidate: bystander, anchor: anchor))
        precondition(PrimaryGolferTrackingPolicy.shouldRetainAnchor(afterConsecutiveMisses: 4))
        precondition(!PrimaryGolferTrackingPolicy.shouldRetainAnchor(afterConsecutiveMisses: 5))
    }
}

import Foundation

@main
struct PrimaryGolferTrackingPolicySmoke {
    static func main() {
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

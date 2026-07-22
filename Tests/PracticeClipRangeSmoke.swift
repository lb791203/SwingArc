import Foundation

@main
struct PracticeClipRangeSmoke {
    static func main() {
        let window = PracticeClipWindow.standard
        let centered = PracticeClipRangePolicy.resolve(
            impactTime: 3,
            sourceDuration: 5,
            window: window
        )
        precondition(centered == PracticeClipRange(start: 1, duration: 3))

        precondition(PracticeClipRangePolicy.resolve(
            impactTime: 1.99,
            sourceDuration: 5,
            window: window
        ) == nil)
        precondition(PracticeClipRangePolicy.resolve(
            impactTime: 4.01,
            sourceDuration: 5,
            window: window
        ) == nil)
    }
}

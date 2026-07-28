import Foundation

@main
struct CompactPlaybackPolicySmoke {
    static func main() {
        precondition(CompactPlaybackPolicy.minimumTouchTarget == 44)
        precondition(
            CompactPlaybackPolicy.command(
                for: .togglePlayback,
                isPlaying: false
            ) == .play
        )
        precondition(
            CompactPlaybackPolicy.command(
                for: .togglePlayback,
                isPlaying: true
            ) == .pause
        )
        precondition(
            CompactPlaybackPolicy.command(
                for: .previousFrame,
                isPlaying: true
            ) == .stepFrame(forward: false)
        )
        precondition(
            CompactPlaybackPolicy.command(
                for: .nextFrame,
                isPlaying: false
            ) == .stepFrame(forward: true)
        )
        precondition(
            CompactPlaybackPolicy.command(
                for: .selectRate(0.25),
                isPlaying: true
            ) == .setRate(0.25)
        )
    }
}

import Foundation

@main
struct FullscreenReplayPolicySmoke {
    static func main() {
        precondition(FullscreenReplayPolicy.action(for: .video) == .togglePlayback)
        precondition(FullscreenReplayPolicy.action(for: .feedbackPill) == .openFeedback)
        precondition(FullscreenReplayPolicy.action(for: .phase(.top)) == .seek(.top))
        precondition(FullscreenReplayPolicy.action(for: .dismiss) == .dismiss)

        precondition(
            SwingPhaseRailPolicy.appearance(for: .confirmed, hasMarker: true) == .confirmed
        )
        precondition(
            SwingPhaseRailPolicy.appearance(for: .review, hasMarker: true) == .subdued
        )
        precondition(
            SwingPhaseRailPolicy.appearance(for: .unresolved, hasMarker: false) == .hidden
        )
        precondition(FullscreenPlaybackPolicy.minimumTouchTarget == 44)
        precondition(!FullscreenPlaybackPolicy.showsTimeLabels)
        precondition(!FullscreenPlaybackPolicy.showsTransportButtons)
    }
}

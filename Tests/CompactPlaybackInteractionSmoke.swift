import Foundation

@main
struct CompactPlaybackInteractionSmoke {
    static func main() {
        var events: [String] = []
        let perform: (CompactPlaybackAction, Bool) -> Void = { action, isPlaying in
            CompactPlaybackInteraction.perform(
                action,
                isPlaying: isPlaying,
                play: { events.append("play") },
                pause: { events.append("pause") },
                stepFrame: { events.append($0 ? "next" : "previous") },
                setRate: { events.append("rate:\($0)") }
            )
        }

        perform(.togglePlayback, false)
        perform(.togglePlayback, true)
        perform(.previousFrame, true)
        perform(.nextFrame, false)
        perform(.selectRate(0.5), true)
        precondition(events == ["play", "pause", "previous", "next", "rate:0.5"])
    }
}

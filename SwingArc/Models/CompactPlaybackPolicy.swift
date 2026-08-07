import Foundation

enum CompactPlaybackAction: Equatable {
    case togglePlayback
    case previousFrame
    case nextFrame
    case selectRate(Double)
}

enum CompactPlaybackCommand: Equatable {
    case play
    case pause
    case stepFrame(forward: Bool)
    case setRate(Double)
}

enum CompactPlaybackPolicy {
    static let minimumTouchTarget: CGFloat = 44
    static let emphasizedTouchTarget: CGFloat = 50
    static let speedControlWidth: CGFloat = 48
    static let speedControlVisualHeight: CGFloat = 32
    static let rowHeight: CGFloat = 50
    static let controlSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 10

    static func command(
        for action: CompactPlaybackAction,
        isPlaying: Bool
    ) -> CompactPlaybackCommand {
        switch action {
        case .togglePlayback:
            return isPlaying ? .pause : .play
        case .previousFrame:
            return .stepFrame(forward: false)
        case .nextFrame:
            return .stepFrame(forward: true)
        case let .selectRate(rate):
            return .setRate(rate)
        }
    }
}

enum CompactPlaybackInteraction {
    static func perform(
        _ action: CompactPlaybackAction,
        isPlaying: Bool,
        play: () -> Void,
        pause: () -> Void,
        stepFrame: (Bool) -> Void,
        setRate: (Double) -> Void
    ) {
        switch CompactPlaybackPolicy.command(
            for: action,
            isPlaying: isPlaying
        ) {
        case .play:
            play()
        case .pause:
            pause()
        case let .stepFrame(forward):
            stepFrame(forward)
        case let .setRate(rate):
            setRate(rate)
        }
    }
}

import Foundation

@main
struct CompactPlaybackSourceSmoke {
    static func main() throws {
        let workspace = try String(
            contentsOfFile: "SwingArc/Views/AnalysisWorkspaceView.swift",
            encoding: .utf8
        )
        let components = try String(
            contentsOfFile: "SwingArc/Views/WorkspaceComponents.swift",
            encoding: .utf8
        )

        let mobile = try section(
            of: workspace,
            from: "private var mobileReplayOverlayControls",
            to: "private var mobileReplayActionRow"
        )
        precondition(mobile.contains("CompactPlaybackControlsView("))
        precondition(mobile.contains("MobileReplayTimelineView("))

        let controls = try section(
            of: components,
            from: "struct CompactPlaybackControlsView",
            to: "struct PlaybackControlsView"
        )
        precondition(controls.contains("CompactPlaybackInteraction.perform"))
        precondition(controls.contains("playbackManager.play"))
        precondition(controls.contains("playbackManager.pause"))
        precondition(controls.contains("playbackManager.stepFrame"))
        precondition(controls.contains("playbackManager.setSpeed"))
        for label in ["播放", "暂停", "前一帧", "后一帧", "播放速度"] {
            precondition(controls.contains(label))
        }
        precondition(controls.contains("CompactPlaybackPolicy.minimumTouchTarget"))
    }

    private static func section(
        of source: String,
        from start: String,
        to end: String
    ) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(
                  of: end,
                  range: startRange.upperBound..<source.endIndex
              ) else {
            throw SourceContractError.missing(start)
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
}

private enum SourceContractError: Error {
    case missing(String)
}

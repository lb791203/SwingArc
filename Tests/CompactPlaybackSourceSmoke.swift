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
        precondition(mobile.contains("VStack(spacing: CompactPlaybackPolicy.sectionSpacing)"))
        precondition(mobile.contains("CompactPlaybackControlsView("))
        precondition(mobile.contains("MobileReplayTimelineView("))
        precondition(mobile.contains(".contentShape(Rectangle())"))
        precondition(mobile.contains(".onTapGesture { }"))

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
        precondition(controls.contains("ZStack"))
        precondition(controls.contains("HStack(spacing: CompactPlaybackPolicy.controlSpacing)"))
        precondition(controls.contains("width: CompactPlaybackPolicy.speedControlWidth"))
        precondition(controls.contains("height: CompactPlaybackPolicy.speedControlVisualHeight"))
        precondition(controls.contains("Spacer(minLength: 0)"))
        precondition(controls.contains("CompactPlaybackPolicy.emphasizedTouchTarget"))
        precondition(controls.contains("frame(height: CompactPlaybackPolicy.rowHeight)"))
        precondition(controls.contains("Label(rate.label, systemImage: \"checkmark\")"))
        precondition(controls.contains(".overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))"))
        precondition(controls.contains(".contentShape(Rectangle())"))
        precondition(controls.contains(".onTapGesture { }"))
        precondition(controls.contains(".accessibilityElement(children: .contain)"))
        precondition(controls.contains("选择 0.1、0.25、0.5 或 1 倍速度"))
        for label in ["播放", "暂停", "前一帧", "后一帧", "播放速度"] {
            precondition(controls.contains(label))
        }
        precondition(controls.contains("CompactPlaybackPolicy.minimumTouchTarget"))

        let timeline = try section(
            of: components,
            from: "struct MobileReplayTimelineView",
            to: "private struct SwingStagePoseGlyph"
        )
        precondition(timeline.contains("Slider("))
        precondition(timeline.contains("accessibilityValue"))
        precondition(!timeline.contains("Text(formatTime"))
        precondition(!timeline.contains("private func formatTime"))
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

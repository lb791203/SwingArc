import Foundation

@main
struct PhoneCorrectionIntegrationSourceSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let content = try String(
            contentsOf: root.appendingPathComponent("SwingArc/Views/ContentView.swift"),
            encoding: .utf8
        )
        let workspace = try String(
            contentsOf: root.appendingPathComponent("SwingArc/Views/AnalysisWorkspaceView.swift"),
            encoding: .utf8
        )
        let components = try String(
            contentsOf: root.appendingPathComponent("SwingArc/Views/WorkspaceComponents.swift"),
            encoding: .utf8
        )
        let playback = try String(
            contentsOf: root.appendingPathComponent("SwingArc/Views/CustomVideoPlayer.swift"),
            encoding: .utf8
        )

        precondition(content.contains("showPPointCorrection"))
        precondition(content.contains("PPointCorrectionWorkspace("))
        precondition(content.contains("refineManualPPoint("))
        precondition(content.contains("refineManualPPoints("))
        precondition(content.contains("markers: keyframes"))
        precondition(content.contains("sourceFrameIndex: sourceFrameIndex"))
        precondition(content.contains("playbackManager.seek(to: marker)"))
        precondition(!content.contains("AnnotationWorkspaceView("))
        let fullscreenStart = workspace.range(
            of: "struct FullscreenVideoPlaybackView"
        )!.lowerBound
        let publicWorkspace = String(workspace[..<fullscreenStart])

        precondition(publicWorkspace.contains("let onCorrectPPoints: () -> Void"))
        precondition(publicWorkspace.contains(".accessibilityLabel(\"修正 P 点\")"))
        precondition(publicWorkspace.contains("Text(\"画线\")"))
        precondition(!publicWorkspace.contains("选择拍摄视角"))
        precondition(!publicWorkspace.contains("title: \"正后方 DTL\""))
        precondition(!publicWorkspace.contains("title: \"正面 Face-on\""))
        precondition(!publicWorkspace.contains("SimplifiedSwingFeedbackView("))
        precondition(!publicWorkspace.contains("trajectoryCategory:"))
        precondition(components.contains("let onCorrectPPoints: () -> Void"))
        precondition(components.contains("Text(\"修正 P 点\")"))
        let mobileTimeline = try section(
            of: components,
            from: "struct MobileReplayTimelineView",
            to: "private struct SwingStagePoseGlyph"
        )
        precondition(mobileTimeline.contains("let onCorrectPPoints: () -> Void"))
        precondition(mobileTimeline.contains("onCorrectPPoints()"))
        precondition(mobileTimeline.contains("playbackManager.seek(to: marker)"))
        precondition(!mobileTimeline.contains("playbackManager.seek(to: marker.time)"))
        precondition(
            !mobileTimeline.contains(".allowsHitTesting(marker != nil)"),
            "An unresolved P stage must remain actionable"
        )
        precondition(
            mobileTimeline.contains(
                ".accessibilityHint(marker == nil ? \"打开 P 点修正\" : \"跳到该阶段\")"
            )
        )
        let mobileCall = try section(
            of: workspace,
            from: "MobileReplayTimelineView(",
            to: ")"
        )
        precondition(mobileCall.contains("onCorrectPPoints: onCorrectPPoints"))
        precondition(
            playback.contains("func seek(to marker: KeyframeMarker)") &&
                playback.contains("session?.presentationTime(") &&
                playback.contains("exactPresentationTime: exactTime"),
            "P-point playback must resolve the persisted source frame before seeking"
        )
        precondition(
            !workspace.contains("playbackManager.seek(to: marker.time)"),
            "Workspace stage actions must not discard the persisted source frame"
        )
        precondition(
            !components.contains("onSeek(marker.time)") &&
                !components.contains("onSelect(marker.time)"),
            "Inspector and fullscreen stage actions must retain the source frame"
        )
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

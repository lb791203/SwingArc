import Foundation

@main
struct CaptureReplayPresentationSmoke {
    static func main() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let practiceModels = read(root.appending(path: "SwingArc/Models/PracticeModels.swift"))
        let camera = read(root.appending(path: "SwingArc/Views/CameraView.swift"))
        let workspace = read(root.appending(path: "SwingArc/Views/AnalysisWorkspaceView.swift"))
        let components = read(root.appending(path: "SwingArc/Views/WorkspaceComponents.swift"))
        let library = read(root.appending(path: "SwingArc/Views/ProjectLibraryView.swift"))
        let home = read(root.appending(path: "SwingArc/Views/PracticeHomeView.swift"))
        let content = read(root.appending(path: "SwingArc/Views/ContentView.swift"))
        let practiceSession = read(root.appending(path: "SwingArc/Views/PracticeSessionView.swift"))

        precondition(
            practiceModels.contains("case .aligning:\n            return nil"),
            "Alignment copy must live beside the frame, not repeat in the status card."
        )
        precondition(camera.contains("ManualCapturePresentation.title"))
        precondition(camera.contains("ManualCapturePresentation.framingPrompt"))
        precondition(workspace.contains("mobileReplayWorkbench"))
        precondition(workspace.contains("mobileReplayHeader"))
        precondition(workspace.contains("mobileAnalysisStatus"))
        precondition(workspace.contains("mobileReplayOverlayControls"))
        precondition(!workspace.contains("AnalysisProgressCard("))
        let mobileTimeline = section(
            from: "struct MobileReplayTimelineView",
            until: "struct PlaybackControlsView",
            in: components
        )
        precondition(mobileTimeline.contains("ForEach(SwingStage.allCases)"))
        precondition(mobileTimeline.contains("SwingStagePoseGlyph"))
        precondition(!mobileTimeline.contains("Text(stage.pNumber)"))
        precondition(!mobileTimeline.contains("Image(systemName: \"figure.golf\")"))
        precondition(mobileTimeline.contains(".allowsHitTesting(marker != nil)"))
        precondition(!mobileTimeline.contains(".disabled(marker == nil)"))
        precondition(components.contains("struct SwingStagePoseGlyph"))
        precondition(components.contains("private enum SwingStagePoseCue"))
        for cue in [
            "准备：双膝微屈，杆头落在球后",
            "起杆：杆身在身后平行地面",
            "上杆左臂平行：左臂平行地面，右肘收拢",
            "上杆顶点：双手越过后肩，杆身横过肩线",
            "下杆左臂平行：左臂平行地面，杆身从身后下落",
            "下杆杆身平行：双手降至前髋，杆身水平滞后",
            "击球：双臂伸向球位，杆身前倾",
            "送杆杆身平行：双臂越过身体，杆身再次平行"
        ] {
            precondition(
                components.contains(cue),
                "Each replay glyph must describe the real swing checkpoint: \(cue)"
            )
        }
        precondition(components.contains("case .address:"))
        precondition(components.contains("case .shaftParallelDownswing:"))
        precondition(components.contains("case .finish:"))
        precondition(!workspace.contains("showsFullscreenPlayback"))
        precondition(!workspace.contains("arrow.up.left.and.arrow.down.right"))
        precondition(!library.contains("showsNewProjectSheet"))
        precondition(!library.contains("NewProjectSheet"))
        precondition(!library.contains("let onImport"))
        precondition(!library.contains("Button(action: onImport)"))
        precondition(!library.contains("Label(\"导入视频\""))
        precondition(!library.contains("onRecord"))
        precondition(home.contains("let onImport"))
        let homeHeader = section(
            from: "private var header",
            until: "@ViewBuilder\n    private func modeSelector",
            in: home
        )
        precondition(!homeHeader.contains("LOCAL AI"))
        precondition(homeHeader.contains("Text(\"记录\")"))
        precondition(homeHeader.contains("Button(action: onOpenLibrary)"))
        let modeSelector = section(
            from: "private func modeSelector",
            until: "private func utilityButton",
            in: home
        )
        let importVideoMode = section(
            from: "case .importVideo:",
            until: "case .history:",
            in: modeSelector
        )
        precondition(importVideoMode.contains("PracticeModeSelector("))
        precondition(content.contains("import PhotosUI"))
        precondition(content.contains("showVideoPicker"))
        precondition(content.contains("onImport: { showVideoPicker = true }"))
        precondition(content.contains(".photosPicker"))
        precondition(content.contains("loadVideoFromURL(videoURL, origin: .importCompleted)"))
        precondition(content.contains("origin: .capturedClipSaved"))
        precondition(practiceSession.contains(".onChange(of: persistedLastClipURL)"))
        precondition(practiceSession.contains("onOpenLastClip(clipURL)"))
        precondition(!content.contains("showCameraView"))
        precondition(workspace.contains("mobileReplayActionRow"))
        precondition(workspace.contains("Text(\"标注\")"))
        let mobileActionRow = section(
            from: "private var mobileReplayActionRow",
            until: "private func toggleWorkspacePlayback",
            in: workspace
        )
        precondition(
            mobileActionRow.contains("onAnalyze()"),
            "Portrait replay must keep a retry/manual analysis action for reopened or failed projects"
        )
    }

    private static func read(_ url: URL) -> String {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Missing source file: \(url.path)")
        }
        return contents
    }

    private static func section(from start: String, until end: String, in source: String) -> String {
        guard let startRange = source.range(of: start) else {
            return ""
        }
        let tail = source[startRange.lowerBound...]
        guard let endRange = tail.range(of: end) else {
            return String(tail)
        }
        return String(tail[..<endRange.lowerBound])
    }
}

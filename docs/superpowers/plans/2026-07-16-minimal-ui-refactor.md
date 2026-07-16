# SwingArc Minimal Professional UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Replace SwingArc’s golf-themed dashboard prototype with a focused iPhone video-analysis library, recorder, and editing workbench.

**Architecture:** Retain AVFoundation playback/capture and the drawing engine behind focused SwiftUI screens. ContentView becomes a navigation shell; ProjectLibraryView owns entry and selection; AnalysisWorkspaceView owns the active-video UI; reusable timeline, layer menu, and tool tray receive bindings rather than owning media state.

**Tech Stack:** SwiftUI, AVFoundation, PhotosUI, Vision, XCTest, iOS 17.0+.

## Global Constraints

- No screen may show a golf course, club type, score, rating, coaching advice, AI diagnosis, lesson, social feed, account, or cloud-sync UI.
- Use a neutral light project-library surface and graphite-black video workbench.
- Use white for neutral UI, yellow for current-frame/active-marker/editing state, and cyan only for optional pose overlays.
- The available local developer tools do not include full Xcode; source edits receive static verification now and iPhone/Xcode verification later.

---

## Files and ownership

| Path | Responsibility |
| --- | --- |
| SwingArc/Design/AnalysisTheme.swift | Named colors and pure workspace state. |
| SwingArc/Views/ContentView.swift | Navigation shell and media-entry routing. |
| SwingArc/Views/ProjectLibraryView.swift | Neutral project library and import/record actions. |
| SwingArc/Views/AnalysisWorkspaceView.swift | Header, player canvas, modes and sheets for one loaded video. |
| SwingArc/Views/TimelineControlView.swift | Playback, speed, frame step, scrubber and stage markers. |
| SwingArc/Views/LayerMenuView.swift | Non-blocking pose/grid controls. |
| SwingArc/Views/DrawingToolTray.swift | On-demand tool, color, width, undo and clear controls. |
| SwingArc/Views/CameraView.swift | Neutral recording UI and optional framing guide. |
| SwingArc/Views/DrawingOverlay.swift | Existing geometry/magnifier with neutral presentation. |
| SwingArcTests/AnalysisThemeTests.swift | Pure UI state tests after the Xcode target exists. |

## Task 1: Establish the neutral visual system and workbench state

**Files:**
- Create: SwingArc/Design/AnalysisTheme.swift
- Create: SwingArcTests/AnalysisThemeTests.swift

**Interfaces:**
- Produces AnalysisTheme, WorkspaceMode, and PlaybackRate.
- Consumed by every UI task.

- [ ] **Step 1: Write failing pure state tests**

~~~swift
import XCTest
@testable import SwingArc

final class AnalysisThemeTests: XCTestCase {
    func testDrawingModeEnablesTrayAndPausesPlayback() {
        XCTAssertTrue(WorkspaceMode.drawing.showsToolTray)
        XCTAssertTrue(WorkspaceMode.drawing.requiresPausedPlayback)
        XCTAssertFalse(WorkspaceMode.layers.showsToolTray)
    }

    func testPlaybackRatesExposeRequiredValues() {
        XCTAssertEqual(PlaybackRate.allCases.map(\.value), [0.1, 0.25, 0.5, 1.0])
    }
}
~~~

- [ ] **Step 2: Record the current Xcode verification block**

Run: xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SwingArcTests/AnalysisThemeTests

Expected now: failure because the repository has no Xcode project and the active developer directory is Command Line Tools. Do not install Xcode or fabricate test output.

- [ ] **Step 3: Implement the pure visual state**

~~~swift
import SwiftUI

enum AnalysisTheme {
    static let libraryBackground = Color(red: 0.95, green: 0.95, blue: 0.94)
    static let canvasBackground = Color(red: 0.08, green: 0.09, blue: 0.09)
    static let chrome = Color(red: 0.16, green: 0.17, blue: 0.17)
    static let active = Color(red: 0.97, green: 0.79, blue: 0.26)
    static let overlay = Color(red: 0.26, green: 0.83, blue: 0.77)
}

enum WorkspaceMode: Equatable {
    case idle, layers, drawing, keyframes
    var showsToolTray: Bool { self == .drawing }
    var requiresPausedPlayback: Bool { self == .drawing }
}

enum PlaybackRate: Double, CaseIterable, Identifiable {
    case tenth = 0.1, quarter = 0.25, half = 0.5, normal = 1
    var id: Double { rawValue }
    var value: Double { rawValue }
    var label: String { rawValue == 1 ? "1×" : "\(rawValue)×" }
}
~~~

- [ ] **Step 4: Static-check and commit**

Run: swiftc -parse SwingArc/Design/AnalysisTheme.swift

Expected: no output and exit code 0.

~~~bash
git add SwingArc/Design/AnalysisTheme.swift SwingArcTests/AnalysisThemeTests.swift
git commit -m "feat: add minimal analysis UI theme"
~~~

## Task 2: Replace the entry screen with a neutral project library

**Files:**
- Create: SwingArc/Views/ProjectLibraryView.swift
- Modify: SwingArc/Views/ContentView.swift

**Interfaces:**
- Consumes AnalysisTheme and closures onRecord and onImport.
- Produces ProjectLibraryView(hasActiveVideo:onRecord:onImport:).

- [ ] **Step 1: Define and implement the library**

~~~swift
struct ProjectLibraryView: View {
    let hasActiveVideo: Bool
    let onRecord: () -> Void
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("分析项目")
            }
                .navigationTitle("分析项目")
        }
    }
}
~~~

Use a title “分析项目”, a plus button, and an empty-state pair of full-width buttons labelled “录制视频” and “导入视频”. When a video is loaded, show one neutral thumbnail card named “未命名分析” with duration and annotation state. Do not include any of these strings: 高尔夫, 挥杆评分, AI 诊断, 球场, 球杆.

- [ ] **Step 2: Connect current routing**

In ContentView, remove emptyStateView, topMenuBar, showAnalysisReport, swingScore, headSwayScore, and spineAngleDelta. Render ProjectLibraryView when player is nil, with onRecord setting showCameraView true and onImport setting showVideoPicker true.

- [ ] **Step 3: Static-check and commit**

Run: swiftc -parse SwingArc/Views/ProjectLibraryView.swift

Expected: no output and exit code 0.

~~~bash
git add SwingArc/Views/ProjectLibraryView.swift SwingArc/Views/ContentView.swift
git commit -m "feat: add neutral analysis project library"
~~~

## Task 3: Build the video-first analysis workbench and timeline

**Files:**
- Create: SwingArc/Views/AnalysisWorkspaceView.swift
- Create: SwingArc/Views/TimelineControlView.swift
- Modify: SwingArc/Views/ContentView.swift

**Interfaces:**
- Consumes VideoPlaybackManager, DrawingElement bindings, KeyframeMarker bindings, and WorkspaceMode.
- Produces AnalysisWorkspaceView(playbackManager:drawings:keyframes:onExit:).

- [ ] **Step 1: Define the workbench interface**

~~~swift
struct AnalysisWorkspaceView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    @Binding var drawings: [DrawingElement]
    @Binding var keyframes: [KeyframeMarker]
    let onExit: () -> Void
    @State private var mode: WorkspaceMode = .idle
}
~~~

- [ ] **Step 2: Implement fixed workbench hierarchy**

Render a graphite VStack in this exact order: header with back, project title and export; PlayerViewRepresentable plus DrawingOverlay sharing videoRect; TimelineControlView; mode row; conditionally expanded LayerMenuView or DrawingToolTray. Delete the leftToolPanel and rightAnalysisPanel landscape branches so portrait is the only iPhone workbench layout.

- [ ] **Step 3: Implement timeline controls**

~~~swift
struct TimelineControlView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    @Binding var keyframes: [KeyframeMarker]
    let onManualMarker: (SwingStage) -> Void
}
~~~

Render play/pause, previous/next frame, a menu of PlaybackRate, and a scrubber bound to currentTime. Render Address, Top, Impact, and Finish as tappable markers above the scrubber. Tap calls seek(to:); long press calls onManualMarker using current time.

- [ ] **Step 4: Connect media flow**

ContentView shows ProjectLibraryView until existing photo-picker or CameraView callback calls loadVideoFromURL. It then shows AnalysisWorkspaceView. The workbench back action calls playbackManager.unloadVideo() and returns to the library without deleting the imported temporary file.

- [ ] **Step 5: Static-check and commit**

Run: swiftc -parse SwingArc/Views/AnalysisWorkspaceView.swift SwingArc/Views/TimelineControlView.swift

Expected: no output and exit code 0.

~~~bash
git add SwingArc/Views/AnalysisWorkspaceView.swift SwingArc/Views/TimelineControlView.swift SwingArc/Views/ContentView.swift
git commit -m "feat: add video-first analysis workbench"
~~~

## Task 4: Make overlays and drawing tools explicitly on-demand

**Files:**
- Create: SwingArc/Views/LayerMenuView.swift
- Create: SwingArc/Views/DrawingToolTray.swift
- Modify: SwingArc/Views/AnalysisWorkspaceView.swift
- Modify: SwingArc/Views/DrawingOverlay.swift

**Interfaces:**
- Consumes WorkspaceMode and drawing/pose/grid bindings.
- Produces LayerMenuView and DrawingToolTray.

- [ ] **Step 1: Implement layer menu**

~~~swift
struct LayerMenuView: View {
    @Binding var showsPose: Bool
    @Binding var showsHeadTrace: Bool
    @Binding var showsSpine: Bool
    @Binding var showsGrid: Bool
    let noPoseDetected: Bool
}
~~~

Use four Toggle rows: 骨架, 头部轨迹, 脊椎倾斜线, 参考网格. Show 未检测到人体 only when noPoseDetected is true. No layer is enabled by default.

- [ ] **Step 2: Implement drawing tray**

~~~swift
struct DrawingToolTray: View {
    @Binding var activeTool: DrawingTool
    @Binding var selectedColor: Color
    @Binding var strokeWidth: CGFloat
    let onUndo: () -> Void
    let onClear: () -> Void
}
~~~

Render existing tool cases horizontally followed by yellow/cyan/white color choices, a width control, undo, and clear. It appears only when mode is drawing; entering drawing pauses playback and leaving returns mode to idle.

- [ ] **Step 3: Remove product-specific overlay UI**

Delete the “头部高度” label from DrawingOverlay. Keep skeleton, head trace, spine line, control handles and 2x vector magnifier. Use AnalysisTheme.overlay for pose strokes, AnalysisTheme.active for active edit handles, and white for neutral handles.

- [ ] **Step 4: Static-check and commit**

Run: swiftc -parse SwingArc/Views/LayerMenuView.swift SwingArc/Views/DrawingToolTray.swift

Expected: no output and exit code 0.

~~~bash
git add SwingArc/Views/LayerMenuView.swift SwingArc/Views/DrawingToolTray.swift SwingArc/Views/AnalysisWorkspaceView.swift SwingArc/Views/DrawingOverlay.swift
git commit -m "feat: add on-demand layers and drawing tray"
~~~

## Task 5: Simplify recorder and document the verification gap

**Files:**
- Modify: SwingArc/Views/CameraView.swift
- Modify: README.md
- Create: docs/verification/2026-07-16-minimal-ui-handoff.md

**Interfaces:**
- Consumes CameraStateModel.
- Produces neutral camera copy, optional framing guide, actual selected frame-rate status.

- [ ] **Step 1: Replace golf-specific camera chrome**

Remove green head circle, stance rails, “请对齐头部与身体框架”, and the hardcoded “120 FPS 慢动作录像” badge. Keep close, camera flip, actual FPS, optional low-contrast full-person framing rectangle, countdown, recording status, and record/stop control.

- [ ] **Step 2: Display the actual selected frame rate**

Add published selectedFrameRate Double set from the active device format in configureHighFrameRate(for:). Render the selected FPS when positive, otherwise “正在配置相机”. Do not hardcode 120 or 240 FPS in the UI.

- [ ] **Step 3: Add verification handoff**

Document hardware checks for camera permission; frame-rate fallback; recording; import; portrait/landscape playback; all four speeds; frame stepping; layer toggles; every drawing tool; magnifier; and exported marks.

- [ ] **Step 4: Inspect and commit**

Run:

~~~bash
rg -n "高尔夫|球场|球杆|评分|AI 诊断|极佳|优秀" SwingArc README.md
git diff --check
~~~

Expected: no product-facing matches in active UI sources and no whitespace errors.

~~~bash
git add SwingArc/Views/CameraView.swift README.md docs/verification/2026-07-16-minimal-ui-handoff.md
git commit -m "feat: simplify recording for video analysis"
~~~

## Spec coverage check

| UI requirement | Implementing task |
| --- | --- |
| Neutral local project library | 2 |
| Native recording with honest FPS state | 5 |
| Video-first black workbench | 3 |
| Playback, frame step, speed, timeline and keyframes | 3 |
| Optional pose/grid layers | 4 |
| On-demand drawing tray and magnifier | 4 |
| No golf lifestyle, scoring, advice or dashboard UI | 2, 3, 4, 5 |
| Static and later real-device verification | 1, 5 |

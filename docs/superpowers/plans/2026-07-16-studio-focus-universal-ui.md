# SwingArc Studio Focus Universal UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the prototype editor with the confirmed Studio Focus project library and adaptive iPhone/iPad analysis workbench while preserving and committing the current P1–P8 detector fixes.

**Architecture:** `ContentView` becomes the media and persistence coordinator. Focused SwiftUI components render the light project library, the stable dark video workbench, the stage timeline, drawing rail, progress card and inspectors; pure workspace policies live in a Foundation model so they can be smoke-tested without a simulator. Existing AVFoundation, Vision, drawing and export services remain the implementation layer.

**Tech Stack:** Swift 5, SwiftUI, AVFoundation, PhotosUI, Vision, UIKit, iOS 17+; pure `swiftc` smoke tests plus the external `SwingArcProject.xcodeproj` device build.

## Global Constraints

- The first screen is a light local project library; the analysis workbench is graphite dark.
- The first release is for a personal player and contains no coaching, lesson, messaging, social, scoring or cloud-account UI.
- Video remains the largest stable workbench region; opening tools or analysis state must not resize it.
- Green means a primary action or confirmed state, yellow means the current context or review warning, cyan means pose overlay, and white means neutral drawing.
- P1–P8 uses a single-row 1x8 stage strip on compact and regular widths; every target is 44pt high.
- Drawing mode pauses playback and shows the rail; leaving drawing mode hides the rail but keeps global annotations visible.
- AI progress is non-blocking, cancellable and based only on real work performed by the current detector.
- Manual stage markers remain locked and automatic analysis cannot overwrite them.
- The current dirty changes in `SwingStageDetector.swift`, `ContentView.swift` and `CustomVideoPlayer.swift` are in scope and must land in the same final commit.
- Work in the current checkout because those requested dirty changes exist only there; do not create a worktree that omits them.

---

### Task 1: Establish testable workspace and project-library contracts

**Files:**
- Create: `SwingArc/Models/WorkspaceModels.swift`
- Modify: `SwingArc/Services/LocalProjectStore.swift`
- Create: `Tests/WorkspaceModelsSmoke.swift`
- Create: `Tests/ProjectLibraryStoreSmoke.swift`

**Interfaces:**
- Produces: `WorkspaceLayoutMode.resolve(isRegularWidth:)`, `AnalysisProgressPhase`, `AnalysisProgressPresentation`, `AnalysisRunGate`, `WorkspaceSaveStatus`, `StageResultSummary`.
- Produces: `LocalProjectSummary`, `LocalProjectStore.projects()`, `upsertSummary(_:)`, `rename(_:to:)`, and `remove(_:)`.
- Consumes: existing `LocalAnalysisProject`, `SwingStageDetectionStatus` and per-video persistence keys.

- [ ] **Step 1: Write failing workspace-policy smoke tests**

```swift
import Foundation

@main
struct WorkspaceModelsSmoke {
    static func main() {
        precondition(WorkspaceLayoutMode.resolve(isRegularWidth: false) == .compact)
        precondition(WorkspaceLayoutMode.resolve(isRegularWidth: true) == .regular)
        precondition(AnalysisProgressPresentation(phase: .extracting, progress: 0.5).title == "逐帧提取")
        precondition(StageResultSummary(statuses: [.confirmed, .confirmed, .lowConfidence, .unresolved]).confirmed == 2)

        let gate = AnalysisRunGate()
        let first = gate.begin()
        let second = gate.begin()
        precondition(!gate.isActive(first))
        precondition(gate.isActive(second))
        gate.cancel()
        precondition(!gate.isActive(second))
    }
}
```

- [ ] **Step 2: Run the workspace test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library SwingArc/Models/WorkspaceModels.swift Tests/WorkspaceModelsSmoke.swift -o /tmp/workspace-models
```

Expected: compile failure because `WorkspaceModels.swift` and the named contracts do not exist.

- [ ] **Step 3: Implement the minimal pure contracts**

```swift
enum WorkspaceLayoutMode { case compact, regular }
enum AnalysisProgressPhase { case preparing, extracting, solving }
struct AnalysisProgressPresentation { let phase: AnalysisProgressPhase; let progress: Double }
final class AnalysisRunGate {
    private var activeID: UUID?
    func begin() -> UUID { let id = UUID(); activeID = id; return id }
    func cancel() { activeID = nil }
    func isActive(_ id: UUID) -> Bool { activeID == id }
}
```

Add exact localized titles, clamped percentage and status counts required by the smoke test.

- [ ] **Step 4: Write the failing project-index smoke test**

Use an injected `UserDefaults(suiteName:)` store, upsert two summaries with different `modifiedAt` values, assert newest-first ordering, rename one, remove one, and assert the remaining identifier and name.

- [ ] **Step 5: Run the project-index test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Models/WorkspaceModels.swift \
SwingArc/Services/LocalProjectStore.swift Tests/ProjectLibraryStoreSmoke.swift -o /tmp/project-library
```

Expected: compile failure because `LocalProjectSummary` and injected storage do not exist.

- [ ] **Step 6: Implement the indexed local library and verify GREEN**

Keep the current per-video `LocalAnalysisProject` payload. Add a Codable summary index keyed by video URL, inject `UserDefaults` with `.standard` as the default, sort by `modifiedAt` descending, and make rename/remove update only the requested summary and payload. Run both commands from Steps 2 and 5; both executables must exit 0.

---

### Task 2: Build the light project library and root coordinator

**Files:**
- Create: `SwingArc/Views/ProjectLibraryView.swift`
- Modify: `SwingArc/Views/ContentView.swift`

**Interfaces:**
- Produces: `ProjectLibraryView(projects:onOpen:onImport:onRecord:onRename:onDelete:)` and `NewProjectSheet(onImport:onRecord:)`.
- Consumes: `LocalProjectSummary` and coordinator callbacks; it does not read files or invoke AVFoundation directly.
- Produces: a smaller `ContentView` that owns picker/camera sheets, active URL, playback state, persistence and export routing.

- [ ] **Step 1: Replace the entry view**

Render a `NavigationStack` with title `分析项目`, one add button, newest-first project cards and a two-action empty state. Do not include the network demo entry, score, coaching copy, or permanently visible import/camera buttons.

- [ ] **Step 2: Add a discoverable new-project sheet**

`NewProjectSheet` presents equal-weight `导入视频` and `录制视频` buttons, each at least 50pt high, and dismisses before invoking the coordinator closure.

- [ ] **Step 3: Add real video thumbnails and project actions**

`VideoThumbnailView` asynchronously asks `AVAssetImageGenerator` for the first frame. Each project card displays name, duration, source fps, state and modification date; its menu exposes rename and delete. Delete requires confirmation in the library.

- [ ] **Step 4: Refactor `ContentView` into a coordinator**

When no active URL exists, show `ProjectLibraryView`. Import/record persists the media, creates or updates a summary and opens the workbench. Opening an existing summary loads its saved annotations. Returning to the library pauses and unloads playback but does not delete the project.

- [ ] **Step 5: Static parse the library**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse \
SwingArc/Views/ProjectLibraryView.swift SwingArc/Views/ContentView.swift
```

Expected: exit 0 with no parse diagnostics.

---

### Task 3: Build the adaptive Studio Focus workbench

**Files:**
- Create: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Create: `SwingArc/Views/WorkspaceComponents.swift`
- Modify: `SwingArc/Design/AnalysisTheme.swift`
- Modify: `SwingArc/Views/ContentView.swift`

**Interfaces:**
- Produces: `AnalysisWorkspaceView`, `VideoCanvasView`, `StageTimelineView`, `PlaybackControlsView`, `DrawingToolRail`, `AnalysisProgressCard`, `StageInspectorView`, and `WorkspaceInspectorView`.
- Consumes: one `VideoPlaybackManager`, bindings for drawings, keyframes and overlay preferences, plus callbacks for back, export, analyze, cancel and project selection.

- [ ] **Step 1: Extend named theme tokens**

Add warm library background, white card, graphite canvas, blue-gray control surface, green confirmed, yellow current, cyan pose and system red destructive tokens. Use Dynamic Type styles in views rather than fixed display sizes.

- [ ] **Step 2: Implement the stable center workbench**

The center column is always header, expanding video canvas, scrubber plus P1–P8, and playback/mode controls. The header contains back, project name/save state, export and more only. No analysis or drawing tools live in the header.

- [ ] **Step 3: Implement adaptive stage layout**

`StageTimelineView` uses four flexible columns in compact width and eight in regular width. A marker shows `✓`, low confidence shows `!`, unresolved shows `未确定`, manual shows a lock, and the stage nearest the current frame receives the yellow current treatment. Every stage button has `minHeight: 44` and a complete VoiceOver label.

- [ ] **Step 4: Replace the jog dial with explicit playback controls**

Provide speed menu values `0.1×`, `0.25×`, `0.5×`, `1×`, previous frame, play/pause, next frame, drawing and AI. `VideoPlaybackManager` exposes source fps and steps by `1 / sourceFrameRate` instead of a fixed 1/60 second.

- [ ] **Step 5: Implement iPad regular-width columns**

In regular width, show a collapsible project sidebar, the center workbench and a non-overlapping 300pt inspector. In compact width, omit both side columns and use sheets for results and stage adjustment. Choose by horizontal size class, not device model.

- [ ] **Step 6: Static parse all new UI files**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse \
SwingArc/Views/AnalysisWorkspaceView.swift SwingArc/Views/WorkspaceComponents.swift \
SwingArc/Views/ProjectLibraryView.swift SwingArc/Views/ContentView.swift
```

Expected: exit 0 with no parse diagnostics.

---

### Task 4: Make drawing, analysis progress and manual stages truthful

**Files:**
- Modify: `SwingArc/Views/DrawingOverlay.swift`
- Modify: `SwingArc/Views/CustomVideoPlayer.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `SwingArc/Views/WorkspaceComponents.swift`
- Modify: `Tests/SwingPhaseTransitionSmoke.swift`

**Interfaces:**
- `DrawingOverlay` consumes `isInteractionEnabled`; saved drawings render in every workspace mode, while drag gestures activate only in drawing mode.
- `VideoPlaybackManager` produces `analysisProgressPhase`, `cancelAnalysis()`, `sourceFrameRate`, and `unloadVideo()`.
- `StageInspectorView` produces explicit seek and adjust actions; the coordinator writes manual `KeyframeMarker` values through `StageMarkerMerger`.

- [ ] **Step 1: Protect the requested P5/P6 detector behavior**

Run the existing `SwingPhaseTransitionSmoke` against the dirty detector and verify it chooses P5 at the shoulder-line crossing and P6 at the hip-aligned high-speed frame.

- [ ] **Step 2: Add the interaction-mode test before changing the overlay**

Extend `WorkspaceModelsSmoke` with `WorkspaceModeTransition.enterDrawing(isPlaying: true)` and assert it requests pause and shows the rail; assert `.beginPlayback` returns idle and hides the rail. Run and verify the new assertions fail to compile before implementing the transition policy.

- [ ] **Step 3: Gate drawing gestures without gating rendering**

Pass `isInteractionEnabled: mode == .drawing` into `DrawingOverlay`. The canvas continues to render every `DrawingDisplayPolicy`-approved element, but the transparent drag layer has hit testing disabled outside drawing mode. Entering drawing pauses; playing or tapping `完成` returns to idle.

- [ ] **Step 4: Add cancellable current-run analysis**

Use `AnalysisRunGate` in `VideoPlaybackManager`: `analyzeSwing` starts a new identifier, the extraction loop and every main-thread write check that identifier, and `cancelAnalysis()` invalidates it and returns to idle. Publish `.preparing`, `.extracting`, then `.solving` only when those operations actually run.

- [ ] **Step 5: Add compact progress and result presentations**

During scanning, compact width shows `AnalysisProgressCard` above controls and regular width shows the same information in `WorkspaceInspectorView`. Completed results summarize confirmed, review and unresolved counts. Failures show a specific reason and recovery action without clearing drawings.

- [ ] **Step 6: Add explicit manual adjustment**

Every inspector stage row has `调整`. `StageAdjustmentSheet` shows stage name, confidence, current time, frame number, previous/next-frame buttons, `设为当前帧` and cancel. Saving creates a `.manual` marker; later automatic results merge around it without overwrite.

- [ ] **Step 7: Verify the interaction and detector smoke tests are GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
SwingArc/Models/DrawingModels.swift SwingArc/Models/WorkspaceModels.swift \
Tests/WorkspaceModelsSmoke.swift -o /tmp/workspace-models && /tmp/workspace-models

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift \
Tests/SwingPhaseTransitionSmoke.swift -o /tmp/swing-phase && /tmp/swing-phase
```

Expected: both commands exit 0.

---

### Task 5: Integrate, build, install and commit the complete requested scope

**Files:**
- Modify outside repository for build only: `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj`
- Modify: `README.md`
- Include all source, tests and this plan in the repository commit.

**Interfaces:**
- External Xcode project references each new repository source file; it remains a build harness and is not added to this Git repository.
- The final Git commit contains the Studio Focus implementation and the previously dirty P1–P8 fixes together.

- [ ] **Step 1: Add new files to the external Xcode build harness**

Add file references and Sources build-phase entries for `WorkspaceModels.swift`, `ProjectLibraryView.swift`, `AnalysisWorkspaceView.swift`, and `WorkspaceComponents.swift`, all relative to the existing `../SwingArc/SwingArc` group.

- [ ] **Step 2: Run the full pure smoke suite**

Compile and execute every file in `Tests/` with its declared source dependencies. Required result: every executable exits 0; no failure is ignored.

- [ ] **Step 3: Type-check the complete iOS source set**

Run with the iOS simulator SDK and all repository Swift sources:

```bash
SDK=$(DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun --sdk iphonesimulator --show-sdk-path)
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
  -target arm64-apple-ios27.0-simulator -sdk "$SDK" -typecheck \
  SwingArc/Models/*.swift SwingArc/Services/*.swift SwingArc/Views/*.swift \
  SwingArc/Design/*.swift SwingArc/SwingArcApp.swift
```

Expected: exit 0.

- [ ] **Step 4: Build and install the iPhone app**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject -destination 'id=ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3' \
  -allowProvisioningUpdates build
```

Install the produced `Debug-iphoneos/SwingArcProject.app` with `devicectl`, launch it, and visually verify the project library, workbench, drawing rail, P1–P8 grid and non-blocking analysis card in the connected mirror.

- [ ] **Step 5: Verify Git scope and commit once**

Run `git diff --check`, inspect `git status --short`, and confirm the diff contains no `.superpowers` state or external project files. Then:

```bash
git add SwingArc Tests README.md docs/superpowers/plans/2026-07-16-studio-focus-universal-ui.md
git commit -m "feat: implement Studio Focus universal workspace"
```

The commit must include the requested `SwingStageDetector.swift` and `CustomVideoPlayer.swift` P1–P8/debug changes together with the UI implementation.

## Self-review

- Spec coverage: Tasks 2–4 cover the light library, dark stable workbench, single-row 1x8 stages, explicit playback, drawing persistence, truthful non-blocking progress, manual locks, compact sheets and regular-width sidebars.
- Detection scope: Task 4 preserves the requested current P5/P6 changes but does not claim the parked two-stage algorithm has been implemented.
- Type consistency: the same `AnalysisProgressPhase`, `AnalysisRunGate`, `LocalProjectSummary` and component names are used from model tests through coordinator and build integration.
- Placeholder scan: no TBD, TODO, “implement later”, or unspecified test step remains.

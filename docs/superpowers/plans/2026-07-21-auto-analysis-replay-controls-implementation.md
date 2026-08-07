# Auto Analysis Replay Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore explicit historical video import, automatically analyze both imported and captured clips, and turn iPhone replay controls into one coherent playback dock.

**Architecture:** `ContentView` remains the sole owner of Photos picker state, local-media persistence, project loading, and automatic-analysis origin. `PracticeSessionView` reports a successfully persisted capture to `ContentView`, which changes directly to the shared analysis workspace. `AnalysisWorkspaceView` owns the compact replay dock presentation but retains the existing drawing and analysis callbacks.

**Tech Stack:** SwiftUI, PhotosUI, AVFoundation, existing `LocalProjectStore`, `VideoPlaybackManager`, source smoke tests compiled with `xcrun swiftc`.

## Global Constraints

- Keep the history-page `+`, `NewProjectSheet`, and manual `CameraView` route removed.
- Use `VideoLoadOrigin.importCompleted` only for newly imported media and `.capturedClipSaved` only for a newly completed camera capture; preserve `.projectReopened` for history.
- Preserve the direct iPhone playback layout and visible P1–P8 timeline.
- Do not stage or commit: this worktree contains unrelated user changes.

---

### Task 1: Lock the restored entry points and automatic-analysis contract

**Files:**
- Modify: `Tests/CaptureReplayPresentationSmoke.swift`
- Modify: `Tests/ProTourPresentationSmoke.swift`

**Interfaces:**
- Consumes: source strings in `ContentView.swift`, `ProjectLibraryView.swift`, `PracticeSessionView.swift`, and `AnalysisWorkspaceView.swift`.
- Produces: regression checks for import availability, capture origin, automatic-analysis policy, and the unified compact dock.

- [ ] **Step 1: Write the failing test**

Replace the removal assertions with checks equivalent to:

```swift
precondition(library.contains("let onImport"))
precondition(content.contains("showVideoPicker"))
precondition(content.contains(".photosPicker"))
precondition(content.contains("origin: .capturedClipSaved"))
precondition(!workspace.contains("Label(\n                        playbackManager.analysisState.hasCompletedResult ? \"结果\" : \"AI 分析\""))
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcrun swiftc -parse-as-library Tests/CaptureReplayPresentationSmoke.swift -o /tmp/swingarc-auto-analysis-contract && /tmp/swingarc-auto-analysis-contract
```

Expected: failure because the current sources have no picker/import callback, use `.projectReopened` after capture, and retain the old AI button label.

- [ ] **Step 3: Keep existing policy coverage explicit**

In `Tests/ProTourPresentationSmoke.swift`, retain/extend assertions that `.importCompleted` and `.capturedClipSaved` automatically analyze while `.projectReopened` does not.

- [ ] **Step 4: Run policy smoke**

Run:

```bash
xcrun swiftc -parse-as-library SwingArc/Models/PracticeModels.swift Tests/ProTourPresentationSmoke.swift -o /tmp/swingarc-auto-analysis-policy && /tmp/swingarc-auto-analysis-policy
```

Expected: pass before the UI implementation because the policy already encodes the required origins.

### Task 2: Restore import and direct captured-clip analysis

**Files:**
- Modify: `SwingArc/Views/ContentView.swift`
- Modify: `SwingArc/Views/ProjectLibraryView.swift`
- Modify: `SwingArc/Views/PracticeSessionView.swift`

**Interfaces:**
- Consumes: `PhotosPickerItem`, `LocalProjectStore.videoDirectory()`, `loadVideoFromURL(_:existingSummary:practiceView:origin:)`, and `PracticeSessionView.onOpenLastClip`.
- Produces: `onImport` callback in `ProjectLibraryView`, imported private media, and a one-shot direct capture handoff using `.capturedClipSaved`.

- [ ] **Step 1: Restore the minimal Photos import path**

Add `import PhotosUI`; add `showVideoPicker` and `selectedPickerItem` state; pass `onImport: { showVideoPicker = true }` into `ProjectLibraryView`; and restore picker handling that writes selected data to:

```swift
LocalProjectStore.videoDirectory()
    .appendingPathComponent("imported-\(UUID().uuidString).mp4")
```

Then call:

```swift
loadVideoFromURL(videoURL, origin: .importCompleted)
```

- [ ] **Step 2: Add an explicit archive import affordance without restoring `+`**

Give `ProjectLibraryView` only an `onImport` closure and add a toolbar button labeled/accessibility-labeled “导入视频”. Do not add `onRecord`, `NewProjectSheet`, `showsNewProjectSheet`, or a `plus` image.

- [ ] **Step 3: Hand off a persisted capture immediately**

In `PracticeSessionView`, observe the successful persisted clip URL and call `onOpenLastClip` once; guard against duplicate handoff. In `ContentView`, change that handoff to:

```swift
loadVideoFromURL(
    clipURL,
    practiceView: practiceView,
    origin: .capturedClipSaved
)
```

- [ ] **Step 4: Run regression contract test**

Run:

```bash
xcrun swiftc -parse-as-library Tests/CaptureReplayPresentationSmoke.swift -o /tmp/swingarc-auto-analysis-contract && /tmp/swingarc-auto-analysis-contract
```

Expected: pass.

### Task 3: Make the iPhone dock coherent and contextual

**Files:**
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `Tests/CaptureReplayPresentationSmoke.swift`

**Interfaces:**
- Consumes: `MobileReplayTimelineView`, `toggleDrawingMode()`, `showResults(isRegularLayout:)`, and `playbackManager.analysisState`.
- Produces: a single mobile dock whose action row is part of the timeline container.

- [ ] **Step 1: Write a failing presentation assertion**

Require a named action-dock subview and forbid the old persistent `AI 分析` label in `mobileReplayControls`.

- [ ] **Step 2: Run the contract test to verify the assertion fails**

Run the Task 1 contract command. Expected: fail because the current dock has a separate `HStack` under `MobileReplayTimelineView` and a permanent AI action.

- [ ] **Step 3: Implement the unified dock**

Keep `MobileReplayTimelineView` at the top of the dock and place its contextual action row inside the same rounded background: a secondary `标注` button at leading edge and a `结果` button only after completed analysis. While scanning or before results, no manual AI primary button is rendered; existing central progress and failure cards remain unchanged.

- [ ] **Step 4: Run source smoke and build**

Run:

```bash
xcrun swiftc -parse-as-library Tests/CaptureReplayPresentationSmoke.swift -o /tmp/swingarc-auto-analysis-contract && /tmp/swingarc-auto-analysis-contract
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj -scheme SwingArcProject -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Expected: source smoke passes and Xcode prints `** BUILD SUCCEEDED **`.

### Task 4: Exercise the user flows on a device

**Files:**
- No source changes.

**Interfaces:**
- Consumes: signed `SwingArcProject.app` and physical iPhone bundle identifier `com.liangbo.swingarc`.
- Produces: visual evidence that import entry, automatic import analysis, and direct captured-clip handoff work as designed.

- [ ] **Step 1: Install the signed Debug build**

Run the existing signed iOS build against the paired iPhone, then install its `Debug-iphoneos/SwingArcProject.app` with `xcrun devicectl device install app`.

- [ ] **Step 2: Launch and test import**

Open “历史分析”, use “导入视频”, choose a short golf clip, and verify the review page opens with the central scan progress without tapping AI analysis.

- [ ] **Step 3: Test recording handoff**

Complete one automatic practice recording and verify that saving it changes directly to the same review page and begins scanning; reopening an old library project must not restart analysis.


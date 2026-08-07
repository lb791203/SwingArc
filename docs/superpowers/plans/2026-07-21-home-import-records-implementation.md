# Home Import and Records Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make video import a first-class third home-screen card and make the top-right capsule open saved records.

**Architecture:** `PracticeHomePresentation` owns the visible home action order. `PracticeHomeView` maps that order to the shared large-card component and emits import or records closures. `ContentView` owns the Photos picker state, so the new home import closure only sets `showVideoPicker`; the existing `.importCompleted` policy remains responsible for automatically starting AI analysis.

**Tech Stack:** SwiftUI, PhotosUI, standalone Swift smoke tests.

## Global Constraints

- Keep DTL and FACE-ON behaviour unchanged.
- Import is available only from the home screen; remove import controls from the records library.
- Selecting an imported video continues directly into the existing automatic local-AI analysis flow.
- Preserve existing projects and the records-library navigation.

---

### Task 1: Lock the home-screen contract with failing smoke assertions

**Files:**
- Modify: `Tests/ProTourPresentationSmoke.swift:6-7`
- Modify: `Tests/CaptureReplayPresentationSmoke.swift:58-70`

**Interfaces:**
- Consumes: `PracticeHomePresentation.modeOrder`, `PracticeHomePresentation.secondaryActions`, `PracticeHomeView`, and `ContentView` source.
- Produces: source-contract coverage for home import, records navigation, and the Photos picker handoff.

- [ ] **Step 1: Write the failing assertions**

```swift
precondition(
    PracticeHomePresentation.modeOrder == [.downTheLine, .faceOn, .importVideo]
)
precondition(PracticeHomePresentation.secondaryActions.isEmpty)
precondition(home.contains("let onImport"))
precondition(!home.contains("LOCAL AI"))
precondition(home.contains("Text(\"记录\")"))
precondition(home.contains("case .importVideo"))
precondition(content.contains("onImport: { showVideoPicker = true }"))
```

- [ ] **Step 2: Run the focused smoke tests and verify failure**

Run:

```bash
swiftc SwingArc/Models/PracticeModels.swift SwingArc/Models/WorkspaceModels.swift Tests/ProTourPresentationSmoke.swift -o /tmp/swingarc-home-presentation-smoke && /tmp/swingarc-home-presentation-smoke
swiftc Tests/CaptureReplayPresentationSmoke.swift -o /tmp/swingarc-home-import-contract-smoke && /tmp/swingarc-home-import-contract-smoke
```

Expected: the new home-import / records assertions fail against the current history-card implementation.

### Task 2: Move import into the main card stack and records into the header

**Files:**
- Modify: `SwingArc/Models/PracticeModels.swift:10-13`
- Modify: `SwingArc/Views/PracticeHomeView.swift:6-167`
- Modify: `SwingArc/Views/ContentView.swift:92-97`
- Modify: `SwingArc/Views/ProjectLibraryView.swift:9-56`
- Modify: `SwingArc/Views/ProjectLibraryView.swift:91-140`

**Interfaces:**
- Consumes: `onStartPractice`, `onOpenLibrary`, and `showVideoPicker`.
- Produces: `onImport` home callback; a large `.importVideo` card; a header `记录` button that opens the library.

- [ ] **Step 1: Change the home action model**

```swift
static let modeOrder: [PracticeHomeAction] = [.downTheLine, .faceOn, .importVideo]
static let secondaryActions: [PracticeHomeAction] = []
```

- [ ] **Step 2: Add the explicit import callback and render the third large card**

```swift
let onImport: () -> Void

case .importVideo:
    PracticeModeSelector(
        index: "03",
        eyebrow: "IMPORT VIDEO",
        title: "导入视频",
        detail: "从相册选择 · 自动 AI 分析",
        systemImage: "photo.on.rectangle",
        usesBrandSurface: false,
        action: onImport
    )
```

- [ ] **Step 3: Replace the status capsule with records navigation**

```swift
Button(action: onOpenLibrary) {
    Label("记录", systemImage: "clock.arrow.circlepath")
}
.accessibilityLabel("打开挥杆记录")
```

- [ ] **Step 4: Wire the home callback to the picker state**

```swift
PracticeHomeView(
    onStartPractice: { selectedPracticeView = $0 },
    onImport: { showVideoPicker = true },
    onOpenLibrary: { showProjectLibrary = true }
)
```

- [ ] **Step 5: Remove all records-library import controls in the same change**

```swift
struct ProjectLibraryView: View {
    let projects: [LocalProjectSummary]
    let onOpen: (LocalProjectSummary) -> Void
    let onRename: (LocalProjectSummary, String) -> Void
    let onDelete: (LocalProjectSummary) -> Void
}
```

- [ ] **Step 6: Remove the toolbar import control and empty-state import button**

The records screen retains its back-to-practice button, archive title, empty-state explanatory copy, and project collection. It no longer offers a second video-import path.

### Task 3: Verify source contracts and build

**Files:**
- Test: `Tests/ProTourPresentationSmoke.swift`
- Test: `Tests/CaptureReplayPresentationSmoke.swift`

**Interfaces:**
- Consumes: the updated home, library, and content entry points.
- Produces: passing smoke contracts and a compilable iOS Simulator app.

- [ ] **Step 1: Run the two focused smoke tests**

Run:

```bash
swiftc -parse-as-library Tests/CaptureReplayPresentationSmoke.swift -o /tmp/swingarc-home-import-contract-smoke && /tmp/swingarc-home-import-contract-smoke
```

Expected: the source-contract command exits 0; the iOS build below proves the SwiftUI integration compiles.

- [ ] **Step 2: Build the iOS Simulator target**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj -scheme SwingArcProject -configuration Debug -destination 'platform=iOS Simulator,id=867A3106-4032-4F9C-8BB5-E4B8C14F0780' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Install and inspect the home screen on the physical iPhone**

Run the already-signed Debug device build through `devicectl`, then open the app while the phone remains unlocked. Confirm the third card says `导入视频`, the header says `记录`, and the records screen has no import control.

## Self-Review

- Spec coverage: Task 1 locks the contract; Task 2 atomically moves import and removes the duplicate records entry; Task 3 verifies the requested UI and build.
- Placeholder scan: no placeholders or deferred implementation steps remain.
- Type consistency: `PracticeHomeView.onImport` sends only the existing `showVideoPicker` state change; `ProjectLibraryView` no longer declares or receives `onImport`.

# Stable Video Path and Fullscreen Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep saved SwingArc projects playable across App updates and add true full-screen playback that preserves the current frame and visible overlays.

**Architecture:** Replace persisted sandbox-absolute URLs with a stable managed-media reference that stores a file name and resolves it against the current Application Support directory, migrating legacy indexes and analysis keys in place. Keep `VideoPlaybackManager` as the only player owner; a dedicated full-screen SwiftUI surface receives that same manager and renders existing overlays with drawing interaction disabled.

**Tech Stack:** Swift 5, SwiftUI, AVFoundation, Foundation file and UserDefaults APIs, iOS/iPadOS 17+, smoke executables, Xcode and `devicectl`.

## Global Constraints

- SwingArc-managed media lives under `Library/Application Support/SwingArcVideos`.
- Managed projects persist a stable file name, never an application-container absolute path.
- Legacy project IDs, names, dates, P1-P8 markers, drawings, duration, frame rate, and status survive migration.
- Filename recovery is restricted to the current `SwingArcVideos` directory.
- Missing media displays `视频文件缺失` without erasing analysis or annotations.
- Full screen reuses the existing `VideoPlaybackManager` and `AVPlayer`; it does not reload the asset.
- Full screen shows video and saved overlays, hides workspace chrome, and disables drawing edits.
- Controls are close, previous frame, play/pause, and next frame, with 44pt targets and a 2.5-second auto-hide.
- Pinch zoom remains enabled and double tap resets zoom to 1x.
- iPhone and iPad portrait and landscape bounds are supported without new dependencies.

---

### Task 1: Stable Media References and Legacy Migration

**Files:**
- Modify: `SwingArc/Services/LocalProjectStore.swift`
- Modify: `SwingArc/Views/ContentView.swift`
- Modify: `Tests/ProjectLibraryStoreSmoke.swift`

**Interfaces:**
- Produces: `LocalProjectStore.videoDirectory(fileManager:) -> URL`.
- Produces: optional `videoDirectory` and `fileManager` injection on project-index operations.
- Produces: a private Codable stored summary containing `videoFileName`, while views keep using `LocalProjectSummary.videoURL`.

- [ ] **Step 1: Write the failing container-change migration test**

Extend `ProjectLibraryStoreSmoke.main()` with old and new temporary container roots. Seed a legacy summary and analysis payload at the old absolute URL, put the same media file name under the new root, then assert:

```swift
let restored = LocalProjectStore.projects(
    defaults: migrationDefaults,
    videoDirectory: newDirectory,
    fileManager: fileManager
)
precondition(restored.count == 1)
precondition(restored[0].id == legacySummary.id)
precondition(restored[0].videoURL == newURL)
precondition(restored[0].name == legacySummary.name)
precondition(
    LocalProjectStore.load(for: newURL, defaults: migrationDefaults)?.keyframes
        == legacyProject.keyframes
)

let secondLoad = LocalProjectStore.projects(
    defaults: migrationDefaults,
    videoDirectory: newDirectory,
    fileManager: fileManager
)
precondition(secondLoad == restored)
```

Add an internal legacy-seeding helper to `LocalProjectStore` so the test does not duplicate private JSON/key formats.

- [ ] **Step 2: Run the persistence test and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Services/LocalProjectStore.swift Tests/ProjectLibraryStoreSmoke.swift \
  -o /tmp/project-library-red
```

Expected: compilation fails because directory injection and legacy seeding do not exist.

- [ ] **Step 3: Add the stored-summary mapping**

Add this private DTO to `LocalProjectStore.swift`:

```swift
private struct StoredProjectSummary: Codable, Equatable {
    let id: UUID
    let videoFileName: String
    var name: String
    var duration: Double
    var sourceFrameRate: Double
    var modifiedAt: Date
    var status: LocalProjectStatus

    init(_ summary: LocalProjectSummary) {
        id = summary.id
        videoFileName = summary.videoURL.lastPathComponent
        name = summary.name
        duration = summary.duration
        sourceFrameRate = summary.sourceFrameRate
        modifiedAt = summary.modifiedAt
        status = summary.status
    }

    func resolved(in directory: URL) -> LocalProjectSummary {
        LocalProjectSummary(
            id: id,
            videoURL: directory.appendingPathComponent(videoFileName),
            name: name,
            duration: duration,
            sourceFrameRate: sourceFrameRate,
            modifiedAt: modifiedAt,
            status: status
        )
    }
}
```

Add:

```swift
static func videoDirectory(fileManager: FileManager = .default) -> URL {
    let directory = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0].appendingPathComponent("SwingArcVideos", isDirectory: true)
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
```

- [ ] **Step 4: Decode new indexes first and legacy indexes second**

Implement `projects(defaults:videoDirectory:fileManager:)` using:

```swift
let directory = videoDirectory ?? self.videoDirectory(fileManager: fileManager)
if let data = defaults.data(forKey: projectIndexKey),
   let stored = try? JSONDecoder().decode([StoredProjectSummary].self, from: data) {
    return stored.map { $0.resolved(in: directory) }
        .sorted { $0.modifiedAt > $1.modifiedAt }
}
if let data = defaults.data(forKey: projectIndexKey),
   let legacy = try? JSONDecoder().decode([LocalProjectSummary].self, from: data) {
    let migrated = legacy.map {
        migrateLegacySummary($0, to: directory, defaults: defaults, fileManager: fileManager)
    }
    saveIndex(migrated, defaults: defaults)
    return migrated.sorted { $0.modifiedAt > $1.modifiedAt }
}
```

`migrateLegacySummary` rebuilds the runtime URL from `oldURL.lastPathComponent`, copies the legacy absolute-path analysis payload to the stable key, removes the old key only after a successful copy, and preserves every summary field. A missing file still resolves to its expected current-directory URL so project metadata remains visible.

- [ ] **Step 5: Stabilize analysis and last-video keys**

Use the managed file name:

```swift
private static func projectKey(for videoURL: URL) -> String {
    let identifier = Data(videoURL.lastPathComponent.utf8).base64EncodedString()
    return projectPrefix + identifier
}
```

Store `videoURL.lastPathComponent` under `lastVideoURLKey`. When reading an older absolute URL string, extract the last path component and resolve it under the injected/current directory. Update `upsertSummary`, `rename`, `remove`, and `saveIndex` to encode `[StoredProjectSummary]`.

- [ ] **Step 6: Centralize the managed directory**

Replace all `ContentView.persistentVideoDirectory()` calls with:

```swift
LocalProjectStore.videoDirectory()
```

Delete the duplicate ContentView function. Imports and recordings continue to be copied into this directory before indexing.

- [ ] **Step 7: Run GREEN verification**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Services/LocalProjectStore.swift Tests/ProjectLibraryStoreSmoke.swift \
  -o /tmp/project-library && /tmp/project-library
```

Expected: exit 0, including migration and idempotency assertions.

- [ ] **Step 8: Commit**

```bash
git add SwingArc/Services/LocalProjectStore.swift SwingArc/Views/ContentView.swift Tests/ProjectLibraryStoreSmoke.swift
git commit -m "fix: preserve saved videos across app updates"
```

---

### Task 2: Explicit Missing-Media State

**Files:**
- Modify: `SwingArc/Models/WorkspaceModels.swift`
- Modify: `SwingArc/Views/CustomVideoPlayer.swift`
- Modify: `SwingArc/Views/ContentView.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `Tests/WorkspaceModelsSmoke.swift`

**Interfaces:**
- Produces: `MediaLoadState`, `MediaLoadPolicy`, and `VideoPlaybackManager.mediaLoadState`.
- Changes: `VideoPlaybackManager.loadVideo(url:) -> Bool`.

- [ ] **Step 1: Write failing model assertions**

```swift
precondition(MediaLoadPolicy.state(fileExists: true) == .ready)
precondition(MediaLoadPolicy.state(fileExists: false) == .missing)
precondition(MediaLoadPolicy.missingMessage == "视频文件缺失")
```

- [ ] **Step 2: Verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/WorkspaceModels.swift Tests/WorkspaceModelsSmoke.swift \
  -o /tmp/workspace-models-red
```

Expected: compilation fails because `MediaLoadPolicy` is undefined.

- [ ] **Step 3: Implement the pure state**

```swift
enum MediaLoadState: Equatable {
    case idle
    case ready
    case missing
}

enum MediaLoadPolicy {
    static let missingMessage = "视频文件缺失"
    static func state(fileExists: Bool) -> MediaLoadState {
        fileExists ? .ready : .missing
    }
}
```

- [ ] **Step 4: Validate before creating AVAsset**

Add `@Published private(set) var mediaLoadState: MediaLoadState = .idle`. Change loading to:

```swift
@discardableResult
func loadVideo(url: URL, fileManager: FileManager = .default) -> Bool {
    guard !url.isFileURL || fileManager.fileExists(atPath: url.path) else {
        unloadVideo()
        mediaLoadState = .missing
        return false
    }
    mediaLoadState = .ready
}
```

Insert that guard at the beginning of the existing method, retain the complete current AVAsset/player setup immediately after it, and add `return true` after the existing first-frame pose scheduling block. Set `mediaLoadState = .idle` in `unloadVideo()`.

- [ ] **Step 5: Preserve saved metadata on failed load**

In `ContentView.loadVideoFromURL`, only replace duration/frame rate when loading succeeds:

```swift
let didLoad = playbackManager.loadVideo(url: url)
if didLoad {
    summary.duration = playbackManager.duration
    summary.sourceFrameRate = playbackManager.sourceFrameRate
}
```

Restore the saved `LocalAnalysisProject` and open the workspace even when missing so annotations are not deleted.

- [ ] **Step 6: Render the missing state**

In `VideoCanvasView`:

```swift
if playbackManager.mediaLoadState == .missing {
    ContentUnavailableView(
        MediaLoadPolicy.missingMessage,
        systemImage: "video.slash",
        description: Text("视频文件已被删除或无法恢复，项目标注仍会保留。")
    )
    .foregroundStyle(.white)
} else {
    ProgressView("正在载入视频")
        .tint(.white)
        .foregroundStyle(.white)
}
```

- [ ] **Step 7: Verify model and simulator build**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/WorkspaceModels.swift Tests/WorkspaceModelsSmoke.swift \
  -o /tmp/workspace-models && /tmp/workspace-models

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project .superpowers/xcode/SwingArcProject.xcodeproj -scheme SwingArcProject \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/SwingArcMissingMediaDerived -jobs 2 build
```

Expected: smoke exits 0 and Xcode prints `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add SwingArc/Models/WorkspaceModels.swift SwingArc/Views/CustomVideoPlayer.swift \
  SwingArc/Views/ContentView.swift SwingArc/Views/AnalysisWorkspaceView.swift Tests/WorkspaceModelsSmoke.swift
git commit -m "fix: show missing saved media explicitly"
```

---

### Task 3: Shared-Player Full-Screen Playback

**Files:**
- Create: `SwingArc/Views/FullscreenVideoPlaybackView.swift`
- Modify: `SwingArc/Models/WorkspaceModels.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `Tests/WorkspaceModelsSmoke.swift`
- Modify: `.superpowers/xcode/SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `FullscreenPlaybackPolicy`.
- Produces: `FullscreenVideoPlaybackView` receiving the existing manager, drawing bindings, overlay flags, and `onDismiss`.
- Consumes: `VideoPlaybackManager.stepFrame(forward:)` and the existing video/overlay renderer.

- [ ] **Step 1: Write failing policy assertions**

```swift
precondition(FullscreenPlaybackPolicy.autoHideDelay == 2.5)
precondition(FullscreenPlaybackPolicy.minimumTouchTarget == 44)
precondition(!FullscreenPlaybackPolicy.allowsDrawing)
precondition(!FullscreenPlaybackPolicy.showsWorkspaceChrome)
```

- [ ] **Step 2: Verify RED**

Run the Task 2 model command. Expected: compilation fails because `FullscreenPlaybackPolicy` is undefined.

- [ ] **Step 3: Implement the policy**

```swift
enum FullscreenPlaybackPolicy {
    static let autoHideDelay: TimeInterval = 2.5
    static let minimumTouchTarget: CGFloat = 44
    static let allowsDrawing = false
    static let showsWorkspaceChrome = false
}
```

- [ ] **Step 4: Parameterize the existing canvas**

Add:

```swift
let showsFullscreenButton: Bool
let onEnterFullscreen: () -> Void
```

Show this only for a ready player in idle mode:

```swift
.overlay(alignment: .topTrailing) {
    if showsFullscreenButton,
       interactionMode == .idle,
       playbackManager.mediaLoadState == .ready {
        Button(action: onEnterFullscreen) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.55), in: Circle())
        }
        .foregroundStyle(.white)
        .padding(12)
        .accessibilityLabel("全屏播放")
    }
}
```

The full-screen call site passes `.idle`, `showsFullscreenButton: false`, and the same bindings; therefore overlay rendering remains active while drawing interaction is false.

- [ ] **Step 5: Create the full-screen view**

Create `FullscreenVideoPlaybackView` with the existing manager and bindings:

```swift
struct FullscreenVideoPlaybackView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    @Binding var drawings: [DrawingElement]
    @Binding var isKeyframeMode: Bool
    let showPoseSkeleton: Bool
    let showHeadStability: Bool
    let showSpineAngle: Bool
    let showGrid: Bool
    let onDismiss: () -> Void

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var inertTool: DrawingTool = .line
    @State private var inertColor: Color = .white
    @State private var inertWidth: CGFloat = 3
}
```

Use this body structure:

```swift
var body: some View {
    ZStack {
        Color.black.ignoresSafeArea()
        VideoCanvasView(
            playbackManager: playbackManager,
            drawings: $drawings,
            activeTool: $inertTool,
            selectedColor: $inertColor,
            strokeWidth: $inertWidth,
            isKeyframeMode: $isKeyframeMode,
            showPoseSkeleton: showPoseSkeleton,
            showHeadStability: showHeadStability,
            showSpineAngle: showSpineAngle,
            showGrid: showGrid,
            interactionMode: .idle,
            showsFullscreenButton: false,
            onEnterFullscreen: {}
        )
        if controlsVisible {
            VStack {
                HStack {
                    Spacer()
                    controlButton("xmark", label: "退出全屏", action: onDismiss)
                }
                Spacer()
                HStack(spacing: 20) {
                    controlButton("backward.frame.fill", label: "前一帧") {
                        playbackManager.stepFrame(forward: false)
                        scheduleAutoHide()
                    }
                    controlButton(
                        playbackManager.isPlaying ? "pause.fill" : "play.fill",
                        label: playbackManager.isPlaying ? "暂停" : "播放"
                    ) {
                        playbackManager.isPlaying ? playbackManager.pause() : playbackManager.play()
                        scheduleAutoHide()
                    }
                    controlButton("forward.frame.fill", label: "后一帧") {
                        playbackManager.stepFrame(forward: true)
                        scheduleAutoHide()
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding()
        }
    }
    .contentShape(Rectangle())
    .onTapGesture {
        controlsVisible.toggle()
        if controlsVisible { scheduleAutoHide() }
    }
    .onAppear { scheduleAutoHide() }
    .onDisappear { hideTask?.cancel() }
    .preferredColorScheme(.dark)
}

private func controlButton(
    _ systemName: String,
    label: String,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: systemName)
            .frame(
                minWidth: FullscreenPlaybackPolicy.minimumTouchTarget,
                minHeight: FullscreenPlaybackPolicy.minimumTouchTarget
            )
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white)
    .accessibilityLabel(label)
}
```

Use cancellation-safe hiding:

```swift
private func scheduleAutoHide() {
    hideTask?.cancel()
    guard playbackManager.isPlaying else { return }
    hideTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(FullscreenPlaybackPolicy.autoHideDelay))
        guard !Task.isCancelled else { return }
        controlsVisible = false
    }
}
```

Single tap toggles controls. Existing pinch zoom and double-tap reset come from `VideoCanvasView`.

- [ ] **Step 6: Present with the same playback manager**

Add `@State private var showsFullscreenPlayback = false` to `AnalysisWorkspaceView` and:

```swift
.fullScreenCover(isPresented: $showsFullscreenPlayback) {
    FullscreenVideoPlaybackView(
        playbackManager: playbackManager,
        drawings: $drawings,
        isKeyframeMode: $isKeyframeMode,
        showPoseSkeleton: showPoseSkeleton,
        showHeadStability: showHeadStability,
        showSpineAngle: showSpineAngle,
        showGrid: showGrid,
        onDismiss: { showsFullscreenPlayback = false }
    )
}
```

Do not call `loadVideo`, `seek`, or create another manager on entry/exit.

- [ ] **Step 7: Add the view to the explicit Xcode project**

Use IDs `F51700000000000000000001` and `F51700000000000000000002`:

```
F51700000000000000000001 /* FullscreenVideoPlaybackView.swift in Sources */ = {
    isa = PBXBuildFile;
    fileRef = F51700000000000000000002 /* FullscreenVideoPlaybackView.swift */;
};
F51700000000000000000002 /* FullscreenVideoPlaybackView.swift */ = {
    isa = PBXFileReference;
    lastKnownFileType = sourcecode.swift;
    path = FullscreenVideoPlaybackView.swift;
    sourceTree = "<group>";
};
```

Insert the file reference in group `6DB7E57C30086B6E00B7B98C /* Views */` and the build file in phase `000000000000000120000000 /* Sources */`.

- [ ] **Step 8: Verify GREEN and build**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/WorkspaceModels.swift Tests/WorkspaceModelsSmoke.swift \
  -o /tmp/workspace-models && /tmp/workspace-models

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project .superpowers/xcode/SwingArcProject.xcodeproj -scheme SwingArcProject \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/SwingArcFullscreenDerived -jobs 2 build
```

Expected: smoke exits 0 and Xcode prints `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add SwingArc/Models/WorkspaceModels.swift SwingArc/Views/AnalysisWorkspaceView.swift \
  SwingArc/Views/FullscreenVideoPlaybackView.swift Tests/WorkspaceModelsSmoke.swift \
  .superpowers/xcode/SwingArcProject.xcodeproj/project.pbxproj
git commit -m "feat: add shared-player fullscreen playback"
```

---

### Task 4: Regression, Device Build, Install, and Acceptance

**Files:**
- Verify only unless a test exposes a defect.

**Interfaces:**
- Consumes all preceding tasks.
- Produces fresh test/build/install evidence.

- [ ] **Step 1: Run lightweight regression tests**

Run the two newly built executables plus the existing zoom and presentation smokes:

```bash
/tmp/project-library
/tmp/workspace-models
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/WorkspaceModels.swift Tests/VideoZoomPolicySmoke.swift \
  -o /tmp/video-zoom && /tmp/video-zoom
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Models/WorkspaceModels.swift Tests/AnalysisWorkspacePresentationSmoke.swift \
  -o /tmp/workspace-presentation && /tmp/workspace-presentation
```

Expected: all four executables exit 0.

- [ ] **Step 2: Validate source integration**

```bash
git diff --check
rg -n 'FullscreenVideoPlaybackView.swift in Sources|FullscreenVideoPlaybackView.swift' \
  .superpowers/xcode/SwingArcProject.xcodeproj/project.pbxproj
```

Expected: no whitespace errors and the new file appears in both the Views group and Sources phase.

- [ ] **Step 3: Build Release for the phone with bounded CPU**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project .superpowers/xcode/SwingArcProject.xcodeproj -scheme SwingArcProject \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/SwingArcStableVideoFullscreenDevice \
  -allowProvisioningUpdates -jobs 2 build
```

Expected: `** BUILD SUCCEEDED **` and the app exists under `Release-iphoneos`.

- [ ] **Step 4: Install and launch**

```bash
xcrun devicectl device install app \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 \
  /tmp/SwingArcStableVideoFullscreenDevice/Build/Products/Release-iphoneos/SwingArcProject.app
xcrun devicectl device process launch \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 com.liangbo.swingarc
```

Expected: install succeeds and the application starts.

- [ ] **Step 5: Manual acceptance**

1. Open a saved project created before the update; confirm video, drawings, and P1-P8 markers restore.
2. Enter full screen; confirm the exact current frame appears.
3. Play, pause, step both directions, pinch zoom, and double-tap reset.
4. During playback, wait 2.5 seconds for controls to hide and tap once to restore them.
5. Exit and confirm time, speed, play/pause state, and workspace are unchanged.
6. Open a deliberately unavailable project and confirm `视频文件缺失` appears without deleting annotations.

- [ ] **Step 6: Verify final branch state**

```bash
git status --short --branch
git log -5 --oneline
```

Expected: the three implementation commits are present and no generated build artifacts are tracked.

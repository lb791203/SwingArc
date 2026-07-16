# SwingArc iPhone MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native, offline iPhone MVP that records or imports golf-swing videos, supports frame-accurate slow-motion review and drawing, suggests four swing stages from Vision pose data, persists editable projects, and exports annotated videos.

**Architecture:** Split the existing view-heavy prototype into a SwiftUI feature shell, isolated media/playback services, pure analysis/persistence models, and a renderable annotation layer. `AVPlayerItemVideoOutput` supplies only the frame currently needed for UI analysis; background sampling fills stage candidates after interaction becomes idle. A persistent project stores normalized geometry and user-confirmed stage overrides, while an exporter composites the same normalized overlay onto a derived video.

**Tech Stack:** Swift 5.10, SwiftUI, AVFoundation, PhotosUI, Vision, Core Graphics, Core Media, XCTest, iOS 17.0+.

## Global Constraints

- Target iPhone running iOS 17.0 or later; no third-party runtime dependencies.
- Keep all video analysis, metadata, project state, and exports on-device; do not add sign-in, network APIs, or cloud sync.
- Preserve original media: all imports are copied into the application container and exports are new files.
- Store every annotation point in video-normalized coordinates with a lower-left origin; convert only at rendering boundaries.
- A manually edited stage is authoritative and must never be overwritten by automatic analysis.
- Playback and touch handling must remain responsive when Vision is slow, fails, or returns no pose.
- Do not claim a device supports 120/240fps without inspecting and configuring a compatible `AVCaptureDevice.Format`.

---

## File structure and ownership

| Path | Responsibility |
| --- | --- |
| `SwingArc.xcodeproj` | iOS app/test targets, iOS 17 deployment target, privacy keys. |
| `SwingArc/App/SwingArcApp.swift` | App entry point and `ProjectStore` environment injection. |
| `SwingArc/Models/SwingProject.swift` | Codable project, media descriptor, stages, normalized annotations and playback loop. |
| `SwingArc/Models/PoseSample.swift` | Codable pose/metric sample and analysis state. |
| `SwingArc/Services/ProjectStore.swift` | Atomic JSON project persistence and managed media directory. |
| `SwingArc/Services/VideoAssetImporter.swift` | Copies camera/photo-picker files into app storage and reads asset metadata. |
| `SwingArc/Services/CameraCaptureController.swift` | Camera authorization, highest supported capture format and movie recording. |
| `SwingArc/Services/PlaybackController.swift` | AVPlayer lifecycle, `AVPlayerItemVideoOutput`, seeks, frame stepping, looping and pose scheduling. |
| `SwingArc/Services/VisionPoseDetector.swift` | Vision request and conversion from Vision output to normalized pose samples. |
| `SwingArc/Services/SwingStageDetector.swift` | Pure stage-candidate rules over timed pose samples. |
| `SwingArc/Services/VideoExporter.swift` | AVFoundation video composition plus Core Graphics annotation rendering. |
| `SwingArc/Views/HomeView.swift` | Project list and capture/import entry points. |
| `SwingArc/Views/CaptureView.swift` | Camera preview, alignment grid, countdown and recording controls. |
| `SwingArc/Views/ReviewView.swift` | Project review composition and state binding. |
| `SwingArc/Views/VideoPlayerView.swift` | AVPlayerLayer bridge and exact rendered-video rectangle reporting. |
| `SwingArc/Views/TimelineView.swift` | Scrubber, stage buttons and A/B loop editing. |
| `SwingArc/Views/AnnotationCanvas.swift` | Tools, normalized hit testing, undo/redo and magnifier. |
| `SwingArc/Views/PoseOverlay.swift` | Skeleton, head trace, and spine-angle rendering from normalized pose data. |
| `SwingArcTests/*.swift` | Unit tests for models, persistence, stage analysis, scheduling and export overlay geometry. |
| `SwingArcUITests/*.swift` | Smoke tests for capture/import/review navigation with injected fixtures. |

Existing prototype files are migration sources, not permanent boundaries: `ContentView.swift` is replaced by `HomeView` and `ReviewView`; `CustomVideoPlayer.swift` becomes `PlaybackController` and `VideoPlayerView`; `CameraView.swift` becomes `CameraCaptureController` and `CaptureView`; `DrawingOverlay.swift` becomes `AnnotationCanvas` and `PoseOverlay`.

## Task 1: Create a buildable Xcode app and test harness

**Files:**
- Create: `SwingArc.xcodeproj/project.pbxproj` (via Xcode App template, not handwritten)
- Create: `SwingArc/App/SwingArcApp.swift`
- Create: `SwingArcTests/SwingArcTests.swift`
- Create: `SwingArcUITests/SwingArcUITests.swift`
- Modify: `.gitignore`
- Remove from target after migration: `SwingArc/SwingArcApp.swift`

**Interfaces:**
- Produces an `SwingArc` app target and `SwingArcTests`/`SwingArcUITests` targets with bundle identifier selected by the developer.

- [ ] **Step 1: Create the app and two test targets in Xcode**

Create an iOS App named `SwingArc`, interface `SwiftUI`, language `Swift`, deployment target `iOS 17.0`, and add Unit Testing and UI Testing targets. Move the source root to `SwingArc/` and select every app source file in Target Membership.

- [ ] **Step 2: Add the actual privacy keys and a deterministic test launch argument**

Set these `Info.plist` values in the app target:

```xml
<key>NSCameraUsageDescription</key>
<string>需要访问相机以录制高尔夫挥杆视频进行慢动作分析。</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>需要将带标注的挥杆分析视频保存到相册。</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>需要访问相册以导入高尔夫挥杆视频进行分析。</string>
```

Use this initial entry point so tests can later provide an isolated store directory:

```swift
import SwiftUI

@main
struct SwingArcApp: App {
    @StateObject private var projectStore = ProjectStore.live()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(projectStore)
        }
    }
}
```

- [ ] **Step 3: Add a failing launch smoke test**

```swift
import XCTest

final class SwingArcUITests: XCTestCase {
    func testLaunchShowsProjectLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "1"]
        app.launch()
        XCTAssertTrue(app.navigationBars["我的挥杆"].waitForExistence(timeout: 3))
    }
}
```

- [ ] **Step 4: Run the test before implementing the shell**

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SwingArcUITests/SwingArcUITests/testLaunchShowsProjectLibrary`

Expected: compile failure because `ProjectStore` and `HomeView` do not exist.

- [ ] **Step 5: Add a temporary empty `HomeView` that makes the test pass**

```swift
import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack { Text("No projects") }
            .navigationTitle("我的挥杆")
    }
}
```

Task 4 replaces this minimal initial screen with the implemented project list and media actions.

- [ ] **Step 6: Run the smoke test and commit**

Run the command in Step 4. Expected: `** TEST SUCCEEDED **`.

```bash
git add .gitignore SwingArc.xcodeproj SwingArc/App/SwingArcApp.swift SwingArc/Views/HomeView.swift SwingArcTests SwingArcUITests
git commit -m "build: add iOS app target and test harness"
```

## Task 2: Define Codable project and annotation domain models

**Files:**
- Create: `SwingArc/Models/SwingProject.swift`
- Create: `SwingArc/Models/PoseSample.swift`
- Create: `SwingArcTests/SwingProjectTests.swift`
- Modify: `SwingArc/Models/DrawingModels.swift`

**Interfaces:**
- Produces `SwingProject`, `VideoAssetDescriptor`, `StageMarker`, `Annotation`, `LoopRange`, `PoseSample`, and `AnalysisState`.
- Consumed by persistence, playback, canvas, review, and exporter tasks.

- [ ] **Step 1: Write failing persistence/model tests**

```swift
import XCTest
@testable import SwingArc

final class SwingProjectTests: XCTestCase {
    func testRoundTripPreservesNormalizedAnnotationAndManualStage() throws {
        var project = SwingProject.fixture()
        project.annotations = [.line(start: .init(x: 0.1, y: 0.2), end: .init(x: 0.9, y: 0.8), color: .green, width: 3)]
        project.stages[.impact] = StageMarker(time: 1.25, source: .manual)

        let restored = try JSONDecoder().decode(SwingProject.self, from: JSONEncoder().encode(project))

        XCTAssertEqual(restored.annotations, project.annotations)
        XCTAssertEqual(restored.stages[.impact]?.source, .manual)
        XCTAssertEqual(restored.stages[.impact]?.time, 1.25, accuracy: 0.0001)
    }

    func testLoopRangeClampsAndOrdersTimes() {
        XCTAssertEqual(LoopRange(start: 9, end: 2).clamped(to: 5), .init(start: 2, end: 5))
    }
}
```

- [ ] **Step 2: Run the model tests to verify they fail**

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SwingArcTests/SwingProjectTests`

Expected: compile failure because `SwingProject` does not exist.

- [ ] **Step 3: Implement the shared coordinate and stage types**

Use this exact public shape; keep all points lower-left normalized and `Codable`:

```swift
struct NormalizedPoint: Codable, Equatable { var x: Double; var y: Double }
enum StageSource: String, Codable, Equatable { case automatic, manual }
enum SwingStage: String, CaseIterable, Codable { case address, top, impact, finish }
struct StageMarker: Codable, Equatable { var time: Double; var source: StageSource }
struct LoopRange: Codable, Equatable {
    var start: Double; var end: Double
    func clamped(to duration: Double) -> Self {
        let a = min(max(0, start), duration); let b = min(max(0, end), duration)
        return Self(start: min(a, b), end: max(a, b))
    }
}
```

Define `Annotation` as an enum with associated values for `.line`, `.circle`, `.angle`, and `.freehand`. Implement explicit `CodingKeys` with a `kind` discriminator so all four cases round-trip. Define `SwingProject` with `id`, `createdAt`, `updatedAt`, `asset`, `annotations`, `stages`, `loopRange`, and `analysisState`; include a `fixture()` factory used only by tests.

- [ ] **Step 4: Implement pose samples and update old drawing types**

```swift
enum AnalysisState: String, Codable, Equatable { case idle, analyzing, ready, noPose, failed }
struct PoseSample: Codable, Equatable {
    var time: Double
    var joints: [String: NormalizedPoint]
    var spineAngleDegrees: Double?
    var headCenter: NormalizedPoint?
}
```

Move any still-needed colors/tool labels from `DrawingModels.swift` into `Annotation` UI helpers. Delete prototype-only `KeyframeMarker` and `DrawingElement` only after `ReviewView` has been migrated in Task 7.

- [ ] **Step 5: Run model tests and commit**

Run the command in Step 2. Expected: `** TEST SUCCEEDED **`.

```bash
git add SwingArc/Models SwingArcTests/SwingProjectTests.swift
git commit -m "feat: add persistent swing project models"
```

## Task 3: Persist projects and imported media safely

**Files:**
- Create: `SwingArc/Services/ProjectStore.swift`
- Create: `SwingArc/Services/VideoAssetImporter.swift`
- Create: `SwingArcTests/ProjectStoreTests.swift`

**Interfaces:**
- Consumes: `SwingProject`, `VideoAssetDescriptor`.
- Produces: `ProjectStore.live()`, `ProjectStore.save(_:)`, `ProjectStore.delete(_:)`, `ProjectStore.projects`, `VideoAssetImporter.importMovie(from:)`.

- [ ] **Step 1: Write failing file-system tests using a temporary directory**

```swift
final class ProjectStoreTests: XCTestCase {
    func testSaveThenReloadReturnsProjectAndManagedMedia() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = try ProjectStore(rootURL: root)
        let source = root.appending(path: "source.mov")
        try Data([1, 2, 3]).write(to: source)
        var project = SwingProject.fixture(assetURL: source)

        try await store.save(project)
        let reloaded = try ProjectStore(rootURL: root)

        XCTAssertEqual(reloaded.projects.map(\.id), [project.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: reloaded.projects[0].asset.localURL.path))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SwingArcTests/ProjectStoreTests`

Expected: compile failure because `ProjectStore` and `VideoAssetDescriptor` do not exist.

- [ ] **Step 3: Implement atomic project persistence**

```swift
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [SwingProject]
    let rootURL: URL
    private let projectsURL: URL
    let mediaURL: URL

    init(rootURL: URL) throws {
        self.rootURL = rootURL
        self.projectsURL = rootURL.appending(path: "Projects", directoryHint: .isDirectory)
        self.mediaURL = rootURL.appending(path: "Media", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        self.projects = try FileManager.default.contentsOfDirectory(at: projectsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(SwingProject.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func live() -> ProjectStore {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "SwingArc", directoryHint: .isDirectory)
        return try! ProjectStore(rootURL: root)
    }

    func save(_ project: SwingProject) async throws {
        let finalURL = projectsURL.appending(path: "\(project.id.uuidString).json")
        let temporaryURL = finalURL.appendingPathExtension("tmp")
        try JSONEncoder().encode(project).write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: temporaryURL, backupItemName: nil, options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        }
        projects = (projects.filter { $0.id != project.id } + [project]).sorted { $0.updatedAt > $1.updatedAt }
    }

    func delete(_ project: SwingProject) async throws {
        try FileManager.default.removeItem(at: projectsURL.appending(path: "\(project.id.uuidString).json"))
        try? FileManager.default.removeItem(at: project.asset.localURL)
        projects.removeAll { $0.id == project.id }
    }
}
```

Persist each project as `Projects/<UUID>.json`. Write `Data.write(options: .atomic)` to a temporary URL and replace the final JSON only after successful encoding. Store managed movie paths relative to the root directory so app-container paths are not serialized as absolute paths.

- [ ] **Step 4: Implement importer copy and metadata extraction**

```swift
struct VideoAssetImporter {
    func importMovie(from sourceURL: URL, into rootURL: URL) async throws -> VideoAssetDescriptor
}
```

Copy the security-scoped/photo-picker temporary file to `Media/<UUID>.<original-extension>`, load `duration`, `naturalSize`, `preferredTransform`, and nominal frame rate from `AVURLAsset`, and return them in `VideoAssetDescriptor`. On any failure, delete a partially copied destination before throwing.

- [ ] **Step 5: Run tests and commit**

Run the command in Step 2. Expected: `** TEST SUCCEEDED **`.

```bash
git add SwingArc/Services/ProjectStore.swift SwingArc/Services/VideoAssetImporter.swift SwingArcTests/ProjectStoreTests.swift
git commit -m "feat: persist swing projects and managed media"
```

## Task 4: Implement library home, import, and project restoration

**Files:**
- Modify: `SwingArc/Views/HomeView.swift`
- Create: `SwingArc/Views/ProjectRow.swift`
- Create: `SwingArcTests/HomeViewModelTests.swift`
- Modify: `SwingArc/App/SwingArcApp.swift`

**Interfaces:**
- Consumes: `ProjectStore`, `VideoAssetImporter`.
- Produces: project creation from a `PhotosPickerItem`, project list deletion, and `ReviewView(projectID:)` navigation.

- [ ] **Step 1: Write a failing import coordinator test with a fake importer**

```swift
final class HomeViewModelTests: XCTestCase {
    func testImportedMovieCreatesProjectInStore() async throws {
        let store = try ProjectStore.testStore()
        let importer = FakeVideoImporter(descriptor: .fixture())
        let model = HomeViewModel(store: store, importer: importer)

        try await model.createProject(from: URL(fileURLWithPath: "/tmp/swing.mov"))

        XCTAssertEqual(store.projects.count, 1)
        XCTAssertEqual(store.projects[0].asset, .fixture())
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SwingArcTests/HomeViewModelTests`

Expected: compile failure because `HomeViewModel` does not exist.

- [ ] **Step 3: Implement an injectable import coordinator and HomeView**

Define `protocol MovieImporting { func importMovie(from: URL) async throws -> VideoAssetDescriptor }`. `HomeViewModel.createProject(from:)` must call the importer, build `SwingProject(asset:)`, call `store.save`, then set `selectedProjectID`.

In `HomeView`, use `PhotosPicker` with `.videos`, show only “开始拍摄”, “导入视频”, and project rows, and present a localized alert on import error. Use this navigation contract:

```swift
NavigationStack(path: $model.path) {
    List(store.projects) { project in
        NavigationLink(value: project.id) { ProjectRow(project: project) }
    }
    .navigationDestination(for: UUID.self) { ReviewView(projectID: $0) }
}
```

- [ ] **Step 4: Add and run UI restoration smoke coverage**

Add a launch fixture through `-uiTesting 1` that creates one test project in a test root. Assert its title appears, open it, then navigate back and assert the title remains.

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SwingArcUITests`

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SwingArc/App SwingArc/Views/HomeView.swift SwingArc/Views/ProjectRow.swift SwingArcTests/HomeViewModelTests.swift SwingArcUITests
git commit -m "feat: add swing project library and video import"
```

## Task 5: Build reliable high-frame-rate camera capture

**Files:**
- Create: `SwingArc/Services/CameraCaptureController.swift`
- Create: `SwingArc/Views/CaptureView.swift`
- Create: `SwingArcTests/CameraFormatSelectionTests.swift`
- Modify: `SwingArc/Views/HomeView.swift`
- Retire after migration: `SwingArc/Views/CameraView.swift`

**Interfaces:**
- Produces: `CameraCaptureController.authorization`, `configure()`, `startCountdown()`, `startRecording()`, `stopRecording()`, and `recordedMovieURL`.
- Consumed by `CaptureView` and `HomeViewModel`.

- [ ] **Step 1: Write a pure format-ranking test**

```swift
func testFormatSelectorPrefers240Then120ThenHighestAvailable() {
    let formats = [
        CameraFormatCandidate(id: "60", maxFPS: 60),
        CameraFormatCandidate(id: "120", maxFPS: 120),
        CameraFormatCandidate(id: "240", maxFPS: 240)
    ]
    XCTAssertEqual(CameraFormatSelector.best(in: formats, requestedFPS: 240)?.id, "240")
    XCTAssertEqual(CameraFormatSelector.best(in: formats.dropLast(), requestedFPS: 240)?.id, "120")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SwingArcTests/CameraFormatSelectionTests`

Expected: compile failure because `CameraFormatSelector` does not exist.

- [ ] **Step 3: Implement format selection and capture controller**

Create the pure types:

```swift
struct CameraFormatCandidate: Equatable { let id: String; let maxFPS: Double }
enum CameraFormatSelector {
    static func best(in formats: [CameraFormatCandidate], requestedFPS: Double) -> CameraFormatCandidate? {
        formats.filter { $0.maxFPS > 0 }.sorted { min($0.maxFPS, requestedFPS) > min($1.maxFPS, requestedFPS) }.first
    }
}
```

In the controller, enumerate `AVCaptureDevice.formats`, choose the candidate with the highest `videoSupportedFrameRateRanges.maxFrameRate` capped at requested 240, lock the device, set `activeFormat`, and set both active frame durations to `CMTime(value: 1, timescale: Int32(selectedFPS))`. Publish the actual selected FPS. On denied/restricted authorization, publish a typed error and never create a session.

- [ ] **Step 4: Implement CaptureView behavior**

Display the `AVCaptureVideoPreviewLayer`, non-interactive alignment grid, selected `120 FPS`/`240 FPS`/fallback label, three-second countdown, start/stop control, and an explicit permission retry route to Settings. Once `recordedMovieURL` is available, import it through the same `HomeViewModel.createProject(from:)` path and navigate to review.

- [ ] **Step 5: Run unit tests, build for a device, and commit**

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SwingArcTests/CameraFormatSelectionTests`

Expected: `** TEST SUCCEEDED **`.

Run: `xcodebuild build -project SwingArc.xcodeproj -scheme SwingArc -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`

Expected: `** BUILD SUCCEEDED **`.

```bash
git add SwingArc/Services/CameraCaptureController.swift SwingArc/Views/CaptureView.swift SwingArc/Views/HomeView.swift SwingArcTests/CameraFormatSelectionTests.swift
git rm SwingArc/Views/CameraView.swift
git commit -m "feat: add high-frame-rate swing capture"
```

## Task 6: Replace prototype playback with on-demand frame analysis

**Files:**
- Create: `SwingArc/Services/PlaybackController.swift`
- Modify: `SwingArc/Services/VisionPoseDetector.swift`
- Create: `SwingArc/Views/VideoPlayerView.swift`
- Create: `SwingArcTests/PlaybackSchedulingTests.swift`
- Retire after migration: `SwingArc/Views/CustomVideoPlayer.swift`

**Interfaces:**
- Consumes: `VideoAssetDescriptor`, `VisionPoseDetector`.
- Produces: `PlaybackController.currentTime`, `duration`, `speed`, `currentPose`, `analysisState`, `play()`, `pause()`, `seek(to:)`, `step(by:)`, `setLoop(_:)`.

- [ ] **Step 1: Write scheduling tests that do not require AVFoundation decoding**

```swift
func testSchedulerDropsOlderRequestWhenNewerTimeArrives() {
    var scheduler = PoseRequestScheduler(minimumInterval: 1.0 / 15.0)
    XCTAssertTrue(scheduler.shouldStart(time: 1.0, now: 1.0))
    XCTAssertFalse(scheduler.shouldStart(time: 1.02, now: 1.02))
    XCTAssertTrue(scheduler.shouldStart(time: 1.10, now: 1.10))
}

func testSchedulerAlwaysAnalyzesSettledSeek() {
    var scheduler = PoseRequestScheduler(minimumInterval: 1.0 / 15.0)
    XCTAssertTrue(scheduler.shouldStartSettledSeek(time: 3.0))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SwingArcTests/PlaybackSchedulingTests`

Expected: compile failure because `PoseRequestScheduler` does not exist.

- [ ] **Step 3: Implement a serial, cancelable pose pipeline**

Implement `PoseRequestScheduler` as a pure struct. `PlaybackController` owns `AVPlayer`, `AVPlayerItemVideoOutput`, an analysis `Task`, and a monotonically increasing `requestGeneration`. On playback ticks, get a pixel buffer at `player.currentTime()`, check scheduler throttling, increment generation, then call Vision on a detached task. Only publish a result when the task's generation equals the current generation and the result time is within one frame duration of `currentTime`.

The required request method is:

```swift
func requestPose(at time: CMTime, reason: PoseRequestReason) {
    // `.settledSeek` bypasses playback throttling; `.playback` uses scheduler.
}
```

`seek(to:)` must pause transient analysis, seek with zero tolerance, then request `.settledSeek` in the seek completion. `step(by:)` must use the asset's nominal frame rate, falling back to 30 fps only when metadata is zero.

- [ ] **Step 4: Update Vision output to domain samples**

Make the detector stateless per call and use this shape:

```swift
protocol PoseDetecting: Sendable {
    func detect(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, time: Double) throws -> PoseSample?
}
```

Map Vision points directly to `NormalizedPoint`; calculate spine angle only when left/right shoulder and hip midpoint data exists. Return `nil` for no body observation; throw only processing failures. The controller maps `nil` to `.noPose`, processing errors to `.failed`, and neither condition pauses playback.

- [ ] **Step 5: Implement video layer geometry and verify behavior**

`VideoPlayerView` wraps `AVPlayerLayer`, sets `.resizeAspect`, and reports the actual aspect-fit rectangle in its bounds through `onVideoRectChanged`. This rectangle is the only frame supplied to overlay views.

Run the tests from Step 2, then run full unit tests. Expected: `** TEST SUCCEEDED **`.

```bash
git add SwingArc/Services/PlaybackController.swift SwingArc/Services/VisionPoseDetector.swift SwingArc/Views/VideoPlayerView.swift SwingArcTests/PlaybackSchedulingTests.swift
git rm SwingArc/Views/CustomVideoPlayer.swift
git commit -m "feat: add on-demand video pose analysis"
```

## Task 7: Add stage analysis, review controls, and user overrides

**Files:**
- Create: `SwingArc/Services/SwingStageDetector.swift`
- Create: `SwingArc/Views/ReviewView.swift`
- Create: `SwingArc/Views/TimelineView.swift`
- Create: `SwingArcTests/SwingStageDetectorTests.swift`
- Modify: `SwingArc/Services/ProjectStore.swift`
- Retire after migration: `SwingArc/Views/ContentView.swift`

**Interfaces:**
- Consumes: `[PoseSample]`, `PlaybackController`, `SwingProject`.
- Produces: `SwingStageDetector.detect(in:) -> [SwingStage: StageMarker]`, `ReviewView(projectID:)`, and persistent manual stage overrides.

- [ ] **Step 1: Write stage detector tests with fixed pose samples**

```swift
func testDetectorFindsTopAtHighestLeadWristPositionAndImpactAtLowestHandSpeed() {
    let samples = PoseSample.swingFixture()
    let stages = SwingStageDetector().detect(in: samples)
    XCTAssertEqual(stages[.top]?.time, 0.80, accuracy: 0.001)
    XCTAssertEqual(stages[.impact]?.time, 1.20, accuracy: 0.001)
    XCTAssertEqual(stages[.top]?.source, .automatic)
}

func testManualStageWinsWhenApplyingAutomaticCandidates() {
    let existing: [SwingStage: StageMarker] = [.impact: .init(time: 1.3, source: .manual)]
    let merged = StageMarker.merging(existing: existing, automatic: [.impact: .init(time: 1.2, source: .automatic)])
    XCTAssertEqual(merged[.impact]?.time, 1.3)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SwingArcTests/SwingStageDetectorTests`

Expected: compile failure because `SwingStageDetector` does not exist.

- [ ] **Step 3: Implement deterministic candidate rules and merge logic**

For a valid sequence of at least six samples, derive: Address from the earliest stable wrist/hip distance, Top from the greatest vertical lead-wrist excursion, Impact from the maximum downward wrist velocity after Top, and Finish from the latest stable pose after Impact. Reject a stage if its required joints are missing or temporal order is invalid. Never manufacture markers from fixed duration percentages.

Use this merge function:

```swift
static func merging(existing: [SwingStage: StageMarker], automatic: [SwingStage: StageMarker]) -> [SwingStage: StageMarker] {
    automatic.merging(existing) { automaticValue, existingValue in
        existingValue.source == .manual ? existingValue : automaticValue
    }
}
```

- [ ] **Step 4: Implement review controls**

`ReviewView` loads its project from `ProjectStore`, wires playback controls for `0.1`, `0.25`, `0.5`, and `1.0`, exposes `step(by: -1/1)`, and presents `TimelineView`. The timeline allows scrubbing and changing A/B loop bounds. Tapping a stage seeks to its time; a long press at the current time assigns `StageMarker(time: currentTime, source: .manual)` and saves immediately.

When playback pauses or the user requests analysis, obtain background samples around candidate windows, call `SwingStageDetector`, merge with the project stages, and save. Show `.analyzing`, `.noPose`, and `.failed` as non-blocking status text.

- [ ] **Step 5: Run tests, UI smoke test, and commit**

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`

Expected: `** TEST SUCCEEDED **`.

```bash
git add SwingArc/Services/SwingStageDetector.swift SwingArc/Services/ProjectStore.swift SwingArc/Views/ReviewView.swift SwingArc/Views/TimelineView.swift SwingArcTests/SwingStageDetectorTests.swift SwingArcUITests
git rm SwingArc/Views/ContentView.swift
git commit -m "feat: add swing stage review and overrides"
```

## Task 8: Build the annotation canvas, pose overlay, and magnifier

**Files:**
- Create: `SwingArc/Views/AnnotationCanvas.swift`
- Create: `SwingArc/Views/PoseOverlay.swift`
- Create: `SwingArcTests/AnnotationGeometryTests.swift`
- Modify: `SwingArc/Views/ReviewView.swift`
- Retire after migration: `SwingArc/Views/DrawingOverlay.swift`

**Interfaces:**
- Consumes: `[Annotation]`, `PoseSample?`, `CGRect videoRect`, current time and loop/project bindings.
- Produces: normalized annotation editing, undo/redo, magnifier display, and render-equivalent overlay geometry.

- [ ] **Step 1: Write coordinate and hit-test tests**

```swift
func testRendererMapsLowerLeftNormalizedPointIntoAspectFitVideoRect() {
    let rect = CGRect(x: 10, y: 20, width: 200, height: 100)
    XCTAssertEqual(OverlayGeometry.viewPoint(.init(x: 0.25, y: 0.75), in: rect), CGPoint(x: 60, y: 45))
}

func testHitTestSelectsNearestLineEndpointInsideTolerance() {
    let annotation = Annotation.line(start: .init(x: 0.2, y: 0.2), end: .init(x: 0.8, y: 0.8), color: .green, width: 3)
    XCTAssertEqual(AnnotationHitTester.hit(at: .init(x: 0.21, y: 0.21), annotations: [annotation], tolerance: 0.03), .endpoint(annotationID: annotation.id, index: 0))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SwingArcTests/AnnotationGeometryTests`

Expected: compile failure because `OverlayGeometry` and `AnnotationHitTester` do not exist.

- [ ] **Step 3: Implement one renderer geometry source of truth**

```swift
enum OverlayGeometry {
    static func viewPoint(_ point: NormalizedPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.maxY - point.y * rect.height)
    }
    static func normalizedPoint(_ point: CGPoint, in rect: CGRect) -> NormalizedPoint {
        .init(x: (point.x - rect.minX) / rect.width, y: (rect.maxY - point.y) / rect.height)
    }
}
```

Use this geometry in canvas drawing, hit testing, `PoseOverlay`, and exporter rendering. Reject gesture locations outside `videoRect`; clamp accepted normalized values to `0...1`.

- [ ] **Step 4: Implement canvas tools and edit history**

Support line, circle, angle, freehand, swing-plane line, head trace, spine line, undo and redo. Begin every completed gesture by appending the pre-edit `[Annotation]` to undo history, clear redo history after a new edit, and save the project only in gesture end. A keyframe-scoped annotation must store `visibleRange: ClosedRange<Double>?`; draw it only when current time lies in the range.

When a control point is selected, render a circular 2x magnifier above the finger. Its contents must use the same `OverlayGeometry` and `PoseOverlay` drawing functions as the main canvas; do not take a screen snapshot.

- [ ] **Step 5: Render pose results and verify**

`PoseOverlay` draws only toggled layers: joint skeleton, head center/path, and spine segment/angle. It must show nothing when `PoseSample` is nil and must not mutate project data.

Run the test from Step 2 and then all tests. Expected: `** TEST SUCCEEDED **`.

```bash
git add SwingArc/Views/AnnotationCanvas.swift SwingArc/Views/PoseOverlay.swift SwingArc/Views/ReviewView.swift SwingArcTests/AnnotationGeometryTests.swift
git rm SwingArc/Views/DrawingOverlay.swift
git commit -m "feat: add editable swing annotation canvas"
```

## Task 9: Export annotated slow-motion videos

**Files:**
- Create: `SwingArc/Services/VideoExporter.swift`
- Create: `SwingArc/Views/ExportSheet.swift`
- Create: `SwingArcTests/VideoExporterTests.swift`
- Modify: `SwingArc/Views/ReviewView.swift`

**Interfaces:**
- Consumes: `SwingProject`, selected `ExportOptions`, managed asset URL, shared overlay renderer.
- Produces: `VideoExporter.export(project:options:progress:) async throws -> URL`.

- [ ] **Step 1: Write export-validation tests**

```swift
func testExportOptionsRejectNonPositiveSpeed() {
    XCTAssertThrowsError(try ExportOptions(speed: 0, showsPose: true, showsAnnotations: true))
}

func testOutputURLUsesMovExtensionAndDoesNotEqualSource() {
    let source = URL(fileURLWithPath: "/tmp/source.mov")
    XCTAssertNotEqual(VideoExporter.outputURL(for: source), source)
    XCTAssertEqual(VideoExporter.outputURL(for: source).pathExtension, "mov")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SwingArcTests/VideoExporterTests`

Expected: compile failure because `ExportOptions` and `VideoExporter` do not exist.

- [ ] **Step 3: Implement frame-based exporter**

Define:

```swift
struct ExportOptions: Equatable {
    let speed: Double; let showsPose: Bool; let showsAnnotations: Bool
    init(speed: Double, showsPose: Bool, showsAnnotations: Bool) throws {
        guard speed > 0 else { throw ExportError.invalidSpeed }; self.speed = speed; self.showsPose = showsPose; self.showsAnnotations = showsAnnotations
    }
}
```

Use `AVAssetReaderTrackOutput` for decoded video frames and `AVAssetWriterInputPixelBufferAdaptor` for rendered output. Map source presentation time `t` to output time `t / speed`; use `AVAssetReaderAudioMixOutput` plus a matching scaled `AVMutableComposition` only when audio exists. Render annotations and enabled pose layers with the exact shared Core Graphics overlay functions used by Task 8. Check `Task.isCancelled` inside the sample loop, call `cancelReading()`/`cancelWriting()`, and delete unfinished output on cancellation or error.

- [ ] **Step 4: Add export sheet and photo-library save path**

The sheet offers 0.1x, 0.25x, 0.5x, and 1.0x; switches for annotations and pose; progress; cancellation; and a share sheet after success. Saving to Photos must request `.addOnly` authorization, show a Settings action if denied, and never delete the exported file until sharing/save has completed.

- [ ] **Step 5: Run tests, manual export check, and commit**

Run the command in Step 2. Expected: `** TEST SUCCEEDED **`.

On a real iPhone, export a 120fps recording at 0.25x with a line, head trace, and Impact label. Verify the export opens in Photos, runs at the selected duration, and overlay positions match the editor.

```bash
git add SwingArc/Services/VideoExporter.swift SwingArc/Views/ExportSheet.swift SwingArc/Views/ReviewView.swift SwingArcTests/VideoExporterTests.swift
git commit -m "feat: export annotated slow-motion videos"
```

## Task 10: Integrate, remove prototype code, and verify on hardware

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-07-16-swingarc-iphone-design.md`
- Delete only after compilation: obsolete prototype sources listed in Tasks 5-8
- Create: `docs/verification/2026-07-16-iphone-mvp.md`

**Interfaces:**
- Consumes all prior tasks.
- Produces a clean app target containing only the production architecture and an evidence-based verification record.

- [ ] **Step 1: Write an integration regression test**

```swift
func testManualImpactSurvivesAutomaticAnalysisAndProjectReload() async throws {
    let store = try ProjectStore.testStore()
    var project = SwingProject.fixture()
    project.stages[.impact] = .init(time: 1.25, source: .manual)
    project.stages = StageMarker.merging(existing: project.stages, automatic: [.impact: .init(time: 1.10, source: .automatic)])
    try await store.save(project)
    let reloaded = try ProjectStore(rootURL: store.rootURL)
    XCTAssertEqual(reloaded.projects[0].stages[.impact], .init(time: 1.25, source: .manual))
}
```

- [ ] **Step 2: Run the regression test and full suite**

Run: `xcodebuild test -project SwingArc.xcodeproj -scheme SwingArc -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Verify a physical iPhone with the complete scenario**

Build and install using Xcode on a real iPhone. Record a swing on hardware that supports 120/240fps, then repeat with a photo-library import in a different orientation. In both projects: scrub, step frames, toggle pose layers, set all four stages, manually override Impact, edit each annotation type with magnifier, close/reopen, export 0.25x, and inspect the resulting asset in Photos.

Record device model, selected actual FPS, source orientation/frame rate, test outcome, and any fallback behavior in `docs/verification/2026-07-16-iphone-mvp.md`.

- [ ] **Step 4: Update user documentation**

Update README with the actual Xcode opening/build instructions, on-device privacy permissions, capture fallback behavior, project location/privacy, import workflow, manual-stage override, export workflow, and known first-release limits. Change the design spec status from `已确认，待实现计划` to `已实现并验证` only if Step 3 passes fully; otherwise set it to `已实现，待硬件验证`.

- [ ] **Step 5: Inspect final diff, commit, and retain evidence**

Run:

```bash
git status --short
git diff --check
xcodebuild build -project SwingArc.xcodeproj -scheme SwingArc -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Expected: no unintentional files, no whitespace errors, and `** BUILD SUCCEEDED **`.

```bash
git add README.md docs SwingArc SwingArcTests SwingArcUITests SwingArc.xcodeproj .gitignore
git commit -m "docs: verify SwingArc iPhone MVP"
```

## Requirement coverage check

| Confirmed requirement | Implementing task(s) |
| --- | --- |
| iPhone self-record and review | 1, 4, 5, 7, 10 |
| Camera recording and photo-library import | 3, 4, 5 |
| 120/240fps when supported | 5, 10 |
| Slow motion, frame step, scrub, looping | 6, 7 |
| On-demand `AVPlayerItemVideoOutput` and Vision | 6 |
| Skeleton, head trace, and spine angle | 2, 6, 8 |
| Automatic Address/Top/Impact/Finish and manual correction | 2, 7, 10 |
| Swing-plane/head/spine drawing and magnifier | 2, 8 |
| Editable local projects | 2, 3, 4, 10 |
| Export annotated video | 9, 10 |
| Offline/privacy and graceful fallback | Global Constraints, 3, 5, 6, 9, 10 |

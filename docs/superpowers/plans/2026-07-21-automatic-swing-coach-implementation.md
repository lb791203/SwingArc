# Automatic Swing Coach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every imported or automatically captured golf video enter a local, evidence-backed per-swing analysis pipeline that can render selected body/club metrics and give at most one truthful spoken correction.

**Architecture:** Keep `VideoPlaybackManager` as the only AVPlayer owner. Add a coordinator above the existing stateless `SwingVideoAnalysisEngine`: it first identifies one or more candidate swing windows, then solves each attempt independently and persists compact replay-ready results. A separate metric evaluator consumes only solved pose/object evidence and an explicit, versioned standard; replay overlays and speech consume `MetricResult` rather than inferring technique from SwiftUI state.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Vision `VNDetectHumanBodyPoseRequest`, local JSON/UserDefaults persistence, AVSpeechSynthesizer, existing standalone `swiftc` smoke tests, Xcode 27 beta iOS Simulator.

## Global Constraints

- iOS-only and on-device: videos, poses, metrics, standards, baselines, and voice decisions must not be uploaded.
- Do not add club-type recognition in this feature.
- Do not fabricate P points, metric trajectories, scores, or diagnoses. Missing evidence produces an explicit unavailable result.
- DTL and 正面 have different metric profiles. 挥杆平面 requires continuous shaft evidence; 释放 requires shaft plus impact evidence.
- A normal or full-screen replay remains video-first: tap video to play/pause; no permanent time labels, P1–P8 text, or transport controls on compact iPhone replay.
- Configuration is a full separate page, not a half-video panel. It may select one or more available metrics.
- Preserve `VideoPlaybackManager` as the sole owner of `AVPlayer`; analysis services must not create a second playback path.
- Preserve existing stored projects: all new persisted fields are optional and decoding older `LocalAnalysisProject` payloads must continue to work.
- Build and test in the `iPhone 17` simulator first. Do not install to a physical iPhone during these tasks.
- The two supplied real videos currently fail as `noStableGolfer`; no later metric or voice task may claim that they produce a diagnosis until Task 1 changes the verified result.

---

## File structure and responsibility map

| Path | Responsibility |
| --- | --- |
| `SwingArc/Services/VisionPoseDetector.swift` | Primary-golfer tracking policy and diagnostics used by the existing Vision pass. |
| `SwingArc/Services/SwingStageDetector.swift` | Reusable analysis-window and P1–P8 solving primitives. |
| `SwingArc/Services/SwingAttemptCoordinator.swift` | New serial multi-attempt orchestration around the existing engine. |
| `SwingArc/Models/WorkspaceModels.swift` | Persistable `SwingAttempt`, status, and selected-attempt project metadata. |
| `SwingArc/Services/LocalProjectStore.swift` | Backward-compatible persistence for attempts and selected metric layers. |
| `SwingArc/Models/SwingMetricModels.swift` | New Codable measurement, result, standard, evidence, and overlay types. |
| `SwingArc/Services/SwingMetricEvaluator.swift` | Pure normalized geometry + explicit standard evaluation. |
| `SwingArc/Services/SpeechCoach.swift` | Pure feedback selection and the AVSpeechSynthesizer adapter. |
| `SwingArc/Views/ContentView.swift` | Starts analysis automatically after import/capture and persists its output. |
| `SwingArc/Views/AnalysisWorkspaceView.swift` | Selects attempts, routes completed metrics into replay, and removes manual-start dependency on compact UI. |
| `SwingArc/Views/WorkspaceComponents.swift` | Multi-select full-page metric configuration and attempt-result presentation. |
| `SwingArc/Views/DrawingOverlay.swift` | Canvas-only drawing of evidence-backed metric overlays. |
| `SwingArc/Services/OnDevicePracticeAnalyzer.swift` and `SwingArc/Services/PracticeSessionEngine.swift` | Gives the automatic practice loop one completed attempt result and one voice decision. |
| `Tests/*Smoke.swift` | Deterministic policy/geometry/persistence checks; real-video acceptance remains explicit local validation. |
| `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj` | Registers each new Swift source and the bundled standard resource with the app target. |

### Task 1: Make primary-golfer locking observable and more tolerant of a stable single golfer

**Files:**
- Modify: `SwingArc/Services/VisionPoseDetector.swift:257-351`
- Modify: `SwingArc/Services/SwingStageDetector.swift:2436-2451`
- Modify: `SwingArc/Models/WorkspaceModels.swift:67-113`
- Create: `Tests/PrimaryGolferTrackingPolicySmoke.swift`
- Create: `Tests/RealVideoTrackingDiagnostics.swift`

**Interfaces:**
- Consumes: `PoseEstimationResult`, `SwingGeometry.distance`, existing coarse/fine calls to `PrimaryGolferTracker.select(from:stableBall:)`.
- Produces: `PrimaryGolferTrackingDiagnostics` and `AnalysisFailure.noStableGolfer` detail that later coordinator attempts can persist.

- [ ] **Step 1: Write the failing pure-policy smoke test**

Create `Tests/PrimaryGolferTrackingPolicySmoke.swift` with fixtures for an anchored golfer that shifts during a full swing, a same-size bystander outside the allowed envelope, and repeated no-pose frames:

```swift
import Foundation

@main
struct PrimaryGolferTrackingPolicySmoke {
    static func main() {
        let anchor = PrimaryGolferIdentity(center: .init(x: 0.50, y: 0.56), scale: 0.54)
        let movingGolfer = PrimaryGolferIdentity(center: .init(x: 0.72, y: 0.55), scale: 0.53)
        let bystander = PrimaryGolferIdentity(center: .init(x: 0.88, y: 0.55), scale: 0.53)

        precondition(PrimaryGolferTrackingPolicy.matches(candidate: movingGolfer, anchor: anchor))
        precondition(!PrimaryGolferTrackingPolicy.matches(candidate: bystander, anchor: anchor))
        precondition(PrimaryGolferTrackingPolicy.shouldRetainAnchor(afterConsecutiveMisses: 4))
        precondition(!PrimaryGolferTrackingPolicy.shouldRetainAnchor(afterConsecutiveMisses: 5))
    }
}
```

- [ ] **Step 2: Run the new test and confirm it fails because the policy does not exist**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Services/VisionPoseDetector.swift \
  Tests/PrimaryGolferTrackingPolicySmoke.swift \
  -framework Vision -framework CoreGraphics -framework Foundation \
  -o /tmp/PrimaryGolferTrackingPolicySmoke && /tmp/PrimaryGolferTrackingPolicySmoke
```

Expected: compilation fails with `cannot find 'PrimaryGolferIdentity' in scope`.

- [ ] **Step 3: Add scale-aware identity matching and diagnostics**

In `VisionPoseDetector.swift`, add these pure types immediately above `PrimaryGolferTracker`, then make `select` rank only candidates accepted by this policy after the anchor has been locked:

```swift
struct PrimaryGolferIdentity: Equatable {
    let center: CGPoint
    let scale: Double
}

enum PrimaryGolferTrackingPolicy {
    static func maximumCenterDistance(for anchorScale: Double) -> Double {
        min(0.34, max(0.24, anchorScale * 0.52))
    }

    static func matches(candidate: PrimaryGolferIdentity, anchor: PrimaryGolferIdentity) -> Bool {
        let distance = hypot(
            Double(candidate.center.x - anchor.center.x),
            Double(candidate.center.y - anchor.center.y)
        )
        let scaleDelta = abs(candidate.scale - anchor.scale) / max(anchor.scale, 0.10)
        return distance <= maximumCenterDistance(for: anchor.scale) && scaleDelta <= 0.34
    }

    static func shouldRetainAnchor(afterConsecutiveMisses misses: Int) -> Bool {
        misses <= 4
    }
}

struct PrimaryGolferTrackingDiagnostics: Equatable {
    var acceptedFrames = 0
    var rejectedOutsideAnchor = 0
    var rejectedScaleMismatch = 0
    var noPoseFrames = 0
}
```

Use `PrimaryGolferTrackingPolicy.shouldRetainAnchor` instead of the inline `> 4` branch. Count each rejected outcome in the tracker; expose a read-only `diagnostics` value. Extend the engine output with this diagnostic value and keep the failure as `.noStableGolfer` when there are fewer than eight selected fine poses. Do not relax that eight-pose evidence floor.

- [ ] **Step 4: Add a local diagnostic runner for the supplied clips**

Create `Tests/RealVideoTrackingDiagnostics.swift`. It must accept one file path, run `SwingVideoAnalysisEngine`, and print JSON containing the file name, outcome, and `trackingDiagnostics` when available:

```swift
struct TrackingDiagnosticReport: Encodable {
    let video: String
    let outcome: String
    let diagnostics: PrimaryGolferTrackingDiagnostics?
}
```

Use the same `AnalysisRunGate` lifecycle as `Tests/RealVideoP1P8Acceptance.swift`; do not fake a completed analysis in this runner.

- [ ] **Step 5: Re-run smoke and real-video diagnostics**

Run the smoke command from Step 2, then compile the runner with the same source set used by `Tests/RealVideoP1P8Acceptance.swift` and execute it for:

```text
/Users/liangbo/Downloads/SwingArc-386EF602-CFC2-4792-8B1D-80A10CBCA009.MOV
/Users/liangbo/Downloads/11156_raw.MP4
```

Expected: the smoke test passes; each real clip either returns a completed result or a concrete failure plus tracking counts. If either still fails, use the printed rejection category to adjust only the matching policy bound and repeat. Do not proceed by suppressing the failure banner.

- [ ] **Step 6: Build and commit the tracking slice**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -jobs 1 -derivedDataPath /tmp/SwingArcAutoCoachDerivedData \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=90A656D1-01D1-44FB-B9D2-2FFD811F24C3' \
  build CODE_SIGNING_ALLOWED=NO
git add SwingArc/Services/VisionPoseDetector.swift SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Models/WorkspaceModels.swift Tests/PrimaryGolferTrackingPolicySmoke.swift \
  Tests/RealVideoTrackingDiagnostics.swift
git commit -m "fix: stabilize primary golfer tracking"
```

Expected: `BUILD SUCCEEDED` and one focused commit.

### Task 2: Segment imports into independent SwingAttempt records and start analysis automatically

**Files:**
- Modify: `SwingArc/Services/SwingStageDetector.swift:3199-3480`
- Create: `SwingArc/Services/SwingAttemptCoordinator.swift`
- Modify: `SwingArc/Models/WorkspaceModels.swift:620-710`
- Modify: `SwingArc/Services/LocalProjectStore.swift:3-115`
- Modify: `SwingArc/Views/CustomVideoPlayer.swift:330-424`
- Modify: `SwingArc/Views/ContentView.swift:200-330`
- Modify: `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj`
- Create: `Tests/SwingAttemptSegmenterSmoke.swift`
- Create: `Tests/AutomaticAnalysisLaunchSmoke.swift`

**Interfaces:**
- Consumes: the Task 1 tracker, `SwingCoreLocator`, `SwingVideoAnalysisEngine`, `LocalAnalysisProject`, and imported/captured file URLs.
- Produces: `SwingAttempt`, `SwingAttemptState`, `SwingAttemptAnalysis`, `SwingAttemptCoordinator.analyze(url:view:progress:completion:)`, and `VideoPlaybackManager.analyzeAttempts(...)`.

- [ ] **Step 1: Write failing segmentation and auto-start tests**

Add `Tests/SwingAttemptSegmenterSmoke.swift` with synthetic coarse samples that contain two well-separated motion-energy groups. Its assertions must require two non-overlapping windows in chronological order and reject a candidate shorter than 0.8 seconds:

```swift
let attempts = SwingAttemptSegmenter.segment(samples: twoSwingSamples, sourceDuration: 12)
precondition(attempts.map(\.ordinal) == [1, 2])
precondition(attempts[0].endTime < attempts[1].startTime)
precondition(attempts.allSatisfy { $0.duration >= 0.8 && $0.duration <= 8 })
```

Add `Tests/AutomaticAnalysisLaunchSmoke.swift` against a pure `AutomaticAnalysisPolicy`:

```swift
precondition(AutomaticAnalysisPolicy.shouldAnalyze(event: .importCompleted))
precondition(AutomaticAnalysisPolicy.shouldAnalyze(event: .capturedClipSaved))
precondition(!AutomaticAnalysisPolicy.shouldAnalyze(event: .projectReopened))
```

- [ ] **Step 2: Run both tests and confirm the new types are missing**

Compile each smoke executable with the smallest existing source set that contains `SwingCoreLocator` and `WorkspaceModels`.

Expected: compile failures mentioning `SwingAttemptSegmenter` and `AutomaticAnalysisPolicy`.

- [ ] **Step 3: Add persistable attempt boundaries and backward-compatible project storage**

In `WorkspaceModels.swift`, define the project-level types exactly as follows:

```swift
enum SwingAttemptState: String, Codable, Equatable {
    case queued
    case analyzing
    case completed
    case unavailable
}

struct SwingAttempt: Identifiable, Codable, Equatable {
    let id: UUID
    let ordinal: Int
    let startTime: Double
    let endTime: Double
    var state: SwingAttemptState
    var failure: AnalysisFailureRecord?

    var duration: Double { endTime - startTime }
}

struct AnalysisFailureRecord: Codable, Equatable {
    let code: String
    let message: String
}
```

Add optional `attempts: [SwingAttempt]` and `selectedAttemptID: UUID?` to `LocalAnalysisProject`. Decode them with `decodeIfPresent(...) ?? []`, and encode only the values that exist. Extend `LocalProjectStatus` with `case analyzed` only when at least one attempt is completed; unavailable attempts remain saved but do not become an analyzed project.

- [ ] **Step 4: Extract multi-window segmentation without duplicating the P1–P8 solver**

In `SwingStageDetector.swift`, add a pure segmenter using the existing coarse energy calculation:

```swift
enum SwingAttemptSegmenter {
    static func segment(samples: [CoarseSwingSample], sourceDuration: Double) -> [SwingAttempt]
}
```

It must:

1. reuse `SwingCoreLocator` energy, smoothing, and the 0.5-second bridge rule;
2. keep all groups whose duration expanded by `AdaptiveSwingWindowPlanner.initialPadding` is between 0.8 and 8 seconds;
3. merge overlapping expanded windows;
4. sort by start time and assign `ordinal` from one;
5. return `[]` rather than a guessed one-swing window when no group passes the rules.

Refactor the AV coarse scan inside `SwingVideoAnalysisEngine` into an internal `coarseSamples(url:range:...)` helper. Add an optional `candidateWindow: SwingWindow?` argument to `analyze`; when present, it scans and solves only that window while retaining original source-frame timestamps. The current one-attempt method calls the same helper with `nil`.

- [ ] **Step 5: Add a serial coordinator and manager publication boundary**

Create `SwingAttemptCoordinator.swift` with these public shapes:

```swift
struct SwingAttemptAnalysis: Codable, Equatable {
    var attempt: SwingAttempt
    var output: PersistedAttemptOutput?
}

final class SwingAttemptCoordinator: Sendable {
    func analyze(
        url: URL,
        view: PracticeCameraView?,
        runID: UUID,
        gate: AnalysisRunGate,
        progress: @escaping SwingVideoAnalysisEngine.ProgressHandler
    ) -> [SwingAttemptAnalysis]
}
```

`SwingAttemptAnalysis` remains an in-memory wrapper at this task: it retains one `SwingVideoAnalysisOutput?` for the selected live attempt and never retains `CGImage`, `AVAsset`, or Vision request objects. Task 3 introduces the Codable `PersistedAttemptOutput` used when result geometry is ready to save. The coordinator executes attempt windows serially, marks a failed attempt `.unavailable` with the engine's real failure message, and continues to later attempts.

Extend `VideoPlaybackManager` with `@Published private(set) var attemptAnalyses: [SwingAttemptAnalysis] = []`. `analyzeAttempts` uses the existing `AnalysisRunGate`, publishes incremental attempt state only if the run ID remains active, and sets the legacy `analysisOutput` to the selected completed attempt for existing screens. Persist the attempt bounds/state/failure in Task 2; persist replay geometry in Task 3. Never make a second `AVPlayer`.

- [ ] **Step 6: Replace the manual import/capture start with the policy**

In `ContentView.loadVideoFromURL`, add an `origin: VideoLoadOrigin` argument (`.importCompleted`, `.capturedClipSaved`, `.projectReopened`). After `activeProject` is initialized and only if `AutomaticAnalysisPolicy.shouldAnalyze(event:)` is true, dispatch `runAutomaticAttemptAnalysis()` on the next main-loop turn. That method pauses playback, calls `playbackManager.analyzeAttempts`, persists returned attempts, merges automatic stage markers only for the selected completed attempt, and leaves unavailable attempts untouched.

Keep `runAISwingAnalysis()` temporarily as a debug/retry action on regular layouts only; compact iPhone import must not show it as the normal required action. In `PracticeSessionView`'s `onOpenLastClip`, pass `.capturedClipSaved`; in the photo picker pass `.importCompleted`; reopening a library project passes `.projectReopened` and restores stored results without re-running analysis.

- [ ] **Step 7: Register, test, build, and commit**

Add `SwingAttemptCoordinator.swift` to the Xcode project Sources build phase. Run both new smoke tests, existing `Tests/AnalysisSessionStateSmoke.swift`, and `Tests/ProjectPersistenceSmoke.swift`; then run the Xcode build command from Task 1.

Launch the simulator with the existing debug import argument and verify: after import, a scanning overlay appears without tapping `AI 分析`; a single completed attempt enters replay; a real failure remains visible as its reason. Commit:

```bash
git add SwingArc/Services/SwingStageDetector.swift SwingArc/Services/SwingAttemptCoordinator.swift \
  SwingArc/Models/WorkspaceModels.swift SwingArc/Services/LocalProjectStore.swift \
  SwingArc/Views/CustomVideoPlayer.swift SwingArc/Views/ContentView.swift \
  /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj \
  Tests/SwingAttemptSegmenterSmoke.swift Tests/AutomaticAnalysisLaunchSmoke.swift
git commit -m "feat: analyze imported swings automatically"
```

### Task 3: Create evidence-backed metric results and a versioned, non-fabricated standard boundary

**Files:**
- Create: `SwingArc/Models/SwingMetricModels.swift`
- Create: `SwingArc/Services/SwingMetricEvaluator.swift`
- Modify: `SwingArc/Models/WorkspaceModels.swift:413-617`
- Modify: `SwingArc/Services/SwingAttemptCoordinator.swift`
- Modify: `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj`
- Create: `Tests/SwingMetricEvaluatorSmoke.swift`
- Create: `Tests/SwingStandardStoreSmoke.swift`

**Interfaces:**
- Consumes: `SwingPoseSample`, `SwingStageDetection`, `SwingObjectEvidence`, `PracticeCameraView`, `FeedbackMetric`, and per-attempt source frame rate.
- Produces: `PersistedObjectEvidence`, `PersistedAttemptOutput`, `MetricMeasurement`, `MetricResult`, `MetricOverlay`, `SwingStandard`, and `SwingMetricEvaluator.evaluate(...)`.

- [ ] **Step 1: Write failing geometry and evidence-gate tests**

Create `Tests/SwingMetricEvaluatorSmoke.swift` that supplies confirmed P1/P4/P6 body samples. Require a DTL `spineStability` result with a body-only overlay, and require `.insufficientEvidence` for DTL `swingPlane` when shaft evidence is absent and for 正面 `clubRelease` without confirmed impact/shaft evidence:

```swift
precondition(result(for: .spineStability, in: dtlResults)?.state == .inZone)
precondition(result(for: .swingPlane, in: dtlResults)?.state == .insufficientEvidence)
precondition(result(for: .clubRelease, in: faceOnResults)?.state == .insufficientEvidence)
```

Create `Tests/SwingStandardStoreSmoke.swift` that decodes a valid `SwingStandard`, rejects a range where `attention.lowerBound < target.lowerBound`, and returns `.needsApprovedStandard` when no production-approved standard exists for a metric/view/stage.

- [ ] **Step 2: Run tests and confirm they fail for missing models/evaluator**

Compile the two new executables with `WorkspaceModels.swift`, `SwingStageDetector.swift`, and the new files absent.

Expected: `MetricResult`, `SwingStandard`, and `SwingMetricEvaluator` are unresolved symbols.

- [ ] **Step 3: Define Codable measurement and standard types**

Create `SwingMetricModels.swift` with these types:

```swift
enum MetricResultState: String, Codable, Equatable { case inZone, attention, insufficientEvidence, needsApprovedStandard }
enum MetricEvidence: String, Codable, Equatable { case pose, handTrajectory, shaft, impact, ballChange }

struct NormalizedRange: Codable, Equatable {
    let lowerBound: Double
    let upperBound: Double
    func contains(_ value: Double) -> Bool { lowerBound...upperBound ~= value }
}

struct SwingStandard: Codable, Equatable, Identifiable {
    let id: String
    let version: String
    let view: PracticeCameraView
    let metric: FeedbackMetric
    let stage: SwingStage
    let target: NormalizedRange
    let attention: NormalizedRange
    let minimumConfidence: Float
    let approvedAt: Date
    let provenance: String
}

struct MetricMeasurement: Codable, Equatable {
    let metric: FeedbackMetric
    let stage: SwingStage
    let normalizedValue: Double
    let confidence: Float
    let evidence: Set<MetricEvidence>
}

struct MetricResult: Codable, Equatable, Identifiable {
    let id: UUID
    let metric: FeedbackMetric
    let state: MetricResultState
    let measurements: [MetricMeasurement]
    let standardID: String?
    let evidenceMessage: String
    let overlay: MetricOverlay?
}
```

Also define `PersistedObjectEvidence` (source-frame index plus the existing shaft/ball/ball-change flags) and `PersistedAttemptOutput` (stage detections, pose samples, object evidence, lead arm, source frame rate, and `[MetricResult]`). Make the persisted point representation a Codable `NormalizedPoint { let x: Double; let y: Double }`; do not depend on platform-specific `CGPoint` coding. Add `var output: PersistedAttemptOutput?` to `SwingAttempt` with `decodeIfPresent`, so the Task 2 attempt records stay readable. `MetricOverlay` must be Codable normalized points/lines/angles only, so it can be redrawn at any video size. Add an `approved` flag to the standard store; bundled bootstrap fixtures can exercise evaluation but must not be presented as production coaching standards unless their `provenance` identifies the coach-labelled dataset and `approvedAt` is set.

- [ ] **Step 4: Implement body-first geometry and explicit gates**

Create `SwingMetricEvaluator.swift` with:

```swift
enum SwingMetricEvaluator {
    static func evaluate(
        samples: [SwingPoseSample],
        detections: [SwingStageDetection],
        objectEvidence: [PersistedObjectEvidence],
        view: PracticeCameraView,
        standards: [SwingStandard]
    ) -> [MetricResult]
}
```

Use `shoulderWidth`, then `hipWidth`, then torso length as the normalization scale. Only create an `.inZone` or `.attention` result when all required stage samples have `aggregateConfidence >= 0.65` and a matching approved standard exists. Implement these first body metrics and their geometry:

| View | Metric | Measurement |
| --- | --- | --- |
| DTL | 髋部前倾 | address shoulder-mid to hip-mid angle |
| DTL | 髋部深度 | address/top/impact hip-mid horizontal displacement divided by torso length |
| DTL | 膝屈 | mean left/right hip-knee-ankle angle at address |
| DTL | 手位 | hand-mid relative to hip-mid at address |
| DTL | 手部路径 | wrist-mid polyline through confirmed movement stages, normalized by torso |
| DTL | 脊柱稳定 | max P1-to-P4/P6 spine-angle delta and head shift |
| DTL | 头部位置 | max head displacement from address divided by torso |
| 正面 | 髋位、胸位、手位、站距、脊柱侧倾、前导肩、前导髋、头部位置 | equivalent frontal joint distances/angles at the profile-defined stages |

For `.swingPlane` demand at least three continuous shaft observations spanning its configured checkpoints. For `.clubRelease` demand a confirmed impact stage at `>=120 FPS`, shaft evidence at P5/P6, and ball or ball-change evidence at P6. If a gate fails, return the metric with `.insufficientEvidence`, no line/angle overlay, and the exact missing evidence in `evidenceMessage`.

- [ ] **Step 5: Attach metrics to each completed attempt without recomputing Vision**

Create `PersistedAttemptOutput` from the completed `SwingVideoAnalysisOutput`: map stage detections, pose samples, object evidence, `leadArm`, `sourceFrameRate`, and `[MetricResult]` to the Codable forms defined in Step 3. Task 2's coordinator must call `SwingMetricEvaluator` after the existing engine completes; it must not decode the video or invoke Vision again. Store the selected standard version in every resulting `MetricResult`.

- [ ] **Step 6: Run tests, build, and commit**

Run the two new smoke tests plus `Tests/SwingTechniqueEvaluatorSmoke.swift` and `Tests/PracticeFeedbackPolicySmoke.swift`. Build the simulator target and verify a completed fixture attempt produces only metric overlays backed by results; unavailable metrics have no geometry.

```bash
git add SwingArc/Models/SwingMetricModels.swift SwingArc/Services/SwingMetricEvaluator.swift \
  SwingArc/Models/WorkspaceModels.swift SwingArc/Services/SwingAttemptCoordinator.swift \
  /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj \
  Tests/SwingMetricEvaluatorSmoke.swift Tests/SwingStandardStoreSmoke.swift
git commit -m "feat: add evidence-backed swing metrics"
```

### Task 4: Make metric selection multi-select and render only selected evidence on replay

**Files:**
- Modify: `SwingArc/Models/WorkspaceModels.swift:487-546`
- Modify: `SwingArc/Services/LocalProjectStore.swift:3-115`
- Modify: `SwingArc/Views/ContentView.swift:1-330`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift:1-650`
- Modify: `SwingArc/Views/WorkspaceComponents.swift:1-210`
- Modify: `SwingArc/Views/DrawingOverlay.swift:1-120`
- Create: `Tests/MetricSelectionPolicySmoke.swift`
- Create: `Tests/MetricOverlayPolicySmoke.swift`

**Interfaces:**
- Consumes: Task 2 selected attempt and Task 3 `[MetricResult]`.
- Produces: `FeedbackConfiguration.selectedMetrics`, `MetricSelectionPolicy`, and `MetricOverlayPolicy.visibleOverlays(...)`.

- [ ] **Step 1: Write failing selection/overlay policy tests**

Create `Tests/MetricSelectionPolicySmoke.swift` requiring one or more selected available metrics and automatic removal of an unavailable metric:

```swift
var configuration = FeedbackConfiguration(selectedMetrics: [.handPath, .spineStability])
configuration = MetricSelectionPolicy.pruned(configuration, against: results)
precondition(configuration.selectedMetrics == [.spineStability])
```

Create `Tests/MetricOverlayPolicySmoke.swift` with selected `handPath` and `spineStability` results. Assert it returns two overlays at their valid stage times, none for a non-selected result, and none for `.insufficientEvidence`.

- [ ] **Step 2: Run tests and confirm the existing one-active-metric configuration cannot satisfy them**

Compile the two tests against the current models. Expected: initialization/signature failures because `FeedbackConfiguration` has only `activeMetric` and checkpoint state.

- [ ] **Step 3: Migrate configuration to an additive selection model**

Replace `FeedbackConfiguration.activeMetric` and `enabledCheckpoints` with:

```swift
struct FeedbackConfiguration: Codable, Equatable {
    var selectedMetrics: Set<FeedbackMetric>
    var selectedAttemptID: UUID?

    static func defaultValue(for view: PracticeCameraView) -> FeedbackConfiguration {
        FeedbackConfiguration(selectedMetrics: [], selectedAttemptID: nil)
    }
}
```

Write custom decoding that maps legacy `activeMetric` to a one-element set and ignores old checkpoints. Keep legacy coding keys until all stored payloads can migrate. `MetricSelectionPolicy.pruned` removes items unless the selected attempt has `.inZone` or `.attention` results with an overlay; it never silently chooses a substitute metric.

- [ ] **Step 4: Render selected metrics via a separate Canvas layer**

Add `MetricOverlayPolicy.visibleOverlays(results:selected:time:frameDuration:)` and a `MetricOverlayLayer` in `DrawingOverlay.swift`. It receives the selected attempt's metric results and returns early unless the current playback time is within one source-frame duration of an overlay checkpoint. Draw standardized colors only from the result payload: hand path blue, posture/spine teal, attention red, target-zone green. Do not use the current real-time `currentPose` as a substitute for missing saved metric geometry.

Pass the selected attempt's results from `ContentView` through `AnalysisWorkspaceView` and `VideoCanvasView` to this layer. Preserve manual drawings and the existing debug skeleton toggles; the feedback overlay is independent and never becomes a drawing element.

- [ ] **Step 5: Update the full-page configuration and compact replay entry**

In `SwingFeedbackConfigurationView`, replace the single-choice checkmark with 48-point checkbox rows. Group only metrics in the selected DTL/正面 profile. Display `目标区`, `需关注`, `证据不足`, or `缺少已审核标准` from the actual `MetricResult`; disabled rows show the result's `evidenceMessage` and do not change selection.

In `FullscreenVideoPlaybackView`, keep the central parameter capsule as the only feedback-settings entrance. Its title is `全部参数` when no metrics are selected, one professional Chinese metric title for one selected metric, or `已选 N 项` for multiple. Do not add explanatory tap text, time labels, P1–P8 labels, pause button, or a half-screen video configuration panel.

In compact workspace, remove the normal `AI 分析` call-to-action once automatic analysis is wired; retain a compact results entry only after there is a selected attempt result.

- [ ] **Step 6: Run smoke tests, validate simulator interaction, and commit**

Run the two new tests plus `Tests/FeedbackProfileSmoke.swift`, `Tests/FullscreenReplayPolicySmoke.swift`, and `Tests/ProjectPersistenceSmoke.swift`. In simulator: import a clip, wait for analysis, select two available parameters from the full page, enter full screen, tap video to play/pause, and confirm only the two chosen overlays appear at their evidence stages.

```bash
git add SwingArc/Models/WorkspaceModels.swift SwingArc/Services/LocalProjectStore.swift \
  SwingArc/Views/ContentView.swift SwingArc/Views/AnalysisWorkspaceView.swift \
  SwingArc/Views/WorkspaceComponents.swift SwingArc/Views/DrawingOverlay.swift \
  Tests/MetricSelectionPolicySmoke.swift Tests/MetricOverlayPolicySmoke.swift
git commit -m "feat: show selected swing metric overlays"
```

### Task 5: Add one-result SpeechCoach and drill routing to automatic practice

**Files:**
- Create: `SwingArc/Services/SpeechCoach.swift`
- Modify: `SwingArc/Models/PracticeModels.swift:50-250`
- Modify: `SwingArc/Services/OnDevicePracticeAnalyzer.swift:1-52`
- Modify: `SwingArc/Services/PracticeSessionEngine.swift:35-180`
- Modify: `SwingArc/Views/PracticeSessionView.swift:1-260`
- Modify: `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj`
- Create: `Tests/SpeechCoachPolicySmoke.swift`
- Modify: `Tests/PracticeSessionEngineSmoke.swift`

**Interfaces:**
- Consumes: a single Task 2 completed attempt and Task 3 `MetricResult` values; existing `PriorityFeedback` remains fallback-compatible during migration.
- Produces: `PracticeAnalysisResult`, `SpeechCoachPolicy.message(for:)`, and `SpeechCoach.speak(_:)`.

- [ ] **Step 1: Write failing speech-selection and practice-loop tests**

Create `Tests/SpeechCoachPolicySmoke.swift`:

```swift
let attention = MetricResult(
    id: UUID(), metric: .handPath, state: .attention, measurements: [],
    standardID: "coach-v1", evidenceMessage: "", overlay: nil
)
let stable = MetricResult(
    id: UUID(), metric: .spineStability, state: .inZone, measurements: [],
    standardID: "coach-v1", evidenceMessage: "", overlay: nil
)
let insufficient = MetricResult(
    id: UUID(), metric: .headPosition, state: .insufficientEvidence, measurements: [],
    standardID: nil, evidenceMessage: "缺少全身入镜", overlay: nil
)
precondition(SpeechCoachPolicy.message(for: [attention]) == "下杆手部路径需要调整。建议练习：腋下夹毛巾。")
precondition(SpeechCoachPolicy.message(for: [stable]) == "本次挥杆稳定，继续保持。")
precondition(SpeechCoachPolicy.message(for: [insufficient]) == "本球证据不足，请调整机位并确保全身入镜。")
```

Modify `Tests/PracticeSessionEngineSmoke.swift` so it asserts a successful analyzed clip yields one `PracticeAnalysisResult` and that a second impact cannot start while the first is speaking/result-ribbon state.

- [ ] **Step 2: Run tests and confirm SpeechCoach types are absent**

Compile the new smoke test with `PracticeModels.swift`. Expected: missing `SpeechCoachPolicy` and `PracticeAnalysisResult` symbols.

- [ ] **Step 3: Add a deterministic policy before AV speech**

In `PracticeModels.swift`, add:

```swift
struct PracticeAnalysisResult: Equatable {
    let feedback: PriorityFeedback
    let metricResults: [MetricResult]
    let drill: DrillRecommendation?
    let voiceMessage: String
}
```

Create `SpeechCoach.swift` with `SpeechCoachPolicy.message(for:)` that sorts only `.attention` results by explicit metric priority and returns one of exactly three cases: one corrective sentence + one drill, one positive sentence, or the evidence/camera sentence. It must never concatenate multiple diagnoses. `SpeechCoach` owns one `AVSpeechSynthesizer`, cancels any unfinished utterance before speaking the next message, sets `voice = AVSpeechSynthesisVoice(language: "zh-CN")`, and reports no state back into metric evaluation.

- [ ] **Step 4: Return the actual completed-attempt result from practice analysis**

Change `PracticeAnalyzing.analyze` to complete with `Result<PracticeAnalysisResult, PracticeSessionError>`. In `OnDevicePracticeAnalyzer`, call `SwingAttemptCoordinator` for the trimmed local clip, select its first completed attempt, derive the existing `PriorityFeedback` only as a compatibility field, derive a Drill from the highest-priority attention result (or existing finding), and call `SpeechCoachPolicy` with actual metric states. A no-result or unavailable attempt must return the explicit evidence message; it must not convert to a fake technique finding.

Update `PracticeSessionEngine` state event payloads to carry `PracticeAnalysisResult` and retain its existing three-second result ribbon sequencing. Inject `SpeechCoach` at the SwiftUI session boundary; call it once when the engine reaches `.resultRibbon`, not inside the reducer or background analysis queue.

- [ ] **Step 5: Make the ribbon and drill match the spoken result**

Update `PracticeSessionView` so the visual ribbon shows the same `voiceMessage` headline and its single linked Drill. The `onOpenLastClip` path continues to open the exact saved local clip and automatic analysis result from Task 2; it must not call Vision again just to show the ribbon.

- [ ] **Step 6: Test, build, and commit**

Run `Tests/SpeechCoachPolicySmoke.swift`, `Tests/PracticeSessionEngineSmoke.swift`, `Tests/PracticeFeedbackPolicySmoke.swift`, and the simulator build. Exercise the debug practice session in simulator to verify result-ribbon timing and that a no-evidence clip displays the camera guidance without speech that claims a swing fault.

```bash
git add SwingArc/Services/SpeechCoach.swift SwingArc/Models/PracticeModels.swift \
  SwingArc/Services/OnDevicePracticeAnalyzer.swift SwingArc/Services/PracticeSessionEngine.swift \
  SwingArc/Views/PracticeSessionView.swift \
  /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj \
  Tests/SpeechCoachPolicySmoke.swift Tests/PracticeSessionEngineSmoke.swift
git commit -m "feat: speak one evidence-backed practice cue"
```

### Task 6: Validate automatic analysis, persistence, and standards readiness on simulator

**Files:**
- Modify: `docs/validation/dtl-fo-fullscreen-replay-simulator.md`
- Create: `docs/validation/automatic-swing-coach-simulator.md`
- Create: `docs/validation/screenshots/automatic-swing-coach/` (generated evidence; do not stage until reviewed)
- Modify: `Tests/RealVideoP1P8Acceptance.swift` only if its output schema must include attempt ordinal and standard version

**Interfaces:**
- Consumes: all prior tasks and the supplied local videos.
- Produces: a reproducible simulator evidence report; no product feature depends on this document.

- [ ] **Step 1: Add a failing persistence regression case**

Extend `Tests/ProjectPersistenceSmoke.swift` with a project containing two attempts, a selected attempt UUID, two selected metrics, and an unavailable metric result. Assert round trip equality and that a legacy JSON payload without these fields still decodes as `attempts == []` and `selectedAttemptID == nil`.

- [ ] **Step 2: Run the regression before finalizing storage migration**

Run the existing project-persistence smoke command. Expected before a correct migration: legacy decode fails or new fields are lost; after Tasks 2–4 it passes.

- [ ] **Step 3: Run the full static and build regression suite**

Run at minimum:

```bash
Tests/PrimaryGolferTrackingPolicySmoke.swift
Tests/SwingAttemptSegmenterSmoke.swift
Tests/AutomaticAnalysisLaunchSmoke.swift
Tests/SwingMetricEvaluatorSmoke.swift
Tests/SwingStandardStoreSmoke.swift
Tests/MetricSelectionPolicySmoke.swift
Tests/MetricOverlayPolicySmoke.swift
Tests/SpeechCoachPolicySmoke.swift
Tests/PracticeSessionEngineSmoke.swift
Tests/ProjectPersistenceSmoke.swift
Tests/FullscreenReplayPolicySmoke.swift
```

Compile each with the exact app sources it imports, then run the Xcode simulator build command from Task 1. Expected: every smoke executable exits `0`; Xcode emits `BUILD SUCCEEDED`.

- [ ] **Step 4: Exercise the user-facing simulator flows**

Using `iPhone 17` simulator only:

1. Import `SwingArc-386EF602-CFC2-4792-8B1D-80A10CBCA009.MOV`; verify automatic scan starts with no required `AI 分析` tap and capture whether the real outcome is completed or its truthful blocker.
2. Import `11156_raw.MP4`; repeat and record tracker/attempt output separately.
3. For a completed fixture/video, select DTL and then 正面 profile metrics; confirm the profiles differ, unavailable metrics cannot be selected, and multiple selected results appear only at corresponding replay points.
4. Enter full screen; confirm video tap toggles playback, the phase rail has silhouettes rather than P1–P8 labels, and no time/transport/feedback-settings button consumes video area.
5. Enter automatic practice preview; confirm exactly one voice/ribbon result per completed clip and no diagnosis for evidence-insufficient clips.
6. Terminate/relaunch the simulator app and reopen the project; confirm attempts, selected metrics, standard version, and failure messages remain local and unchanged.

- [ ] **Step 5: Record evidence without inventing pass results**

Write `docs/validation/automatic-swing-coach-simulator.md` with build command/output, simulator OS/device, source video names, actual attempt states, selected overlays, any failure reasons, and the physical-device exclusion. Add screenshots under `docs/validation/screenshots/automatic-swing-coach/`; leave screenshots untracked until the user has reviewed them.

- [ ] **Step 6: Commit validation text only after review**

After the user approves the visible simulator behavior, stage only source changes and the validation Markdown (not generated screenshots unless explicitly requested):

```bash
git add Tests/ProjectPersistenceSmoke.swift docs/validation/automatic-swing-coach-simulator.md
git commit -m "test: verify automatic swing coach simulator flow"
```

Expected: clean source worktree except deliberately retained, untracked screenshots and any pre-existing user documents.

## Spec coverage self-review

| Spec requirement | Implementing task |
| --- | --- |
| Import and automatic capture analyze without a start button | Task 2 |
| Continuous video becomes independently analyzed swings | Task 2 |
| Stable primary golfer and P1–P8 evidence before judgment | Task 1, Task 2 |
| DTL/正面 body metrics, guarded plane/release | Task 3 |
| Coach-labelled/versioned standards and no global self-learning | Task 3 |
| Multi-metric video-first replay overlays | Task 4 |
| One truthful spoken cue and Drill per practice shot | Task 5 |
| Local persistence, simulator-only validation, truthful failures | Task 6 |

Placeholder scan: no deferred implementation markers are used. All source types, tests, commands, persistence migrations, and UI interaction rules required by later tasks are named above. `AnalysisFailureRecord` is deliberately a Codable record rather than direct persistence of the non-Codable legacy enum.

Type consistency review: `SwingAttemptCoordinator` owns `[SwingAttemptAnalysis]`; `VideoPlaybackManager.attemptAnalyses` publishes the same type; each completed `PersistedAttemptOutput` owns `[MetricResult]`; UI selection refers only to `FeedbackConfiguration.selectedMetrics`; `SpeechCoachPolicy` consumes `MetricResult`, never an overlay view.

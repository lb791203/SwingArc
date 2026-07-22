# Visual Swing Trigger and Manual Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace microphone impact triggering with live person-pose swing detection, add immediate manual recording with a 15-second safety cap, persist and validate every captured clip, and make 239.9/240 FPS clips analyzable.

**Architecture:** A low-rate Vision sampler consumes frames from the existing capture session and feeds a pure `LiveSwingTriggerDetector`; `CameraStateModel` continues one source recording and trims it from visual boundaries. Automatic and manual paths both hand temporary media to an async `CapturedVideoStore` before opening the analysis workspace. The offline analyzer keeps strict source-frame identity but requests each high-speed frame with a half-frame decode tolerance.

**Tech Stack:** Swift 5, SwiftUI, AVFoundation, Vision, Combine, standalone Swift smoke tests, Xcode-beta, `xcodebuild`, `devicectl`.

## Global Constraints

- Automatic practice must not create or consume microphone samples and must never fall back to sound triggering.
- Live Vision sampling is capped at 12 FPS while source recording prefers 240 FPS and may degrade to 120 or 60 FPS only when the device requires it.
- A person must be stable for 0.5 seconds; swing onset requires 3 consecutive samples; minimum swing duration is 0.7 seconds; maximum is 5.0 seconds; finish settling is 0.35 seconds; cooldown is 0.75 seconds.
- Automatic clips retain 1.0 second before visual onset and 0.8 seconds after visual finish.
- Manual recording starts immediately, stops on the second tap, and automatically stops at 15 seconds.
- Temporary URLs never enter the workspace; persistence validates nonzero file size, finite positive duration, and at least one readable video track before an atomic final move.
- High-speed extraction allows a half-frame decode search but still requires the actual timestamp to map to the uniquely requested source frame.
- Existing dirty-worktree changes belong to the user. Stage only exact new implementation hunks and never commit unrelated pre-existing changes.
- The buildable iOS project is `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj`; source remains `/Users/liangbo/Documents/SwingArc/SwingArc`.

---

## Planned File Structure

- Create `SwingArc/Models/LiveSwingCaptureModels.swift`: trigger samples, states, boundaries, quality, and configuration.
- Create `SwingArc/Services/LiveSwingTriggerDetector.swift`: pure visual trigger state machine.
- Create `SwingArc/Services/LivePoseSampler.swift`: Vision body-pose extraction and body-normalized motion features.
- Create `SwingArc/Services/CapturedVideoStore.swift`: async persistent copy, AVAsset validation, and atomic finalization.
- Create `SwingArc/Models/FrameExtractionTolerancePolicy.swift`: pure half-frame tolerance policy.
- Modify `SwingArc/Views/CameraView.swift`: visual frame output, automatic visual capture, immediate 15-second manual capture.
- Modify `SwingArc/Models/PracticeModels.swift`: truthful visual session states, events, home action, and presentation copy.
- Modify `SwingArc/Services/PracticeSessionEngine.swift`: visual status callbacks and typed recorded clips.
- Modify `SwingArc/Views/PracticeSessionView.swift`: visual status display and shared persistent handoff.
- Modify `SwingArc/Views/PracticeHomeView.swift`: manual recording card and callback.
- Modify `SwingArc/Views/ContentView.swift`: manual full-screen route and unified capture persistence.
- Modify `SwingArc/Services/VisionPoseDetector.swift`: high-speed generator tolerances.
- Modify `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj`: add all new production files.
- Create `Tests/LiveSwingTriggerDetectorSmoke.swift`, `Tests/CapturedVideoStoreSmoke.swift`, `Tests/FrameExtractionTolerancePolicySmoke.swift`, and `Tests/VisualCapturePresentationSmoke.swift`.
- Modify `Tests/PracticeSessionEngineSmoke.swift`, `Tests/ProTourPresentationSmoke.swift`, `Tests/CameraRecordingSerializationSmoke.swift`.

---

### Task 1: High-Speed Frame Extraction Contract

**Files:**
- Create: `SwingArc/Models/FrameExtractionTolerancePolicy.swift`
- Create: `Tests/FrameExtractionTolerancePolicySmoke.swift`
- Modify: `SwingArc/Services/VisionPoseDetector.swift:845-865`
- Modify: `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: finite positive `sourceFrameRate: Double`.
- Produces: `FrameExtractionTolerancePolicy.halfFrameSeconds(sourceFrameRate:) -> Double?` and `FrameExtractionTolerancePolicy.halfFrameTime(sourceFrameRate:) -> CMTime?`.

- [ ] **Step 1: Write the failing tolerance test**

```swift
import Foundation

@main
struct FrameExtractionTolerancePolicySmoke {
    static func main() {
        precondition(FrameExtractionTolerancePolicy.halfFrameSeconds(sourceFrameRate: 240) == 1.0 / 480.0)
        precondition(abs(FrameExtractionTolerancePolicy.halfFrameSeconds(sourceFrameRate: 239.9)! - 1.0 / 479.8) < 1e-12)
        precondition(FrameExtractionTolerancePolicy.halfFrameSeconds(sourceFrameRate: 0) == nil)
        precondition(FrameExtractionTolerancePolicy.halfFrameSeconds(sourceFrameRate: .nan) == nil)
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
swiftc Tests/FrameExtractionTolerancePolicySmoke.swift -o /tmp/frame-tolerance-smoke
```

Expected: compilation fails because `FrameExtractionTolerancePolicy` does not exist.

- [ ] **Step 3: Implement the pure policy**

```swift
import Foundation
import CoreMedia

enum FrameExtractionTolerancePolicy {
    static func halfFrameSeconds(sourceFrameRate: Double) -> Double? {
        guard sourceFrameRate.isFinite, sourceFrameRate > 0 else { return nil }
        return 0.5 / sourceFrameRate
    }

    static func halfFrameTime(sourceFrameRate: Double) -> CMTime? {
        guard let seconds = halfFrameSeconds(sourceFrameRate: sourceFrameRate) else { return nil }
        return CMTime(seconds: seconds, preferredTimescale: 60_000)
    }
}
```

- [ ] **Step 4: Apply the tolerance in the offline analyzer**

Immediately after loading `nominalFrameRate`, require a tolerance and configure the generator:

```swift
guard let decodeTolerance = FrameExtractionTolerancePolicy.halfFrameTime(
    sourceFrameRate: nominalFrameRate
) else {
    return activeFailure(.frameExtractionFailed, runID: runID, gate: gate)
}

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = decodeTolerance
generator.requestedTimeToleranceAfter = decodeTolerance
```

Keep `SourceFrameMatchPolicy.validate` unchanged so decoded frames still match the requested index.

- [ ] **Step 5: Run GREEN tests and a simulator reproduction**

Run:

```bash
swiftc SwingArc/Models/FrameExtractionTolerancePolicy.swift Tests/FrameExtractionTolerancePolicySmoke.swift -o /tmp/frame-tolerance-smoke
/tmp/frame-tolerance-smoke
```

Expected: exit 0.

Then launch the recovered 239.9 FPS device clip through `-swingarc-preview-import` and verify the failure is no longer `frameExtractionFailed`; a content-analysis failure such as no golfer is acceptable for a clip without a visible golfer.

- [ ] **Step 6: Stage only this task and commit**

```bash
git add SwingArc/Models/FrameExtractionTolerancePolicy.swift Tests/FrameExtractionTolerancePolicySmoke.swift
git add -p SwingArc/Services/VisionPoseDetector.swift
git commit -m "fix: decode high-speed source frames with bounded tolerance"
```

Update the external PBX file but do not include it in the repository commit.

---

### Task 2: Pure Visual Swing State Machine

**Files:**
- Create: `SwingArc/Models/LiveSwingCaptureModels.swift`
- Create: `SwingArc/Services/LiveSwingTriggerDetector.swift`
- Create: `Tests/LiveSwingTriggerDetectorSmoke.swift`
- Modify: `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `LivePoseMotionSample(time:personVisible:normalizedWristSpeed:normalizedTorsoSpeed:backswingDirectionScore:followThroughScore:)`.
- Produces: `LiveSwingTriggerUpdate(state:boundary:)`, where `boundary` is emitted exactly once per swing.

- [ ] **Step 1: Write the failing state-machine test**

The test must build fixed sample sequences for: no person, stable person, walking without wrist/torso coordination, a completed swing, a 5-second incomplete swing, and cooldown. The completed sequence must assert exactly one boundary with `.complete`; the timeout sequence must assert `.possibleIncomplete`.

```swift
let configuration = LiveSwingTriggerConfiguration.standard
var detector = LiveSwingTriggerDetector(configuration: configuration)
precondition(detector.ingest(.missing(at: 0)).state == .searchingForPerson)
for index in 0...6 {
    _ = detector.ingest(.still(at: Double(index) / 12.0))
}
precondition(detector.state == .ready)

for index in 7...9 {
    _ = detector.ingest(.backswing(at: Double(index) / 12.0))
}
precondition(detector.state == .swingInProgress)

var completion: PracticeCaptureBoundary?
for index in 10...24 {
    let update = detector.ingest(.followThrough(at: Double(index) / 12.0))
    completion = completion ?? update.boundary
}
precondition(completion?.quality == .complete)
precondition(detector.emittedBoundaryCount == 1)
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
swiftc SwingArc/Models/LiveSwingCaptureModels.swift SwingArc/Services/LiveSwingTriggerDetector.swift Tests/LiveSwingTriggerDetectorSmoke.swift -o /tmp/live-trigger-smoke
```

Expected: missing-file or missing-type failure.

- [ ] **Step 3: Implement models and named configuration**

Define these exact public-to-module types:

```swift
enum PracticeCaptureQuality: Equatable { case complete, possibleIncomplete }
enum LiveSwingTriggerState: Equatable { case searchingForPerson, ready, swingInProgress, finishing, cooldown }

struct PracticeCaptureBoundary: Equatable {
    let swingStartTime: TimeInterval
    let swingEndTime: TimeInterval
    let quality: PracticeCaptureQuality
}

struct RecordedPracticeClip: Equatable {
    let url: URL
    let quality: PracticeCaptureQuality
}

struct LiveSwingTriggerConfiguration: Equatable {
    let sampleRate: Double
    let personStableDuration: TimeInterval
    let onsetConfirmationSamples: Int
    let minimumSwingDuration: TimeInterval
    let maximumSwingDuration: TimeInterval
    let finishSettledDuration: TimeInterval
    let cooldownDuration: TimeInterval
    let wristOnsetSpeed: Double
    let torsoCoordinationSpeed: Double
    let settledSpeed: Double

    static let standard = LiveSwingTriggerConfiguration(
        sampleRate: 12,
        personStableDuration: 0.5,
        onsetConfirmationSamples: 3,
        minimumSwingDuration: 0.7,
        maximumSwingDuration: 5.0,
        finishSettledDuration: 0.35,
        cooldownDuration: 0.75,
        wristOnsetSpeed: 0.8,
        torsoCoordinationSpeed: 0.15,
        settledSpeed: 0.25
    )
}
```

- [ ] **Step 4: Implement the deterministic detector**

The detector must keep stable-person start, consecutive onset count, swing start, finish-settled start, cooldown start, and a boundary-emitted flag. Missing person before onset resets to search; missing person after onset can only end through the 5-second incomplete timeout. Complete only after minimum duration, positive follow-through evidence, and 0.35 seconds settled motion.

- [ ] **Step 5: Run GREEN test**

Run the compile command from Step 2, then `/tmp/live-trigger-smoke`.

Expected: exit 0 with one complete and one incomplete boundary across their isolated detector instances.

- [ ] **Step 6: Commit new pure components**

```bash
git add SwingArc/Models/LiveSwingCaptureModels.swift SwingArc/Services/LiveSwingTriggerDetector.swift Tests/LiveSwingTriggerDetectorSmoke.swift
git commit -m "feat: add visual swing trigger state machine"
```

---

### Task 3: Live Vision Sampling and Camera Capture

**Files:**
- Create: `SwingArc/Services/LivePoseSampler.swift`
- Modify: `SwingArc/Views/CameraView.swift:240-640`
- Modify: `SwingArc/Services/PracticeSessionEngine.swift`
- Modify: `SwingArc/Models/PracticeModels.swift:114-235`
- Modify: `Tests/PracticeSessionEngineSmoke.swift`
- Modify: `Tests/CameraRecordingSerializationSmoke.swift`
- Create: `Tests/VisualCapturePresentationSmoke.swift`
- Modify: `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CMSampleBuffer`, `PracticeCameraView`, and `LiveSwingTriggerDetector`.
- Produces: `PracticeCaptureStatus` callbacks and `Result<RecordedPracticeClip, PracticeSessionError>`.

- [ ] **Step 1: Update tests to require visual vocabulary and typed clips**

Replace `waitingForImpact`/`impactDetected` assertions with:

```swift
case searchingForPerson(view: PracticeCameraView, swingCount: Int)
case readyForSwing(view: PracticeCameraView, swingCount: Int)
case capturingSwing(view: PracticeCameraView, swingCount: Int)
```

Require presentation copy `正在寻找人物`, `人物已入镜，请准备`, and `检测挥杆中`. The recorder fake must publish statuses and complete with:

```swift
RecordedPracticeClip(url: clipURL, quality: .complete)
```

Add a source smoke assertion that `CameraStateModel` owns `AVCaptureVideoDataOutput`, uses a `visionQueue`, and does not contain `AVCaptureAudioDataOutput` or `startImpactMonitoring`.

- [ ] **Step 2: Run updated tests and verify RED**

Compile the same source sets used by `PracticeSessionEngineSmoke`, `ProTourPresentationSmoke`, and `CameraRecordingSerializationSmoke`.

Expected: failures for missing visual states, typed completion, and video output.

- [ ] **Step 3: Implement `LivePoseSampler`**

Use one `VNDetectHumanBodyPoseRequest`. Require shoulders, hips, and at least one wrist above confidence 0.35. Compute torso length from shoulder midpoint to hip midpoint, reject torso length below 0.05 normalized units, and emit wrist/torso speeds in torso-lengths per second. Reset velocity history when timestamps regress or the person is missing. Emit at most one sample every `1 / 12` seconds.

- [ ] **Step 4: Replace audio output with visual output in `CameraStateModel`**

Add:

```swift
private let videoDataOutput = AVCaptureVideoDataOutput()
private let visionQueue = DispatchQueue(label: "com.liangbo.swingarc.live-vision", qos: .userInitiated)
private var livePoseSampler = LivePoseSampler()
private var liveSwingDetector = LiveSwingTriggerDetector(configuration: .standard)
private var practiceRecordingTimeOrigin: CMTime?
private var pendingBoundary: PracticeCaptureBoundary?
```

Configure BGRA video frames, `alwaysDiscardsLateVideoFrames = true`, and the sample-buffer delegate on `visionQueue`. Remove the audio device input, `AVCaptureAudioDataOutput`, RMS computation, and `ImpactTriggerPolicy` from the automatic path.

- [ ] **Step 5: Convert detector updates into recording boundaries**

On `didStartRecording`, reset the sampler/detector and enable visual monitoring. The first accepted video buffer establishes `practiceRecordingTimeOrigin`. Each later sample is converted to source-relative seconds before detector ingestion. Publish status changes on main. When a complete or incomplete boundary arrives, wait until `swingEnd + 0.8`, stop the movie output, and export from `max(0, swingStart - 1.0)` through `min(sourceDuration, swingEnd + 0.8)`.

- [ ] **Step 6: Update recorder and engine interfaces**

Use:

```swift
enum PracticeCaptureStatus: Equatable {
    case searchingForPerson
    case readyForSwing
    case capturingSwing
    case finalizing
    case captureFrameRateChanged(Double)
    case visualUnavailable(message: String)
}

protocol PracticeClipRecording: AnyObject {
    func requestClip(
        status: @escaping (PracticeCaptureStatus) -> Void,
        completion: @escaping (Result<RecordedPracticeClip, PracticeSessionError>) -> Void
    )
    func cancelPendingClip()
}
```

Add `@Published private(set) var lastClip: RecordedPracticeClip?` to the engine. It maps status callbacks to the truthful visual session states and transitions to processing only after a typed clip arrives. Remove `lastClipURL`, `ingestImpact`, and all sound-listening copy.

Add two failure statuses: `.visualUnavailable(message: String)` when `AVCaptureVideoDataOutput` cannot be added, and `.captureFrameRateChanged(Double)` when the session must degrade from 240 to 120 or 60 FPS. The session view displays the selected frame rate and, for visual unavailability, the exact message `此设备无法启动视觉检测，请返回选择手动录像。`; it must not start an audio fallback.

- [ ] **Step 7: Run GREEN smoke tests and build**

Expected: all targeted smoke binaries exit 0; simulator and unsigned device builds succeed. Confirm the built binary contains `VNDetectHumanBodyPoseRequest` and no automatic `AVCaptureAudioDataOutput` path.

- [ ] **Step 8: Stage exact hunks and commit**

```bash
git add SwingArc/Services/LivePoseSampler.swift Tests/VisualCapturePresentationSmoke.swift
git add -p SwingArc/Views/CameraView.swift SwingArc/Services/PracticeSessionEngine.swift SwingArc/Models/PracticeModels.swift Tests/PracticeSessionEngineSmoke.swift Tests/CameraRecordingSerializationSmoke.swift
git commit -m "feat: trigger automatic capture from live pose motion"
```

---

### Task 4: Shared Persistent Capture Store

**Files:**
- Create: `SwingArc/Services/CapturedVideoStore.swift`
- Create: `Tests/CapturedVideoStoreSmoke.swift`
- Modify: `SwingArc/Views/PracticeSessionView.swift:1-130,400-420`
- Modify: `SwingArc/Views/ContentView.swift:1-280`
- Modify: `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: temporary URL, filename prefix, capture quality.
- Produces: `CapturedVideoStore.persist(sourceURL:prefix:quality:) async throws -> RecordedPracticeClip`.

- [ ] **Step 1: Write failing policy/store tests**

Test a missing file, zero-byte file, and a copied valid local video. Require missing/empty media to throw `CapturedVideoStoreError.missingSource` or `.emptyFile`, and require successful output to live inside the injected destination directory with the requested prefix.

- [ ] **Step 2: Run test and verify RED**

Compile with AVFoundation:

```bash
swiftc -framework AVFoundation SwingArc/Models/LiveSwingCaptureModels.swift Tests/CapturedVideoStoreSmoke.swift -o /tmp/captured-store-smoke
```

Expected: `CapturedVideoStore` missing.

- [ ] **Step 3: Implement async validation and atomic finalization**

Define errors `missingSource`, `emptyFile`, `invalidDuration`, `missingVideoTrack`, `copyFailed`, and `finalizeFailed`. Copy to `<uuid>.partial`, check file size, then await `asset.load(.duration)` and `asset.loadTracks(withMediaType: .video)`. Move the validated partial file to `<prefix>-<uuid>.mp4`. Leave the original source untouched on failure and remove only the store-owned partial file.

- [ ] **Step 4: Replace `PracticeSessionView.persistPracticeClip`**

When `sessionEngine.lastClip` changes, run one `Task`, persist via `CapturedVideoStore`, then call `onOpenLastClip` with the stable URL on main. On failure, call `reportClipPersistenceFailure()` and retain the current retry alert.

- [ ] **Step 5: Route all captured URLs through the same store**

Add a `ContentView` helper that persists manual temporary media before `loadVideoFromURL(..., origin: .capturedClipSaved)`. Never pass `CameraStateModel.recordedVideoURL` directly to the workspace.

- [ ] **Step 6: Run GREEN tests and persistence regression tests**

Expected: missing and empty fixtures throw the exact errors; valid video produces a stable file; `LocalProjectStore.projects()` resolves the persisted filename after app relaunch.

- [ ] **Step 7: Commit isolated store work**

```bash
git add SwingArc/Services/CapturedVideoStore.swift Tests/CapturedVideoStoreSmoke.swift
git add -p SwingArc/Views/PracticeSessionView.swift SwingArc/Views/ContentView.swift
git commit -m "feat: validate and persist captured clips before analysis"
```

---

### Task 5: Immediate Manual Recording Entry

**Files:**
- Modify: `SwingArc/Models/PracticeModels.swift:1-15`
- Modify: `SwingArc/Views/PracticeHomeView.swift:1-125`
- Modify: `SwingArc/Views/ContentView.swift:10-160`
- Modify: `SwingArc/Views/CameraView.swift:1-240`
- Modify: `Tests/ProTourPresentationSmoke.swift`
- Create: `Tests/ManualCaptureTimingSmoke.swift`

**Interfaces:**
- Consumes: home `onManualCapture` callback and `CameraView.onRecordCompleted`.
- Produces: `.manualCapture` home action and `ManualCaptureTiming.maximumDuration == 15`.

- [ ] **Step 1: Write failing home/timing tests**

Require:

```swift
precondition(PracticeHomePresentation.modeOrder == [.downTheLine, .faceOn, .manualCapture, .importVideo])
precondition(ManualCaptureTiming.maximumDuration == 15)
```

Source smoke assertions must reject `startCountdown`, `isCountingDown`, `countdownValue`, and the text `3 秒后自动录制`.

- [ ] **Step 2: Run tests and verify RED**

Expected: missing `.manualCapture`, timing type, and immediate-start behavior.

- [ ] **Step 3: Add the home card and route**

Add `onManualCapture: () -> Void` to `PracticeHomeView`; render index `03`, eyebrow `MANUAL CAPTURE`, title `手动录像`, detail `点击即录 · 最长 15 秒`; move import to index `04`. `ContentView` presents `CameraView` in a full-screen cover and sends its temporary completion through `CapturedVideoStore`.

- [ ] **Step 4: Remove countdown and implement 15-second cap**

The idle button calls `startRecording()` directly. `startRecording` schedules one main-queue deadline using `ManualCaptureTiming.maximumDuration`; `stopRecording` cancels the pending work item, is idempotent, and stops only when recording. Update copy to `点击立即录制` and `最长 15 秒，可随时停止`.

- [ ] **Step 5: Run GREEN tests and simulator UI verification**

Expected: home order is correct, manual capture opens, first tap starts recording immediately, second tap stops, and the 15-second cap stops an unattended capture.

- [ ] **Step 6: Commit exact manual-capture hunks**

```bash
git add Tests/ManualCaptureTimingSmoke.swift
git add -p SwingArc/Models/PracticeModels.swift SwingArc/Views/PracticeHomeView.swift SwingArc/Views/ContentView.swift SwingArc/Views/CameraView.swift Tests/ProTourPresentationSmoke.swift
git commit -m "feat: add immediate manual recording mode"
```

---

### Task 6: Complete Regression and Real-Device Verification

**Files:**
- Modify only if verification exposes an implementation defect in Tasks 1-5.

**Interfaces:**
- Consumes: the complete visual/manual capture implementation.
- Produces: signed app installed on device `00008140-001C20102493C01C` and evidence for every acceptance path.

- [ ] **Step 1: Run all focused smoke tests**

Run the new four tests plus `PracticeSessionEngineSmoke`, `ProTourPresentationSmoke`, `CameraRecordingReadinessSmoke`, `CameraRecordingSerializationSmoke`, `AutomaticAnalysisLaunchSmoke`, and relevant P1–P8 extraction tests.

Expected: every binary exits 0.

- [ ] **Step 2: Build simulator and signed device app**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject -configuration Debug \
  -destination 'platform=iOS,id=00008140-001C20102493C01C' \
  -derivedDataPath /tmp/SwingArcVisualCapture \
  -allowProvisioningUpdates build
```

Expected: `** BUILD SUCCEEDED **` and a signed `Debug-iphoneos/SwingArcProject.app`.

- [ ] **Step 3: Install and launch with live console**

```bash
xcrun devicectl device install app --device 00008140-001C20102493C01C /tmp/SwingArcVisualCapture/Build/Products/Debug-iphoneos/SwingArcProject.app
xcrun devicectl device process launch --device 00008140-001C20102493C01C --terminate-existing --console com.liangbo.swingarc
```

Expected: launch succeeds while unlocked and process remains alive.

- [ ] **Step 4: Verify automatic visual capture**

For both DTL and FACE-ON: walk in, stand still, walk/adjust the ball without swinging, make a normal swing, make an air swing, and make a soft strike with ambient noise. Confirm only swing motion produces clips, no microphone permission is requested, saved files are readable, and automatic analysis starts.

- [ ] **Step 5: Verify manual capture**

Open the independent home card. Confirm the first tap starts immediately, second tap stops, a second run automatically stops at 15 seconds, both saved clips reopen after relaunch, and neither uses a temporary URL.

- [ ] **Step 6: Verify high-speed sample and crash regression**

Reopen the recovered 239.9 FPS clip and confirm it does not fail with `frameExtractionFailed`. Repeat the former crash path: open camera, start automatic practice, and keep it running past the prior `AVCaptureMovieFileOutput` and mirroring failures. Confirm the process remains alive.

- [ ] **Step 7: Final diff and repository safety check**

Run `git status --short`, `git diff --check`, and `git diff --cached --name-only`. Confirm no pre-existing user changes were accidentally staged or reverted. Report any external PBX modification separately because it is outside the source repository.

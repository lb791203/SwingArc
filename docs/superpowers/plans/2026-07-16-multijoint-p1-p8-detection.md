# Multi-Joint P1–P8 Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reliably locate P1–P8 from real Vision pose samples using multiple joints, ordered motion evidence, confidence states, and persistent manual locks.

**Architecture:** Convert every Vision result used during a scan into a timestamped multi-joint `SwingPoseSample`. A state-machine detector advances P1 through P8 only when that stage’s multi-joint evidence and chronological constraints hold, returning a detection status and confidence for every stage. The workspace preserves manually locked markers when automatic analysis is rerun.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Apple Vision `VNDetectHumanBodyPoseRequest`, existing standalone Swift smoke tests.

## Global Constraints

- All automatic stages must reference a real sampled video frame; never invent a time from a fixed video percentage.
- Processing remains local on-device and uses the existing Apple Vision pose request.
- Stage time must be strictly increasing from P1 to P8.
- Missing one joint lowers confidence; it must not discard all otherwise usable pose evidence.
- `confirmed`, `lowConfidence`, and `unresolved` must remain distinguishable in the model and UI.
- A manually set marker is locked and must survive reanalysis, project save, and project restore.

---

### Task 1: Define pose evidence and stage-result contracts

**Files:**
- Modify: `SwingArc/Services/SwingStageDetector.swift:3-48`
- Modify: `SwingArc/Models/DrawingModels.swift:68-79`
- Create: `Tests/MultiJointStageModelSmoke.swift`

**Consumes:** Existing `PoseEstimationResult.point(for:)`, `KeyframeMarker`, and `SwingStage`.

**Produces:** `SwingPoseSample`, `SwingStageDetectionStatus`, `SwingStageDetection`, `KeyframeSource`, and an expanded `SwingAnalysisResult` used by scan, UI, and persistence.

- [ ] **Step 1: Write the failing model-contract test**

```swift
let detection = SwingStageDetection(
    stage: .impact, time: 0.72, confidence: 0.88, status: .confirmed
)
precondition(detection.marker?.stage == SwingStage.impact.rawValue)
precondition(SwingStageDetection(stage: .top, time: nil, confidence: 0, status: .unresolved).marker == nil)

let manual = KeyframeMarker(time: 0.72, stage: .impact, source: .manual)
precondition(manual.isLocked)
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/MultiJointStageModelSmoke.swift -o /tmp/multijoint-model && /tmp/multijoint-model
```

Expected: compilation failure because the multi-joint result contracts do not yet exist.

- [ ] **Step 3: Implement the minimum contracts**

```swift
enum SwingStageDetectionStatus: String, Codable, Equatable { case confirmed, lowConfidence, unresolved }

struct SwingStageDetection: Equatable {
    let stage: SwingStage
    let time: Double?
    let confidence: Double
    let status: SwingStageDetectionStatus
    var marker: KeyframeMarker? {
        guard let time, status != .unresolved else { return nil }
        return KeyframeMarker(time: time, stage: stage, source: .automatic)
    }
}

enum KeyframeSource: String, Codable { case automatic, manual }
```

Extend `SwingPoseSample` with optional points for both wrists, elbows, shoulders, hips, head, its spine angle, and the aggregate Vision confidence. Decode an absent `KeyframeMarker.source` as `.automatic` to preserve existing project files.

- [ ] **Step 4: Run the model test and existing detector test**

Run the Step 2 command and:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/SwingStageDetectorSmoke.swift -o /tmp/stages && /tmp/stages
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit the contract change**

```bash
git add SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/MultiJointStageModelSmoke.swift
git commit -m "feat: add multi-joint stage evidence models"
```

### Task 2: Convert Vision results into full scan samples

**Files:**
- Modify: `SwingArc/Services/VisionPoseDetector.swift:10-31`
- Modify: `SwingArc/Views/CustomVideoPlayer.swift:307-322`
- Create: `Tests/PoseSampleFactorySmoke.swift`

**Consumes:** Task 1 `SwingPoseSample` and current `PoseEstimationResult` keypoints.

**Produces:** `SwingPoseSample.init(time:pose:)` that retains all available landmark evidence and a scan loop that appends it whenever a pose is present.

- [ ] **Step 1: Write the failing sample conversion test**

```swift
var pose = PoseEstimationResult()
pose.keypoints["leftWrist"] = JointKeypoint(name: "leftWrist", position: CGPoint(x: 0.2, y: 0.7), confidence: 0.9)
pose.keypoints["rightShoulder"] = JointKeypoint(name: "rightShoulder", position: CGPoint(x: 0.7, y: 0.3), confidence: 0.8)
let sample = SwingPoseSample(time: 0.5, pose: pose)
precondition(sample.leftWrist?.x == 0.2)
precondition(sample.rightShoulder?.y == 0.3)
precondition(sample.aggregateConfidence > 0.8)
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift SwingArc/Services/VisionPoseDetector.swift Tests/PoseSampleFactorySmoke.swift -o /tmp/pose-sample && /tmp/pose-sample
```

Expected: compilation failure because `SwingPoseSample(time:pose:)` does not yet exist.

- [ ] **Step 3: Implement sample conversion and scan use**

```swift
extension SwingPoseSample {
    init(time: Double, pose: PoseEstimationResult) {
        self.init(time: time, leftWrist: pose.point(for: "leftWrist"), rightWrist: pose.point(for: "rightWrist"),
                  leftElbow: pose.point(for: "leftElbow"), rightElbow: pose.point(for: "rightElbow"),
                  leftShoulder: pose.point(for: "leftShoulder"), rightShoulder: pose.point(for: "rightShoulder"),
                  leftHip: pose.point(for: "leftHip"), rightHip: pose.point(for: "rightHip"),
                  head: pose.headCenter, spineAngle: pose.spineAngle, aggregateConfidence: pose.aggregateConfidence)
    }
}
```

Add `PoseEstimationResult.aggregateConfidence` as the mean of available joint confidences. In `analyzeSwing`, replace the wrist-only append with `if let pose { poseSamples.append(SwingPoseSample(time: time.seconds, pose: pose)) }`.

- [ ] **Step 4: Run the sample and stage tests**

Run the Step 2 command and the Task 1 stage command. Expected: both exit 0.

- [ ] **Step 5: Commit the scan conversion**

```bash
git add SwingArc/Services/VisionPoseDetector.swift SwingArc/Views/CustomVideoPlayer.swift Tests/PoseSampleFactorySmoke.swift
git commit -m "feat: retain multi-joint evidence during swing scans"
```

### Task 3: Implement ordered P1–P8 multi-joint state detection

**Files:**
- Modify: `SwingArc/Services/SwingStageDetector.swift:49-145`
- Modify: `Tests/SwingStageDetectorSmoke.swift:4-70`
- Create: `Tests/MultiJointStageDetectorSmoke.swift`

**Consumes:** Task 1 result contracts and Task 2 pose samples.

**Produces:** `SwingStageDetector.detect(samples:) -> SwingAnalysisResult` with one status and confidence for every `SwingStage`.

- [ ] **Step 1: Write the failing state-machine test**

```swift
let result = SwingStageDetector.detect(samples: multiJointSwingSamples)
precondition(result.detections.map(\.stage) == SwingStage.allCases)
precondition(result.detections.allSatisfy { $0.status == .confirmed })
let times = result.detections.compactMap(\.time)
precondition(zip(times, times.dropFirst()).allSatisfy(<))
```

Use fifteen fixture samples containing: stable P1 head/spine, increasing hand height and shoulder rotation to P4, a down-swing reversal to P6, post-impact rise, and stable P8. Add a second fixture with a missing wrist that verifies the result becomes `.lowConfidence` or `.unresolved`, never falsely `.confirmed`.

- [ ] **Step 2: Run the failing detector test**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/MultiJointStageDetectorSmoke.swift -o /tmp/multijoint-detector && /tmp/multijoint-detector
```

Expected: failure because the current wrist-height-only detector cannot classify the fixture’s multi-joint evidence.

- [ ] **Step 3: Implement state transitions and confidence scoring**

Use a private `StageEvidence` scorer. Each transition only examines samples after the last accepted time:

```swift
private static func detection(_ stage: SwingStage, at sample: SwingPoseSample?, score: Double) -> SwingStageDetection {
    let status: SwingStageDetectionStatus = score >= 0.75 ? .confirmed : (score >= 0.45 ? .lowConfidence : .unresolved)
    return SwingStageDetection(stage: stage, time: status == .unresolved ? nil : sample?.time, confidence: score, status: status)
}
```

Require P1 stability from head/spine variance plus low hand height; P2/P3 from sustained hand-rise and shoulder rotation; P4 from a hand-height extremum followed by a reversal; P5 from the down-swing reversal; P6 from a hand-near-hip candidate plus maximal hand speed and hip/shoulder rotation; P7 from post-impact hand-rise; P8 from stable hand, head, and spine windows. Build `unresolvedStages` only from `.unresolved` detections and keep `detectedMarkers` as confirmed or low-confidence real-frame markers.

- [ ] **Step 4: Run all detector regression tests**

Run the Task 3 command, then:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/SwingStageDetectorSmoke.swift -o /tmp/stages && /tmp/stages
```

Expected: both exit 0; the wrist-only legacy fixtures must retain their documented degraded status rather than claim confirmation without multi-joint support.

- [ ] **Step 5: Commit the detector**

```bash
git add SwingArc/Services/SwingStageDetector.swift Tests/SwingStageDetectorSmoke.swift Tests/MultiJointStageDetectorSmoke.swift
git commit -m "feat: detect P1-P8 with multi-joint evidence"
```

### Task 4: Preserve manual stage locks and show confidence in the workspace

**Files:**
- Modify: `SwingArc/Views/ContentView.swift:676-731,945-970,1034-1072`
- Modify: `SwingArc/Services/LocalProjectStore.swift:1-70`
- Modify: `Tests/ProjectPersistenceSmoke.swift:4-35`
- Create: `Tests/ManualStageLockSmoke.swift`

**Consumes:** Task 1 `KeyframeSource` and Task 3 `SwingStageDetection`.

**Produces:** Manual markers that remain locked through reanalysis and persistence; stage chips and report text that distinguish confirmed, low-confidence, and unresolved results.

- [ ] **Step 1: Write the failing manual-lock test**

```swift
let manual = KeyframeMarker(time: 0.42, stage: .top, source: .manual)
let automatic = KeyframeMarker(time: 0.55, stage: .top, source: .automatic)
let merged = StageMarkerMerger.merge(existing: [manual], automatic: [automatic])
precondition(merged == [manual])
```

Extend `ProjectPersistenceSmoke` to encode/decode a `.manual` marker and assert its source remains `.manual`.

- [ ] **Step 2: Run the failing lock test**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/LocalProjectStore.swift Tests/ManualStageLockSmoke.swift -o /tmp/manual-lock && /tmp/manual-lock
```

Expected: compilation failure because `StageMarkerMerger` is not implemented.

- [ ] **Step 3: Implement merge, persistence, and presentation**

```swift
enum StageMarkerMerger {
    static func merge(existing: [KeyframeMarker], automatic: [KeyframeMarker]) -> [KeyframeMarker] {
        let lockedStages = Set(existing.filter(\.isLocked).map(\.stage))
        return (existing.filter(\.isLocked) + automatic.filter { !lockedStages.contains($0.stage) })
            .sorted { $0.time < $1.time }
    }
}
```

Set `saveKeyframe(stage:)` to `.manual`; use the merger in `runAISwingAnalysis`. Show a checkmark only for confirmed markers, an orange warning for low-confidence candidates, and `未确定` for unresolved stages. Keep the existing project codec backward-compatible by defaulting missing sources to `.automatic`.

- [ ] **Step 4: Run lock, persistence, and workspace tests**

Run the Step 2 command, then:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/LocalProjectStore.swift Tests/ProjectPersistenceSmoke.swift -o /tmp/project && /tmp/project
```

Expected: both exit 0.

- [ ] **Step 5: Commit the workspace integration**

```bash
git add SwingArc/Views/ContentView.swift SwingArc/Services/LocalProjectStore.swift Tests/ProjectPersistenceSmoke.swift Tests/ManualStageLockSmoke.swift
git commit -m "feat: preserve manual P1-P8 stage locks"
```

### Task 5: Verify the iOS target and document real-device acceptance

**Files:**
- Modify: `README.md:1-100`
- Modify: `docs/superpowers/specs/2026-07-16-multijoint-p1-p8-detection-design.md:33-40`

**Consumes:** Tasks 1–4.

**Produces:** Reproducible static verification and a real-iPhone test protocol for annotated side-view swings.

- [ ] **Step 1: Add the acceptance checklist**

Add these exact manual cases to `README.md`: stable side-view swing, brief top-of-backswing pause, one-wrist occlusion, fast swing, slow swing, no-person video, and manual P4 correction followed by rerun/save/restore. For each valid case, record whether each P stage is confirmed, low-confidence, or unresolved and compare times with an annotated reference.

- [ ] **Step 2: Run full static typecheck**

Run:

```bash
SDK=$(DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun --sdk iphonesimulator --show-sdk-path)
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -target arm64-apple-ios27.0-simulator -sdk "$SDK" -typecheck SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift SwingArc/Services/VisionPoseDetector.swift SwingArc/Services/LocalProjectStore.swift SwingArc/Services/MediaExportService.swift SwingArc/Views/CustomVideoPlayer.swift SwingArc/Views/DrawingOverlay.swift SwingArc/Views/CameraView.swift SwingArc/Views/ShareSheet.swift SwingArc/Views/ContentView.swift SwingArc/Design/AnalysisTheme.swift SwingArc/SwingArcApp.swift
```

Expected: exit 0; pre-existing SDK deprecation warnings may remain, but no errors.

- [ ] **Step 3: Commit documentation and verification record**

```bash
git add README.md docs/superpowers/specs/2026-07-16-multijoint-p1-p8-detection-design.md
git commit -m "docs: add multi-joint P1-P8 acceptance protocol"
```

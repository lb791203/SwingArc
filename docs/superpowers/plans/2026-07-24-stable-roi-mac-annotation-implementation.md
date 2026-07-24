# SwingArc Stable ROI and Mac Annotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 Apple Vision 全片人体轨迹生成稳定 `512 × 512` ROI，并交付本地三栏 Mac 标注工具。

**Architecture:** Foundation/CoreGraphics 层提供可独立测试的 ROI 变换、人体轨迹与标帧队列；新 macOS target `SwingArcDataset` 负责视频导入、Vision 后台任务、三栏标注和原子保存。Mac UI 依赖计划 1 的数据合同，不直接操作训练脚本或 iPhone 项目状态。

**Tech Stack:** Swift 5、SwiftUI、AVFoundation、Vision、CoreGraphics、CryptoKit、macOS 14+、Xcode 27 beta、standalone Swift smoke tests、无网络上传。

## Global Constraints

- 在 `/Users/liangbo/Documents/SwingArc/.worktrees/precision-swing-analysis` 工作；不得 reset 或覆盖现有未提交更改。
- `SwingArcProject.xcodeproj/project.pbxproj` 已有未提交修改；添加 Mac target 时必须合并现状，不能重建工程文件。
- 原始视频保持外部引用；重新定位后必须复核媒体和时间线 SHA-256。
- ROI 输出固定为 `512 × 512`，人工真值仍保存于方向修正后的原片坐标。
- 原片 → ROI → 原片往返误差 ≤0.5 原片像素。
- Vision 缺失最多插值 150 毫秒；更长缺失或身份切换必须产生失败。
- 日常 training 使用 prediction-first 单人复核；held-out blind 模式隐藏预测。
- 所有生产行为修改遵循 RED → GREEN → REFACTOR。

---

### Task 1: Define invertible ROI geometry

**Files:**
- Create: `SwingArc/Models/StableSwingROIModels.swift`
- Create: `SwingArc/Services/StableSwingROIBuilder.swift`
- Create: `Tests/StableSwingROIGeometrySmoke.swift`

**Interfaces:**
- Consumes: `[GolfPoseTrackFrame]`, oriented frame width/height, target size
- Consumes: `GolfROIAffineTransform` from Plan 1
- Produces: `StableSwingROITrack`, `StableSwingROIFrame`
- Produces: `fullFramePointToROI(_:)`, `roiPointToFullFrame(_:)`
- Produces: `StableSwingROIError.poseGapTooLong`, `.identityUnstable`, `.coverageFailed`

- [ ] **Step 1: Write the failing round-trip and stability test**

Create a synthetic 60-frame track at 30 FPS with a golfer drifting 20 source pixels.
Require:

```swift
let track = try StableSwingROIBuilder.build(
    poseFrames: poseFrames,
    orientedFrameSize: .init(width: 1080, height: 1920),
    targetSize: 512
)
precondition(track.frames.count == 60)
for frame in track.frames {
    let source = NormalizedPoint(x: 0.42, y: 0.63)
    let roi = frame.transform.fullFramePointToROI(source)
    let restored = frame.transform.roiPointToFullFrame(roi)
    let sourcePixelError = hypot(
        (restored.x - source.x) * 1080,
        (restored.y - source.y) * 1920
    )
    precondition(sourcePixelError <= 0.5)
}
precondition(track.centerMovementP95InTargetPixels <= 12)
```

Add a 4-frame gap at 30 FPS and require interpolation. Add a 6-frame gap
(200 ms) and require `.poseGapTooLong`.

- [ ] **Step 2: Run RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/GolfPredictionRun.swift \
  SwingArc/Models/StableSwingROIModels.swift \
  SwingArc/Services/StableSwingROIBuilder.swift \
  Tests/StableSwingROIGeometrySmoke.swift \
  -o /tmp/stable-swing-roi-geometry-smoke
```

Expected: FAIL because the ROI model and builder are absent.

- [ ] **Step 3: Implement the deterministic clip anchor**

`GolfPoseTrackFrame` stores source frame/time, body center, body bounds,
hand center, and identity confidence. The builder must:

1. sort and de-duplicate by source frame;
2. interpolate gaps whose source-time duration is ≤0.150 seconds;
3. reject non-monotonic time and longer gaps;
4. compute the clip anchor from robust body-center/scale percentiles;
5. add the spec’s club/ball safety margin;
6. allow only bounded bidirectionally smoothed per-frame correction;
7. save forward and inverse affine coefficients.

Use one transform implementation:

```swift
func fullFramePointToROI(_ point: NormalizedPoint) -> NormalizedPoint {
    .init(
        x: a * point.x + c * point.y + tx,
        y: b * point.x + d * point.y + ty
    )
}

func roiPointToFullFrame(_ point: NormalizedPoint) -> NormalizedPoint {
    .init(
        x: inverseA * point.x + inverseC * point.y + inverseTX,
        y: inverseB * point.x + inverseD * point.y + inverseTY
    )
}
```

- [ ] **Step 4: Run GREEN and commit**

```bash
git add SwingArc/Models/StableSwingROIModels.swift \
  SwingArc/Services/StableSwingROIBuilder.swift \
  Tests/StableSwingROIGeometrySmoke.swift
git commit -m "feat: add stable swing ROI geometry"
```

---

### Task 2: Extract and lock the primary golfer track

**Files:**
- Create: `SwingArc/Services/VisionFullClipPoseExtractor.swift`
- Create: `SwingArc/Services/PrimaryGolferTrackResolver.swift`
- Create: `Tests/PrimaryGolferTrackResolverSmoke.swift`

**Interfaces:**
- Consumes: oriented `CGImage` source frames and source presentation times
- Produces: `[GolfPoseCandidateFrame]`
- Produces: `PrimaryGolferTrackResolver.resolve(candidates:manualAnchor:)`
- Produces: one `[GolfPoseTrackFrame]` or a typed identity failure

- [ ] **Step 1: Write the failing multi-person identity test**

Use two synthetic candidates per frame: golfer A moves through a swing while a
bystander remains near the edge. Anchor frame 0 to golfer A and assert all 60
resolved frames keep candidate A. Add a five-frame crossing where the bystander is
larger and assert geometry continuity still wins. Remove the anchor with equal
tracks and require `.manualAnchorRequired`.

- [ ] **Step 2: Run RED**

Compile `SwingObservationModels.swift`, the new resolver, and its test. Expected:
FAIL because `PrimaryGolferTrackResolver` is absent.

- [ ] **Step 3: Implement candidate extraction and identity continuity**

The extractor uses `VNDetectHumanBodyPoseRequest` per oriented frame and converts
Vision coordinates once into top-left normalized coordinates. It must never choose
the largest person by itself.

The pure resolver scores transitions using:

```swift
let transitionCost =
    3.0 * centerDistance
    + 1.5 * abs(log(current.bodyScale / previous.bodyScale))
    + 2.0 * jointShapeDistance
    + (candidate.identityConfidence < 0.5 ? 1.0 : 0.0)
```

Reject a path when two candidates remain within the ambiguity margin for more than
150 ms; return `.manualAnchorRequired` instead of switching silently.

- [ ] **Step 4: Run GREEN, run the existing primary-golfer test, and commit**

Run the new smoke plus `Tests/PrimaryGolferTrackingPolicySmoke.swift`. Expected:
both exit 0.

```bash
git add SwingArc/Services/VisionFullClipPoseExtractor.swift \
  SwingArc/Services/PrimaryGolferTrackResolver.swift \
  Tests/PrimaryGolferTrackResolverSmoke.swift
git commit -m "feat: lock full-clip primary golfer trajectory"
```

---

### Task 3: Build sparse and dense annotation queues

**Files:**
- Create: `SwingArc/Services/GolfAnnotationFrameQueueBuilder.swift`
- Create: `Tests/GolfAnnotationFrameQueueSmoke.swift`

**Interfaces:**
- Consumes: P1–P8 source frames, split, frame count, anomaly frames
- Produces: sorted unique `[GolfAnnotationQueueItem]`
- Encodes: P1–P5 stride 4, P5–P8 stride 2, P6/P8 ±12 dense, validation/held-out P5−12…P8+12 dense, up to 10 pre/post negatives

- [ ] **Step 1: Write the failing exact-queue test**

For P1=100, P5=200, P6=220, P8=260 and 400 total frames, assert:

```swift
let training = GolfAnnotationFrameQueueBuilder.build(input: trainingInput)
precondition(training.map(\.sourceFrameIndex) == Array(
    Set(
        Array(stride(from: 100, through: 200, by: 4))
        + Array(stride(from: 200, through: 260, by: 2))
        + Array(208...232)
        + Array(248...272)
        + anomalyFrames
        + negativeFrames
    )
).sorted())

let validation = GolfAnnotationFrameQueueBuilder.build(input: validationInput)
precondition(Set(validation.map(\.sourceFrameIndex))
    .isSuperset(of: Set(188...272)))
```

Also assert protected P-stage/dense frames cannot be removed by the UI.

- [ ] **Step 2: Run RED**

Compile the new service and test. Expected: FAIL because the builder is absent.

- [ ] **Step 3: Implement one policy object**

Create `GolfAnnotationQueuePolicy.v1` with the exact values from the spec. Each
queue item stores its reasons as a sorted set so one frame can be both P6-dense
and low-confidence without duplication.

- [ ] **Step 4: Run GREEN and commit**

```bash
git add SwingArc/Services/GolfAnnotationFrameQueueBuilder.swift \
  Tests/GolfAnnotationFrameQueueSmoke.swift
git commit -m "feat: build golf keypoint annotation queues"
```

---

### Task 4: Add the local macOS application target and import flow

**Files:**
- Create: `SwingArcDataset/SwingArcDatasetApp.swift`
- Create: `SwingArcDataset/Models/DatasetWorkspaceState.swift`
- Create: `SwingArcDataset/Services/DatasetImportController.swift`
- Create: `SwingArcDataset/Views/DatasetImportSheet.swift`
- Create: `Tests/MacDatasetImportContractSmoke.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `GolfDatasetStore`, `ExactVideoFrameSession`, `AnnotationStore`, P-point truth JSON
- Produces: imported `GolfClipIdentity`, security-scoped bookmark, assigned golferID and inherited split
- Target: `SwingArcDataset`
- Bundle ID: `com.liangbo.swingarc.dataset`

- [ ] **Step 1: Write the failing import-state test**

Test the pure reducer:

```swift
var state = DatasetImportState.empty
state = DatasetImportReducer.reduce(
    state,
    .mediaVerified(
        media: fixtureMedia,
        securityScopedBookmark: Data([1, 2, 3])
    )
)
state = DatasetImportReducer.reduce(
    state,
    .assignGolfer("golfer-001")
)
state = DatasetImportReducer.reduce(state, .setView(.downTheLine))
state = DatasetImportReducer.reduce(state, .setHandedness(.right))
state = DatasetImportReducer.reduce(
    state,
    .setAuthorization(.trainingAllowed)
)
precondition(state.canImport)
precondition(state.split == .training)
```

Use a registry fixture where golfer-001 is already locked to training. Require a
split override action to be rejected.

- [ ] **Step 2: Run RED**

Compile the plan-1 models/store plus `DatasetWorkspaceState.swift` and the new
test. Expected: FAIL because the Mac workspace files are absent.

- [ ] **Step 3: Implement the macOS target**

Add target settings:

```text
PRODUCT_NAME = SwingArcDataset
PRODUCT_BUNDLE_IDENTIFIER = com.liangbo.swingarc.dataset
SDKROOT = macosx
MACOSX_DEPLOYMENT_TARGET = 14.0
SWIFT_VERSION = 5.0
CODE_SIGN_STYLE = Automatic
ENABLE_APP_SANDBOX = YES
ENABLE_USER_SELECTED_FILES = readwrite
```

Create a shared scheme `SwingArcDataset`. Add only platform-neutral shared model
and service files needed by the target; do not add iPhone views or camera capture.

The import controller must compute the media SHA-256, open the real source
timeline, match a P-point package by media/timeline hash, then require explicit
golferID/view/handedness/authorization before saving.
Create dataset ID `swingarc-golf-keypoints-v1`; Plan 1 exports the first frozen
snapshot as export ID `bootstrap-v1`.

- [ ] **Step 4: Build the Mac target and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -jobs 1 \
  -project SwingArcProject.xcodeproj \
  -scheme SwingArcDataset \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

```bash
git add SwingArcDataset \
  SwingArcProject.xcodeproj/project.pbxproj \
  SwingArcProject.xcodeproj/xcshareddata/xcschemes/SwingArcDataset.xcscheme \
  Tests/MacDatasetImportContractSmoke.swift
git commit -m "feat: add SwingArcDataset Mac import app"
```

---

### Task 5: Build the three-column annotation workspace

**Files:**
- Create: `SwingArcDataset/Models/DatasetAnnotationState.swift`
- Create: `SwingArcDataset/Views/DatasetWorkspaceView.swift`
- Create: `SwingArcDataset/Views/DatasetClipSidebar.swift`
- Create: `SwingArcDataset/Views/DatasetFrameCanvas.swift`
- Create: `SwingArcDataset/Views/DatasetKeypointInspector.swift`
- Create: `SwingArcDataset/Views/DatasetTimelineView.swift`
- Create: `Tests/MacDatasetAnnotationStateSmoke.swift`
- Create: `Tests/MacDatasetWorkspaceSourceSmoke.swift`
- Modify: `SwingArcDataset/SwingArcDatasetApp.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Input: clip, queue, selected prediction run, active revision
- Output: five decisions for each reviewed source frame
- Navigation: left clip/anomaly filters, center frame/timeline, right keypoint inspector
- Reuse: `ExactVideoFrameSession`, `GolfAnnotationFrameQueueBuilder`

- [ ] **Step 1: Write the failing reducer test**

Require selection, stepping, and completion:

```swift
var state = DatasetAnnotationState.fixture(frameCount: 757, frame: 542)
state = DatasetAnnotationReducer.reduce(state, .step(-5))
precondition(state.currentSourceFrameIndex == 537)
state = DatasetAnnotationReducer.reduce(state, .step(5))
for landmark in GolfLandmark.allCases {
    state = DatasetAnnotationReducer.reduce(
        state,
        .acceptPrediction(landmark)
    )
}
precondition(state.currentFrameIsComplete)
precondition(state.decisionsForCurrentFrame.count == 5)
```

Then mark ball out-of-frame and assert its coordinate is nil. Mark shaftEnd
unresolved and assert the frame can be saved but is excluded from complete
training export.

- [ ] **Step 2: Write the failing source contract**

Read the five new SwiftUI files as text and require:

```swift
for token in [
    "NavigationSplitView",
    "DatasetClipSidebar",
    "DatasetFrameCanvas",
    "DatasetKeypointInspector",
    "DatasetTimelineView",
    "接受当前帧",
    "−5", "−1", "+1", "+5",
    "grip", "shaftStart", "shaftEnd", "clubhead", "ball"
] {
    precondition(combinedSource.contains(token), "missing \(token)")
}
```

- [ ] **Step 3: Run RED**

Compile the pure reducer test; separately compile/run the source test. Expected:
FAIL because the workspace files are absent.

- [ ] **Step 4: Implement the A-layout**

Use a `NavigationSplitView` with fixed minimum side widths and a flexible center.
The canvas toggles full frame/ROI, renders Vision skeleton, five points, the shaft
line, and adjacent-frame trails. The inspector exposes exactly:

```swift
enum InspectorAction: String, CaseIterable {
    case acceptPrediction
    case correctPoint
    case occluded
    case outOfFrame
    case unresolved
}
```

“接受当前帧” dispatches five individual decisions. Disable it if any prediction
is absent without an explicit hidden/unresolved decision.

- [ ] **Step 5: Run GREEN, build, and commit**

Run both new tests and the Mac target build.

```bash
git add SwingArcDataset \
  SwingArcProject.xcodeproj/project.pbxproj \
  Tests/MacDatasetAnnotationStateSmoke.swift \
  Tests/MacDatasetWorkspaceSourceSmoke.swift
git commit -m "feat: add three-column golf annotation workspace"
```

---

### Task 6: Add autosave, blind held-out mode, and real-video proof

**Files:**
- Create: `SwingArcDataset/Services/DatasetWorkspaceController.swift`
- Create: `Tests/MacDatasetBlindModeSmoke.swift`
- Create: `docs/validation/mac-golf-keypoint-annotation-2026-07-24.md`
- Modify: `SwingArcDataset/Views/DatasetWorkspaceView.swift`
- Modify: `SwingArcDataset/Views/DatasetFrameCanvas.swift`
- Modify: `SwingArcDataset/Views/DatasetKeypointInspector.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Autosaves one atomic revision after every decision
- Restores clip/frame/filter/revision after relaunch
- Blind held-out mode never loads prediction overlays
- Media/timeline mismatch opens read-only

- [ ] **Step 1: Write the failing blind-mode test**

Assert:

```swift
let heldOut = DatasetAnnotationPresentation(
    split: .heldOut,
    reviewMode: .blindIndependentPass,
    prediction: fixturePrediction
)
precondition(heldOut.visiblePredictionPoints.isEmpty)
precondition(!heldOut.showsConfidence)
precondition(!heldOut.allowsAcceptPrediction)

let training = DatasetAnnotationPresentation(
    split: .training,
    reviewMode: .predictionFirst,
    prediction: fixturePrediction
)
precondition(training.visiblePredictionPoints.count == 5)
precondition(training.allowsAcceptPrediction)
```

Add a store spy and require one `saveRevision` call after each decision.

- [ ] **Step 2: Run RED**

Compile the pure presentation/controller test. Expected: FAIL because blind mode
and the controller are absent.

- [ ] **Step 3: Implement autosave and read-only failure states**

The controller owns `ExactVideoFrameSession`, active prediction/revision IDs, and
`GolfDatasetStore`. It writes after every reducer action and restores from the
last revision. On media/timeline mismatch, expose:

```swift
enum DatasetWorkspaceAccess {
    case editable
    case readOnly(reason: String)
}
```

Blind mode must omit prediction loading at the controller boundary, not merely
hide an already loaded overlay.

- [ ] **Step 4: Verify the eight current videos**

Import the 8 files in `/tmp/SwingArc-8-videos-20260724-153013`, match the 8 truth
files in `/Users/liangbo/Desktop/test/P 点`, and manually assign the two anonymous
golfer IDs. Do not guess golfer identity from filenames.

Record:

- 8/8 media and timeline matches;
- 5 DTL and 3 Face-on;
- one golfer locked to training and one to validation;
- ROI coverage/jitter report;
- P6/P8 dense queue sizes;
- relaunch/autosave proof;
- blind mode proof using a fixture held-out clip.

- [ ] **Step 5: Run all Plan 2 tests and both platform builds**

Run every new smoke test, then:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -jobs 1 -project SwingArcProject.xcodeproj \
  -scheme SwingArcDataset -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -jobs 1 -project SwingArcProject.xcodeproj \
  -scheme SwingArcProject -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: both builds succeed.

- [ ] **Step 6: Commit validation evidence**

```bash
git add SwingArcDataset/Services/DatasetWorkspaceController.swift \
  SwingArcDataset/Views/DatasetWorkspaceView.swift \
  SwingArcDataset/Views/DatasetFrameCanvas.swift \
  SwingArcDataset/Views/DatasetKeypointInspector.swift \
  SwingArcProject.xcodeproj/project.pbxproj \
  Tests/StableSwingROIGeometrySmoke.swift \
  Tests/PrimaryGolferTrackResolverSmoke.swift \
  Tests/GolfAnnotationFrameQueueSmoke.swift \
  Tests/MacDatasetImportContractSmoke.swift \
  Tests/MacDatasetAnnotationStateSmoke.swift \
  Tests/MacDatasetWorkspaceSourceSmoke.swift \
  Tests/MacDatasetBlindModeSmoke.swift \
  docs/validation/mac-golf-keypoint-annotation-2026-07-24.md
git commit -m "test: verify Mac golf keypoint annotation workflow"
```

## Plan 2 Completion Gate

- Mac target builds and launches locally.
- All 8 current videos match their media/timeline identities.
- ROI round-trip error, coverage, and jitter gates are reported.
- Five decisions can be completed without altering a prediction run.
- Relaunch restores the exact clip, frame, and revision.
- held-out blind mode never loads prediction points.
- iOS target still builds without any Mac training UI.

# SwingArc Golf Tracking and P1–P8 Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Swift/Core ML 中解码五热图，连续跟踪球杆/球轨迹，并以严格杆身证据融合进 P1–P8。

**Architecture:** `GolfHeatmapDecoder` 把模型热图和可见性转换为带 top-K 候选的原片坐标；`GolfKeypointSequenceTracker` 对连续源帧执行双向动态规划；`VisionPoseDetector` 在姿态定位的挥杆窗口运行稳定 ROI 和专用模型。最终求解器只接受 Core ML/人工结论级双端点杆身，轮廓证据仅能扩大候选窗口。

**Tech Stack:** Swift 5、Core ML、CoreVideo、CoreGraphics、AVFoundation、Vision、现有 standalone Swift smoke tests、Xcode 27 beta、iOS 17+。

## Global Constraints

- 输入模型固定为 `512 × 512`，输出 `[1, 5, 128, 128]` heatmaps 和 `[1, 5, 3]` visibility。
- landmark 和 visibility 顺序必须与模型 metadata 完全一致。
- occluded/out-of-frame 不得产生下游坐标；跟踪器不得把不可见状态伪造成 detected。
- 连续挥杆窗口按真实源帧运行；不要求对整段 240 FPS 文件实时推理。
- P6/P8 confirmed 必须同时有 conclusion-grade shaftStart 和 shaftEnd。
- contour 只能成为 diagnostic/sampling candidate，不能成为 P6/P8 最终证据。
- 没有 locked held-out 时只能集成 `development` 模型，不得标记 release。
- 所有生产行为修改遵循 RED → GREEN → REFACTOR。

---

### Task 1: Decode heatmaps and visibility in a pure Swift layer

**Files:**
- Create: `SwingArc/Models/GolfKeypointInferenceModels.swift`
- Create: `SwingArc/Services/GolfHeatmapDecoder.swift`
- Create: `Tests/GolfHeatmapDecoderSmoke.swift`

**Interfaces:**
- Consumes: flat heatmap/visibility arrays, exact shapes, `GolfROIAffineTransform`
- Produces: `GolfHeatmapFramePrediction`
- Produces: five `GolfLandmarkPrediction` values with top-K candidates, confidence, dispersion, visibility
- Throws: shape/order/non-finite/transform errors

- [ ] **Step 1: Write the failing peak, transform, and hidden-state test**

Create five `128 × 128` heatmaps. Put one peak for grip at `(96, 32)`, two peaks
for clubhead, and a peak for ball while visibility says out-of-frame. Assert:

```swift
let prediction = try GolfHeatmapDecoder.decode(
    heatmaps: heatmaps,
    heatmapShape: [1, 5, 128, 128],
    visibilityLogits: visibility,
    visibilityShape: [1, 5, 3],
    transform: fixtureTransform,
    sourceFrameIndex: 542,
    time: 18.066
)
precondition(prediction.points[.grip]?.visibility == .visible)
precondition(prediction.points[.grip]?.candidates.count == 3)
precondition(
    abs((prediction.points[.grip]?.candidates[0].roiPoint.x ?? 0) - 96.0 / 127.0)
        < 0.001
)
precondition(prediction.points[.ball]?.visibility == .outOfFrame)
precondition(prediction.points[.ball]?.resolvedFullFramePoint == nil)
```

Pass shape `[1, 5, 64, 64]` and require `.invalidHeatmapShape`. Insert NaN and
require `.nonFiniteOutput`.

- [ ] **Step 2: Run RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/GolfPredictionRun.swift \
  SwingArc/Models/GolfKeypointInferenceModels.swift \
  SwingArc/Services/GolfHeatmapDecoder.swift \
  Tests/GolfHeatmapDecoderSmoke.swift \
  -o /tmp/golf-heatmap-decoder-smoke
```

Expected: FAIL because the inference model and decoder are absent.

- [ ] **Step 3: Implement deterministic top-K decoding**

Use 3×3 non-maximum suppression, top K=3, and sub-pixel weighted centroid within
the peak neighborhood. Apply softmax to each visibility row. Only `.visible`
may expose `resolvedFullFramePoint`; hidden classes retain diagnostic heatmap
candidates but return nil downstream.

Map ROI points through the stored inverse affine transform, then reject values
outside `[0, 1]` instead of clamping them into the source frame.

- [ ] **Step 4: Run GREEN and commit**

```bash
git add SwingArc/Models/GolfKeypointInferenceModels.swift \
  SwingArc/Services/GolfHeatmapDecoder.swift \
  Tests/GolfHeatmapDecoderSmoke.swift
git commit -m "feat: decode golf heatmaps and visibility"
```

---

### Task 2: Load only provenance-valid Core ML models

**Files:**
- Create: `SwingArc/Services/GolfKeypointModelRegistry.swift`
- Modify: `SwingArc/Services/CoreMLGolfObjectDetector.swift`
- Modify: `SwingArc/Services/GolfObjectObservationProvider.swift`
- Modify: `Tests/GolfObjectObservationProviderSmoke.swift`
- Create: `Tests/GolfKeypointModelRegistrySmoke.swift`

**Interfaces:**
- Produces: `GolfKeypointModelDescriptor`
- Produces: `GolfKeypointModelRegistry.load(url:allowedStatus:)`
- Replaces provider input with `GolfObjectInferenceInput(image:transform:pose:sourceFrameIndex:time:)`
- Provider output includes raw `GolfHeatmapFramePrediction`
- Produces: `GolfObjectObservation.evidenceGrades: [SwingLandmark: GolfEvidenceGrade]`

- [ ] **Step 1: Write the failing metadata gate**

Build descriptors without loading Core ML bytes:

```swift
let descriptor = GolfKeypointModelDescriptor.fixture(
    status: .development,
    inputSize: 512,
    heatmapSize: 128,
    landmarks: ["grip", "shaftStart", "shaftEnd", "clubhead", "ball"],
    visibility: ["visible", "occluded", "out-of-frame"]
)
precondition(
    GolfKeypointModelRegistry.validate(
        descriptor,
        allowedStatus: .development
    ).isEmpty
)
precondition(
    GolfKeypointModelRegistry.validate(
        descriptor,
        allowedStatus: .release
    ).contains(.promotionStatusMismatch)
)
```

Change model/manifest/evaluation hashes to 63 characters, reorder landmarks, and
change input size to 256; require exact validation failures.

- [ ] **Step 2: Run RED**

Compile the registry test. Expected: FAIL because the registry is absent.

- [ ] **Step 3: Update the provider contract**

Replace:

```swift
func observe(image: CGImage, pose: PoseEstimationResult?) throws
```

with:

```swift
func observe(
    input: GolfObjectInferenceInput
) throws -> GolfObjectObservation
```

`CoreMLGolfObjectDetector` creates a 512 pixel buffer from the already chosen ROI,
requests `heatmaps` and `visibility`, passes arrays to `GolfHeatmapDecoder`, and
returns both decoded points and the raw frame prediction. Delete the old 256
aspect-fit coordinate decoder.

- [ ] **Step 4: Preserve contour as diagnostic-only**

Add:

```swift
enum GolfEvidenceGrade: String, Codable {
    case diagnosticCandidate
    case conclusionGrade
}
```

Core ML visible detections with valid metadata can be conclusion-grade. Contour
adapter output is always diagnosticCandidate. Store the grade per landmark in
`GolfObjectObservation.evidenceGrades`, then copy it into
`SwingObjectEvidence.trackedPointGrades`.

- [ ] **Step 5: Run focused regression and commit**

Run the registry, decoder, and updated provider smoke tests.

```bash
git add SwingArc/Services/GolfKeypointModelRegistry.swift \
  SwingArc/Services/CoreMLGolfObjectDetector.swift \
  SwingArc/Services/GolfObjectObservationProvider.swift \
  Tests/GolfKeypointModelRegistrySmoke.swift \
  Tests/GolfObjectObservationProviderSmoke.swift
git commit -m "feat: load provenance-locked golf heatmap models"
```

---

### Task 3: Track top-K candidates through continuous source frames

**Files:**
- Create: `SwingArc/Services/GolfKeypointSequenceTracker.swift`
- Create: `Tests/GolfKeypointSequenceTrackerSmoke.swift`
- Modify: `SwingArc/Services/GolfObjectObservationProvider.swift`
- Modify: `Tests/ClubheadTrajectoryTrackerSmoke.swift`

**Interfaces:**
- Consumes: ordered `[GolfHeatmapFramePrediction]`
- Produces: ordered `[SwingFrameObservation]`
- Produces: `GolfTrackDiagnostics` with gaps, rejected observations, forward/back disagreement
- Replaces carry-forward `GolfObjectTrajectoryTracker` for Core ML evidence

- [ ] **Step 1: Write the failing path-selection test**

Create 12 continuous frames. In frame 6, give clubhead a high-confidence clothing
peak far from the motion path and a lower-confidence peak on the continuous path.
Require the path candidate. Add:

- a one-frame low-confidence gap: output `.estimated`;
- a three-frame visible-truth gap: output `.missing` after two frames;
- an occluded frame with a strong heatmap peak: output `.occluded` with nil point;
- inconsistent shaft length: reject the shaftEnd candidate;
- forward/back paths that disagree: lower confidence and mark diagnostics.

```swift
let tracked = GolfKeypointSequenceTracker.track(predictions)
precondition(tracked.frames.count == predictions.count)
precondition(tracked.frames[6].landmarks[.clubhead]?.point == expectedPathPoint)
precondition(tracked.frames[8].landmarks[.ball]?.state == .occluded)
precondition(tracked.frames[8].landmarks[.ball]?.point == nil)
precondition(tracked.diagnostics.longestVisibleGap[.clubhead] == 1)
```

- [ ] **Step 2: Run RED**

Compile inference models, decoder, tracker, and test. Expected: FAIL because the
new tracker is absent.

- [ ] **Step 3: Implement deterministic bidirectional dynamic programming**

For each landmark, define node cost from negative log heatmap confidence and
visibility. Define transition cost from source-time-normalized velocity and
acceleration. For shaftStart/shaftEnd add joint pair cost for shaft length and
axis change. For grip add distance to Vision hand center; for ball add a low-speed
cost before impact.

Run forward and reversed paths. Accept a point when their selected candidate
indices agree or their source-space distance is within 0.02; otherwise mark the
frame low-confidence/missing. Never interpolate through explicit occluded or
out-of-frame visibility.

- [ ] **Step 4: Remove unsafe carry-forward behavior**

Keep `SwingTrajectoryTracker` for body observations. Replace
`GolfObjectTrajectoryTracker` use for Core ML frames; retain it only for legacy
diagnostic contour tests until Plan 4 completion, then remove if unused.

- [ ] **Step 5: Run GREEN and commit**

```bash
git add SwingArc/Services/GolfKeypointSequenceTracker.swift \
  SwingArc/Services/GolfObjectObservationProvider.swift \
  Tests/GolfKeypointSequenceTrackerSmoke.swift \
  Tests/ClubheadTrajectoryTrackerSmoke.swift
git commit -m "feat: track golf heatmap candidates bidirectionally"
```

---

### Task 4: Run continuous ROI inference inside the swing window

**Files:**
- Create: `SwingArc/Services/GolfInferenceWindowPlanner.swift`
- Create: `Tests/GolfInferenceWindowPlannerSmoke.swift`
- Modify: `SwingArc/Services/VisionPoseDetector.swift`
- Modify: `Tests/SparseObjectSamplingPlanSmoke.swift`
- Modify: `Tests/VideoAnalysisMediaPipelineSmoke.swift`

**Interfaces:**
- Consumes: pose-derived swing window, source timeline, stable ROI track
- Produces: every source-frame reference in the expanded swing window
- Uses: `CoreMLGolfObjectDetector`, `GolfKeypointSequenceTracker`
- Keeps: sparse contour sampling only when a promoted model is unavailable

- [ ] **Step 1: Write the failing continuous-window test**

For a source timeline with frames 0…999 and a pose window 400…520, require:

```swift
let plan = GolfInferenceWindowPlanner.frames(
    sourceFrameRange: 400...520,
    frameCount: 1_000,
    marginFrames: 12
)
precondition(plan == Array(388...532))
precondition(zip(plan, plan.dropFirst()).allSatisfy { $1 == $0 + 1 })
```

Clamp at video bounds. Give an ROI track missing frame 450 and require a typed
`.roiUnavailable(450)` rather than silently skipping it.

- [ ] **Step 2: Run RED**

Compile the planner and test. Expected: FAIL because the planner is absent.

- [ ] **Step 3: Replace sparse Core ML sampling**

In `VisionPoseDetector`:

1. preserve the pose-derived coarse/fine swing window;
2. build/reuse a stable ROI track;
3. enumerate every source frame in the expanded window;
4. decode each frame once through the existing cache/ledger;
5. run the Core ML provider with its exact ROI transform;
6. run the sequence tracker after all raw predictions are available;
7. merge tracked golf points into `SwingFrameObservation`;
8. publish typed diagnostics and cancellation progress.

When no valid development/release model is present, keep current sparse contour
sampling for diagnostics but mark every contour point diagnostic-only.

- [ ] **Step 4: Verify decode-once and cancellation**

Extend `VideoAnalysisMediaPipelineSmoke` so each planned source frame registers
one decode at most. Cancel mid-window and require no later model calls or partial
confirmed shaft evidence.

- [ ] **Step 5: Run GREEN, the real-video diagnostic compile, and commit**

Run the planner, sparse fallback, decode-ledger, and existing real-video tracking
smokes.

```bash
git add SwingArc/Services/GolfInferenceWindowPlanner.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  Tests/GolfInferenceWindowPlannerSmoke.swift \
  Tests/SparseObjectSamplingPlanSmoke.swift \
  Tests/VideoAnalysisMediaPipelineSmoke.swift
git commit -m "feat: run continuous golf inference in swing window"
```

---

### Task 5: Make P6 and P8 require conclusion-grade shaft endpoints

**Files:**
- Create: `Tests/P6P8HeatmapShaftGateSmoke.swift`
- Modify: `SwingArc/Services/SwingStageDetector.swift`
- Modify: `SwingArc/Services/SwingFeedbackAssembler.swift`
- Modify: `Tests/OrderedStageSolverSmoke.swift`
- Modify: `Tests/ContinuousEvidenceStageSolverSmoke.swift`
- Modify: `Tests/ProductAnalysisFallbackSmoke.swift`

**Interfaces:**
- Produces: `SwingObjectEvidence.hasConclusionGradeShaft`
- P6/P8 confirmed gate: both endpoints visible/detected, conclusion-grade, accepted confidence, continuous local shaft angle
- Contour/provisional candidates remain at most low-confidence/unresolved

- [ ] **Step 1: Write the failing strict-gate matrix**

Build one otherwise valid ordered path and vary only shaft evidence:

```swift
precondition(resolve(p6: coreMLBothEndpoints).p6.status == .confirmed)
precondition(resolve(p6: contourBothEndpoints).p6.status == .unresolved)
precondition(resolve(p6: coreMLShaftStartOnly).p6.status == .unresolved)
precondition(resolve(p8: coreMLBothEndpoints).p8.status == .confirmed)
precondition(resolve(p8: estimatedEndpoints).p8.status == .unresolved)
precondition(resolve(p8: occludedShaftEnd).p8.status == .unresolved)
```

Also assert a pose-only provisional P8 can expand the inference window but cannot
appear as a final stage marker.

- [ ] **Step 2: Run RED**

Compile the stage detector and new test. Expected: at least the contour case fails
because current object evidence can still expose a shaft without a grade.

- [ ] **Step 3: Implement one shared evidence predicate**

```swift
var hasConclusionGradeShaft: Bool {
    guard let start = trackedPoints[.shaftStart],
          let end = trackedPoints[.shaftEnd] else { return false }
    return start.state == .detected
        && end.state == .detected
        && start.point != nil
        && end.point != nil
        && start.source == .coreMLGolf
        && end.source == .coreMLGolf
        && trackedPointGrades[.shaftStart] == .conclusionGrade
        && trackedPointGrades[.shaftEnd] == .conclusionGrade
}
```

Use this predicate in P6 candidate creation, P8 candidate creation, final
constrained-path validation, and feedback assembly. Do not duplicate looser local
checks.

- [ ] **Step 4: Run stage regressions and commit**

Run the new gate test plus ordered, continuous-evidence, product-fallback, real
video stage, and feedback tests.

```bash
git add SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingFeedbackAssembler.swift \
  Tests/P6P8HeatmapShaftGateSmoke.swift \
  Tests/OrderedStageSolverSmoke.swift \
  Tests/ContinuousEvidenceStageSolverSmoke.swift \
  Tests/ProductAnalysisFallbackSmoke.swift
git commit -m "fix: require heatmap shaft evidence for P6 and P8"
```

---

### Task 6: Extend release evaluation to all golf points and device gates

**Files:**
- Modify: `Tools/PrecisionDataset/PrecisionDatasetModels.swift`
- Modify: `Tools/PrecisionDataset/RunPrecisionEvaluation.swift`
- Modify: `Tests/PrecisionEvaluationReportSmoke.swift`
- Create: `Tests/GolfReleaseEvaluationSmoke.swift`

**Interfaces:**
- Consumes: held-out per-frame five-point predictions/truth, visibility, view, shaft angles, device timing/memory
- Produces: per-view/per-point metrics, sample sufficiency, gaps, shaft-angle rows, P1–P8 rows, failed thresholds
- Release gate: 10 held-out golfers, 5/view, 30 clips/stage/view, 100 visible + 30 non-visible/point/view, 10 negatives, model P95 ≤100 ms, memory ≤250 MB

- [ ] **Step 1: Write the failing all-landmark release fixture**

Replace the current clubhead-only passing fixture with all five points and exact
sample counts. Require `releasePassed == true`. Then fail:

- grip DTL hit rate 0.89;
- ball Face-on false-visible 0.06;
- shaftEnd three-frame gap;
- P6 shaft median 3.1°;
- only 4 Face-on golfers;
- 29 P8 Face-on clips;
- device P95 100.1 ms;
- peak memory 250.1 MB;
- only 9 negative clips.

Each failure must add one exact `failedThresholds` row.

- [ ] **Step 2: Run RED**

Compile `PrecisionDatasetModels.swift`, `RunPrecisionEvaluation.swift`, and both
evaluation tests. Expected: FAIL because the models/report only cover clubhead.

- [ ] **Step 3: Generalize report types**

Replace `PrecisionClubheadSummary` with:

```swift
struct PrecisionGolfLandmarkSummary: Codable {
    let view: DatasetView
    let landmark: String
    let visibleFrameCount: Int
    let nonVisibleFrameCount: Int
    let visibleFrameHitRate: Double
    let medianError: Double?
    let p90Error: Double?
    let visibleRecall: Double
    let falseVisibleRate: Double
    let longestVisibleGap: Int
    let sufficientSamples: Bool
}
```

Add shaft-angle, negative-suite, inference-P95, and incremental-memory fields.
Keep explicit nulls for unavailable metrics and deterministic JSON/Markdown.

- [ ] **Step 4: Run GREEN and commit**

```bash
git add Tools/PrecisionDataset/PrecisionDatasetModels.swift \
  Tools/PrecisionDataset/RunPrecisionEvaluation.swift \
  Tests/PrecisionEvaluationReportSmoke.swift \
  Tests/GolfReleaseEvaluationSmoke.swift
git commit -m "feat: gate golf keypoints and device performance"
```

---

### Task 7: Build, run the eight-video regression, and verify development model on iPhone

**Files:**
- Modify: `Tests/RealVideoTrackingDiagnostics.swift`
- Modify: `Tests/RealVideoStageDiagnostics.swift`
- Modify: `Tests/RealVideoP1P8Acceptance.swift`
- Create: `docs/validation/golf-heatmap-p1p8-integration-2026-07-24.md`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj` only to add a verified development model resource

**Interfaces:**
- Consumes: Plan 3 development mlpackage when validation and parity pass
- Produces: current 8-video regression, device timing/memory, P1–P8 evidence report
- Does not produce: release approval

- [ ] **Step 1: Run the focused Swift suite**

Compile/run decoder, registry, sequence tracker, window planner, P6/P8 gate,
precision evaluation, and existing analysis smoke tests. Expected: all exit 0.

- [ ] **Step 2: Build both targets**

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

- [ ] **Step 3: Re-run the eight-video development evaluation**

Use `/tmp/SwingArc-8-videos-20260724-153013` and
`/Users/liangbo/Desktop/test/P 点`. Record:

- the same 8 media/timeline identities;
- baseline 29/64;
- new P1–P8 hit/unresolved/timing miss rows;
- P6/P8 conclusion-grade shaft coverage;
- all five keypoint/visibility metrics where truth exists;
- analysis elapsed time;
- any ROI/model/tracker failure.

Do not count unreviewed auto points as truth.

- [ ] **Step 4: Verify on an unlocked iPhone**

If the development model passed validation/parity, include it only in an internal
development build. Install, launch, import one DTL and one Face-on clip, and
record:

- model metadata loaded;
- P95 inference time ≤100 ms per ROI;
- incremental peak memory ≤250 MB;
- no crash or memory termination;
- P6/P8 remain unresolved whenever shaft endpoints are insufficient.

If the phone is locked or unavailable, record that limit and do not claim device
completion.

- [ ] **Step 5: Commit evidence**

```bash
git add SwingArc/Services/CoreMLGolfObjectDetector.swift \
  SwingArc/Services/GolfKeypointModelRegistry.swift \
  SwingArc/Services/GolfHeatmapDecoder.swift \
  SwingArc/Services/GolfKeypointSequenceTracker.swift \
  SwingArc/Services/GolfInferenceWindowPlanner.swift \
  SwingArc/Services/GolfObjectObservationProvider.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingFeedbackAssembler.swift \
  SwingArc/Models/GolfKeypointInferenceModels.swift \
  Tests/RealVideoTrackingDiagnostics.swift \
  Tests/RealVideoStageDiagnostics.swift \
  Tests/RealVideoP1P8Acceptance.swift \
  Tools/PrecisionDataset/PrecisionDatasetModels.swift \
  Tools/PrecisionDataset/RunPrecisionEvaluation.swift \
  SwingArcProject.xcodeproj/project.pbxproj \
  docs/validation/golf-heatmap-p1p8-integration-2026-07-24.md
git commit -m "test: verify golf heatmap P point integration"
```

## Plan 4 Completion Gate

- Swift decoder matches the fixed output contract.
- Core ML models with missing/mismatched provenance are rejected.
- Continuous tracking prefers motion-consistent heatmap candidates and never invents hidden points.
- Core ML runs on every source frame in the selected swing window without duplicate decodes.
- P6/P8 cannot be confirmed by contour, one endpoint, estimated endpoints, or pose-only candidates.
- Release evaluation covers five points, both views, shaft angle, stages, negatives, timing, and memory.
- The eight-video and physical-device reports distinguish improvement, failure, and unverified evidence.

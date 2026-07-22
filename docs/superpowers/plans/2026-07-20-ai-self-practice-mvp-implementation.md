# SwingArc AI 自助練球 MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an on-device, single-iPhone AI practice loop whose P1–P8 stages and technique feedback are evidence-backed, calibratable, and safe to withhold when uncertain.

**Architecture:** First make the existing Vision/P1–P8 engine measurable against versioned, manually labelled ground truth. Then add bounded per-user calibration and view-gated technique evaluators that consume confirmed stages only. Finally add the DTL/front live-practice shell, reusing the existing `SwingVideoAnalysisEngine`, `AnalysisWorkspaceView`, local project store and export path instead of creating a second video-analysis stack.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Vision, Foundation/JSON, existing standalone Swift smoke tests, external `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj` for iPhone verification.

## Global Constraints

- All media, analysis and calibration remain on-device in MVP; no account, cloud inference or silent data export.
- Every automatic P1–P8 marker must reference a decoded source frame. Never synthesize markers from a percentage of video duration.
- A technique finding may be emitted only when required stages are `.confirmed`, pose evidence is sufficient, and the matching camera view is selected.
- `lowConfidence` and `unresolved` must be visible states, not coerced into a score or verbal diagnosis.
- User edits always override auto markers for the current video.
- Per-user calibration may adjust bounded timing offset, smoothing and evaluator thresholds only after adequate same-view evidence; it never retrains `VNDetectHumanBodyPoseRequest`.
- DTL and front views are separate single-camera sessions; do not promise simultaneous two-angle capture.
- Live-practice controls must be single-tap, at least 64 × 64 pt, with one explicit `開始自動練習` / `暫停自動練習` action.
- Build and launch on an unlocked physical iPhone before claiming camera, audio, continuous capture, or outdoor usability works.

---

## File Structure

- `SwingArc/Services/StageCalibration.swift` — ground-truth schema, report calculation, baseline comparison and bounded personal calibration policy.
- `SwingArc/Services/SwingTechniqueEvaluator.swift` — pure, view-gated posture/over-the-top/chicken-wing evidence and findings.
- `SwingArc/Models/PracticeModels.swift` — practice view, session state, finding and Drill presentation models.
- `SwingArc/Services/PracticeSessionEngine.swift` — capture-cycle state machine; it receives impact events and completed clips, then invokes the existing analysis engine.
- `SwingArc/Views/PracticeHomeView.swift` — three large entry points.
- `SwingArc/Views/PracticeSessionView.swift` — alignment, explicit start/pause, large remote status and last-result ribbon.
- `SwingArc/Views/AnalysisWorkspaceView.swift` — priority-finding and Drill presentation above existing evidence controls.
- `SwingArc/Services/LocalProjectStore.swift` / `SwingArc/Models/WorkspaceModels.swift` — persistent manual corrections, practice metadata and calibration data.
- `Tests/StageCalibrationSmoke.swift`, `Tests/SwingTechniqueEvaluatorSmoke.swift`, `Tests/PracticeSessionStateSmoke.swift` — pure policy coverage.
- `Tests/Fixtures/stage-ground-truth/*.json` — checked-in consented or synthetic-only manifests; source videos remain outside Git.

## Task 1: Make P1–P8 accuracy measurable before changing any threshold

**Files:**
- Create: `SwingArc/Services/StageCalibration.swift`
- Create: `Tests/StageCalibrationSmoke.swift`
- Create: `Tests/Fixtures/stage-ground-truth/README.md`
- Modify: `Tests/P1P8AcceptanceSupport.swift`
- Modify: `Tests/P1P8AcceptanceEvaluationSmoke.swift`

**Interfaces:**
- Produces `StageGroundTruthSet`, `StageCalibrationReport`, `StageCalibrationReport.evaluate(truth:result:)`, and `StageBaselineComparator.canPromote(candidate:baseline:)`.
- Consumes existing `SwingAnalysisResult`, `SwingStageDetection`, `GroundTruthManifest`, and `SwingStage`.

- [ ] **Step 1: Write failing evaluator tests for exact, unresolved and out-of-tolerance P points.**

```swift
let report = StageCalibrationReport.evaluate(truth: truth, result: result)
precondition(report.metrics[.top]!.absoluteFrameErrors == [2])
precondition(report.metrics[.followThrough]!.unresolvedCount == 1)
precondition(report.metrics[.impact]!.falseConfirmationCount == 1)
precondition(!StageBaselineComparator.canPromote(candidate: regressed, baseline: baseline))
```

- [ ] **Step 2: Run the new test and verify RED.**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/StageCalibration.swift Tests/StageCalibrationSmoke.swift \
  -o /tmp/stage-calibration && /tmp/stage-calibration
```

Expected: compilation fails because `StageCalibrationReport` and `StageBaselineComparator` do not exist.

- [ ] **Step 3: Implement the schema and promotion gate.**

Implement metrics per `SwingStage`: confirmed count, unresolved count, false-confirmation count, absolute source-frame errors, median frame error and in-tolerance ratio. Require a candidate to have no increase in false confirmations or unresolved stages and no worse median error before it can replace a baseline.

```swift
struct StageCalibrationReport: Equatable {
    let metrics: [SwingStage: StageMetric]

    static func evaluate(truth: StageGroundTruthSet, result: SwingAnalysisResult) -> Self
}

enum StageBaselineComparator {
    static func canPromote(candidate: StageCalibrationReport,
                           baseline: StageCalibrationReport) -> Bool
}
```

- [ ] **Step 4: Re-run the calibration and existing acceptance tests.**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/StageCalibration.swift Tests/StageCalibrationSmoke.swift \
  -o /tmp/stage-calibration && /tmp/stage-calibration
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift \
  Tests/P1P8AcceptanceSupport.swift Tests/P1P8AcceptanceEvaluationSmoke.swift \
  -o /tmp/p1p8-acceptance && /tmp/p1p8-acceptance Tests/Fixtures/IMG_4500-ground-truth.json
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit the measurable-stage baseline.**

```bash
git add SwingArc/Services/StageCalibration.swift Tests/StageCalibrationSmoke.swift \
  Tests/P1P8AcceptanceSupport.swift Tests/P1P8AcceptanceEvaluationSmoke.swift \
  Tests/Fixtures/stage-ground-truth/README.md
git commit -m "test: measure stage detection against ground truth"
```

## Task 2: Add manual P-point correction and bounded personal calibration

**Files:**
- Modify: `SwingArc/Models/WorkspaceModels.swift`
- Modify: `SwingArc/Services/LocalProjectStore.swift`
- Modify: `SwingArc/Services/StageCalibration.swift`
- Create: `SwingArc/Models/PracticeModels.swift`
- Create: `Tests/PersonalCalibrationSmoke.swift`
- Modify: `Tests/ProjectPersistenceSmoke.swift`

**Interfaces:**
- Produces `PracticeCameraView`, `StageCorrection`, `PersonalStageCalibration`, and `PersonalCalibrationPolicy.update(current:corrections:view:)`.
- Consumes manual `KeyframeMarker` values.

- [ ] **Step 1: Write failing persistence and sufficiency tests.**

```swift
let calibration = PersonalCalibrationPolicy.update(
    current: .empty,
    corrections: eightConsistentDTLCorrections,
    view: .downTheLine
)
precondition(calibration.offsetFrames[.top] == 3)
precondition(calibration.offsetFrames[.impact] == 0)
precondition(PersonalCalibrationPolicy.update(current: .empty,
    corrections: twoCorrections, view: .downTheLine) == .empty)
```

- [ ] **Step 2: Run tests and verify RED.**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Services/LocalProjectStore.swift SwingArc/Services/StageCalibration.swift \
  Tests/PersonalCalibrationSmoke.swift -o /tmp/personal-calibration && /tmp/personal-calibration
```

Expected: compilation fails because correction and calibration types do not exist.

- [ ] **Step 3: Implement corrections as video-local truth and bounded aggregation.**

Implement `PracticeCameraView` with `.downTheLine` and `.faceOn`, then persist a manual override per stage with original automatic source frame and view. Require at least eight same-view corrections for a stage, use the median frame delta, and clamp any stored offset to `-6...6` source frames. Persist no raw video and never alter Vision model weights.

```swift
struct PersonalStageCalibration: Codable, Equatable {
    var offsetFrames: [SwingStage: Int]
    static let empty = Self(offsetFrames: [:])
}
```

- [ ] **Step 4: Run persistence and calibration smoke tests.**

Run the command in Step 2 plus:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Services/LocalProjectStore.swift Tests/ProjectPersistenceSmoke.swift \
  -o /tmp/project-persistence && /tmp/project-persistence
```

Expected: both exit 0 and a project round-trip retains manual stage data.

- [ ] **Step 5: Commit correction and calibration storage.**

```bash
git add SwingArc/Models/PracticeModels.swift SwingArc/Models/WorkspaceModels.swift SwingArc/Services/LocalProjectStore.swift \
  SwingArc/Services/StageCalibration.swift Tests/PersonalCalibrationSmoke.swift \
  Tests/ProjectPersistenceSmoke.swift
git commit -m "feat: persist manual stage corrections and calibration"
```

## Task 3: Define evidence-backed technique findings before UI work

**Files:**
- Create: `SwingArc/Services/SwingTechniqueEvaluator.swift`
- Create: `Tests/SwingTechniqueEvaluatorSmoke.swift`
- Modify: `SwingArc/Services/SwingStageDetector.swift`

**Interfaces:**
- Produces `TechniqueFinding`, `TechniqueSeverity`, `TechniqueEvidence`, and `SwingTechniqueEvaluator.evaluate(samples:stages:view:leadArm:)`.
- Consumes confirmed P1–P8 detections plus `SwingPoseSample` values already generated by `SwingStageDetector`.

- [ ] **Step 1: Write failing pure-geometry tests.**

```swift
let findings = SwingTechniqueEvaluator.evaluate(
    samples: postureLossFixture,
    stages: confirmedStages,
    view: .downTheLine,
    leadArm: .left
)
precondition(findings.first?.kind == .postureLoss)
precondition(findings.first?.severity == .attention)
precondition(SwingTechniqueEvaluator.evaluate(
    samples: lowConfidenceFixture, stages: confirmedStages,
    view: .downTheLine, leadArm: .left).isEmpty)
```

- [ ] **Step 2: Run the evaluator test and verify RED.**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingTechniqueEvaluator.swift Tests/SwingTechniqueEvaluatorSmoke.swift \
  -o /tmp/technique-evaluator && /tmp/technique-evaluator
```

Expected: compilation fails because `SwingTechniqueEvaluator` is absent.

- [ ] **Step 3: Implement view gates and three conservative evaluators.**

Implement posture loss from normalized shoulder-mid/hip-mid angle plus head displacement between P1, P4 and P6/P7. Implement over-the-top only for `.downTheLine`, using the P4→P6 hand-center path relative to the P2→P4 path. Implement chicken wing only for `.faceOn`, using lead shoulder-elbow-wrist extension and elbow distance from torso over P6→P7. Require all requisite stages `.confirmed`, aggregate pose confidence ≥ `0.65`, and at least three adjacent supporting samples. Return no finding for an unsupported view or incomplete evidence.

- [ ] **Step 4: Run evaluator, stage and acceptance tests.**

Run the command in Step 2, then `Tests/SwingStageDetectorSmoke.swift` and `Tests/P1P8AcceptanceEvaluationSmoke.swift` with their existing compile commands. Expected: all exit 0.

- [ ] **Step 5: Commit the evaluator core.**

```bash
git add SwingArc/Services/SwingTechniqueEvaluator.swift \
  SwingArc/Services/SwingStageDetector.swift Tests/SwingTechniqueEvaluatorSmoke.swift
git commit -m "feat: add evidence-backed swing technique evaluator"
```

## Task 4: Add explicit practice and presentation models

**Files:**
- Modify: `SwingArc/Models/PracticeModels.swift`
- Create: `Tests/PracticeSessionStateSmoke.swift`
- Modify: `SwingArc/Models/WorkspaceModels.swift`

**Interfaces:**
- Produces `PracticeSessionState`, `PracticeSessionReducer.reduce(state:event:)`, `PriorityFeedback`, and `DrillRecommendation`.
- Consumes `TechniqueFinding` from Task 3.

- [ ] **Step 1: Write failing state-machine tests.**

```swift
var state = PracticeSessionState.aligning(view: .downTheLine)
state = PracticeSessionReducer.reduce(state: state, event: .alignmentConfirmed)
precondition(state == .readyToStart(view: .downTheLine))
state = PracticeSessionReducer.reduce(state: state, event: .startTapped)
precondition(state == .waitingForImpact(view: .downTheLine, swingCount: 0))
```

- [ ] **Step 2: Run tests and verify RED.**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/PracticeModels.swift Tests/PracticeSessionStateSmoke.swift \
  -o /tmp/practice-state && /tmp/practice-state
```

Expected: compilation fails because `PracticeSessionState` and `PracticeSessionReducer` do not exist.

- [ ] **Step 3: Implement the closed state machine and priority policy.**

Define only `.aligning`, `.readyToStart`, `.waitingForImpact`, `.processing`, `.resultRibbon`, `.paused`, `.degraded` and `.failed`. `PriorityFeedback` selects the highest-severity confirmed finding; if none exists, it emits `.unresolved` rather than a positive score. Map each supported finding to a local drill identifier; do not include network URLs.

- [ ] **Step 4: Run state smoke tests.**

Run the Step 2 command. Expected: exit 0; an impact event from `.waitingForImpact` must enter `.processing`, and `.analysisFinished` must return to `.resultRibbon` then `.waitingForImpact`.

- [ ] **Step 5: Commit models.**

```bash
git add SwingArc/Models/PracticeModels.swift SwingArc/Models/WorkspaceModels.swift \
  Tests/PracticeSessionStateSmoke.swift
git commit -m "feat: define practice session state and feedback models"
```

## Task 5: Build the live-practice capture-cycle service

**Files:**
- Create: `SwingArc/Services/PracticeSessionEngine.swift`
- Create: `Tests/PracticeSessionEngineSmoke.swift`
- Modify: `SwingArc/Views/CameraView.swift`
- Modify: `SwingArc/Services/LocalProjectStore.swift`

**Interfaces:**
- Produces `PracticeSessionEngine.start(view:)`, `pause()`, `ingestImpact(time:)`, and completion callback `(URL, SwingAnalysisResult, [TechniqueFinding]) -> Void`.
- Consumes `PracticeSessionReducer`, `SwingVideoAnalysisEngine`, `SwingTechniqueEvaluator`, and the existing camera recorder.

- [ ] **Step 1: Write failing stateful service tests with a fake impact detector.**

```swift
engine.start(view: .faceOn)
engine.ingestImpact(time: 12.4)
precondition(recorder.requestedWindows == [PracticeClipWindow(preImpact: 2, postImpact: 1)])
precondition(engine.state == .processing(view: .faceOn, swingCount: 1))
```

- [ ] **Step 2: Run tests and verify RED.**

Compile `PracticeModels.swift`, `PracticeSessionEngine.swift`, and `PracticeSessionEngineSmoke.swift` with `swiftc`; expected failure because the engine/protocols are missing.

- [ ] **Step 3: Implement dependency-injected capture orchestration.**

Define `ImpactDetecting`, `PracticeClipRecording`, and `PracticeAnalyzing` protocols. The production recorder bridges AVFoundation; the engine only requests a `2.0` second pre-impact plus `1.0` second post-impact clip, serializes analysis, and transitions through the reducer. Reject impact callbacks unless state is `.waitingForImpact`; retain completed clips even if analysis fails.

- [ ] **Step 4: Run deterministic engine tests, then build the iOS project.**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -quiet \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject -configuration Debug -sdk iphoneos build
```

Expected: smoke tests exit 0 and the iPhone build exits 0.

- [ ] **Step 5: Commit capture orchestration.**

```bash
git add SwingArc/Services/PracticeSessionEngine.swift SwingArc/Views/CameraView.swift \
  SwingArc/Services/LocalProjectStore.swift Tests/PracticeSessionEngineSmoke.swift
git commit -m "feat: add continuous practice capture cycle"
```

## Task 6: Implement the three-entry home and remote session UI

**Files:**
- Create: `SwingArc/Views/PracticeHomeView.swift`
- Create: `SwingArc/Views/PracticeSessionView.swift`
- Modify: `SwingArc/Views/ContentView.swift`
- Modify: `SwingArc/Design/AnalysisTheme.swift`
- Modify: `SwingArc/Views/CameraView.swift`
- Create: `Tests/PracticePresentationSmoke.swift`

**Interfaces:**
- Consumes `PracticeSessionState`, `PracticeCameraView` and `PriorityFeedback` from Task 4.
- Produces navigation from home to `.downTheLine`, `.faceOn`, or the existing photo importer.

- [ ] **Step 1: Write failing presentation-policy tests.**

```swift
precondition(PracticePresentationPolicy.primaryControl(for: .readyToStart(view: .downTheLine)) == .start)
precondition(PracticePresentationPolicy.primaryControl(for: .waitingForImpact(view: .downTheLine)) == .pause)
precondition(PracticePresentationPolicy.remoteStatus(for: .processing(view: .faceOn, swingCount: 4)) == "第 4 球分析中")
```

- [ ] **Step 2: Run tests and verify RED.**

Compile `PracticeModels.swift`, `AnalysisTheme.swift` and `PracticePresentationSmoke.swift`; expected failure because `PracticePresentationPolicy` is absent.

- [ ] **Step 3: Implement the confirmed UI direction.**

Render three large home entries: `正後方練習`, `正面練習`, `導入已有揮杆影片`. In the session view show an alignment frame, actual selected frame rate, one start/pause control, and remote status only. Keep controls at least 64 pt. After a result ribbon, automatically transition back to waiting state; expose `查看上一球慢動作` as a secondary action. At 60 seconds without impact, use a low-brightness waiting appearance without ending the session.

- [ ] **Step 4: Build the iPhone project.**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -quiet \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject -configuration Debug -sdk iphoneos build
```

Expected: project build exits 0.

- [ ] **Step 5: Commit the practice UI.**

```bash
git add SwingArc/Views/PracticeHomeView.swift SwingArc/Views/PracticeSessionView.swift \
  SwingArc/Views/ContentView.swift SwingArc/Views/CameraView.swift \
  SwingArc/Design/AnalysisTheme.swift Tests/PracticePresentationSmoke.swift
git commit -m "feat: add remote-first practice session UI"
```

## Task 7: Integrate evidence and correction into the analysis workspace

**Files:**
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `SwingArc/Views/WorkspaceComponents.swift`
- Modify: `SwingArc/Views/ContentView.swift`
- Modify: `SwingArc/Services/LocalProjectStore.swift`
- Create: `Tests/TechniqueFeedbackPresentationSmoke.swift`

**Interfaces:**
- Consumes `TechniqueFinding`, `PriorityFeedback`, manual stage corrections and `SwingAnalysisResult`.
- Produces a visible priority-finding section, source-frame evidence navigation and a manual-correction save path.

- [ ] **Step 1: Write failing presentation tests.**

```swift
let model = TechniqueFeedbackPresentation.make(
    feedback: .finding(overTheTopFinding), analysis: confirmedAnalysis
)
precondition(model.title == "下杆略偏外")
precondition(model.showsEvidence)
precondition(TechniqueFeedbackPresentation.make(
    feedback: .unresolved, analysis: unresolvedAnalysis).title == "本球未能判定")
```

- [ ] **Step 2: Run the new smoke test and verify RED.**

Compile the relevant models, evaluator and `TechniqueFeedbackPresentationSmoke.swift`; expected failure because the presentation model does not exist.

- [ ] **Step 3: Implement evidence-first workspace behavior.**

Show one priority finding, its supporting P stages and an optional local Drill card. For a low-confidence or unresolved result, hide the Drill and show the specific missing evidence. When a user updates a P marker, save the correction and re-run evaluation from the corrected stage set; never overwrite a manual marker during later automatic analysis.

- [ ] **Step 4: Run workspace smoke tests and build.**

Run the new smoke test plus existing `Tests/AnalysisWorkspacePresentationSmoke.swift`, `Tests/ManualStageLockSmoke.swift`, `Tests/ProjectPersistenceSmoke.swift`, then run the Task 5 iPhone build command. Expected: all exit 0.

- [ ] **Step 5: Commit workspace integration.**

```bash
git add SwingArc/Views/AnalysisWorkspaceView.swift SwingArc/Views/WorkspaceComponents.swift \
  SwingArc/Views/ContentView.swift SwingArc/Services/LocalProjectStore.swift \
  Tests/TechniqueFeedbackPresentationSmoke.swift
git commit -m "feat: present evidence-backed practice feedback"
```

## Task 8: Validate calibration and outdoor practice on a real device

**Files:**
- Create: `docs/validation/ai-self-practice-field-checklist.md`
- Modify: `README.md`

**Interfaces:**
- Consumes Tasks 1–7.
- Produces a dated, copyable field-test record; no production code interface.

- [ ] **Step 1: Write the checklist before device testing.**

Include columns for view, handedness, source FPS, light condition, P1–P8 manual truth, automatic P1–P8 frame error, confidence, false diagnosis, missed diagnosis, audio trigger result, clip retention, heat state and user correction. Require at least two independent P-point annotations for every clip admitted to the calibration set.

- [ ] **Step 2: Run the automated regression suite.**

Run all new smoke tests, existing P1–P8 acceptance tests, `git diff --check`, and the iPhone build. Expected: every command exits 0 before installation.

- [ ] **Step 3: Install and exercise on an unlocked iPhone.**

Install the Debug or Release app with `xcrun devicectl`, unlock the phone, then test DTL and front sessions separately: alignment, explicit start, three consecutive impacts, automatic return to waiting, pause, previous-swing review, manual P-point correction and imported-video workflow.

- [ ] **Step 4: Decide whether a calibration/evaluator version may be promoted.**

Generate `StageCalibrationReport` for the new labelled set and compare it to the committed baseline. Promote only if `StageBaselineComparator.canPromote` returns true and no field-test false diagnosis is unresolved. Otherwise keep the baseline, attach the failure row to the checklist and create a focused regression fixture before changing a threshold.

- [ ] **Step 5: Commit validation evidence separately from product code.**

```bash
git add docs/validation/ai-self-practice-field-checklist.md README.md
git commit -m "docs: add AI practice field validation checklist"
```

## Plan Self-Review

- Spec coverage: Tasks 1–3 enforce truth-backed P1–P8, calibration and technical findings; Tasks 4–7 cover the confirmed three-entry, manual-start, continuous-feedback UI and existing imported-video workspace; Task 8 covers required device and field evidence.
- Placeholder scan: no incomplete markers, generic “add tests”, or unspecified interfaces remain.
- Type consistency: all later tasks consume `PracticeCameraView`, `PracticeSessionState`, `TechniqueFinding`, `PriorityFeedback`, `StageGroundTruthSet`, and `PersonalStageCalibration` defined in Tasks 1–4.

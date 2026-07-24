# SwingArc iPhone P 点修正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 iPhone 的研发标注工作流替换为面向用户的单人 P1–P8 修正流程，准确区分人体识别失败与阶段求解失败，并无损保留已有人工 P 点和画线。

**Architecture:** 继续以 `LocalAnalysisProject.keyframes` 和 `stageCorrections` 作为当前视频人工 P 点的权威存储；新增轻量、纯状态驱动的 `PPointCorrectionWorkspace`，复用真实源帧时间线和精确帧读取，不依赖 A/B 标注、关键点复核或训练导出。旧 Annotation 草稿只迁移人工 P1–P8，未复核训练关键点不进入项目或训练数据。

**Tech Stack:** Swift 5、SwiftUI、AVFoundation、CoreMedia、Foundation、现有 standalone Swift smoke tests、Xcode 27 beta、iOS 17+。

## Global Constraints

- 自动预测必须先显示；用户只修正错误或缺失的 P 点。
- 人工 P 点属于当前视频的权威结果，重新分析不得覆盖。
- P 点必须按真实源帧时间线读取，禁止用平均帧率伪造逐帧定位。
- 手机端不得出现 A/B、reviewer、裁定、真值标注或训练关键点。
- 旧项目、普通画线和已有人工 P1–P8 必须保留。
- 旧活动草稿中的未复核人体/球杆关键点不得迁入训练集。
- 所有生产行为修改遵循 RED → GREEN → REFACTOR。

---

### Task 1: Separate pose failure from stage-solver failure

**Files:**
- Modify: `SwingArc/Services/SwingStageDetector.swift`
- Modify: `SwingArc/Services/VisionPoseDetector.swift`
- Modify: `SwingArc/Models/WorkspaceModels.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `Tests/TwoStageAnalysisPolicySmoke.swift`
- Modify: `Tests/AnalysisSessionStateSmoke.swift`

**Interfaces:**
- Add: `AnalysisFailure.insufficientStageEvidence`
- Preserve: `AnalysisFailure.insufficientPoseEvidence` only for actual pose scarcity
- Present: `人体已识别，但未能自动确定完整 P1–P8。你可以手动设置 P 点。`

- [x] **Step 1: Extend the presentation test and verify RED**

Add an `insufficientStageEvidence` row to `Tests/TwoStageAnalysisPolicySmoke.swift` and assert the exact message above. Add state coverage to `Tests/AnalysisSessionStateSmoke.swift`.

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Services/SwingInputQualityEvaluator.swift \
  SwingArc/Services/SwingStageDetector.swift \
  Tests/TwoStageAnalysisPolicySmoke.swift \
  -o /tmp/two-stage-analysis-policy-smoke
```

Expected: FAIL because the new failure case does not exist.

- [x] **Step 2: Add the failure case and correct the solver mapping**

Add `.insufficientStageEvidence` to `AnalysisFailure`. In `VisionPoseDetector`, return this case when `ConstrainedSwingPathSolver` produces no markers after Vision and the evidence timeline have already been built. Keep the existing pose-coverage guards mapped to pose/stable-golfer failures.

- [x] **Step 3: Update every exhaustive switch**

Update analysis-state, diagnostics, mobile status, and presentation switches so compilation remains exhaustive and the user-facing message describes stage evidence rather than body visibility.

- [x] **Step 4: Run focused tests and commit**

Run the two smoke tests plus:

```bash
xcodebuild -project SwingArcProject.xcodeproj -scheme SwingArcProject \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Commit:

```bash
git add SwingArc Tests
git commit -m "fix: distinguish stage evidence from pose failure"
```

---

### Task 2: Define the single-user P-point correction state

**Files:**
- Create: `SwingArc/Models/PPointCorrectionState.swift`
- Create: `Tests/PPointCorrectionStateSmoke.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Produce: `PPointCorrectionState`
- Produce: `PPointCorrectionAction`
- Produce: `PPointCorrectionReducer`
- Consume: automatic `AnnotationStageSelection` candidates and existing manual `KeyframeMarker` values

- [ ] **Step 1: Write the failing reducer test**

Cover these behaviors:

- automatic P1–P8 predictions populate the initial state;
- existing manual markers override automatic frames;
- `−5 / −1 / +1 / +5` clamps to the real frame range;
- setting a stage creates or replaces one manual marker;
- moving one stage cannot cross the previous or next resolved stage;
- unresolved stages remain editable from their suggested candidate frame.

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Models/PPointCorrectionState.swift \
  Tests/PPointCorrectionStateSmoke.swift \
  -o /tmp/p-point-correction-state-smoke
```

Expected: FAIL because `PPointCorrectionState.swift` does not exist.

- [ ] **Step 2: Implement the pure correction model**

The model stores selected stage, current source frame, frame count, prediction rows, and manual stage rows. It exposes an ordered P1–P8 result and never stores body/golf keypoints, annotator IDs, reviewer fields, or training metadata.

- [ ] **Step 3: Verify GREEN and project membership**

Run the focused test and ensure the new source is part of the iOS target.

- [ ] **Step 4: Commit**

```bash
git add SwingArc/Models/PPointCorrectionState.swift \
  Tests/PPointCorrectionStateSmoke.swift \
  SwingArcProject.xcodeproj/project.pbxproj
git commit -m "feat: add single-user P point correction state"
```

---

### Task 3: Build the precise P-point correction workspace

**Files:**
- Create: `SwingArc/Views/PPointCorrectionWorkspace.swift`
- Create: `Tests/PPointCorrectionPresentationSmoke.swift`
- Modify: `SwingArc/Views/AnnotationFrameCanvas.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Input: video URL, automatic stage snapshot, existing manual markers
- Output: one corrected `SwingStage` and exact source-frame index at a time
- Reuse: `ExactVideoFrameProvider`

- [ ] **Step 1: Write the failing presentation contract**

Assert the production source contains:

- title `P 点修正`;
- subtitle `当前视频`;
- P1–P8 selector;
- exact step buttons `−5`, `−1`, `+1`, `+5`;
- action `设为 Pn`;
- no `annotator-a`, `annotator-b`, `reviewer`, `裁定`, `人体`, `球杆` training controls.

- [ ] **Step 2: Implement the workspace**

Render the exact source frame with aspect fit, stage selector, current frame/total frame display, candidate/manual status, step controls, and save button. Pause playback while open. The initial selected frame is manual if present, otherwise the automatic or suggested frame.

- [ ] **Step 3: Verify interaction and accessibility**

Add accessibility labels for each P stage, step control, close, and set-stage action. Verify compact iPhone portrait layout without requiring vertical scrolling for the primary controls.

- [ ] **Step 4: Run tests, build, and commit**

```bash
xcrun swiftc -parse-as-library Tests/PPointCorrectionPresentationSmoke.swift \
  -o /tmp/p-point-correction-presentation-smoke
/tmp/p-point-correction-presentation-smoke
xcodebuild -project SwingArcProject.xcodeproj -scheme SwingArcProject \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
git add SwingArc/Views SwingArcProject.xcodeproj Tests
git commit -m "feat: add precise P point correction workspace"
```

---

### Task 4: Replace the phone annotation entry and preserve manual locks

**Files:**
- Modify: `SwingArc/Views/ContentView.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `SwingArc/Views/WorkspaceComponents.swift`
- Modify: `SwingArc/Services/SwingTechniqueEvaluator.swift`
- Modify: `Tests/AnnotationIntegrationSmoke.swift`
- Modify: `Tests/ManualStageLockSmoke.swift`
- Modify: `Tests/AnalysisWorkspacePresentationSmoke.swift`

**Interfaces:**
- Rename drawing action to `画线`
- Rename precise correction action to `修正 P 点`
- Replace `AnnotationWorkspaceView` presentation with `PPointCorrectionWorkspace`

- [ ] **Step 1: Change source-contract tests and verify RED**

Assert that `ContentView` opens `PPointCorrectionWorkspace`, that the phone-facing source no longer opens `AnnotationWorkspaceView`, and that visible labels use `画线` and `修正 P 点`.

- [ ] **Step 2: Wire corrected stages into the current project**

On save:

1. convert exact source frame to its real timestamp;
2. replace the matching manual `KeyframeMarker`;
3. update `StageCorrection`;
4. persist through `LocalProjectStore`;
5. return to the same analysis screen and seek to the corrected frame.

- [ ] **Step 3: Preserve locks across reanalysis**

Keep `StageMarkerMerger.merge(existing:automatic:)` and `ManualStageDetectionPolicy` behavior covered so automatic analysis never replaces manual stages.

- [ ] **Step 4: Run tests and commit**

Run the presentation, integration, manual-lock, and project-persistence smoke tests plus a full unsigned iOS build.

Commit:

```bash
git add SwingArc Tests
git commit -m "feat: replace phone annotation with P point correction"
```

---

### Task 5: Migrate the current legacy annotation draft safely

**Files:**
- Create: `SwingArc/Services/LegacyAnnotationMigration.swift`
- Create: `Tests/LegacyAnnotationMigrationSmoke.swift`
- Modify: `SwingArc/Services/AnnotationStore.swift`
- Modify: `SwingArc/Views/ContentView.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Read: old active annotation pass for the same media identity
- Import: only valid P1–P8 source-frame selections
- Discard: unreviewed frame labels and all A/B workflow state
- Mark: migration idempotently per media identity

- [ ] **Step 1: Write a fixture matching the phone evidence and verify RED**

Use an active `annotator-a` draft containing P1–P8 plus unreviewed club landmarks. Assert migration produces eight manual markers, produces no keypoint/training records, and a second run changes nothing.

- [ ] **Step 2: Implement the one-time migration**

Resolve the active draft first; if absent, use the latest single submitted pass. Validate ordering and frame bounds. Merge without replacing newer project manual markers. Persist the project first, then record migration completion.

- [ ] **Step 3: Run migration and persistence tests**

Verify old projects and drawings round-trip unchanged.

- [ ] **Step 4: Commit**

```bash
git add SwingArc Tests SwingArcProject.xcodeproj/project.pbxproj
git commit -m "feat: migrate legacy phone P point corrections"
```

---

### Task 6: Regression-test the real phone video and install Release

**Files:**
- Modify: `Tests/RealVideoTrackingDiagnostics.swift`
- Create: `docs/validation/mobile-p-correction-2026-07-24.md`

- [ ] **Step 1: Run the copied 1364-frame video diagnostic**

Use `/tmp/swingarc-phone-evidence-20260724-1/imported.mp4`. Record Vision accepted frames, missing-pose frames, stage result, and final failure. Assert that an empty stage path yields `insufficientStageEvidence`, never `insufficientPoseEvidence`.

- [ ] **Step 2: Run the full smoke suite**

Run all standalone smoke tests and the iOS build. Record any pre-existing exclusions separately.

- [ ] **Step 3: Archive, install, and launch on the unlocked iPhone**

Build a signed Release, install bundle `com.liangbo.swingarc`, launch it, and verify:

- the existing project opens;
- P1–P8 remain present;
- “标注” is absent from the analysis header;
- “修正 P 点” opens the new workspace;
- the real video no longer reports an unclear-body failure.

- [ ] **Step 4: Commit validation evidence**

```bash
git add docs/validation/mobile-p-correction-2026-07-24.md
git commit -m "test: verify mobile P point correction on device"
```

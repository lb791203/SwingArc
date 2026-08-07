# SwingArc Mac 数据集与算法学习 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Mac 上建立从原始 240 FPS 视频自动预测、人工修正、数据集拆分、训练、验证到 Core ML 发布的可复现研发闭环。

**Architecture:** 以现有 `Tools/PrecisionDataset` 为数据与命令行核心，新增单人 correction-on-prediction 数据契约和批处理分析；原生 macOS 修正界面读取同一数据包，叠加 Apple Vision 人体预测和 SwingArc 球杆预测。训练脚本只消费通过授权、身份校验和人工复核门的数据，模型发布由留出集报告控制。

**Tech Stack:** Swift 5、SwiftUI for macOS、AVFoundation、Vision、Core ML、CryptoKit、Python/PyTorch、coremltools、现有 PrecisionDataset 工具与 smoke tests。

## Global Constraints

- 优先读取 `/Users/liangbo/Desktop/test/original-240fps` 原片，不以 Photos 慢动作副本替代训练时间线。
- Apple Vision 人体预测只作为输入；学习发生在 SwingArc 的纠正、平滑、球杆关键点与阶段融合层，不修改 Apple Vision。
- 球杆预测必须先显示，人工只修正错误或缺失点。
- 单人修正是日常流程；A/B 只保留为未来最终准确率协议。
- 视频、时间线、预测、修正和模型版本必须可追溯。
- 数据按球员隔离拆分，禁止同一球员跨训练与留出集泄漏。
- 未授权、未复核或身份不匹配的数据不得训练。
- 不检测杆头速度、攻角、杆面角、动态杆面倾角或弹道。
- 所有生产行为修改遵循 RED → GREEN → REFACTOR。

---

### Task 1: Freeze the Mac correction package contract

**Files:**
- Create: `Tools/PrecisionDataset/CorrectionPackageModels.swift`
- Create: `Tools/PrecisionDataset/ValidateCorrectionPackage.swift`
- Create: `Tests/CorrectionPackageModelsSmoke.swift`

**Interfaces:**
- Produce: media identity, exact frame timeline identity, model manifest, body predictions, golf predictions, P predictions, manual corrections, clip metadata, split and authorization
- Preserve: predicted value separately from corrected value

- [ ] Write a failing JSON round-trip and validation smoke test.
- [ ] Implement the minimal Codable models and validator.
- [ ] Reject missing SHA values, invalid coordinates, non-monotonic P1–P8, player split leakage metadata, and training without authorization/review.
- [ ] Run the focused test and commit `feat: define Mac correction package`.

---

### Task 2: Inventory and verify the eight original 240 FPS videos

**Files:**
- Modify: `Tools/PrecisionDataset/InventoryVideos.swift`
- Modify: `Tools/PrecisionDataset/PrecisionVideoInventory.swift`
- Create: `Tests/Original240FPSInventorySmoke.swift`
- Create: `docs/validation/original-240fps-inventory-2026-07-24.md`

- [ ] Write a failing inventory test for codec, dimensions, nominal and actual timeline rates, frame count, duration, orientation, SHA-256, and timeline SHA-256.
- [ ] Extend inventory output without transcoding any source.
- [ ] Run against `/Users/liangbo/Desktop/test/original-240fps`.
- [ ] Record which files truly expose 240 FPS source timing and commit the report.

---

### Task 3: Build the batch prediction pipeline

**Files:**
- Create: `Tools/PrecisionDataset/AnalyzePrecisionCorpus.swift`
- Create: `SwingArc/Services/PrecisionAnalysisPipeline.swift`
- Modify: `SwingArc/Services/SwingPoseObservationAdapter.swift`
- Modify: `SwingArc/Services/GolfObjectObservationProvider.swift`
- Create: `Tests/PrecisionAnalysisPipelineSmoke.swift`

- [ ] Write a failing deterministic fixture test for exact-frame Vision output, golf prediction output, fused P candidates, diagnostics, and model version.
- [ ] Extract a platform-neutral analysis pipeline from the app analyzer where practical.
- [ ] Run Apple Vision over exact original frames and retain confidence/visibility for each joint.
- [ ] Run the current SwingArc golf detector as prediction only, retaining missing/uncertain states.
- [ ] Fuse both streams into suggested P1–P8 without fixed-percent fallback.
- [ ] Save one correction package per clip and commit.

---

### Task 4: Build the native Mac correction workspace

**Files:**
- Create: `SwingArcDataset/SwingArcDatasetApp.swift`
- Create: `SwingArcDataset/DatasetLibraryView.swift`
- Create: `SwingArcDataset/CorrectionWorkspaceView.swift`
- Create: `SwingArcDataset/CorrectionCanvas.swift`
- Create: `SwingArcDataset/CorrectionDocumentStore.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`
- Create: `Tests/MacCorrectionPresentationSmoke.swift`

- [ ] Write a failing source/presentation contract for video library, exact frame stepping, prediction overlays, P1–P8, keypoint selection, and correction save.
- [ ] Add a macOS target that opens correction packages and original videos.
- [ ] Show Apple Vision skeleton, grip, shaft start/end, clubhead, ball, and automatic P1–P8 before any edit.
- [ ] Support drag-to-correct, add-missing, visible/occluded/out-of-frame/unresolved, and P frame correction.
- [ ] Autosave revisions atomically and never modify the source video.
- [ ] Build and manually open all eight videos, then commit.

---

### Task 5: Generate training, validation, and held-out datasets

**Files:**
- Create: `Tools/PrecisionDataset/BuildTrainingDataset.swift`
- Modify: `Tools/PrecisionDataset/PrecisionDatasetModels.swift`
- Create: `Tests/TrainingDatasetGateSmoke.swift`
- Modify: `docs/validation/precision-dataset/README.md`

- [ ] Write failing gates for authorization, review state, media identity, model version, stage order, and player-isolated split.
- [ ] Export corrected golf keypoints and fused-stage features while keeping predictions for audit.
- [ ] Prevent unreviewed phone keypoints and ordinary current-video P corrections from entering training automatically.
- [ ] Produce reproducible manifests with seeds and SHA-256 checksums.
- [ ] Commit `feat: build gated precision training datasets`.

---

### Task 6: Train and evaluate the golf-keypoint model

**Files:**
- Modify: `Training/golf_keypoints/dataset.py`
- Modify: `Training/golf_keypoints/model.py`
- Modify: `Training/golf_keypoints/train.py`
- Modify: `Training/golf_keypoints/evaluate.py`
- Modify: `Training/golf_keypoints/export_coreml.py`
- Modify: `Training/golf_keypoints/test_contract.py`
- Create: `docs/validation/golf-keypoint-model-report.md`

- [ ] Extend tests for `grip`, `shaftStart`, `shaftEnd`, `clubhead`, and `ball`, including visibility and missing-point masks.
- [ ] Train on high-resolution golfer/club ROI crops with temporal augmentation.
- [ ] Report normalized/pixel error, visible-frame recall, false confirmations, and trajectory gaps by DTL/Face-on.
- [ ] Export a versioned Core ML model only if held-out metrics improve over baseline.
- [ ] Record reproducible commands and commit model code/report; do not commit large private videos.

---

### Task 7: Train and evaluate the P1–P8 fusion model

**Files:**
- Create: `Training/p_stages/dataset.py`
- Create: `Training/p_stages/model.py`
- Create: `Training/p_stages/train.py`
- Create: `Training/p_stages/evaluate.py`
- Create: `Training/p_stages/export_coreml.py`
- Create: `Training/p_stages/test_contract.py`
- Create: `docs/validation/p-stage-model-report.md`

- [ ] Define temporal features from Vision joints, corrected golf tracks, direction, stage order, and true source timing.
- [ ] Train against corrected source-frame indices with explicit unresolved output.
- [ ] Report per-stage absolute source-frame error, within-1/2/5-frame accuracy, unresolved rate, and false-confirmation rate by camera view.
- [ ] Reject fixed percentage or nearest-neighbor filling in tests.
- [ ] Export only after held-out improvement and commit.

---

### Task 8: Register validated Core ML models in the iPhone app

**Files:**
- Create: `SwingArc/Services/ModelRegistry.swift`
- Modify: `SwingArc/Services/CoreMLGolfObjectDetector.swift`
- Modify: `SwingArc/Services/SwingStageDetector.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`
- Create: `Tests/ModelRegistrySmoke.swift`
- Create: `docs/validation/model-release-checklist.md`

- [ ] Write a failing registry test for semantic version, schema compatibility, metrics report SHA, and safe fallback.
- [ ] Bundle only models that pass the release gate.
- [ ] Keep prior validated model available for rollback.
- [ ] Run corpus evaluation, all app smoke tests, unsigned iOS build, signed device build, and physical-device validation.
- [ ] Commit the registry and validation evidence.


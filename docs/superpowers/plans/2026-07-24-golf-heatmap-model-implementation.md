# SwingArc Golf Heatmap Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有整图 256 坐标回归骨架升级为稳定 ROI 上的五热图、三分类可见性、全关键点验收和版本化 Core ML 开发模型。

**Architecture:** Python 数据集只读取计划 1 冻结的 resolved export，并用每帧 ROI 变换生成 `512 × 512` 输入和 `128 × 128` 热图目标。MobileNetV3-Small + 轻量 FPN 输出五热图和五组三分类 logits；训练、评估、Core ML 转换分别验证数据哈希、全关键点/双视角门和 PyTorch/Core ML 一致性。

**Tech Stack:** Python 3、PyTorch、torchvision、Pillow、pytest、Apple MPS、coremltools；现有 `.venv-golf-keypoints` 和锁定依赖文件。

## Global Constraints

- 只读取 `training-allowed`、已冻结、已复核、golfer split 无泄漏的 resolved export。
- 输入固定 `[B, 3, 512, 512]`；输出 heatmaps `[B, 5, 128, 128]`、visibility `[B, 5, 3]`。
- landmark 顺序固定为 grip、shaftStart、shaftEnd、clubhead、ball。
- visible 点训练 heatmap + visibility；occluded/out-of-frame 只训练 visibility；unresolved 完全 mask。
- validation 标签在候选训练前冻结，候选不得回写。
- 当前两位球员只能产生 development 候选；没有 locked held-out 时禁止 release 标记。
- 不通过验收时保留失败报告，禁止通过降低门槛导出 release。
- 所有生产行为修改遵循 RED → GREEN → REFACTOR。

---

### Task 1: Read resolved labels and generate heatmap targets

**Files:**
- Create: `Training/golf_keypoints/contracts.py`
- Create: `Training/golf_keypoints/heatmaps.py`
- Modify: `Training/golf_keypoints/dataset.py`
- Create: `Training/golf_keypoints/test_dataset_heatmaps.py`
- Modify: `Training/golf_keypoints/test_contract.py`
- Modify: `Training/golf_keypoints/README.md`

**Interfaces:**
- Produces: `LANDMARK_NAMES`, `VISIBILITY_NAMES`, `INPUT_SIZE=512`, `HEATMAP_SIZE=128`
- Produces: `gaussian_heatmap(x, y, size, sigma) -> torch.Tensor`
- Produces: `GolfHeatmapDataset`
- Dataset item: `(image, heatmaps, visibility_targets, coordinate_mask, metadata)`

- [ ] **Step 1: Write the failing visible/hidden dataset test**

Create a temporary resolved export with one 320×180 fixture image loader and one
ROI transform. Require:

```python
image, heatmaps, visibility, coordinate_mask, metadata = dataset[0]
assert image.shape == (3, 512, 512)
assert heatmaps.shape == (5, 128, 128)
assert visibility.shape == (5,)
assert coordinate_mask.tolist() == [True, True, True, False, False]
assert visibility.tolist() == [0, 0, 0, 1, -100]
assert metadata["view"] == "dtl"
assert metadata["source_frame_index"] == 542
assert metadata["stage_codes"] == ["P6"]

grip_peak = torch.nonzero(
    heatmaps[0] == heatmaps[0].max(),
    as_tuple=False,
)[0]
assert grip_peak.tolist() == [64, 32]
assert heatmaps[3].sum().item() == 0
assert heatmaps[4].sum().item() == 0
```

Use grip ROI coordinate `(0.25, 0.50)`, shaft points visible, clubhead occluded,
and ball unresolved/absent. Add an out-of-frame sample with no point and require
visibility class 2.

- [ ] **Step 2: Run RED**

```bash
.venv-golf-keypoints/bin/pytest \
  Training/golf_keypoints/test_dataset_heatmaps.py -q
```

Expected: FAIL because the new contracts/heatmap dataset do not exist.

- [ ] **Step 3: Implement strict resolved-export decoding**

`contracts.py`:

```python
LANDMARK_NAMES = (
    "grip", "shaft_start", "shaft_end", "clubhead", "ball",
)
MANIFEST_NAMES = {
    "grip": "grip",
    "shaft_start": "shaftStart",
    "shaft_end": "shaftEnd",
    "clubhead": "clubhead",
    "ball": "ball",
}
VISIBILITY_NAMES = ("visible", "occluded", "out-of-frame")
VISIBILITY_INDEX = {name: index for index, name in enumerate(VISIBILITY_NAMES)}
INPUT_SIZE = 512
HEATMAP_SIZE = 128
IGNORE_VISIBILITY = -100
```

`gaussian_heatmap` must clamp neither hidden points nor invalid visible points:

```python
def gaussian_heatmap(x, y, size=HEATMAP_SIZE, sigma=1.5):
    if not (math.isfinite(x) and math.isfinite(y) and 0 <= x <= 1 and 0 <= y <= 1):
        raise ReviewedTrainingLabelsRequired("visible point is outside ROI")
    xs = torch.arange(size, dtype=torch.float32)
    ys = torch.arange(size, dtype=torch.float32)
    grid_y, grid_x = torch.meshgrid(ys, xs, indexing="ij")
    center_x = x * (size - 1)
    center_y = y * (size - 1)
    return torch.exp(
        -((grid_x - center_x) ** 2 + (grid_y - center_y) ** 2)
        / (2 * sigma ** 2)
    )
```

The dataset verifies export `manifestSHA256`, split, authorization, completed
revision, media/timeline identity, and frame bounds before exposing samples.

- [ ] **Step 4: Update the dataset portion of the legacy contract and run GREEN**

Replace only the old dataset tuple/256 assertions in `test_contract.py` with the
new 512/heatmap/visibility-mask contract. Keep the old model-output assertions
until Task 2 replaces the model. Run:

```bash
.venv-golf-keypoints/bin/pytest \
  Training/golf_keypoints/test_dataset_heatmaps.py \
  Training/golf_keypoints/test_contract.py -q
```

Expected: all dataset assertions and the still-legacy model assertions pass, so
the repository never ends a task with a knowingly failing pytest suite.

- [ ] **Step 5: Commit**

```bash
git add Training/golf_keypoints/contracts.py \
  Training/golf_keypoints/heatmaps.py \
  Training/golf_keypoints/dataset.py \
  Training/golf_keypoints/test_dataset_heatmaps.py \
  Training/golf_keypoints/test_contract.py \
  Training/golf_keypoints/README.md
git commit -m "feat: generate golf heatmap training targets"
```

---

### Task 2: Replace coordinate regression with MobileNetV3-Small FPN

**Files:**
- Modify: `Training/golf_keypoints/model.py`
- Modify: `Training/golf_keypoints/test_contract.py`
- Create: `Training/golf_keypoints/test_model_heatmaps.py`

**Interfaces:**
- Produces: `GolfHeatmapNet(pretrained: bool)`
- Forward: `image -> (heatmaps, visibility_logits)`
- Produces: `heatmap_soft_argmax(heatmaps) -> [B, 5, 2]`

- [ ] **Step 1: Write the failing output-contract test**

```python
def test_heatmap_output_contract():
    model = GolfHeatmapNet(pretrained=False).eval()
    with torch.no_grad():
        heatmaps, visibility = model(torch.zeros(2, 3, 512, 512))
    assert heatmaps.shape == (2, 5, 128, 128)
    assert visibility.shape == (2, 5, 3)
    assert torch.all((heatmaps >= 0) & (heatmaps <= 1))


def test_soft_argmax_returns_normalized_xy():
    heatmaps = torch.zeros(1, 5, 128, 128)
    heatmaps[:, :, 32, 96] = 20
    points = heatmap_soft_argmax(heatmaps, input_is_logits=True)
    assert points.shape == (1, 5, 2)
    assert torch.allclose(
        points[0, 0],
        torch.tensor([96 / 127, 32 / 127]),
        atol=1e-2,
    )
```

- [ ] **Step 2: Run RED**

```bash
.venv-golf-keypoints/bin/pytest \
  Training/golf_keypoints/test_model_heatmaps.py -q
```

Expected: FAIL because `GolfHeatmapNet` is undefined.

- [ ] **Step 3: Implement the FPN**

Use torchvision only:

```python
class GolfHeatmapNet(nn.Module):
    def __init__(self, pretrained=True):
        super().__init__()
        weights = MobileNet_V3_Small_Weights.DEFAULT if pretrained else None
        self.features = mobilenet_v3_small(weights=weights).features
        self.lateral = nn.ModuleList([
            nn.Conv2d(16, 64, 1),
            nn.Conv2d(24, 64, 1),
            nn.Conv2d(48, 64, 1),
            nn.Conv2d(576, 64, 1),
        ])
        self.smooth = nn.ModuleList([
            nn.Conv2d(64, 64, 3, padding=1),
            nn.Conv2d(64, 64, 3, padding=1),
            nn.Conv2d(64, 64, 3, padding=1),
        ])
        self.heatmap_head = nn.Sequential(
            nn.Conv2d(64, 64, 3, padding=1),
            nn.ReLU(inplace=True),
            nn.Conv2d(64, len(LANDMARK_NAMES), 1),
        )
        self.visibility_head = nn.Sequential(
            nn.AdaptiveAvgPool2d(1),
            nn.Flatten(),
            nn.Linear(576, len(LANDMARK_NAMES) * len(VISIBILITY_NAMES)),
        )
```

Capture feature indices 1, 3, 8, and 12; fuse from deepest to shallowest with
bilinear interpolation. Return `torch.sigmoid(heatmap_logits)` and reshape
visibility to `[-1, 5, 3]`. Keep ImageNet mean/std buffers inside the model.

- [ ] **Step 4: Replace the old contract test**

Remove assertions for `(B, 5, 2)` coordinate output. Preserve tests for exact
landmark order and pretrained=False offline construction. Do not keep a legacy
coordinate head.

- [ ] **Step 5: Run GREEN and commit**

```bash
.venv-golf-keypoints/bin/pytest \
  Training/golf_keypoints/test_model_heatmaps.py \
  Training/golf_keypoints/test_contract.py -q

git add Training/golf_keypoints/model.py \
  Training/golf_keypoints/test_model_heatmaps.py \
  Training/golf_keypoints/test_contract.py
git commit -m "feat: add five-heatmap golf keypoint model"
```

---

### Task 3: Add masked losses and reproducible MPS training

**Files:**
- Create: `Training/golf_keypoints/losses.py`
- Modify: `Training/golf_keypoints/train.py`
- Create: `Training/golf_keypoints/test_losses.py`
- Create: `Training/golf_keypoints/test_training_contract.py`

**Interfaces:**
- Produces: `golf_keypoint_loss(...) -> dict[str, Tensor]`
- Produces: coordinate-masked heatmap MSE, visibility CE with ignore index, shaft-angle auxiliary loss
- Checkpoint metadata: manifest hash, ROI version, landmark order, visibility order, architecture, seed

- [ ] **Step 1: Write the failing mask test**

```python
def test_hidden_and_unresolved_points_have_no_heatmap_gradient():
    predicted = torch.zeros(1, 5, 128, 128, requires_grad=True)
    target = torch.ones_like(predicted)
    mask = torch.tensor([[1, 0, 0, 1, 0]], dtype=torch.bool)
    visibility_logits = torch.zeros(1, 5, 3, requires_grad=True)
    visibility_targets = torch.tensor([[0, 1, 2, 0, -100]])
    losses = golf_keypoint_loss(
        predicted,
        visibility_logits,
        target,
        visibility_targets,
        mask,
    )
    losses["total"].backward()
    assert predicted.grad[0, 0].abs().sum() > 0
    assert predicted.grad[0, 1].abs().sum() == 0
    assert predicted.grad[0, 2].abs().sum() == 0
    assert predicted.grad[0, 4].abs().sum() == 0
```

Add a test where both shaft endpoints are visible and rotating only shaftEnd
increases `shaft_angle`.

- [ ] **Step 2: Run RED**

```bash
.venv-golf-keypoints/bin/pytest \
  Training/golf_keypoints/test_losses.py -q
```

Expected: FAIL because `losses.py` does not exist.

- [ ] **Step 3: Implement the losses**

Use:

```python
heatmap_error = (
    (predicted_heatmaps - target_heatmaps).square()
    * coordinate_mask[:, :, None, None]
).sum() / coordinate_mask.sum().clamp_min(1)

visibility_error = F.cross_entropy(
    visibility_logits.reshape(-1, 3),
    visibility_targets.reshape(-1),
    ignore_index=-100,
    weight=visibility_class_weights,
)
```

Decode differentiable shaft endpoints with soft-argmax. Apply cosine-angle loss
only where both shaft masks are true. Return separate values and
`total = heatmap + 0.25 * visibility + 0.10 * shaft_angle`.

- [ ] **Step 4: Make training deterministic**

Add `--seed` default 1729, seed Python/Torch, use a seeded DataLoader generator,
and store:

```python
{
    "architecture": "mobilenet-v3-small-fpn-heatmap-v1",
    "manifestSHA256": manifest_sha256(args.manifest),
    "roiVersion": dataset.roi_version,
    "landmarks": list(LANDMARK_NAMES),
    "visibilityClasses": list(VISIBILITY_NAMES),
    "inputSize": 512,
    "heatmapSize": 128,
    "seed": args.seed,
}
```

Select MPS when available and print the selected device once.

- [ ] **Step 5: Run GREEN, one-batch MPS smoke, and commit**

The unit test uses a two-sample synthetic loader and one epoch. Expected: a
checkpoint is written and contains every field above.

```bash
.venv-golf-keypoints/bin/pytest \
  Training/golf_keypoints/test_losses.py \
  Training/golf_keypoints/test_training_contract.py -q

git add Training/golf_keypoints/losses.py \
  Training/golf_keypoints/train.py \
  Training/golf_keypoints/test_losses.py \
  Training/golf_keypoints/test_training_contract.py
git commit -m "feat: train golf heatmaps with masked supervision"
```

---

### Task 4: Evaluate all five points, views, visibility, gaps, and shaft angle

**Files:**
- Modify: `Training/golf_keypoints/evaluate.py`
- Create: `Training/golf_keypoints/metrics.py`
- Create: `Training/golf_keypoints/test_evaluation_gates.py`

**Interfaces:**
- Produces: per-view/per-landmark `visibleFrameHitRate`, median, P90, visible recall, false-visible rate, longest visible gap, sample sufficiency
- Produces: P6/P8 shaft-angle median/P90
- Produces: `developmentPromotionPassed`
- Thresholds: 0.02 hit, 0.01 median, 0.02 P90, 0.95 recall, 0.05 false-visible, max gap 2, shaft 3°/7°

- [ ] **Step 1: Write the failing gate matrix**

Create predictions/targets for both views and assert:

```python
report = build_evaluation_report(batches)
for view in ("dtl", "face-on"):
    for landmark in LANDMARK_NAMES:
        row = report["views"][view]["landmarks"][landmark]
        assert row["visibleFrameHitRate"] == 1.0
        assert row["medianDiagonalNormalizedError"] == 0.0
        assert row["p90DiagonalNormalizedError"] == 0.0
        assert row["visibleRecall"] == 1.0
        assert row["falseVisibleRate"] == 0.0
        assert row["longestVisibleGap"] == 0
        assert row["sufficientSamples"]
assert report["developmentPromotionPassed"]
```

Then fail one row at a time: grip hit 0.89, ball recall 0.94, shaftEnd false-visible
0.06, three-frame clubhead gap, shaft angle P90 7.1°, missing Face-on samples.
Every case must make promotion false; aggregate averages cannot rescue it.

- [ ] **Step 2: Run RED**

```bash
.venv-golf-keypoints/bin/pytest \
  Training/golf_keypoints/test_evaluation_gates.py -q
```

Expected: FAIL because current evaluation only gates clubhead.

- [ ] **Step 3: Implement metric primitives**

`metrics.py` provides deterministic percentile, source-pixel conversion, contiguous
gap calculation by `(clipID, sourceFrameIndex)`, visibility confusion counts, and
shaft angle:

```python
def shaft_angle_degrees(start, end):
    delta = end - start
    return torch.rad2deg(torch.atan2(delta[..., 1], delta[..., 0]))


def circular_angle_error_degrees(predicted, target):
    return torch.abs((predicted - target + 180) % 360 - 180)
```

Require development validation counts ≥30 visible and ≥10 non-visible for each
landmark/view. Explicitly write `null` metrics and `sufficientSamples: false` when
counts are insufficient.

- [ ] **Step 4: Bind reports to artifacts**

Include checkpoint SHA-256, manifest SHA-256, split, model/ROI/decoder versions,
sample counts, view counts, and exact failed thresholds. Reject evaluation when
the checkpoint manifest or ROI version differs from the export.

- [ ] **Step 5: Run GREEN and commit**

```bash
.venv-golf-keypoints/bin/pytest \
  Training/golf_keypoints/test_evaluation_gates.py \
  Training/golf_keypoints/test_contract.py -q

git add Training/golf_keypoints/evaluate.py \
  Training/golf_keypoints/metrics.py \
  Training/golf_keypoints/test_evaluation_gates.py
git commit -m "feat: gate every golf keypoint and view"
```

---

### Task 5: Export development Core ML with parity and provenance

**Files:**
- Modify: `Training/golf_keypoints/export_coreml.py`
- Create: `Training/golf_keypoints/coreml_parity.py`
- Create: `Training/golf_keypoints/test_coreml_export_gate.py`
- Modify: `Training/golf_keypoints/README.md`

**Interfaces:**
- Input: checkpoint, validation report, parity samples
- Output: `GolfKeypoints.mlpackage` with `development` metadata
- Blocks: validation failure, hash mismatch, shape/order mismatch, >1 input-pixel decoded difference, visibility mismatch

- [ ] **Step 1: Write the failing export-gate tests**

Use mocked conversion/parity callbacks so unit tests do not compile a model:

```python
assert_report_passes(checkpoint, passing_report)

with pytest.raises(ValueError, match="all landmarks and views"):
    assert_report_passes(checkpoint, report_with_ball_failure)

with pytest.raises(ValueError, match="held-out"):
    assert_release_status_allowed("release", report_without_heldout)

with pytest.raises(ValueError, match="parity"):
    assert_parity_passes({
        "maximumDecodedPixelDifference": 1.01,
        "visibilityClassMatches": True,
    })
```

- [ ] **Step 2: Run RED**

Run the new pytest file. Expected: FAIL because current exporter only checks
clubhead and has no parity contract.

- [ ] **Step 3: Convert the heatmap model**

Trace with `torch.zeros(1, 3, 512, 512)` and declare outputs:

```python
converted = ct.convert(
    traced,
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS17,
    inputs=[
        ct.ImageType(
            name="image",
            shape=(1, 3, 512, 512),
            scale=1 / 255.0,
        )
    ],
    outputs=[
        ct.TensorType(name="heatmaps"),
        ct.TensorType(name="visibility"),
    ],
)
```

Store model/checkpoint/manifest/ROI/evaluation hashes, output order, sizes,
architecture, and `promotionStatus=development`.

- [ ] **Step 4: Add real parity**

On fixed validation samples, run PyTorch and Core ML, decode both heatmaps, and
write:

```json
{
  "maximumDecodedPixelDifference": 0.0,
  "visibilityClassMatches": true,
  "sampleCount": 0
}
```

Set actual values and require at least 10 samples per view. Block save when the
decoded delta exceeds 1 input pixel or any visibility class differs.

- [ ] **Step 5: Run GREEN and commit**

```bash
.venv-golf-keypoints/bin/pytest \
  Training/golf_keypoints/test_coreml_export_gate.py \
  Training/golf_keypoints/test_evaluation_gates.py -q

git add Training/golf_keypoints/export_coreml.py \
  Training/golf_keypoints/coreml_parity.py \
  Training/golf_keypoints/test_coreml_export_gate.py \
  Training/golf_keypoints/README.md
git commit -m "feat: export provenance-locked golf heatmap Core ML"
```

---

### Task 6: Train and report the first development candidate

**Files:**
- Create: `docs/validation/golf-keypoint-development-model-2026-07-24.md`
- Modify only if a verified defect is found: `Training/golf_keypoints/*.py`

**Interfaces:**
- Consumes: completed Plan 2 training and validation exports
- Produces: checkpoint, validation JSON, parity JSON, optional development mlpackage
- Never produces: release status without held-out

- [ ] **Step 1: Verify the frozen export before training**

Run the Plan 1 validator and record:

- golfer counts by split;
- DTL/Face-on reviewed counts;
- visible/non-visible counts per landmark;
- manifest SHA-256;
- ROI version;
- no golfer leakage.

If any validation view/landmark is below 30 visible or 10 non-visible frames,
record `insufficientSamples` and continue only with a pipeline smoke; do not claim
promotion.

- [ ] **Step 2: Run the complete pytest suite**

```bash
.venv-golf-keypoints/bin/pytest Training/golf_keypoints -q
```

Expected: all tests pass.

- [ ] **Step 3: Train on MPS**

```bash
.venv-golf-keypoints/bin/python Training/golf_keypoints/train.py \
  --manifest '/Users/liangbo/Library/Application Support/SwingArcDataset/swingarc-golf-keypoints-v1/exports/bootstrap-v1/manifest.json' \
  --video-root /tmp/SwingArc-8-videos-20260724-153013 \
  --output Training/artifacts/golf-heatmap-v1.pt \
  --epochs 20 \
  --batch-size 8 \
  --learning-rate 0.0001 \
  --seed 1729
```

Expected: selected device is `mps`; checkpoint metadata matches the manifest.

- [ ] **Step 4: Evaluate without changing labels**

```bash
.venv-golf-keypoints/bin/python Training/golf_keypoints/evaluate.py \
  --checkpoint Training/artifacts/golf-heatmap-v1.pt \
  --manifest '/Users/liangbo/Library/Application Support/SwingArcDataset/swingarc-golf-keypoints-v1/exports/bootstrap-v1/manifest.json' \
  --video-root /tmp/SwingArc-8-videos-20260724-153013 \
  --split validation \
  --output Training/artifacts/golf-heatmap-v1-validation.json
```

Record every failed threshold. Do not rerun annotation from this candidate.

- [ ] **Step 5: Export only when development gates pass**

If `developmentPromotionPassed` is true, run export and parity. Otherwise preserve
the checkpoint/report as a failed candidate and skip Core ML export.

- [ ] **Step 6: Commit the evidence report**

The report states data counts, hardware, elapsed time, hashes, all metrics,
promotion status, and the explicit absence of held-out/release evidence.

```bash
git add docs/validation/golf-keypoint-development-model-2026-07-24.md
git commit -m "test: report first golf heatmap development model"
```

## Plan 3 Completion Gate

- Hidden/out-of-frame labels require no coordinates and produce no heatmap gradient.
- Model outputs exactly five `128 × 128` heatmaps and five three-class rows.
- MPS training and deterministic checkpoint metadata work.
- Every landmark and both views have independent sample/accuracy gates.
- Core ML parity is ≤1 input pixel with identical visibility classes.
- The first candidate is honestly recorded as passed, failed, or insufficient.
- No artifact is marked release without locked held-out evidence.

# Golf keypoint development model evidence — 2026-07-28

## Result

The first real full-frame heatmap candidate was trained successfully, but it is
**development-only and not promoted**. `developmentPromotionPassed` is `false`.
The frozen validation split has only 16 DTL frames, no Face-on frames, and no
validation-dense samples, so the required per-view, per-landmark, dense-gap, and
P6/P8 shaft gates cannot be satisfied. This checkpoint must not be connected to
the app, described as release-ready, or used as held-out evidence.

No labels were changed. No training source defect was found, so no Python source
was modified.

## Frozen input audit

- Frozen manifest: `/Users/liangbo/Library/Application Support/SwingArcDataset/golf-keypoints-v1/exports/golf-heatmap-full-frame-v2-c92d7c90adce28fe0e3d912089dc8ff00d1cdd2e177206b92c76040380665aad/manifest.json`
- Expected and actual manifest SHA-256: `c92d7c90adce28fe0e3d912089dc8ff00d1cdd2e177206b92c76040380665aad`
- Resolved-labels SHA-256: `194ef565fcd9370da485813b126317f2c324834a3197343e1dadfd309dc4fe78`
- Schema: `2`; input transform: `full-frame-aspect-fit-v1`; input: `512 × 512`
- 8/8 manifest clips, label clips, and source videos matched by filename and media SHA-256.
- Every clip is `training-allowed`, every clip has 8 reviewed resolved frames, and no unresolved landmark remains.
- Golfer split lock: `golfer-001` appears only in training; `golfer-002` appears only in validation. There is no golfer leakage.
- Training: 48 frames, comprising 24 DTL and 24 Face-on.
- Validation: 16 frames, comprising 16 DTL and 0 Face-on.
- Total labels: 250 visible, 44 occluded, 26 out-of-frame.
- P6 stage frames: 8 total (training DTL 3, training Face-on 3, validation DTL 2).
- P8 stage frames: 8 total (training DTL 3, training Face-on 3, validation DTL 2).

Media identities independently recomputed from the eight source files:

| Clip | Media SHA-256 |
|---|---|
| golfer-001-dtl-001 | `6a4f3e116f68f85ea20912f1a917e9f3bd7d527e0d733995cb5cba03e1ff0e32` |
| golfer-001-dtl-002 | `3088c3ebf3d0e88f03d2b293c0b19dd7438c83f39bd762422ce1ed1f0a6be230` |
| golfer-001-dtl-003 | `1a14208a29b0d7d2d176dd8107d106535a7cd4e573103943cb629b2829973814` |
| golfer-001-face-on-001 | `e7c85e30554c9c5a66b5bffaad3d7d069e7b1a51281bbe211e16443fb541cb68` |
| golfer-001-face-on-002 | `a58bb2f53f44980b4e013b09947b0f5250f6b93445cc210af685c4584f827450` |
| golfer-001-face-on-003 | `60bdcbda98425901ef8fbe9405cdd3debc98498a67095249548fd5a705fa8adb` |
| golfer-002-dtl-001 | `8251675efa2fc0400f1bf415ddadda2ec2dac3b03fe598c56cc24c4c590c80cc` |
| golfer-002-dtl-002 | `aa5f312d231e0eb9176df0d06eaa56c3ba9667db31986b5fadad601fd895e2d2` |

Visibility counts are `visible / occluded / out-of-frame`:

| Split / view | grip | shaftStart | shaftEnd | clubhead | ball |
|---|---:|---:|---:|---:|---:|
| training / DTL | 19 / 5 / 0 | 12 / 12 / 0 | 17 / 7 / 0 | 22 / 2 / 0 | 24 / 0 / 0 |
| training / Face-on | 24 / 0 / 0 | 24 / 0 / 0 | 13 / 1 / 10 | 13 / 0 / 11 | 19 / 0 / 5 |
| validation / DTL | 13 / 3 / 0 | 10 / 6 / 0 | 10 / 6 / 0 | 14 / 2 / 0 | 16 / 0 / 0 |
| validation / Face-on | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |

## Test suite

`.venv-golf-keypoints/bin/pytest Training/golf_keypoints -q` completed with
`117 passed, 9 warnings in 15.66s`. The warnings are PyTorch JIT tracing
deprecation notices in the existing Core ML contract tests.

## Training run

- Device: Apple Metal Performance Shaders (`mps_available=true`, `mps_built=true`)
- Architecture: `mobilenet-v3-small-fpn-heatmap-v1`
- Pretrained weights: `MobileNet_V3_Small_Weights.DEFAULT`
- Python 3.12.13; PyTorch 2.13.0; torchvision 0.28.0; macOS 27.0; arm64
- Epochs: 20 requested and 20 completed; 6 batches per epoch; 120 steps total
- Batch size: 8; learning rate: 0.0001; seed: 1729
- `maxSteps`: null; stop reason: `completed-epochs`; partial epoch: false
- Determinism mode: `seeded-best-effort`
- Elapsed wall time: 600.39 seconds
- Visibility class counts used for weighting: visible 187, occluded 27, out-of-frame 26
- Checkpoint: `Training/artifacts/golf-heatmap-v1.pt` (4.4 MiB)
- Checkpoint SHA-256: `7d30e5915c641170bdea0170a8f2bf4c3b02a4a6edfbe023b65ea6e3b069e753`
- Model-state SHA-256: `3d4d6ad64583c353b3457a1384cd689c813deaeac1385c1145ca44a895299dd7`

| Epoch | Total | Heatmap | Visibility | Shaft angle |
|---:|---:|---:|---:|---:|
| 1 | 0.526537 | 0.166243 | 1.031061 | 1.025296 |
| 2 | 0.486268 | 0.161197 | 0.922085 | 0.945500 |
| 3 | 0.443365 | 0.156045 | 0.822210 | 0.817671 |
| 4 | 0.427833 | 0.150336 | 0.784960 | 0.812572 |
| 5 | 0.395117 | 0.143335 | 0.712235 | 0.737237 |
| 6 | 0.372091 | 0.133582 | 0.700226 | 0.634526 |
| 7 | 0.325744 | 0.120834 | 0.633417 | 0.465563 |
| 8 | 0.285279 | 0.106243 | 0.618171 | 0.244931 |
| 9 | 0.270210 | 0.091536 | 0.580893 | 0.334507 |
| 10 | 0.246859 | 0.079099 | 0.586527 | 0.211280 |
| 11 | 0.227292 | 0.068883 | 0.580105 | 0.133836 |
| 12 | 0.205383 | 0.058400 | 0.547411 | 0.101307 |
| 13 | 0.194892 | 0.051664 | 0.544028 | 0.072206 |
| 14 | 0.199861 | 0.049400 | 0.568242 | 0.084012 |
| 15 | 0.188913 | 0.044568 | 0.549268 | 0.070284 |
| 16 | 0.182368 | 0.041590 | 0.546247 | 0.042160 |
| 17 | 0.186266 | 0.040507 | 0.563546 | 0.048721 |
| 18 | 0.174751 | 0.037709 | 0.531107 | 0.042652 |
| 19 | 0.171688 | 0.036921 | 0.524957 | 0.035286 |
| 20 | 0.164365 | 0.034756 | 0.501290 | 0.042868 |

## Frozen validation evaluation

- Evaluation elapsed time: 9.61 seconds
- Report: `Training/artifacts/golf-heatmap-v1-validation.json`
- Report SHA-256: `ea55d1a2ec08d16341dfcdf81647be26ecdcf0b16b5be293bb4fa16a14812b52`
- Checkpoint binding in report matches `7d30e591…e753`; model binding matches `3d4d6ad6…9dd7`.
- Samples: 16 DTL, 0 Face-on; `developmentPromotionPassed=false`.
- `paddingCoordinateCount=0` and `paddingPredictionCount=0` for every row.
- Accuracy/recall/error fields remain null because the minimum sample contracts
  are not met; this report does not infer performance from insufficient data.

All 38 failed thresholds are recorded below. For each landmark the required
minimum is 30 visible, 10 non-visible, and `denseGapSufficient=true`.

| View | Landmark | Dense gap | Visible actual / required | Non-visible actual / required |
|---|---|---:|---:|---:|
| DTL | grip | false / true | 13 / 30 | 3 / 10 |
| DTL | shaft_start | false / true | 10 / 30 | 6 / 10 |
| DTL | shaft_end | false / true | 10 / 30 | 6 / 10 |
| DTL | clubhead | false / true | 14 / 30 | 2 / 10 |
| DTL | ball | false / true | 16 / 30 | 0 / 10 |
| Face-on | grip | false / true | 0 / 30 | 0 / 10 |
| Face-on | shaft_start | false / true | 0 / 30 | 0 / 10 |
| Face-on | shaft_end | false / true | 0 / 30 | 0 / 10 |
| Face-on | clubhead | false / true | 0 / 30 | 0 / 10 |
| Face-on | ball | false / true | 0 / 30 | 0 / 10 |

Those rows account for 30 failures. The remaining eight shaft failures are:

| View | Stage | Eligible samples / required | Predicted-double-visible coverage / required |
|---|---|---:|---:|
| DTL | P6 | 0 / 30 | null / 0.95 |
| DTL | P8 | 0 / 30 | null / 0.95 |
| Face-on | P6 | 0 / 30 | null / 0.95 |
| Face-on | P8 | 0 / 30 | null / 0.95 |

## Reproduction commands

Run these commands from the repository root. The video root
`/private/tmp/SwingArc-8-videos-20260724-153013` is a machine-local temporary
dependency, not a durable repository asset. It must be retained, or the same
eight media files must be provided again with the SHA-256 identities listed
above, before reproducing this run.

The common frozen inputs used by every model command were:

```bash
set -euo pipefail

MANIFEST='/Users/liangbo/Library/Application Support/SwingArcDataset/golf-keypoints-v1/exports/golf-heatmap-full-frame-v2-c92d7c90adce28fe0e3d912089dc8ff00d1cdd2e177206b92c76040380665aad/manifest.json'
EXPECTED_FILE='Training/artifacts/golf-heatmap-v1.expected-manifest-sha256'
VIDEO_ROOT='/private/tmp/SwingArc-8-videos-20260724-153013'
EXPECTED='c92d7c90adce28fe0e3d912089dc8ff00d1cdd2e177206b92c76040380665aad'

test -s "$EXPECTED_FILE"
test "$(tr -d '[:space:]' < "$EXPECTED_FILE")" = "$EXPECTED"
test "$(shasum -a 256 "$MANIFEST" | awk '{print $1}')" = "$EXPECTED"
test -d "$VIDEO_ROOT"
```

Complete Python test suite:

```bash
set -euo pipefail
.venv-golf-keypoints/bin/pytest Training/golf_keypoints -q
```

MPS training, with explicit no-overwrite checks:

```bash
set -euo pipefail

MANIFEST='/Users/liangbo/Library/Application Support/SwingArcDataset/golf-keypoints-v1/exports/golf-heatmap-full-frame-v2-c92d7c90adce28fe0e3d912089dc8ff00d1cdd2e177206b92c76040380665aad/manifest.json'
EXPECTED='c92d7c90adce28fe0e3d912089dc8ff00d1cdd2e177206b92c76040380665aad'
VIDEO_ROOT='/private/tmp/SwingArc-8-videos-20260724-153013'
CHECKPOINT='Training/artifacts/golf-heatmap-v1.pt'
TRAIN_LOG='/private/tmp/golf-heatmap-v1-train-20260728.log'

test ! -e "$CHECKPOINT"
test ! -e "$TRAIN_LOG"
test -d "$VIDEO_ROOT"

.venv-golf-keypoints/bin/python - <<'PY'
import torch
assert torch.backends.mps.is_available()
assert torch.backends.mps.is_built()
PY

/usr/bin/time -p \
  .venv-golf-keypoints/bin/python -u Training/golf_keypoints/train.py \
  --manifest "$MANIFEST" \
  --expected-manifest-sha256 "$EXPECTED" \
  --video-root "$VIDEO_ROOT" \
  --output "$CHECKPOINT" \
  --epochs 20 \
  --batch-size 8 \
  --learning-rate 0.0001 \
  --seed 1729 \
  2>&1 | tee "$TRAIN_LOG"
```

Frozen validation evaluation, also refusing to overwrite either the report or
the captured timing log:

```bash
set -euo pipefail

MANIFEST='/Users/liangbo/Library/Application Support/SwingArcDataset/golf-keypoints-v1/exports/golf-heatmap-full-frame-v2-c92d7c90adce28fe0e3d912089dc8ff00d1cdd2e177206b92c76040380665aad/manifest.json'
EXPECTED='c92d7c90adce28fe0e3d912089dc8ff00d1cdd2e177206b92c76040380665aad'
VIDEO_ROOT='/private/tmp/SwingArc-8-videos-20260724-153013'
CHECKPOINT='Training/artifacts/golf-heatmap-v1.pt'
EVALUATION='Training/artifacts/golf-heatmap-v1-validation.json'
EVALUATE_LOG='/private/tmp/golf-heatmap-v1-evaluate-20260728.log'

test -s "$CHECKPOINT"
test ! -e "$EVALUATION"
test ! -e "$EVALUATE_LOG"
test -d "$VIDEO_ROOT"

/usr/bin/time -p \
  .venv-golf-keypoints/bin/python -u Training/golf_keypoints/evaluate.py \
  --checkpoint "$CHECKPOINT" \
  --manifest "$MANIFEST" \
  --expected-manifest-sha256 "$EXPECTED" \
  --video-root "$VIDEO_ROOT" \
  --split validation \
  --output "$EVALUATION" \
  2>&1 | tee "$EVALUATE_LOG"
```

Real Core ML export fail-closed invocation. The current CLI and README define
one `--output` export-bundle directory; there is no second parity-output
argument.

```bash
set -euo pipefail

MANIFEST='/Users/liangbo/Library/Application Support/SwingArcDataset/golf-keypoints-v1/exports/golf-heatmap-full-frame-v2-c92d7c90adce28fe0e3d912089dc8ff00d1cdd2e177206b92c76040380665aad/manifest.json'
EXPECTED='c92d7c90adce28fe0e3d912089dc8ff00d1cdd2e177206b92c76040380665aad'
VIDEO_ROOT='/private/tmp/SwingArc-8-videos-20260724-153013'
CHECKPOINT='Training/artifacts/golf-heatmap-v1.pt'
EVALUATION='Training/artifacts/golf-heatmap-v1-validation.json'
OUTPUT_BUNDLE='/private/tmp/golf-heatmap-v1-development-export-blocked-20260728'
EXPORT_STDOUT='/private/tmp/golf-heatmap-v1-export-blocked.stdout'
EXPORT_STDERR='/private/tmp/golf-heatmap-v1-export-blocked.stderr'

test -s "$CHECKPOINT"
test -s "$EVALUATION"
test ! -e "$OUTPUT_BUNDLE"
test ! -e "$EXPORT_STDOUT"
test ! -e "$EXPORT_STDERR"
test -z "$(
  find "$(dirname "$OUTPUT_BUNDLE")" -maxdepth 1 \
    -name ".$(basename "$OUTPUT_BUNDLE").staging-*" -print -quit
)"

set +e
.venv-golf-keypoints/bin/python Training/golf_keypoints/export_coreml.py \
  --checkpoint "$CHECKPOINT" \
  --evaluation "$EVALUATION" \
  --manifest "$MANIFEST" \
  --expected-manifest-sha256 "$EXPECTED" \
  --video-root "$VIDEO_ROOT" \
  --output "$OUTPUT_BUNDLE" \
  >"$EXPORT_STDOUT" 2>"$EXPORT_STDERR"
EXPORT_EXIT=$?
set -e

test "$EXPORT_EXIT" -eq 2
rg -F 'development promotion did not pass; Core ML export is blocked' \
  "$EXPORT_STDERR"
test ! -e "$OUTPUT_BUNDLE"
test -z "$(
  find "$(dirname "$OUTPUT_BUNDLE")" -maxdepth 1 \
    -name ".$(basename "$OUTPUT_BUNDLE").staging-*" -print -quit
)"
```

The expected result of the final block is exit code 2, the fail-closed error
text shown above, and no output bundle or staging directory.

## Core ML fail-closed proof

The real `export_coreml.py` CLI was invoked against this checkpoint and frozen
evaluation report. It exited with code 2 before conversion:

`development promotion did not pass; Core ML export is blocked`

No output bundle and no staging directory were created. Therefore there is no
Core ML package or parity result for this failed development candidate.

## Scope and next evidence needed

This run has no locked held-out split, no Face-on validation examples, and no
dense validation queue. It is not release evidence. Promotion requires a newly
frozen, rights-cleared dataset that independently meets every per-view,
per-landmark and P6/P8 dense gate; the current labels and this candidate must
remain immutable when that evidence is collected.

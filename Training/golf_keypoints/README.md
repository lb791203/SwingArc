# Golf keypoint training pipeline

This directory contains tooling only. Raw videos, extracted frames, checkpoints, evaluation artifacts, and failed model candidates remain outside Git.

## Label contract

`GolfHeatmapDataset` reads only an immutable resolved-export directory (or its
`manifest.json`) plus the separately supplied media root. It never opens active
App Support prediction or annotation sidecars. Callers must provide the expected
SHA-256 of `manifest.json`; the loader then verifies the referenced
`resolved-labels.json` SHA-256 before exposing a sample.

Only clips with `authorization: training-allowed`, a completed frozen revision,
and the requested golfer-level split are read. Manifest and resolved-label
identity fields must agree, including clip/golfer IDs, split, media/timeline
hashes, file name, frame count, oriented dimensions, prediction/revision IDs,
and resolved-frame count. Frame indexes must be in range and every per-frame ROI
transform must be finite, invertible, and internally consistent.
The resolved frame-index set must exactly equal the unique P1–P8 truth frame
set; synchronizing a shortened frame count in both files cannot hide a missing
stage. Manifest and resolved-label bytes are each read once, then hashed and
decoded from that same immutable in-memory buffer.

The model landmark order is:

1. `grip`
2. `shaftStart`
3. `shaftEnd`
4. `clubhead`
5. `ball`

Visible points remain in oriented full-frame coordinates. The reader recomputes
`full-frame-aspect-fit-v1`, bilinearly resizes the entire frame into the exported
integer content rectangle, and centers it on a black `512 × 512` canvas. It
never crops, stretches, clamps, or uses `annotationROITransform` for model
input. That old ROI is validated only as immutable provenance.

Visible points produce a `128 × 128` Gaussian target. Occluded and out-of-frame
points produce only three-class visibility targets. An absent landmark is
unresolved and is masked from both losses. Frames are extracted at the exported
source time with `ffmpeg`; source-file SHA-256 and oriented decode dimensions
are checked before samples are returned.

Video decode explicitly enables ffmpeg `-autorotate`. Therefore exported
`orientedWidth`/`orientedHeight` and every full-frame point refer to the
display-matrix-corrected frame, not the encoded raster. A decode whose corrected
size differs from those frozen dimensions is rejected.

Each dataset item is:

```python
(image, heatmaps, visibility_targets, coordinate_mask, metadata)
```

with shapes `[3, 512, 512]`, `[5, 128, 128]`, `[5]`, and `[5]`.

## Environment and checks

```bash
python3 -m venv .venv-golf-keypoints
.venv-golf-keypoints/bin/python -m pip install -r Training/golf_keypoints/requirements-lock.txt
.venv-golf-keypoints/bin/pytest \
  Training/golf_keypoints -q
```

## Load a frozen export

```python
from dataset import GolfHeatmapDataset

dataset = GolfHeatmapDataset(
    export_path="/path/to/export-or-manifest.json",
    video_root="/path/to/media",
    split="training",
    expected_manifest_sha256="<64 lowercase hex characters>",
)
```

## Train a development checkpoint

`train.py` consumes the five-value heatmap dataset item and requires the
out-of-band expected manifest SHA-256:

```bash
.venv-golf-keypoints/bin/python Training/golf_keypoints/train.py \
  --manifest /path/to/frozen-export/manifest.json \
  --expected-manifest-sha256 "<64 lowercase hex characters>" \
  --video-root /path/to/immutable-media \
  --output /path/to/development-candidate.pt \
  --epochs 20 \
  --batch-size 8 \
  --learning-rate 0.0001 \
  --seed 1729
```

Training automatically computes inverse-frequency three-class visibility
weights from the complete training split and refuses a split with zero examples
for any class. Heatmap supervision balances foreground and background per
visible landmark; unresolved points have no coordinate or visibility gradient.
Every non-finite loss, gradient, or updated parameter fails immediately with
the clip, source-frame, and P-stage identities for the affected batch.

The checkpoint is a development training artifact, not a promoted production
package. It stores model weights and audit metadata, but no optimizer state;
`resumeSupported` is therefore false. `--max-steps` is only a smoke-test limit
and is recorded distinctly from requested and completed epochs. A completed
epoch means the DataLoader was fully exhausted: a mid-epoch limit records
`partialEpoch=true` and `partialEpochSteps`, while `epochRecords` includes the
partial history record without inflating `completedEpochs`.

CPU training enables PyTorch deterministic algorithms. MPS is selected when
available and records `determinismMode=seeded-best-effort`: with PyTorch 2.13,
short runs using the same seed reproduced locally, but the complete MPS graph
does not support a strict deterministic-algorithms claim.

`evaluate.py` and `export_coreml.py` still implement legacy coordinate-model
stages. Do not use them with this heatmap checkpoint until Tasks 4 and 5 migrate
those commands.

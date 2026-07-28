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
  Training/golf_keypoints/test_dataset_heatmaps.py \
  Training/golf_keypoints/test_contract.py -q
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

## Legacy train and evaluate commands

`train.py`, `evaluate.py`, and Core ML export still implement the legacy
coordinate-regression stages. Tasks 2–5 replace those stages; do not use them
with the new five-value dataset item until that work is complete.

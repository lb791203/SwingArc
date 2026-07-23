# Golf keypoint training pipeline

This directory contains tooling only. Raw videos, extracted frames, checkpoints, evaluation artifacts, and failed model candidates remain outside Git.

## Label contract

Only manifest clips with `authorization: training-allowed` and the requested golfer-level split are read. Every training frame must be reviewed and contain normalized coordinates plus visibility for:

1. `grip`
2. `shaftStart`
3. `shaftEnd`
4. `clubhead`
5. `ball`

Hidden or out-of-frame points remain in the label schema but do not contribute coordinate loss. Frame extraction uses the source-frame index and source FPS through the locally installed `ffmpeg` command. Images are resized with aspect fit onto a black 256 × 256 canvas, and label coordinates are transformed into that padded model space; the iOS decoder applies the inverse transform back to full-frame normalized coordinates.

## Environment and checks

```bash
python3 -m venv .venv-golf-keypoints
.venv-golf-keypoints/bin/python -m pip install -r Training/golf_keypoints/requirements-lock.txt
.venv-golf-keypoints/bin/pytest Training/golf_keypoints/test_contract.py -q
```

## Train and evaluate

```bash
.venv-golf-keypoints/bin/python Training/golf_keypoints/train.py \
  --manifest docs/validation/precision-dataset/precision-dataset.json \
  --video-root /Users/liangbo/Desktop/test \
  --output Training/artifacts/golf_keypoints.pt

.venv-golf-keypoints/bin/python Training/golf_keypoints/evaluate.py \
  --checkpoint Training/artifacts/golf_keypoints.pt \
  --manifest docs/validation/precision-dataset/precision-dataset.json \
  --video-root /Users/liangbo/Desktop/test \
  --split validation \
  --output Training/artifacts/golf_keypoints-validation.json
```

The checkpoint stores the manifest SHA-256. Core ML export is blocked unless the matching validation report gives the clubhead a visible-frame hit rate of at least 90% at a diagonal-normalized error threshold of 0.02, with mean error no greater than 0.02.

```bash
.venv-golf-keypoints/bin/python Training/golf_keypoints/export_coreml.py \
  --checkpoint Training/artifacts/golf_keypoints.pt \
  --evaluation Training/artifacts/golf_keypoints-validation.json \
  --output Training/artifacts/GolfKeypoints.mlpackage
```

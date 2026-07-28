import hashlib
import json
import math
import subprocess
from pathlib import Path

import pytest
import torch
from PIL import Image

from contracts import (
    IGNORE_VISIBILITY,
    INPUT_TRANSFORM_VERSION,
    aspect_fit_transform,
    canvas_to_source,
    input_transform_sha256,
    source_to_canvas,
)
from dataset import (
    GolfFrameSample,
    GolfHeatmapDataset,
    ReviewedTrainingLabelsRequired,
)


ANNOTATION_ROI_TRANSFORM = {
    "a": 2.0,
    "b": 0.0,
    "c": 0.0,
    "d": 2.0,
    "tx": -0.5,
    "ty": -0.5,
    "invA": 0.5,
    "invB": 0.0,
    "invC": 0.0,
    "invD": 0.5,
    "invTx": 0.25,
    "invTy": 0.25,
}


def _json_bytes(value):
    return (
        json.dumps(value, indent=2, sort_keys=True, separators=(",", ": "))
        + "\n"
    ).encode()


def _write_export(tmp_path, *, authorization="training-allowed"):
    media_sha = "a" * 64
    timeline_sha = "b" * 64
    revision_completed_at = "2026-07-27T08:14:41Z"
    input_transform = aspect_fit_transform(180, 320)
    stage_frames = (544, 545, 546, 547, 548, 542, 543, 549)
    stages = [
        {"stage": f"P{number}", "sourceFrameIndex": frame}
        for number, frame in enumerate(stage_frames, start=1)
    ]
    labels = {
        "schemaVersion": 2,
        "datasetID": "fixture-dataset",
        "roiAlgorithmVersion": "roi-v1",
        "inputTransformVersion": INPUT_TRANSFORM_VERSION,
        "inputWidth": 512,
        "inputHeight": 512,
        "golfers": [{"golferID": "golfer-1", "split": "training"}],
        "clips": [{
            "clipID": "clip-1",
            "golferID": "golfer-1",
            "split": "training",
            "view": "dtl",
            "handedness": "right",
            "authorization": authorization,
            "fileName": "clip.mov",
            "frameCount": 600,
            "orientedWidth": 180,
            "orientedHeight": 320,
            "sourceTimescale": 600,
            "mediaSHA256": media_sha,
            "timelineSHA256": timeline_sha,
            "pPointTruthSHA256": "c" * 64,
            "predictionRunID": "prediction-1",
            "revisionID": "revision-1",
            "revisionCompletedAt": revision_completed_at,
            "trainingInputTransform": input_transform,
            "pPointTruth": stages,
            "frames": [{
                "sourceFrameIndex": 542,
                "sourceTime": 18.0666666667,
                "queueReasons": ["p6-stage"],
                "annotationROITransform": ANNOTATION_ROI_TRANSFORM,
                "landmarks": [
                    {
                        "landmark": "grip",
                        "visibility": "visible",
                        "point": {"x": 0.50, "y": 0.50},
                        "source": "corrected-point",
                    },
                    {
                        "landmark": "shaftStart",
                        "visibility": "visible",
                        "point": {"x": 0.30, "y": 0.55},
                        "source": "corrected-point",
                    },
                    {
                        "landmark": "shaftEnd",
                        "visibility": "visible",
                        "point": {"x": 0.45, "y": 0.60},
                        "source": "corrected-point",
                    },
                    {
                        "landmark": "clubhead",
                        "visibility": "occluded",
                        "point": None,
                        "source": "occluded",
                    },
                ],
            }, {
                "sourceFrameIndex": 543,
                "sourceTime": 18.1,
                "queueReasons": [],
                "annotationROITransform": ANNOTATION_ROI_TRANSFORM,
                "landmarks": [{
                    "landmark": "ball",
                    "visibility": "out-of-frame",
                    "point": None,
                    "source": "out-of-frame",
                }],
            }] + [{
                "sourceFrameIndex": frame,
                "sourceTime": frame / 30,
                "queueReasons": [],
                "annotationROITransform": ANNOTATION_ROI_TRANSFORM,
                "landmarks": [],
            } for frame in (544, 545, 546, 547, 548, 549)],
        }],
    }
    labels_data = _json_bytes(labels)
    (tmp_path / "resolved-labels.json").write_bytes(labels_data)
    manifest = {
        "schemaVersion": 2,
        "datasetID": "fixture-dataset",
        "roiAlgorithmVersion": "roi-v1",
        "inputTransformVersion": INPUT_TRANSFORM_VERSION,
        "inputWidth": 512,
        "inputHeight": 512,
        "resolvedLabelsFile": "resolved-labels.json",
        "resolvedLabelsSHA256": hashlib.sha256(labels_data).hexdigest(),
        "clips": [{
            "clipID": "clip-1",
            "golferID": "golfer-1",
            "split": "training",
            "view": "dtl",
            "handedness": "right",
            "predictionRunID": "prediction-1",
            "revisionID": "revision-1",
            "revisionCompletedAt": revision_completed_at,
            "authorization": authorization,
            "fileName": "clip.mov",
            "frameCount": 600,
            "orientedWidth": 180,
            "orientedHeight": 320,
            "sourceTimescale": 600,
            "mediaSHA256": media_sha,
            "timelineSHA256": timeline_sha,
            "pPointTruthSHA256": "c" * 64,
            "predictionProvenanceHash": "d" * 64,
            "resolvedFrameCount": 8,
            "trainingInputTransformSHA256":
                input_transform_sha256(input_transform),
        }],
    }
    manifest_data = _json_bytes(manifest)
    (tmp_path / "manifest.json").write_bytes(manifest_data)
    return hashlib.sha256(manifest_data).hexdigest()


def _rewrite_documents(tmp_path, mutate_labels=None, mutate_manifest=None):
    labels_path = tmp_path / "resolved-labels.json"
    manifest_path = tmp_path / "manifest.json"
    labels = json.loads(labels_path.read_text())
    manifest = json.loads(manifest_path.read_text())
    if mutate_labels:
        mutate_labels(labels)
    labels_data = _json_bytes(labels)
    labels_path.write_bytes(labels_data)
    manifest["resolvedLabelsSHA256"] = hashlib.sha256(labels_data).hexdigest()
    if mutate_manifest:
        mutate_manifest(manifest)
    manifest_data = _json_bytes(manifest)
    manifest_path.write_bytes(manifest_data)
    return hashlib.sha256(manifest_data).hexdigest()


def _fixture_image(_sample):
    return Image.new("RGB", (180, 320), (255, 0, 0))


def test_visible_and_hidden_landmarks_generate_full_frame_targets(tmp_path):
    manifest_sha = _write_export(tmp_path)
    dataset = GolfHeatmapDataset(
        export_path=tmp_path,
        video_root=tmp_path,
        split="training",
        expected_manifest_sha256=manifest_sha,
        image_loader=_fixture_image,
    )

    image, heatmaps, visibility, coordinate_mask, metadata = dataset[0]
    assert image.shape == (3, 512, 512)
    assert heatmaps.shape == (5, 128, 128)
    assert visibility.shape == (5,)
    assert coordinate_mask.tolist() == [True, True, True, False, False]
    assert visibility.tolist() == [0, 0, 0, 1, IGNORE_VISIBILITY]
    assert metadata["view"] == "dtl"
    assert metadata["source_frame_index"] == 542
    assert metadata["stage_codes"] == ["P6"]
    assert metadata["input_transform_version"] == INPUT_TRANSFORM_VERSION
    assert metadata["content_rect"] == {
        "width": 288,
        "height": 512,
        "offset_x": 112,
        "offset_y": 0,
    }
    # A full-frame midpoint remains the canvas midpoint. The deliberately
    # non-identity annotation ROI would instead map it to another audit space.
    peak_yx = torch.nonzero(
        heatmaps[0] == heatmaps[0].max(), as_tuple=False
    )[0]
    peak_xy = peak_yx.flip(0).float() / 127
    assert torch.allclose(peak_xy, torch.tensor([0.5, 0.5]), atol=1 / 127)
    assert metadata["canvas_points"]["grip"] == {"x": 0.5, "y": 0.5}
    assert heatmaps[3].sum().item() == 0
    assert heatmaps[4].sum().item() == 0
    # Portrait content is red and both horizontal bars remain pure black.
    assert torch.equal(image[:, 256, 111], torch.zeros(3))
    assert torch.equal(image[:, 256, 112], torch.tensor([1.0, 0.0, 0.0]))
    assert torch.equal(image[:, 256, 399], torch.tensor([1.0, 0.0, 0.0]))
    assert torch.equal(image[:, 256, 400], torch.zeros(3))

    _, hidden_heatmaps, hidden_visibility, hidden_mask, _ = dataset[1]
    assert hidden_visibility.tolist()[-1] == 2
    assert not hidden_mask[-1]
    assert hidden_heatmaps[-1].sum().item() == 0


@pytest.mark.parametrize(
    ("width", "height", "expected"),
    [
        (1080, 1920, (288, 512, 112, 0)),
        (1920, 1080, (512, 288, 0, 112)),
        (511, 511, (512, 512, 0, 0)),
        (1001, 777, (512, 397, 0, 57)),
        (777, 1001, (397, 512, 57, 0)),
        (2048, 1, (512, 1, 0, 255)),
        (1, 2048, (1, 512, 255, 0)),
        (1025, 1, (512, 1, 0, 255)),
    ],
)
def test_aspect_fit_golden_fixtures_and_round_trip(
    width, height, expected
):
    transform = aspect_fit_transform(width, height)
    assert (
        transform["contentWidth"],
        transform["contentHeight"],
        transform["offsetX"],
        transform["offsetY"],
    ) == expected
    assert all(
        math.isfinite(value)
        for direction in ("forward", "inverse")
        for value in transform[direction].values()
    )
    for source_x, source_y in ((0, 0), (1, 1), (0.37, 0.61)):
        canvas = source_to_canvas(source_x, source_y, transform)
        round_trip = canvas_to_source(*canvas, transform)
        assert abs(round_trip[0] - source_x) <= 1e-9
        assert abs(round_trip[1] - source_y) <= 1e-9


def test_hashes_and_cross_file_identity_are_mandatory(tmp_path):
    manifest_sha = _write_export(tmp_path)
    with pytest.raises(ReviewedTrainingLabelsRequired, match="manifest SHA-256"):
        GolfHeatmapDataset(
            tmp_path,
            tmp_path,
            "training",
            expected_manifest_sha256="0" * 64,
            image_loader=_fixture_image,
        )

    labels_path = tmp_path / "resolved-labels.json"
    labels_path.write_bytes(labels_path.read_bytes() + b" ")
    with pytest.raises(
        ReviewedTrainingLabelsRequired, match="resolved labels SHA-256"
    ):
        GolfHeatmapDataset(
            tmp_path,
            tmp_path,
            "training",
            expected_manifest_sha256=manifest_sha,
            image_loader=_fixture_image,
        )

    _write_export(tmp_path)
    changed_sha = _rewrite_documents(
        tmp_path,
        mutate_manifest=lambda value:
            value["clips"][0].update({"timelineSHA256": "e" * 64}),
    )
    with pytest.raises(ReviewedTrainingLabelsRequired, match="identity mismatch"):
        GolfHeatmapDataset(
            tmp_path,
            tmp_path,
            "training",
            expected_manifest_sha256=changed_sha,
            image_loader=_fixture_image,
        )


def test_recomputed_input_and_annotation_transforms_are_mandatory(tmp_path):
    _write_export(tmp_path)
    changed_sha = _rewrite_documents(
        tmp_path,
        mutate_labels=lambda value:
            value["clips"][0]["trainingInputTransform"].update(
                {"contentWidth": 287}
            ),
    )
    with pytest.raises(
        ReviewedTrainingLabelsRequired, match="contentWidth mismatch"
    ):
        GolfHeatmapDataset(
            tmp_path,
            tmp_path,
            "training",
            expected_manifest_sha256=changed_sha,
            image_loader=_fixture_image,
        )

    _write_export(tmp_path)
    changed_sha = _rewrite_documents(
        tmp_path,
        mutate_labels=lambda value:
            value["clips"][0]["frames"][0]["annotationROITransform"].update(
                {"invTx": 0.20}
            ),
    )
    with pytest.raises(
        ReviewedTrainingLabelsRequired, match="inverse is inconsistent"
    ):
        GolfHeatmapDataset(
            tmp_path,
            tmp_path,
            "training",
            expected_manifest_sha256=changed_sha,
            image_loader=_fixture_image,
        )


def test_resolved_frames_must_exactly_match_p1_p8_truth(tmp_path):
    _write_export(tmp_path)

    def remove_p6(labels):
        frames = labels["clips"][0]["frames"]
        labels["clips"][0]["frames"] = [
            frame for frame in frames
            if frame["sourceFrameIndex"] != 542
        ]

    changed_sha = _rewrite_documents(
        tmp_path,
        mutate_labels=remove_p6,
        mutate_manifest=lambda value:
            value["clips"][0].update({"resolvedFrameCount": 7}),
    )
    with pytest.raises(
        ReviewedTrainingLabelsRequired,
        match="resolved frame set does not match P1-P8 truth",
    ):
        GolfHeatmapDataset(
            tmp_path,
            tmp_path,
            "training",
            expected_manifest_sha256=changed_sha,
            image_loader=_fixture_image,
        )


def test_manifest_and_labels_use_one_buffer_each(monkeypatch, tmp_path):
    manifest_sha = _write_export(tmp_path)
    original_read_bytes = Path.read_bytes
    reads = {}

    def tracked_read_bytes(path):
        resolved = path.resolve()
        reads[resolved] = reads.get(resolved, 0) + 1
        if reads[resolved] > 1:
            raise AssertionError(f"{resolved} was read more than once")
        return original_read_bytes(path)

    monkeypatch.setattr(Path, "read_bytes", tracked_read_bytes)
    dataset = GolfHeatmapDataset(
        tmp_path,
        tmp_path,
        "training",
        expected_manifest_sha256=manifest_sha,
        image_loader=_fixture_image,
    )
    assert len(dataset) == 8
    assert reads[(tmp_path / "manifest.json").resolve()] == 1
    assert reads[(tmp_path / "resolved-labels.json").resolve()] == 1


def test_ffmpeg_autorotates_display_matrix_and_preserves_corner_identity(
    tmp_path,
):
    source_path = tmp_path / "source.png"
    source = Image.new("RGB", (32, 16))
    colors = {
        "top_left": (255, 0, 0),
        "top_right": (0, 255, 0),
        "bottom_left": (0, 0, 255),
        "bottom_right": (255, 255, 0),
    }
    for y in range(source.height):
        for x in range(source.width):
            if y < source.height // 2:
                color = (
                    colors["top_left"]
                    if x < source.width // 2
                    else colors["top_right"]
                )
            else:
                color = (
                    colors["bottom_left"]
                    if x < source.width // 2
                    else colors["bottom_right"]
                )
            source.putpixel((x, y), color)
    source.save(source_path)

    base_video = tmp_path / "base.mov"
    rotated_video = tmp_path / "rotated.mov"
    subprocess.run([
        "ffmpeg", "-v", "error", "-loop", "1", "-i", str(source_path),
        "-t", "1", "-c:v", "png", str(base_video),
    ], check=True)
    subprocess.run([
        "ffmpeg", "-v", "error",
        "-display_rotation:v:0", "90",
        "-i", str(base_video),
        "-c", "copy",
        str(rotated_video),
    ], check=True)
    probe = json.loads(subprocess.run([
        "ffprobe", "-v", "error",
        "-show_entries", "stream=width,height:stream_side_data",
        "-of", "json", str(rotated_video),
    ], check=True, capture_output=True).stdout)
    assert probe["streams"][0]["width"] == 32
    assert probe["streams"][0]["height"] == 16
    assert probe["streams"][0]["side_data_list"][0]["rotation"] == 90

    transform = aspect_fit_transform(16, 32)
    sample = GolfFrameSample(
        clip_id="orientation-golden",
        golfer_id="golfer-golden",
        video_path=rotated_video,
        media_sha256=hashlib.sha256(rotated_video.read_bytes()).hexdigest(),
        source_frame_index=0,
        source_time=0.0,
        oriented_width=16,
        oriented_height=32,
        view="dtl",
        handedness="right",
        stage_codes=("P1",),
        queue_reasons=(),
        annotation_roi_transform=ANNOTATION_ROI_TRANSFORM,
        training_input_transform=transform,
        landmarks={},
    )
    loader = object.__new__(GolfHeatmapDataset)
    loader._verified_media = set()
    decoded = loader._load_video_frame(sample)
    assert decoded.size == (16, 32)
    # A +90° display matrix is counter-clockwise in ffmpeg's contract.
    assert decoded.getpixel((2, 2)) == colors["top_right"]
    assert decoded.getpixel((13, 2)) == colors["bottom_right"]
    assert decoded.getpixel((2, 29)) == colors["top_left"]
    assert decoded.getpixel((13, 29)) == colors["bottom_left"]

    canvas = loader._render_full_frame(decoded, transform)
    assert canvas.size == (512, 512)
    assert canvas.getpixel((transform["offsetX"] + 4, 4)) == colors["top_right"]
    assert source_to_canvas(0.0, 0.0, transform) == (
        transform["offsetX"] / 512,
        0.0,
    )


def test_bounds_decode_size_and_authorization_are_enforced(tmp_path):
    _write_export(tmp_path)
    changed_sha = _rewrite_documents(
        tmp_path,
        mutate_labels=lambda value:
            value["clips"][0]["frames"][0].update(
                {"sourceFrameIndex": 600}
            ),
    )
    with pytest.raises(ReviewedTrainingLabelsRequired, match="out of range"):
        GolfHeatmapDataset(
            tmp_path,
            tmp_path,
            "training",
            expected_manifest_sha256=changed_sha,
            image_loader=_fixture_image,
        )

    _write_export(tmp_path, authorization="internal-review")
    with pytest.raises(ReviewedTrainingLabelsRequired, match="training-allowed"):
        GolfHeatmapDataset(
            tmp_path,
            tmp_path,
            "training",
            expected_manifest_sha256=hashlib.sha256(
                (tmp_path / "manifest.json").read_bytes()
            ).hexdigest(),
            image_loader=_fixture_image,
        )

    manifest_sha = _write_export(tmp_path)
    dataset = GolfHeatmapDataset(
        tmp_path,
        tmp_path,
        "training",
        expected_manifest_sha256=manifest_sha,
        image_loader=lambda _sample: Image.new("RGB", (181, 320)),
    )
    with pytest.raises(ReviewedTrainingLabelsRequired, match="decoded size"):
        dataset[0]


def test_visible_points_are_rejected_not_clamped(tmp_path):
    _write_export(tmp_path)
    changed_sha = _rewrite_documents(
        tmp_path,
        mutate_labels=lambda value:
            value["clips"][0]["frames"][0]["landmarks"][0]["point"].update(
                {"x": 1.001}
            ),
    )
    with pytest.raises(
        ReviewedTrainingLabelsRequired, match="full-frame visible point"
    ):
        GolfHeatmapDataset(
            tmp_path,
            tmp_path,
            "training",
            expected_manifest_sha256=changed_sha,
            image_loader=_fixture_image,
        )

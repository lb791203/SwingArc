import math
from types import SimpleNamespace

import pytest
import torch
from torch import nn
from torch.utils.data import Dataset

from contracts import (
    HEATMAP_SIZE,
    INPUT_SIZE,
    INPUT_TRANSFORM_VERSION,
    LANDMARK_NAMES,
    MANIFEST_NAMES,
    VISIBILITY_NAMES,
)
from evaluate import (
    ARCHITECTURE,
    build_argument_parser,
    build_evaluation_report,
    evaluate_model,
    promotion_passed,
    validate_checkpoint_contract,
)
from metrics import (
    canvas_point_is_in_content_rect,
    circular_angle_error_degrees,
    dense_longest_visible_gap,
    deterministic_percentile,
    shaft_angle_degrees,
)


VISIBLE_SAMPLE_COUNT = 100
NONVISIBLE_SAMPLE_COUNT = 100


def _visibility_logits(predicted_class):
    logits = torch.full(
        (len(LANDMARK_NAMES), len(VISIBILITY_NAMES)),
        -8.0,
    )
    for landmark_index, class_index in enumerate(predicted_class):
        logits[landmark_index, class_index] = 8.0
    return logits


def _perfect_batches():
    batches = []
    for view_index, view in enumerate(("dtl", "face-on")):
        predicted_coordinates = []
        visibility_targets = []
        visibility_logits = []
        metadata = []
        for frame_index in range(
            VISIBLE_SAMPLE_COUNT + NONVISIBLE_SAMPLE_COUNT
        ):
            true_visible = frame_index < VISIBLE_SAMPLE_COUNT
            target_visibility = [0 if true_visible else 1] * len(LANDMARK_NAMES)
            predicted_class = list(target_visibility)
            points = []
            canvas_points = {}
            for landmark_index, model_name in enumerate(LANDMARK_NAMES):
                point = {
                    "x": 0.20 + 0.10 * landmark_index,
                    "y": 0.25 + 0.05 * landmark_index,
                }
                points.append([point["x"], point["y"]])
                if true_visible:
                    canvas_points[MANIFEST_NAMES[model_name]] = point
            predicted_coordinates.append(points)
            visibility_targets.append(target_visibility)
            visibility_logits.append(_visibility_logits(predicted_class))
            metadata.append({
                "clip_id": f"{view}-clip",
                "view": view,
                "source_frame_index": frame_index,
                "stage_codes": ["P6" if frame_index % 2 == 0 else "P8"],
                "queue_reasons": ["validation-dense"],
                "input_transform_version": INPUT_TRANSFORM_VERSION,
                "source_oriented_width": 1000 + view_index * 200,
                "source_oriented_height": 1000,
                "content_rect": {
                    "width": 512,
                    "height": 512,
                    "offset_x": 0,
                    "offset_y": 0,
                },
                "canvas_points": canvas_points,
            })
        batches.append({
            "predicted_canvas_coordinates": torch.tensor(
                predicted_coordinates, dtype=torch.float32
            ),
            "visibility_targets": torch.tensor(
                visibility_targets, dtype=torch.long
            ),
            "predicted_visibility_logits": torch.stack(visibility_logits),
            "metadata": metadata,
        })
    return batches


def _set_predicted_visibility(
    batches,
    *,
    view,
    landmark,
    frame_indexes,
    class_index,
):
    landmark_index = LANDMARK_NAMES.index(landmark)
    batch = next(
        item for item in batches if item["metadata"][0]["view"] == view
    )
    for frame_index in frame_indexes:
        batch["predicted_visibility_logits"][
            frame_index, landmark_index
        ] = -8.0
        batch["predicted_visibility_logits"][
            frame_index, landmark_index, class_index
        ] = 8.0


def test_perfect_gate_matrix_passes_every_landmark_and_view():
    report = build_evaluation_report(
        _perfect_batches(), split="validation"
    )

    for view in ("dtl", "face-on"):
        for landmark in LANDMARK_NAMES:
            row = report["views"][view]["landmarks"][landmark]
            assert row["trueVisibleCount"] == VISIBLE_SAMPLE_COUNT
            assert row["trueNonVisibleCount"] == NONVISIBLE_SAMPLE_COUNT
            assert row["visibleFrameHitRate"] == 1.0
            assert row["medianSourcePixelError"] == 0.0
            assert row["p90SourcePixelError"] == 0.0
            assert row["medianDiagonalNormalizedError"] == 0.0
            assert row["p90DiagonalNormalizedError"] == 0.0
            assert row["visibleRecall"] == 1.0
            assert row["falseVisibleRate"] == 0.0
            assert row["longestVisibleGap"] == 0
            assert row["denseGapSufficient"] is True
            assert row["sufficientSamples"] is True
    assert report["developmentPromotionPassed"] is True
    assert promotion_passed(report) is True
    assert report["failedThresholds"] == []


@pytest.mark.parametrize(
    ("landmark", "mutation", "metric"),
    [
        (
            "grip",
            lambda batches: _set_predicted_visibility(
                batches,
                view="dtl",
                landmark="grip",
                frame_indexes=range(11),
                class_index=1,
            ),
            "visibleFrameHitRate",
        ),
        (
            "ball",
            lambda batches: _set_predicted_visibility(
                batches,
                view="dtl",
                landmark="ball",
                frame_indexes=range(6),
                class_index=1,
            ),
            "visibleRecall",
        ),
        (
            "shaft_end",
            lambda batches: _set_predicted_visibility(
                batches,
                view="dtl",
                landmark="shaft_end",
                frame_indexes=range(
                    VISIBLE_SAMPLE_COUNT,
                    VISIBLE_SAMPLE_COUNT + 6,
                ),
                class_index=0,
            ),
            "falseVisibleRate",
        ),
        (
            "clubhead",
            lambda batches: _set_predicted_visibility(
                batches,
                view="dtl",
                landmark="clubhead",
                frame_indexes=(10, 11, 12),
                class_index=1,
            ),
            "longestVisibleGap",
        ),
    ],
)
def test_one_failed_landmark_row_cannot_be_rescued_by_averages(
    landmark,
    mutation,
    metric,
):
    batches = _perfect_batches()
    mutation(batches)

    report = build_evaluation_report(batches, split="validation")

    assert report["developmentPromotionPassed"] is False
    assert promotion_passed(report) is False
    assert any(
        failure.get("view") == "dtl"
        and failure.get("landmark") == landmark
        and failure["metric"] == metric
        for failure in report["failedThresholds"]
    )


def test_shaft_p90_of_7_point_1_degrees_fails_its_own_gate():
    batches = _perfect_batches()
    dtl = batches[0]
    shaft_start_index = LANDMARK_NAMES.index("shaft_start")
    shaft_end_index = LANDMARK_NAMES.index("shaft_end")
    for frame_index in (0, 2, 4, 6, 8, 10):
        start = dtl["predicted_canvas_coordinates"][
            frame_index, shaft_start_index
        ]
        length = 0.10
        angle = math.radians(7.1)
        dtl["predicted_canvas_coordinates"][
            frame_index, shaft_end_index
        ] = torch.tensor([
            start[0] + length * math.cos(angle),
            start[1] + length * math.sin(angle),
        ])
        target_start = dtl["metadata"][frame_index]["canvas_points"]["shaftStart"]
        dtl["metadata"][frame_index]["canvas_points"]["shaftEnd"] = {
            "x": target_start["x"] + length,
            "y": target_start["y"],
        }

    report = build_evaluation_report(batches, split="validation")

    p6 = report["views"]["dtl"]["shaftAngles"]["P6"]
    assert p6["medianCircularErrorDegrees"] == pytest.approx(0.0)
    assert p6["p90CircularErrorDegrees"] == pytest.approx(7.1, abs=1e-3)
    assert report["developmentPromotionPassed"] is False
    assert any(
        failure.get("view") == "dtl"
        and failure.get("stage") == "P6"
        and failure["metric"] == "p90CircularErrorDegrees"
        for failure in report["failedThresholds"]
    )


def test_missing_view_is_explicitly_insufficient_and_cannot_promote():
    report = build_evaluation_report(
        [_perfect_batches()[0]], split="validation"
    )

    row = report["views"]["face-on"]["landmarks"]["grip"]
    assert row["trueVisibleCount"] == 0
    assert row["trueNonVisibleCount"] == 0
    assert row["visibleFrameHitRate"] is None
    assert row["medianDiagonalNormalizedError"] is None
    assert row["p90DiagonalNormalizedError"] is None
    assert row["visibleRecall"] is None
    assert row["falseVisibleRate"] is None
    assert row["longestVisibleGap"] is None
    assert row["sufficientSamples"] is False
    assert report["viewSampleCounts"]["face-on"] == 0
    assert report["developmentPromotionPassed"] is False


def test_insufficient_counts_null_all_derived_metrics():
    batches = _perfect_batches()
    dtl = batches[0]
    keep = list(range(29)) + list(
        range(VISIBLE_SAMPLE_COUNT, VISIBLE_SAMPLE_COUNT + 9)
    )
    for field in (
        "predicted_canvas_coordinates",
        "visibility_targets",
        "predicted_visibility_logits",
    ):
        dtl[field] = dtl[field][keep]
    dtl["metadata"] = [dtl["metadata"][index] for index in keep]

    report = build_evaluation_report(batches, split="validation")

    row = report["views"]["dtl"]["landmarks"]["ball"]
    assert row["trueVisibleCount"] == 29
    assert row["trueNonVisibleCount"] == 9
    assert row["sufficientSamples"] is False
    for metric in (
        "visibleFrameHitRate",
        "medianDiagonalNormalizedError",
        "p90DiagonalNormalizedError",
        "visibleRecall",
        "falseVisibleRate",
        "longestVisibleGap",
    ):
        assert row[metric] is None
    assert report["developmentPromotionPassed"] is False


def test_metric_primitives_are_deterministic_and_clip_aware():
    values = torch.tensor([0.0] * 8 + [7.1] * 2)
    assert deterministic_percentile(values, 90) == pytest.approx(7.1)
    angles = shaft_angle_degrees(
        torch.tensor([[0.0, 0.0]]),
        torch.tensor([[0.0, 1.0]]),
    )
    assert angles.item() == pytest.approx(90.0)
    error = circular_angle_error_degrees(
        torch.tensor([179.0]),
        torch.tensor([-179.0]),
    )
    assert error.item() == pytest.approx(2.0)


def test_portrait_content_rect_closed_boundary_rejects_black_padding():
    metadata = {
        "input_transform_version": INPUT_TRANSFORM_VERSION,
        "content_rect": {
            "width": 288,
            "height": 512,
            "offset_x": 112,
            "offset_y": 0,
        },
    }
    boundary_x = 112 / 512
    assert canvas_point_is_in_content_rect(
        [boundary_x - 1e-9 / 512, 0.5], metadata
    )
    assert not canvas_point_is_in_content_rect(
        [boundary_x - 1.1e-9 / 512, 0.5], metadata
    )

    batches = _perfect_batches()
    dtl = batches[0]
    for item in dtl["metadata"]:
        item["source_oriented_width"] = 900
        item["source_oriented_height"] = 1600
        item["content_rect"] = metadata["content_rect"]
        for point in item["canvas_points"].values():
            point["x"] = 0.30 + point["x"] * 0.40
    dtl["predicted_canvas_coordinates"][:, :, 0] = (
        0.30 + dtl["predicted_canvas_coordinates"][:, :, 0] * 0.40
    )
    dtl["predicted_canvas_coordinates"][0, 0] = torch.tensor([0.0, 0.5])

    report = build_evaluation_report(batches, split="validation")

    grip = report["views"]["dtl"]["landmarks"]["grip"]
    assert grip["paddingCoordinateCount"] == 1
    assert grip["paddingPredictionCount"] == 1
    assert grip["paddingPredictionRate"] == pytest.approx(0.01)
    assert grip["visibleFrameHitRate"] == pytest.approx(0.99)
    assert grip["medianSourcePixelError"] is None
    assert grip["p90SourcePixelError"] is None
    assert grip["medianDiagonalNormalizedError"] is None
    assert grip["p90DiagonalNormalizedError"] is None
    assert any(
        failure["metric"] == "paddingPredictionRate"
        and failure.get("landmark") == "grip"
        for failure in report["failedThresholds"]
    )
    assert report["developmentPromotionPassed"] is False


def test_dense_gap_rejects_sparse_stage_indexes_and_respects_resets():
    sparse = [
        ("clip-a", 10, True, True, True),
        ("clip-a", 20, True, True, True),
        ("clip-a", 30, True, True, True),
    ]
    assert dense_longest_visible_gap(sparse) == (None, False, 3)

    continuous = [
        ("clip-a", 10, True, True, True),
        ("clip-a", 11, True, True, True),
        ("clip-a", 12, True, True, True),
    ]
    assert dense_longest_visible_gap(continuous) == (3, True, 3)
    all_nonvisible = [
        ("clip-a", 10, False, False, True),
        ("clip-a", 11, False, False, True),
        ("clip-a", 12, False, False, True),
    ]
    assert dense_longest_visible_gap(all_nonvisible) == (
        None,
        False,
        3,
    )

    reset_and_clip_boundary = [
        ("clip-a", 10, True, True, True),
        ("clip-a", 11, True, True, True),
        ("clip-a", 12, False, False, True),
        ("clip-a", 13, True, True, True),
        ("clip-b", 1, True, True, True),
        ("clip-b", 2, True, True, True),
        ("clip-b", 3, True, False, True),
    ]
    assert dense_longest_visible_gap(reset_and_clip_boundary) == (
        2,
        True,
        7,
    )


def test_sparse_p_point_observations_never_claim_a_three_frame_gap():
    batches = _perfect_batches()
    for metadata in batches[0]["metadata"]:
        metadata["queue_reasons"] = ["p-point-first-pass"]
    _set_predicted_visibility(
        batches,
        view="dtl",
        landmark="clubhead",
        frame_indexes=(10, 11, 12),
        class_index=1,
    )

    report = build_evaluation_report(batches, split="validation")

    row = report["views"]["dtl"]["landmarks"]["clubhead"]
    assert row["longestVisibleGap"] is None
    assert row["denseGapSufficient"] is False
    assert any(
        failure["metric"] == "denseGapSufficient"
        and failure.get("landmark") == "clubhead"
        for failure in report["failedThresholds"]
    )


def _set_stage_eligibility(batches, view, stage, eligible_count):
    batch = next(
        item for item in batches if item["metadata"][0]["view"] == view
    )
    for index, metadata in enumerate(batch["metadata"]):
        metadata["stage_codes"] = [stage] if index < eligible_count else []


def test_shaft_coverage_uses_true_double_visible_denominator():
    batches = _perfect_batches()
    _set_stage_eligibility(batches, "dtl", "P6", 5)
    _set_predicted_visibility(
        batches,
        view="dtl",
        landmark="shaft_end",
        frame_indexes=(1, 2, 3, 4),
        class_index=1,
    )

    report = build_evaluation_report(batches, split="validation")

    row = report["views"]["dtl"]["shaftAngles"]["P6"]
    assert row["eligibleFrameCount"] == 5
    assert row["predictedDoubleVisibleCount"] == 1
    assert row["predictedDoubleVisibleCoverage"] == pytest.approx(0.2)
    assert row["medianCircularErrorDegrees"] is None
    assert row["p90CircularErrorDegrees"] is None
    metrics = {
        failure["metric"]
        for failure in report["failedThresholds"]
        if failure.get("view") == "dtl"
        and failure.get("stage") == "P6"
    }
    assert metrics == {
        "minimumShaftSamples",
        "predictedDoubleVisibleCoverage",
    }


def test_shaft_one_sample_is_insufficient_but_thirty_perfect_pass():
    one = _perfect_batches()
    _set_stage_eligibility(one, "dtl", "P6", 1)
    one_report = build_evaluation_report(one, split="validation")
    one_row = one_report["views"]["dtl"]["shaftAngles"]["P6"]
    assert one_row["eligibleFrameCount"] == 1
    assert one_row["sufficientSamples"] is False
    assert one_row["medianCircularErrorDegrees"] is None

    thirty = _perfect_batches()
    _set_stage_eligibility(thirty, "dtl", "P6", 30)
    thirty_report = build_evaluation_report(thirty, split="validation")
    row = thirty_report["views"]["dtl"]["shaftAngles"]["P6"]
    assert row["eligibleFrameCount"] == 30
    assert row["predictedDoubleVisibleCount"] == 30
    assert row["predictedDoubleVisibleCoverage"] == 1.0
    assert row["medianCircularErrorDegrees"] == 0.0
    assert row["p90CircularErrorDegrees"] == 0.0
    assert not any(
        failure.get("view") == "dtl"
        and failure.get("stage") == "P6"
        for failure in thirty_report["failedThresholds"]
    )


def test_zero_length_predicted_shaft_is_invalid_not_a_success():
    batches = _perfect_batches()
    _set_stage_eligibility(batches, "dtl", "P6", 30)
    dtl = batches[0]
    start_index = LANDMARK_NAMES.index("shaft_start")
    end_index = LANDMARK_NAMES.index("shaft_end")
    dtl["predicted_canvas_coordinates"][0, end_index] = (
        dtl["predicted_canvas_coordinates"][0, start_index]
    )

    report = build_evaluation_report(batches, split="validation")

    row = report["views"]["dtl"]["shaftAngles"]["P6"]
    assert row["invalidGeometryCount"] == 1
    assert row["medianCircularErrorDegrees"] is None
    assert row["p90CircularErrorDegrees"] is None
    assert any(
        failure["metric"] == "invalidShaftGeometryCount"
        for failure in report["failedThresholds"]
        if failure.get("view") == "dtl"
        and failure.get("stage") == "P6"
    )


def test_training_split_cannot_promote_at_pure_report_layer():
    report = build_evaluation_report(_perfect_batches(), split="training")
    assert report["split"] == "training"
    assert report["developmentPromotionPassed"] is False
    assert promotion_passed(report) is False
    assert any(
        failure["metric"] == "requiredSplit"
        for failure in report["failedThresholds"]
    )


class _OneSampleEvaluationDataset(Dataset):
    split = "training"
    samples = [
        SimpleNamespace(
            clip_id="dtl-clip",
            source_frame_index=0,
            oriented_width=1000,
            oriented_height=1000,
        )
    ]

    def __len__(self):
        return 1

    def __getitem__(self, _index):
        metadata = dict(_perfect_batches()[0]["metadata"][0])
        metadata.pop("source_oriented_width")
        metadata.pop("source_oriented_height")
        image = torch.zeros(3, INPUT_SIZE, INPUT_SIZE)
        heatmaps = torch.zeros(
            len(LANDMARK_NAMES), HEATMAP_SIZE, HEATMAP_SIZE
        )
        visibility = torch.zeros(len(LANDMARK_NAMES), dtype=torch.long)
        coordinate_mask = torch.ones(
            len(LANDMARK_NAMES), dtype=torch.bool
        )
        return image, heatmaps, visibility, coordinate_mask, metadata


class _DeterministicEvaluationModel(nn.Module):
    def forward(self, images):
        batch_size = images.shape[0]
        heatmaps = torch.zeros(
            batch_size,
            len(LANDMARK_NAMES),
            HEATMAP_SIZE,
            HEATMAP_SIZE,
        )
        heatmaps[:, :, 32, 32] = 1.0
        visibility = torch.full(
            (
                batch_size,
                len(LANDMARK_NAMES),
                len(VISIBILITY_NAMES),
            ),
            -8.0,
        )
        visibility[:, :, 0] = 8.0
        return heatmaps, visibility


def test_evaluate_model_collates_five_tuple_and_binds_dataset_split():
    report = evaluate_model(
        _DeterministicEvaluationModel(),
        _OneSampleEvaluationDataset(),
        batch_size=1,
    )
    assert report["sampleCount"] == 1
    assert report["split"] == "training"
    assert report["developmentPromotionPassed"] is False
    assert any(
        failure["metric"] == "requiredSplit"
        for failure in report["failedThresholds"]
    )


def test_evaluate_model_rejects_runtime_output_shape_drift():
    class BadShapeModel(_DeterministicEvaluationModel):
        def forward(self, images):
            heatmaps, visibility = super().forward(images)
            return heatmaps[:, :, :64, :64], visibility

    with pytest.raises(ValueError, match="heatmap output shape"):
        evaluate_model(
            BadShapeModel(),
            _OneSampleEvaluationDataset(),
            batch_size=1,
        )


def test_cli_requires_expected_manifest_sha256():
    parser = build_argument_parser()
    required = [
        "--checkpoint", "candidate.pt",
        "--manifest", "manifest.json",
        "--video-root", "videos",
        "--output", "report.json",
    ]
    with pytest.raises(SystemExit):
        parser.parse_args(required)

    args = parser.parse_args(
        required + ["--expected-manifest-sha256", "a" * 64]
    )
    assert args.expected_manifest_sha256 == "a" * 64
    assert args.split == "validation"


def _valid_checkpoint():
    return {
        "artifactKind": "development-training-checkpoint",
        "architecture": ARCHITECTURE,
        "manifestSHA256": "a" * 64,
        "inputTransformVersion": INPUT_TRANSFORM_VERSION,
        "landmarks": list(LANDMARK_NAMES),
        "visibilityClasses": list(VISIBILITY_NAMES),
        "inputSize": INPUT_SIZE,
        "heatmapSize": HEATMAP_SIZE,
        "model": {"weight": torch.tensor([1.0])},
    }


@pytest.mark.parametrize(
    ("field", "invalid"),
    [
        ("manifestSHA256", "b" * 64),
        ("inputTransformVersion", "roi-v1"),
        ("landmarks", list(reversed(LANDMARK_NAMES))),
        ("visibilityClasses", list(reversed(VISIBILITY_NAMES))),
        ("inputSize", 256),
        ("heatmapSize", 64),
        ("architecture", "legacy-coordinate-model"),
    ],
)
def test_checkpoint_contract_rejects_every_identity_or_shape_mismatch(
    field,
    invalid,
):
    checkpoint = _valid_checkpoint()
    checkpoint[field] = invalid
    with pytest.raises(ValueError, match=field):
        validate_checkpoint_contract(checkpoint, "a" * 64)


def test_checkpoint_contract_accepts_complete_heatmap_identity():
    validate_checkpoint_contract(_valid_checkpoint(), "a" * 64)

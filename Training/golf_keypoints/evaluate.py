import argparse
import hashlib
import json
import re
from pathlib import Path

import torch
from torch.utils.data import DataLoader, default_collate

from contracts import (
    HEATMAP_SIZE,
    IGNORE_VISIBILITY,
    INPUT_SIZE,
    INPUT_TRANSFORM_VERSION,
    LANDMARK_NAMES,
    MANIFEST_NAMES,
    VISIBILITY_INDEX,
    VISIBILITY_NAMES,
)
from dataset import GolfHeatmapDataset, ReviewedTrainingLabelsRequired
from metrics import (
    SHAFT_LENGTH_EPSILON_PIXELS,
    canvas_point_is_in_content_rect,
    canvas_to_source_normalized,
    circular_angle_error_degrees,
    dense_longest_visible_gap,
    deterministic_percentile,
    shaft_angle_degrees,
    source_normalized_to_pixels,
    source_pixel_error,
)
from model import GolfHeatmapNet, heatmap_soft_argmax


ARCHITECTURE = "mobilenet-v3-small-fpn-heatmap-v1"
DECODER_VERSION = "heatmap-soft-argmax-v1"
REPORT_SCHEMA_VERSION = 1
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")

HIT_ERROR_THRESHOLD = 0.02
MINIMUM_VISIBLE_SAMPLES = 30
MINIMUM_NONVISIBLE_SAMPLES = 10
MINIMUM_HIT_RATE = 0.90
MAXIMUM_MEDIAN_ERROR = 0.01
MAXIMUM_P90_ERROR = 0.02
MINIMUM_VISIBLE_RECALL = 0.95
MAXIMUM_FALSE_VISIBLE_RATE = 0.05
MAXIMUM_VISIBLE_GAP = 2
MAXIMUM_SHAFT_MEDIAN_DEGREES = 3.0
MAXIMUM_SHAFT_P90_DEGREES = 7.0
MINIMUM_SHAFT_SAMPLES = 30
MINIMUM_SHAFT_COVERAGE = 0.95
SHAFT_STAGES = ("P6", "P8")
VIEWS = ("dtl", "face-on")


def build_argument_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--expected-manifest-sha256", required=True)
    parser.add_argument("--video-root", required=True)
    parser.add_argument("--split", default="validation")
    parser.add_argument("--output", required=True)
    parser.add_argument("--batch-size", type=int, default=16)
    return parser


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _target_canvas_point(metadata, landmark_name):
    points = metadata.get("canvas_points")
    if not isinstance(points, dict):
        raise ValueError("evaluation metadata canvas points are missing")
    point = points.get(MANIFEST_NAMES[landmark_name])
    if not isinstance(point, dict) or set(point) != {"x", "y"}:
        raise ValueError(
            f"visible {landmark_name} target is missing from evaluation metadata"
        )
    return float(point["x"]), float(point["y"])


def _failure(
    *,
    view,
    metric,
    actual,
    threshold,
    comparison,
    landmark=None,
    stage=None,
):
    result = {
        "view": view,
        "metric": metric,
        "actual": actual,
        "threshold": threshold,
        "comparison": comparison,
    }
    if landmark is not None:
        result["landmark"] = landmark
    if stage is not None:
        result["stage"] = stage
    return result


def _require_batch_contract(batch):
    required = {
        "predicted_canvas_coordinates",
        "visibility_targets",
        "predicted_visibility_logits",
        "metadata",
    }
    if not isinstance(batch, dict) or not required.issubset(batch):
        raise ValueError("evaluation batch contract is incomplete")
    coordinates = torch.as_tensor(batch["predicted_canvas_coordinates"])
    targets = torch.as_tensor(batch["visibility_targets"])
    visibility_logits = torch.as_tensor(
        batch["predicted_visibility_logits"]
    )
    metadata = batch["metadata"]
    batch_size = coordinates.shape[0] if coordinates.ndim else 0
    if coordinates.shape != (batch_size, len(LANDMARK_NAMES), 2):
        raise ValueError("decoded coordinate shape contract mismatch")
    if targets.shape != (batch_size, len(LANDMARK_NAMES)):
        raise ValueError("visibility target shape contract mismatch")
    if visibility_logits.shape != (
        batch_size,
        len(LANDMARK_NAMES),
        len(VISIBILITY_NAMES),
    ):
        raise ValueError("visibility output shape contract mismatch")
    if not isinstance(metadata, (list, tuple)) or len(metadata) != batch_size:
        raise ValueError("evaluation metadata batch contract mismatch")
    if not torch.isfinite(coordinates).all().item():
        raise ValueError("decoded coordinates contain non-finite values")
    if not torch.isfinite(visibility_logits).all().item():
        raise ValueError("visibility output contains non-finite values")
    return (
        coordinates.detach().cpu(),
        targets.detach().cpu(),
        visibility_logits.detach().cpu(),
        list(metadata),
    )


def _flatten_evaluation_batches(batches):
    records = []
    for batch in batches:
        coordinates, targets, visibility_logits, metadata = (
            _require_batch_contract(batch)
        )
        predicted_classes = torch.argmax(visibility_logits, dim=-1)
        for batch_index, item_metadata in enumerate(metadata):
            if not isinstance(item_metadata, dict):
                raise ValueError("evaluation sample metadata must be an object")
            view = item_metadata.get("view")
            if view not in VIEWS:
                raise ValueError(f"unsupported evaluation view {view!r}")
            if (
                item_metadata.get("input_transform_version")
                != INPUT_TRANSFORM_VERSION
            ):
                raise ValueError(
                    "evaluation metadata input transform version mismatch"
                )
            records.append({
                "metadata": item_metadata,
                "view": view,
                "predictedCoordinates": coordinates[batch_index],
                "visibilityTargets": targets[batch_index],
                "predictedVisibility": predicted_classes[batch_index],
            })
    return records


def _landmark_row(records, view, landmark_index, landmark_name):
    visible_count = 0
    nonvisible_count = 0
    diagonal_errors = []
    source_pixel_errors = []
    hits = 0
    predicted_visible_true = 0
    predicted_visible_false = 0
    padding_coordinate_count = 0
    padding_prediction_count = 0
    dense_records = []
    dense_truth_unresolved = False
    for record in records:
        if record["view"] != view:
            continue
        target_class = int(record["visibilityTargets"][landmark_index].item())
        metadata = record["metadata"]
        is_dense = "validation-dense" in metadata.get("queue_reasons", [])
        if target_class == IGNORE_VISIBILITY:
            if is_dense:
                dense_truth_unresolved = True
            continue
        predicted_visible = (
            int(record["predictedVisibility"][landmark_index].item())
            == VISIBILITY_INDEX["visible"]
        )
        if target_class == VISIBILITY_INDEX["visible"]:
            visible_count += 1
            target_canvas = _target_canvas_point(metadata, landmark_name)
            if not canvas_point_is_in_content_rect(target_canvas, metadata):
                raise ValueError(
                    f"visible {landmark_name} target is outside content rectangle"
                )
            predicted_canvas = record["predictedCoordinates"][
                landmark_index
            ].tolist()
            valid_location = canvas_point_is_in_content_rect(
                predicted_canvas, metadata
            )
            error = None
            if valid_location:
                error_result = source_pixel_error(
                    predicted_canvas,
                    target_canvas,
                    metadata,
                )
                error = error_result["diagonalNormalizedError"]
                diagonal_errors.append(error)
                source_pixel_errors.append(
                    error_result["sourcePixelError"]
                )
            else:
                padding_coordinate_count += 1
                padding_prediction_count += int(predicted_visible)
            predicted_visible_true += int(predicted_visible)
            hits += int(
                predicted_visible
                and valid_location
                and error <= HIT_ERROR_THRESHOLD
            )
            dense_records.append((
                metadata.get("clip_id"),
                metadata.get("source_frame_index"),
                True,
                (
                    not predicted_visible
                    or not valid_location
                    or error > HIT_ERROR_THRESHOLD
                ),
                is_dense,
            ))
        elif target_class in (
            VISIBILITY_INDEX["occluded"],
            VISIBILITY_INDEX["out-of-frame"],
        ):
            nonvisible_count += 1
            predicted_visible_false += int(predicted_visible)
            dense_records.append((
                metadata.get("clip_id"),
                metadata.get("source_frame_index"),
                False,
                False,
                is_dense,
            ))
        else:
            raise ValueError(
                f"invalid visibility target class {target_class}"
            )

    sufficient = (
        visible_count >= MINIMUM_VISIBLE_SAMPLES
        and nonvisible_count >= MINIMUM_NONVISIBLE_SAMPLES
    )
    longest_gap, dense_gap_sufficient, dense_sample_count = (
        dense_longest_visible_gap(dense_records)
    )
    if dense_truth_unresolved:
        longest_gap = None
        dense_gap_sufficient = False
    padding_prediction_rate = (
        padding_prediction_count / visible_count
        if visible_count
        else None
    )
    padding_coordinate_rate = (
        padding_coordinate_count / visible_count
        if visible_count
        else None
    )
    row = {
        "trueVisibleCount": visible_count,
        "trueNonVisibleCount": nonvisible_count,
        "validLocationCount": len(diagonal_errors),
        "paddingCoordinateCount": padding_coordinate_count,
        "paddingCoordinateRate": padding_coordinate_rate,
        "paddingPredictionCount": padding_prediction_count,
        "paddingPredictionRate": padding_prediction_rate,
        "hitErrorThreshold": HIT_ERROR_THRESHOLD,
        "visibleFrameHitRate": None,
        "medianSourcePixelError": None,
        "p90SourcePixelError": None,
        "medianDiagonalNormalizedError": None,
        "p90DiagonalNormalizedError": None,
        "visibleRecall": None,
        "falseVisibleRate": None,
        "longestVisibleGap": None,
        "denseSampleCount": dense_sample_count,
        "denseGapSufficient": dense_gap_sufficient,
        "sufficientSamples": sufficient,
    }
    if sufficient:
        row.update({
            "visibleFrameHitRate": hits / visible_count,
            "visibleRecall": predicted_visible_true / visible_count,
            "falseVisibleRate": (
                predicted_visible_false / nonvisible_count
            ),
        })
        if dense_gap_sufficient:
            row["longestVisibleGap"] = longest_gap
        # Never inverse or silently discard a black-padding peak. One anomaly
        # nulls the aggregate location metrics and is an explicit gate failure.
        if padding_coordinate_count == 0:
            row.update({
                "medianSourcePixelError": deterministic_percentile(
                    source_pixel_errors, 50
                ),
                "p90SourcePixelError": deterministic_percentile(
                    source_pixel_errors, 90
                ),
                "medianDiagonalNormalizedError": deterministic_percentile(
                    diagonal_errors, 50
                ),
                "p90DiagonalNormalizedError": deterministic_percentile(
                    diagonal_errors, 90
                ),
            })
    return row


def _landmark_failures(view, landmark, row):
    failures = []
    if row["paddingCoordinateCount"] > 0:
        failures.append(_failure(
            view=view,
            landmark=landmark,
            metric="paddingCoordinateCount",
            actual=row["paddingCoordinateCount"],
            threshold=0,
            comparison="==",
        ))
    if (
        row["paddingPredictionRate"] is not None
        and row["paddingPredictionRate"] > 0
    ):
        failures.append(_failure(
            view=view,
            landmark=landmark,
            metric="paddingPredictionRate",
            actual=row["paddingPredictionRate"],
            threshold=0.0,
            comparison="==",
        ))
    if not row["denseGapSufficient"]:
        failures.append(_failure(
            view=view,
            landmark=landmark,
            metric="denseGapSufficient",
            actual=False,
            threshold=True,
            comparison="==",
        ))
    if not row["sufficientSamples"]:
        if row["trueVisibleCount"] < MINIMUM_VISIBLE_SAMPLES:
            failures.append(_failure(
                view=view,
                landmark=landmark,
                metric="minimumVisibleSamples",
                actual=row["trueVisibleCount"],
                threshold=MINIMUM_VISIBLE_SAMPLES,
                comparison=">=",
            ))
        if row["trueNonVisibleCount"] < MINIMUM_NONVISIBLE_SAMPLES:
            failures.append(_failure(
                view=view,
                landmark=landmark,
                metric="minimumNonVisibleSamples",
                actual=row["trueNonVisibleCount"],
                threshold=MINIMUM_NONVISIBLE_SAMPLES,
                comparison=">=",
            ))
        return failures

    gates = (
        ("visibleFrameHitRate", MINIMUM_HIT_RATE, ">="),
        ("visibleRecall", MINIMUM_VISIBLE_RECALL, ">="),
        ("falseVisibleRate", MAXIMUM_FALSE_VISIBLE_RATE, "<="),
    )
    if row["paddingCoordinateCount"] == 0:
        gates += (
            (
                "medianDiagonalNormalizedError",
                MAXIMUM_MEDIAN_ERROR,
                "<=",
            ),
            ("p90DiagonalNormalizedError", MAXIMUM_P90_ERROR, "<="),
        )
    if row["denseGapSufficient"]:
        gates += (
            ("longestVisibleGap", MAXIMUM_VISIBLE_GAP, "<="),
        )
    for metric, threshold, comparison in gates:
        actual = row[metric]
        passed = (
            actual >= threshold if comparison == ">=" else actual <= threshold
        )
        if not passed:
            failures.append(_failure(
                view=view,
                landmark=landmark,
                metric=metric,
                actual=actual,
                threshold=threshold,
                comparison=comparison,
            ))
    return failures


def _shaft_angle_row(records, view, stage):
    eligible_count = 0
    predicted_double_visible_count = 0
    invalid_geometry_count = 0
    errors = []
    start_index = LANDMARK_NAMES.index("shaft_start")
    end_index = LANDMARK_NAMES.index("shaft_end")
    for record in records:
        metadata = record["metadata"]
        if record["view"] != view or stage not in metadata.get(
            "stage_codes", []
        ):
            continue
        targets = record["visibilityTargets"]
        predicted_visibility = record["predictedVisibility"]
        true_double_visible = all(
            int(targets[index].item()) == VISIBILITY_INDEX["visible"]
            for index in (start_index, end_index)
        )
        if not true_double_visible:
            continue
        eligible_count += 1
        predicted_double_visible = all(
            int(predicted_visibility[index].item())
            == VISIBILITY_INDEX["visible"]
            for index in (start_index, end_index)
        )
        if not predicted_double_visible:
            continue
        predicted_double_visible_count += 1

        predicted_start_canvas = record["predictedCoordinates"][
            start_index
        ].tolist()
        predicted_end_canvas = record["predictedCoordinates"][
            end_index
        ].tolist()
        if not all(
            canvas_point_is_in_content_rect(point, metadata)
            for point in (predicted_start_canvas, predicted_end_canvas)
        ):
            invalid_geometry_count += 1
            continue
        predicted_start_source = canvas_to_source_normalized(
            predicted_start_canvas,
            metadata,
        )
        predicted_end_source = canvas_to_source_normalized(
            predicted_end_canvas,
            metadata,
        )
        target_start_source = canvas_to_source_normalized(
            _target_canvas_point(metadata, "shaft_start"),
            metadata,
        )
        target_end_source = canvas_to_source_normalized(
            _target_canvas_point(metadata, "shaft_end"),
            metadata,
        )
        predicted_start_pixels = source_normalized_to_pixels(
            predicted_start_source, metadata
        )
        predicted_end_pixels = source_normalized_to_pixels(
            predicted_end_source, metadata
        )
        target_start_pixels = source_normalized_to_pixels(
            target_start_source, metadata
        )
        target_end_pixels = source_normalized_to_pixels(
            target_end_source, metadata
        )
        predicted_length = (
            (predicted_end_pixels[0] - predicted_start_pixels[0]) ** 2
            + (predicted_end_pixels[1] - predicted_start_pixels[1]) ** 2
        ) ** 0.5
        target_length = (
            (target_end_pixels[0] - target_start_pixels[0]) ** 2
            + (target_end_pixels[1] - target_start_pixels[1]) ** 2
        ) ** 0.5
        if (
            predicted_length <= SHAFT_LENGTH_EPSILON_PIXELS
            or target_length <= SHAFT_LENGTH_EPSILON_PIXELS
        ):
            invalid_geometry_count += 1
            continue
        predicted_angle = shaft_angle_degrees(
            predicted_start_pixels, predicted_end_pixels
        )
        target_angle = shaft_angle_degrees(
            target_start_pixels, target_end_pixels
        )
        error = circular_angle_error_degrees(
            predicted_angle, target_angle
        )
        errors.append(float(error.item()))
    sufficient = eligible_count >= MINIMUM_SHAFT_SAMPLES
    coverage = (
        predicted_double_visible_count / eligible_count
        if eligible_count
        else None
    )
    row = {
        "eligibleFrameCount": eligible_count,
        "predictedDoubleVisibleCount": predicted_double_visible_count,
        "validAngleCount": len(errors),
        "invalidGeometryCount": invalid_geometry_count,
        "predictedDoubleVisibleCoverage": coverage,
        "medianCircularErrorDegrees": None,
        "p90CircularErrorDegrees": None,
        "sufficientSamples": sufficient,
    }
    if sufficient and invalid_geometry_count == 0 and errors:
        row.update({
            "medianCircularErrorDegrees": deterministic_percentile(
                errors, 50
            ),
            "p90CircularErrorDegrees": deterministic_percentile(errors, 90),
        })
    return row


def _shaft_angle_failures(view, stage, row):
    failures = []
    if row["eligibleFrameCount"] < MINIMUM_SHAFT_SAMPLES:
        failures.append(_failure(
            view=view,
            stage=stage,
            metric="minimumShaftSamples",
            actual=row["eligibleFrameCount"],
            threshold=MINIMUM_SHAFT_SAMPLES,
            comparison=">=",
        ))
    coverage = row["predictedDoubleVisibleCoverage"]
    if coverage is None or coverage < MINIMUM_SHAFT_COVERAGE:
        failures.append(_failure(
            view=view,
            stage=stage,
            metric="predictedDoubleVisibleCoverage",
            actual=coverage,
            threshold=MINIMUM_SHAFT_COVERAGE,
            comparison=">=",
        ))
    if row["invalidGeometryCount"] > 0:
        failures.append(_failure(
            view=view,
            stage=stage,
            metric="invalidShaftGeometryCount",
            actual=row["invalidGeometryCount"],
            threshold=0,
            comparison="==",
        ))
    if not row["sufficientSamples"]:
        return failures
    if row["invalidGeometryCount"] > 0 or not row["validAngleCount"]:
        return failures
    for metric, threshold in (
        ("medianCircularErrorDegrees", MAXIMUM_SHAFT_MEDIAN_DEGREES),
        ("p90CircularErrorDegrees", MAXIMUM_SHAFT_P90_DEGREES),
    ):
        actual = row[metric]
        if actual > threshold:
            failures.append(_failure(
                view=view,
                stage=stage,
                metric=metric,
                actual=actual,
                threshold=threshold,
                comparison="<=",
            ))
    return failures


def build_evaluation_report(batches, split):
    split = str(split)
    records = _flatten_evaluation_batches(batches)
    failed_thresholds = []
    if split != "validation":
        failed_thresholds.append({
            "metric": "requiredSplit",
            "actual": split,
            "threshold": "validation",
            "comparison": "==",
        })
    views = {}
    view_sample_counts = {}
    for view in VIEWS:
        view_records = [
            record for record in records if record["view"] == view
        ]
        view_sample_counts[view] = len(view_records)
        landmark_rows = {}
        for landmark_index, landmark in enumerate(LANDMARK_NAMES):
            row = _landmark_row(
                records, view, landmark_index, landmark
            )
            landmark_rows[landmark] = row
            failed_thresholds.extend(
                _landmark_failures(view, landmark, row)
            )
        shaft_rows = {}
        for stage in SHAFT_STAGES:
            row = _shaft_angle_row(records, view, stage)
            shaft_rows[stage] = row
            failed_thresholds.extend(
                _shaft_angle_failures(view, stage, row)
            )
        views[view] = {
            "sampleCount": len(view_records),
            "landmarks": landmark_rows,
            "shaftAngles": shaft_rows,
        }
    return {
        "schemaVersion": REPORT_SCHEMA_VERSION,
        "decoderVersion": DECODER_VERSION,
        "split": split,
        "sampleCount": len(records),
        "viewSampleCounts": view_sample_counts,
        "views": views,
        "gateThresholds": {
            "hitError": HIT_ERROR_THRESHOLD,
            "minimumVisibleSamples": MINIMUM_VISIBLE_SAMPLES,
            "minimumNonVisibleSamples": MINIMUM_NONVISIBLE_SAMPLES,
            "minimumVisibleFrameHitRate": MINIMUM_HIT_RATE,
            "maximumMedianDiagonalNormalizedError": MAXIMUM_MEDIAN_ERROR,
            "maximumP90DiagonalNormalizedError": MAXIMUM_P90_ERROR,
            "minimumVisibleRecall": MINIMUM_VISIBLE_RECALL,
            "maximumFalseVisibleRate": MAXIMUM_FALSE_VISIBLE_RATE,
            "maximumLongestVisibleGap": MAXIMUM_VISIBLE_GAP,
            "maximumShaftMedianDegrees": MAXIMUM_SHAFT_MEDIAN_DEGREES,
            "maximumShaftP90Degrees": MAXIMUM_SHAFT_P90_DEGREES,
            "minimumShaftSamples": MINIMUM_SHAFT_SAMPLES,
            "minimumPredictedDoubleVisibleCoverage": MINIMUM_SHAFT_COVERAGE,
            "maximumPaddingPredictionRate": 0.0,
            "denseGapRequired": True,
        },
        "failedThresholds": failed_thresholds,
        "developmentPromotionPassed": not failed_thresholds,
    }


def promotion_passed(report):
    """Compatibility hook for Task 5; only the complete Task 4 gate can pass."""
    return (
        report.get("split") == "validation"
        and report.get("developmentPromotionPassed") is True
        and report.get("failedThresholds") == []
    )


def _validate_expected_hash(value):
    if not isinstance(value, str) or not SHA256_PATTERN.fullmatch(value):
        raise ValueError(
            "expected manifest SHA-256 must be 64 lowercase hex characters"
        )
    return value


def validate_checkpoint_contract(checkpoint, expected_manifest_sha256):
    if not isinstance(checkpoint, dict):
        raise ValueError("checkpoint root must be an object")
    exact = {
        "artifactKind": "development-training-checkpoint",
        "architecture": ARCHITECTURE,
        "manifestSHA256": expected_manifest_sha256,
        "inputTransformVersion": INPUT_TRANSFORM_VERSION,
        "landmarks": list(LANDMARK_NAMES),
        "visibilityClasses": list(VISIBILITY_NAMES),
        "inputSize": INPUT_SIZE,
        "heatmapSize": HEATMAP_SIZE,
    }
    for field, expected in exact.items():
        if checkpoint.get(field) != expected:
            raise ValueError(f"checkpoint {field} contract mismatch")
    if not isinstance(checkpoint.get("model"), dict):
        raise ValueError("checkpoint model state is missing")


def _collate_evaluation_samples(samples):
    images, heatmaps, visibility, coordinate_masks, metadata = zip(*samples)
    return (
        default_collate(images),
        default_collate(heatmaps),
        default_collate(visibility),
        default_collate(coordinate_masks),
        list(metadata),
    )


def _source_dimension_lookup(dataset):
    result = {}
    for sample in getattr(dataset, "samples", ()):
        key = (sample.clip_id, sample.source_frame_index)
        dimensions = (sample.oriented_width, sample.oriented_height)
        if key in result and result[key] != dimensions:
            raise ValueError("conflicting oriented source dimensions")
        result[key] = dimensions
    return result


def _metadata_with_source_dimensions(metadata, dimension_lookup):
    enriched = []
    for item in metadata:
        value = dict(item)
        if (
            "source_oriented_width" not in value
            or "source_oriented_height" not in value
        ):
            key = (value.get("clip_id"), value.get("source_frame_index"))
            dimensions = dimension_lookup.get(key)
            if dimensions is None:
                raise ValueError(
                    "oriented source dimensions are missing from evaluation "
                    "dataset metadata"
                )
            value["source_oriented_width"] = dimensions[0]
            value["source_oriented_height"] = dimensions[1]
        enriched.append(value)
    return enriched


def evaluate_model(model, dataset, *, batch_size=16):
    if batch_size <= 0:
        raise ValueError("batch size must be positive")
    model.eval()
    batches = []
    dimension_lookup = _source_dimension_lookup(dataset)
    with torch.no_grad():
        for (
            images,
            _target_heatmaps,
            visibility_targets,
            _coordinate_mask,
            metadata,
        ) in DataLoader(
            dataset,
            batch_size=batch_size,
            shuffle=False,
            collate_fn=_collate_evaluation_samples,
        ):
            predicted_heatmaps, visibility_logits = model(images)
            expected_heatmap_shape = (
                images.shape[0],
                len(LANDMARK_NAMES),
                HEATMAP_SIZE,
                HEATMAP_SIZE,
            )
            expected_visibility_shape = (
                images.shape[0],
                len(LANDMARK_NAMES),
                len(VISIBILITY_NAMES),
            )
            if tuple(predicted_heatmaps.shape) != expected_heatmap_shape:
                raise ValueError("model heatmap output shape contract mismatch")
            if tuple(visibility_logits.shape) != expected_visibility_shape:
                raise ValueError(
                    "model visibility output shape contract mismatch"
                )
            if not torch.isfinite(predicted_heatmaps).all().item():
                raise ValueError("model heatmaps contain non-finite values")
            predicted_coordinates = heatmap_soft_argmax(
                predicted_heatmaps
            )
            batches.append({
                "predicted_canvas_coordinates": predicted_coordinates,
                "visibility_targets": visibility_targets,
                "predicted_visibility_logits": visibility_logits,
                "metadata": _metadata_with_source_dimensions(
                    metadata, dimension_lookup
                ),
            })
    split = getattr(dataset, "split", None)
    if split is None:
        raise ValueError("evaluation dataset split is missing")
    return build_evaluation_report(batches, split=split)


def main(argv=None):
    parser = build_argument_parser()
    args = parser.parse_args(argv)
    try:
        expected_hash = _validate_expected_hash(
            args.expected_manifest_sha256
        )
        current_manifest_hash = sha256(args.manifest)
        if current_manifest_hash != expected_hash:
            raise ValueError(
                "evaluation manifest SHA-256 does not match expected value"
            )
        dataset = GolfHeatmapDataset(
            args.manifest,
            args.video_root,
            args.split,
            expected_manifest_sha256=expected_hash,
        )
        checkpoint = torch.load(
            args.checkpoint,
            map_location="cpu",
            weights_only=False,
        )
        validate_checkpoint_contract(checkpoint, expected_hash)
        model = GolfHeatmapNet(pretrained=False)
        model.load_state_dict(checkpoint["model"], strict=True)
        report = evaluate_model(
            model,
            dataset,
            batch_size=args.batch_size,
        )
        report.update({
            "checkpointSHA256": sha256(args.checkpoint),
            "manifestSHA256": current_manifest_hash,
            "architecture": checkpoint["architecture"],
            "inputTransformVersion": checkpoint[
                "inputTransformVersion"
            ],
            "landmarks": checkpoint["landmarks"],
            "visibilityClasses": checkpoint["visibilityClasses"],
            "modelOutput": {
                "heatmaps": [
                    len(LANDMARK_NAMES),
                    HEATMAP_SIZE,
                    HEATMAP_SIZE,
                ],
                "visibilityLogits": [
                    len(LANDMARK_NAMES),
                    len(VISIBILITY_NAMES),
                ],
            },
        })
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except (
        ReviewedTrainingLabelsRequired,
        OSError,
        RuntimeError,
        ValueError,
    ) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()

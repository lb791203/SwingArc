import argparse
import ctypes
import errno
import hashlib
import json
import math
import os
import shutil
import sys
import tempfile
from pathlib import Path

import torch

from artifact_hashes import (
    canonical_json_sha256,
    file_sha256,
    model_state_sha256,
    package_tree_sha256,
)
from contracts import (
    HEATMAP_SIZE,
    INPUT_SIZE,
    INPUT_TRANSFORM_VERSION,
    LANDMARK_NAMES,
    VISIBILITY_NAMES,
)
from coreml_parity import (
    MAXIMUM_DECODED_PIXEL_DIFFERENCE,
    MINIMUM_SAMPLES_PER_VIEW,
    REQUIRED_VIEWS,
    PARITY_SCHEMA_VERSION,
    parity_configuration,
    run_coreml_parity,
)
from dataset import GolfHeatmapDataset, ReviewedTrainingLabelsRequired
from evaluate import (
    ARCHITECTURE,
    DECODER_VERSION,
    HIT_ERROR_THRESHOLD,
    MAXIMUM_FALSE_VISIBLE_RATE,
    MAXIMUM_MEDIAN_ERROR,
    MAXIMUM_P90_ERROR,
    MAXIMUM_SHAFT_MEDIAN_DEGREES,
    MAXIMUM_SHAFT_P90_DEGREES,
    MAXIMUM_VISIBLE_GAP,
    MINIMUM_HIT_RATE,
    MINIMUM_NONVISIBLE_SAMPLES,
    MINIMUM_SHAFT_COVERAGE,
    MINIMUM_SHAFT_SAMPLES,
    MINIMUM_VISIBLE_RECALL,
    MINIMUM_VISIBLE_SAMPLES,
    SHAFT_STAGES,
    validate_checkpoint_contract,
)
from model import GolfHeatmapNet


DEVELOPMENT_STATUS = "development"
EXPORT_BUNDLE_SCHEMA_VERSION = 1
PACKAGE_NAME = "GolfKeypoints.mlpackage"
PARITY_NAME = "coreml-parity.json"
BUNDLE_MANIFEST_NAME = "export-manifest.json"
COMPLETION_MARKER_NAME = "_SUCCESS"


def _canonical_sha256(value):
    return canonical_json_sha256(value)


def _load_checkpoint_safely(path):
    try:
        checkpoint = torch.load(
            Path(path),
            map_location="cpu",
            weights_only=True,
        )
    except (OSError, RuntimeError, TypeError, ValueError) as error:
        raise ValueError(
            f"checkpoint could not be loaded safely: {error}"
        ) from error
    if not isinstance(checkpoint, dict):
        raise ValueError("checkpoint root must be an object")
    return checkpoint


def _read_report(path):
    try:
        report = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"evaluation report is invalid: {error}") from error
    if not isinstance(report, dict):
        raise ValueError("evaluation report root must be an object")
    return report


def _finite_number(value, description):
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(float(value))
    ):
        raise ValueError(f"{description} must be finite")
    return float(value)


def _minimum(value, threshold, description):
    if _finite_number(value, description) < threshold:
        raise ValueError(f"{description} failed")


def _maximum(value, threshold, description):
    if _finite_number(value, description) > threshold:
        raise ValueError(f"{description} failed")


def _require_exact(actual, expected, description):
    if actual != expected:
        raise ValueError(f"{description} mismatch")


def _nonnegative_int(value, description):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError(f"{description} must be a non-negative integer")
    return value


def _assert_landmark_row(view, landmark, row, view_sample_count):
    prefix = f"all landmarks and views: {view}/{landmark}"
    if not isinstance(row, dict):
        raise ValueError(f"{prefix} row is missing")
    if row.get("sufficientSamples") is not True:
        raise ValueError(f"{prefix} has insufficient samples")
    if row.get("denseGapSufficient") is not True:
        raise ValueError(f"{prefix} has insufficient dense coverage")
    visible_count = _nonnegative_int(
        row.get("trueVisibleCount"),
        f"{prefix} visible sample gate",
    )
    nonvisible_count = _nonnegative_int(
        row.get("trueNonVisibleCount"),
        f"{prefix} non-visible sample gate",
    )
    _minimum(
        visible_count,
        MINIMUM_VISIBLE_SAMPLES,
        f"{prefix} visible sample gate",
    )
    _minimum(
        nonvisible_count,
        MINIMUM_NONVISIBLE_SAMPLES,
        f"{prefix} non-visible sample gate",
    )
    labelled_count = (
        visible_count + nonvisible_count
    )
    if labelled_count > view_sample_count:
        raise ValueError(f"{prefix} sample counts are inconsistent")
    padding_count = _nonnegative_int(
        row.get("paddingCoordinateCount"),
        f"{prefix} padding coordinate gate",
    )
    _require_exact(
        padding_count,
        0,
        f"{prefix} padding coordinate gate",
    )
    _require_exact(
        row.get("paddingCoordinateRate"),
        0.0,
        f"{prefix} padding coordinate rate",
    )
    prediction_padding_count = _nonnegative_int(
        row.get("paddingPredictionCount"),
        f"{prefix} padding prediction count",
    )
    _require_exact(
        prediction_padding_count,
        0,
        f"{prefix} padding prediction count",
    )
    _maximum(
        row.get("paddingPredictionRate"),
        0.0,
        f"{prefix} padding prediction gate",
    )
    valid_location_count = _nonnegative_int(
        row.get("validLocationCount"),
        f"{prefix} valid-location count",
    )
    _require_exact(
        valid_location_count,
        visible_count,
        f"{prefix} valid-location count",
    )
    dense_count = _nonnegative_int(
        row.get("denseSampleCount"),
        f"{prefix} dense sample gate",
    )
    _minimum(
        dense_count,
        3,
        f"{prefix} dense sample gate",
    )
    _require_exact(
        row.get("hitErrorThreshold"),
        HIT_ERROR_THRESHOLD,
        f"{prefix} hit threshold",
    )
    _minimum(
        row.get("visibleFrameHitRate"),
        MINIMUM_HIT_RATE,
        f"{prefix} hit-rate gate",
    )
    _maximum(
        row.get("medianDiagonalNormalizedError"),
        MAXIMUM_MEDIAN_ERROR,
        f"{prefix} median-error gate",
    )
    _maximum(
        row.get("p90DiagonalNormalizedError"),
        MAXIMUM_P90_ERROR,
        f"{prefix} p90-error gate",
    )
    _minimum(
        row.get("visibleRecall"),
        MINIMUM_VISIBLE_RECALL,
        f"{prefix} visible-recall gate",
    )
    _maximum(
        row.get("falseVisibleRate"),
        MAXIMUM_FALSE_VISIBLE_RATE,
        f"{prefix} false-visible gate",
    )
    longest_gap = _nonnegative_int(
        row.get("longestVisibleGap"),
        f"{prefix} visible-gap gate",
    )
    _maximum(
        longest_gap,
        MAXIMUM_VISIBLE_GAP,
        f"{prefix} visible-gap gate",
    )


def _assert_shaft_row(view, stage, row):
    prefix = f"shaft gate {view}/{stage}"
    if not isinstance(row, dict):
        raise ValueError(f"{prefix} row is missing")
    if row.get("sufficientSamples") is not True:
        raise ValueError(f"{prefix} has insufficient samples")
    eligible_count = _nonnegative_int(
        row.get("eligibleFrameCount"),
        f"{prefix} eligible-sample gate",
    )
    _minimum(
        eligible_count,
        MINIMUM_SHAFT_SAMPLES,
        f"{prefix} eligible-sample gate",
    )
    _minimum(
        row.get("predictedDoubleVisibleCoverage"),
        MINIMUM_SHAFT_COVERAGE,
        f"{prefix} coverage gate",
    )
    invalid_count = _nonnegative_int(
        row.get("invalidGeometryCount"),
        f"{prefix} geometry gate",
    )
    _require_exact(
        invalid_count,
        0,
        f"{prefix} geometry gate",
    )
    valid_angle_count = _nonnegative_int(
        row.get("validAngleCount"),
        f"{prefix} valid-angle gate",
    )
    _minimum(
        valid_angle_count,
        1,
        f"{prefix} valid-angle gate",
    )
    predicted_count = _nonnegative_int(
        row.get("predictedDoubleVisibleCount"),
        f"{prefix} predicted-visible count",
    )
    _minimum(predicted_count, 0, f"{prefix} predicted-visible count")
    if predicted_count > eligible_count:
        raise ValueError(f"{prefix} counts are inconsistent")
    expected_coverage = predicted_count / eligible_count
    if abs(
        _finite_number(
            row.get("predictedDoubleVisibleCoverage"),
            f"{prefix} coverage",
        )
        - expected_coverage
    ) > 1e-12:
        raise ValueError(f"{prefix} coverage is inconsistent")
    _require_exact(
        valid_angle_count,
        predicted_count,
        f"{prefix} valid-angle count",
    )
    _maximum(
        row.get("medianCircularErrorDegrees"),
        MAXIMUM_SHAFT_MEDIAN_DEGREES,
        f"{prefix} median-angle gate",
    )
    _maximum(
        row.get("p90CircularErrorDegrees"),
        MAXIMUM_SHAFT_P90_DEGREES,
        f"{prefix} p90-angle gate",
    )


def assert_release_status_allowed(status, report):
    if status == DEVELOPMENT_STATUS:
        return status
    raise ValueError(
        f"unsupported promotion status {status!r}; only development is exportable"
    )


def assert_report_passes(checkpoint_path, evaluation_path):
    checkpoint_path = Path(checkpoint_path)
    evaluation_path = Path(evaluation_path)
    checkpoint = _load_checkpoint_safely(checkpoint_path)
    checkpoint_hash = file_sha256(checkpoint_path)
    report = _read_report(evaluation_path)

    # Preserve the public gate's most actionable outer-artifact diagnostics
    # before inspecting the deeper checkpoint contract.
    if report.get("split") != "validation":
        raise ValueError(
            "a validation split report is required for Core ML export"
        )
    if report.get("checkpointSHA256") != checkpoint_hash:
        raise ValueError("evaluation report does not match checkpoint")
    if report.get("manifestSHA256") != checkpoint.get("manifestSHA256"):
        raise ValueError(
            "evaluation report manifest does not match checkpoint"
        )
    if checkpoint.get("artifactKind") != "development-training-checkpoint":
        raise ValueError("checkpoint artifact kind is not exportable")
    if checkpoint.get("promotionStatus") != DEVELOPMENT_STATUS:
        raise ValueError("checkpoint promotion status must be development")
    manifest_hash = checkpoint.get("manifestSHA256")
    validate_checkpoint_contract(checkpoint, manifest_hash)
    assert_release_status_allowed(DEVELOPMENT_STATUS, report)

    _require_exact(report.get("schemaVersion"), 1, "report schema")
    _require_exact(
        report.get("decoderVersion"),
        DECODER_VERSION,
        "report decoder",
    )
    if report.get("developmentPromotionPassed") is not True:
        raise ValueError(
            "development promotion did not pass; Core ML export is blocked"
        )
    if report.get("failedThresholds") != []:
        raise ValueError(
            "evaluation report contains failed thresholds; export is blocked"
        )

    computed_model_hash = model_state_sha256(checkpoint["model"])
    reported_model_hash = report.get("modelSHA256")
    if reported_model_hash != computed_model_hash:
        raise ValueError("evaluation report modelSHA256 mismatch")
    expected_bindings = {
        "checkpointSHA256": checkpoint_hash,
        "manifestSHA256": manifest_hash,
        "architecture": checkpoint["architecture"],
        "inputTransformVersion": checkpoint["inputTransformVersion"],
        "landmarks": checkpoint["landmarks"],
        "visibilityClasses": checkpoint["visibilityClasses"],
        "modelOutput": {
            "heatmaps": [
                1,
                len(LANDMARK_NAMES),
                HEATMAP_SIZE,
                HEATMAP_SIZE,
            ],
            "visibilityLogits": [
                1,
                len(LANDMARK_NAMES),
                len(VISIBILITY_NAMES),
            ],
        },
    }
    for field, expected in expected_bindings.items():
        _require_exact(
            report.get(field),
            expected,
            f"evaluation report {field}",
        )

    views = report.get("views")
    view_counts = report.get("viewSampleCounts")
    if not isinstance(views, dict) or set(views) != set(REQUIRED_VIEWS):
        raise ValueError("all landmarks and views must be present")
    if not isinstance(view_counts, dict) or set(view_counts) != set(
        REQUIRED_VIEWS
    ):
        raise ValueError("all view sample counts must be present")
    total_samples = 0
    for view in REQUIRED_VIEWS:
        view_report = views[view]
        if not isinstance(view_report, dict):
            raise ValueError(f"all landmarks and views: {view} is missing")
        view_count = view_report.get("sampleCount")
        view_count = _nonnegative_int(
            view_count,
            f"all landmarks and views: {view} sample count",
        )
        if view_count < 1:
            raise ValueError(f"all landmarks and views: {view} is empty")
        reported_view_count = _nonnegative_int(
            view_counts.get(view),
            f"{view} reported sample count",
        )
        _require_exact(
            reported_view_count,
            view_count,
            f"{view} sample count",
        )
        total_samples += view_count
        landmarks = view_report.get("landmarks")
        if not isinstance(landmarks, dict) or set(landmarks) != set(
            LANDMARK_NAMES
        ):
            raise ValueError(
                f"all landmarks and views: {view} landmark matrix mismatch"
            )
        for landmark in LANDMARK_NAMES:
            _assert_landmark_row(
                view,
                landmark,
                landmarks[landmark],
                view_count,
            )
        shaft_rows = view_report.get("shaftAngles")
        if not isinstance(shaft_rows, dict) or set(shaft_rows) != set(
            SHAFT_STAGES
        ):
            raise ValueError(f"shaft gate {view} matrix mismatch")
        for stage in SHAFT_STAGES:
            _assert_shaft_row(view, stage, shaft_rows[stage])
    report_sample_count = _nonnegative_int(
        report.get("sampleCount"),
        "report sample count",
    )
    _require_exact(
        report_sample_count,
        total_samples,
        "report sample count",
    )
    return {
        "checkpoint": checkpoint,
        "checkpointSHA256": checkpoint_hash,
        "modelSHA256": computed_model_hash,
        "evaluationSHA256": file_sha256(evaluation_path),
        "report": report,
    }


def _require_sha256(value, description):
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        raise ValueError(f"parity {description} is not a SHA-256")


def assert_parity_passes(
    report,
    *,
    expected_provenance=None,
    expected_package_tree_sha256=None,
):
    if not isinstance(report, dict):
        raise ValueError("parity report root must be an object")
    _require_exact(
        report.get("schemaVersion"),
        PARITY_SCHEMA_VERSION,
        "parity schema",
    )
    _require_exact(
        report.get("promotionStatus"),
        DEVELOPMENT_STATUS,
        "parity promotion status",
    )
    configuration = report.get("configuration")
    if not isinstance(configuration, dict):
        raise ValueError("parity fixed configuration mismatch")
    samples_per_view = _nonnegative_int(
        configuration.get("samplesPerView"),
        "parity configuration samplesPerView",
    )
    _require_exact(
        samples_per_view,
        MINIMUM_SAMPLES_PER_VIEW,
        "parity configuration samplesPerView",
    )
    _require_exact(
        configuration,
        parity_configuration(),
        "parity fixed configuration",
    )
    difference = _finite_number(
        report.get("maximumDecodedPixelDifference"),
        "parity maximum decoded pixel difference",
    )
    _require_exact(
        report.get("maximumAllowedDecodedPixelDifference"),
        MAXIMUM_DECODED_PIXEL_DIFFERENCE,
        "parity maximum allowed decoded pixel difference",
    )
    if difference > MAXIMUM_DECODED_PIXEL_DIFFERENCE:
        raise ValueError(
            "parity maximum decoded pixel difference exceeds one input pixel"
        )
    if report.get("visibilityClassMatches") is not True:
        raise ValueError("parity visibility classes do not match")
    if report.get("paddingClassificationMatches") is not True:
        raise ValueError("parity padding classification does not match")
    counts = report.get("viewSampleCounts")
    if not isinstance(counts, dict) or set(counts) != set(REQUIRED_VIEWS):
        raise ValueError("parity required view counts are missing")
    total = 0
    for view in REQUIRED_VIEWS:
        count = counts[view]
        count = _nonnegative_int(count, f"parity {view} sample count")
        if count != MINIMUM_SAMPLES_PER_VIEW:
            raise ValueError(
                "parity requires exactly 10 fixed samples per required view"
            )
        total += count
    sample_count = _nonnegative_int(
        report.get("sampleCount"),
        "parity sample count",
    )
    if sample_count != total:
        raise ValueError("parity sample count mismatch")
    for field in ("sampleSetSHA256", "inputTensorSHA256"):
        _require_sha256(report.get(field), field)
    provenance = report.get("provenance")
    if not isinstance(provenance, dict):
        raise ValueError("parity provenance is missing")
    required_provenance = {
        "checkpointSHA256",
        "modelSHA256",
        "manifestSHA256",
        "evaluationSHA256",
        "coreMLSpecSHA256",
        "exportProvenanceHash",
        "packageTreeSHA256",
    }
    if set(provenance) != required_provenance:
        raise ValueError("parity provenance fields mismatch")
    for field, value in provenance.items():
        _require_sha256(value, field)
    if expected_provenance is not None:
        _require_exact(
            provenance,
            expected_provenance,
            "parity provenance",
        )
    package_hash = report.get("packageTreeSHA256")
    _require_sha256(package_hash, "packageTreeSHA256")
    _require_exact(
        package_hash,
        provenance["packageTreeSHA256"],
        "parity package tree",
    )
    if expected_package_tree_sha256 is not None:
        _require_exact(
            package_hash,
            expected_package_tree_sha256,
            "parity expected package tree",
        )
    return report


def _export_contract(bindings):
    input_contract = {
        "name": "image",
        "layout": "RGB",
        "size": [1, 3, INPUT_SIZE, INPUT_SIZE],
        "scale": 1 / 255.0,
        "transformVersion": INPUT_TRANSFORM_VERSION,
    }
    output_contract = {
        "heatmaps": [
            1,
            len(LANDMARK_NAMES),
            HEATMAP_SIZE,
            HEATMAP_SIZE,
        ],
        "visibility": [
            1,
            len(LANDMARK_NAMES),
            len(VISIBILITY_NAMES),
        ],
    }
    return {
        "promotionStatus": DEVELOPMENT_STATUS,
        "checkpointSHA256": bindings["checkpointSHA256"],
        "manifestSHA256": bindings["checkpoint"]["manifestSHA256"],
        "evaluationSHA256": bindings["evaluationSHA256"],
        "modelSHA256": bindings["modelSHA256"],
        "architecture": ARCHITECTURE,
        "architectureSHA256": _canonical_sha256(ARCHITECTURE),
        "inputTransformVersion": INPUT_TRANSFORM_VERSION,
        "inputContractSHA256": _canonical_sha256(input_contract),
        "landmarkOrder": json.dumps(list(LANDMARK_NAMES)),
        "landmarkOrderSHA256": _canonical_sha256(list(LANDMARK_NAMES)),
        "visibilityClassOrder": json.dumps(list(VISIBILITY_NAMES)),
        "visibilityClassOrderSHA256": _canonical_sha256(
            list(VISIBILITY_NAMES)
        ),
        "inputSize": str(INPUT_SIZE),
        "heatmapSize": str(HEATMAP_SIZE),
        "outputContractSHA256": _canonical_sha256(output_contract),
    }


def _conversion_contract_metadata(bindings):
    metadata = _export_contract(bindings)
    metadata["exportProvenanceHash"] = _canonical_sha256(metadata)
    return metadata


def convert_development_model(network):
    import coremltools as ct

    network = network.to("cpu").eval()
    example = torch.zeros(1, 3, INPUT_SIZE, INPUT_SIZE)
    traced = torch.jit.trace(network, example, strict=True)
    with torch.no_grad():
        heatmaps, visibility = traced(example)
    if tuple(heatmaps.shape) != (
        1,
        len(LANDMARK_NAMES),
        HEATMAP_SIZE,
        HEATMAP_SIZE,
    ):
        raise ValueError("traced model heatmap output shape mismatch")
    if tuple(visibility.shape) != (
        1,
        len(LANDMARK_NAMES),
        len(VISIBILITY_NAMES),
    ):
        raise ValueError("traced model visibility output shape mismatch")
    return ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        inputs=[
            ct.ImageType(
                name="image",
                shape=example.shape,
                scale=1 / 255.0,
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[
            ct.TensorType(name="heatmaps"),
            ct.TensorType(name="visibility"),
        ],
    )


def load_coreml_model(package_path):
    import coremltools as ct

    return ct.models.MLModel(str(package_path))


def _path_exists(path):
    return os.path.lexists(os.fspath(path))


def _atomic_rename_noreplace(source, destination):
    """Atomically publish a directory without replacing any competing path."""
    source_bytes = os.fsencode(source)
    destination_bytes = os.fsencode(destination)
    libc = ctypes.CDLL(None, use_errno=True)
    if sys.platform == "darwin":
        rename = libc.renameatx_np
        rename.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        rename.restype = ctypes.c_int
        result = rename(
            -2, source_bytes, -2, destination_bytes, 0x00000004
        )
    elif sys.platform.startswith("linux") and hasattr(libc, "renameat2"):
        rename = libc.renameat2
        rename.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        rename.restype = ctypes.c_int
        result = rename(
            -100, source_bytes, -100, destination_bytes, 0x00000001
        )
    else:
        raise OSError(
            errno.ENOTSUP,
            "atomic no-replace directory rename is unavailable",
        )
    if result != 0:
        error_number = ctypes.get_errno()
        if error_number in (errno.EEXIST, errno.ENOTEMPTY):
            raise FileExistsError(
                error_number,
                "refusing to replace an existing export bundle",
                os.fspath(destination),
            )
        raise OSError(
            error_number,
            os.strerror(error_number),
            os.fspath(destination),
        )


def _validate_staged_bundle(bundle, expected):
    expected_entries = {
        PACKAGE_NAME: "directory",
        PARITY_NAME: "file",
        BUNDLE_MANIFEST_NAME: "file",
        COMPLETION_MARKER_NAME: "file",
    }
    entries = {path.name: path for path in bundle.iterdir()}
    _require_exact(
        set(entries),
        set(expected_entries),
        "staged export bundle root entries",
    )
    for name, kind in expected_entries.items():
        path = entries[name]
        if path.is_symlink():
            raise ValueError(f"staged export bundle {name} is a symlink")
        if kind == "directory" and not path.is_dir():
            raise ValueError(f"staged export bundle {name} is not a directory")
        if kind == "file" and not path.is_file():
            raise ValueError(f"staged export bundle {name} is not a file")

    package = bundle / PACKAGE_NAME
    parity_path = bundle / PARITY_NAME
    manifest_path = bundle / BUNDLE_MANIFEST_NAME
    marker_path = bundle / COMPLETION_MARKER_NAME
    if package_tree_sha256(package) != expected["packageTreeSHA256"]:
        raise ValueError("staged Core ML package tree hash mismatch")
    actual_manifest_hash = file_sha256(manifest_path)
    marker = marker_path.read_text(encoding="ascii")
    _require_exact(
        marker,
        actual_manifest_hash + "\n",
        "staged export completion marker",
    )
    manifest = _read_report(manifest_path)
    actual_parity_hash = file_sha256(parity_path)
    try:
        declared_parity_hash = manifest["parity"]["fileSHA256"]
    except (KeyError, TypeError) as error:
        raise ValueError(
            "staged export bundle manifest parity hash is missing"
        ) from error
    _require_exact(
        declared_parity_hash,
        actual_parity_hash,
        "staged parity file SHA-256",
    )

    # Semantic checks run only after all root and byte-level bindings pass.
    _require_exact(
        manifest,
        expected["bundleManifest"],
        "staged export bundle manifest",
    )
    _require_exact(
        actual_manifest_hash,
        expected["bundleManifestSHA256"],
        "staged export bundle manifest SHA-256",
    )
    parity = _read_report(parity_path)
    assert_parity_passes(
        parity,
        expected_provenance=expected["provenance"],
        expected_package_tree_sha256=expected["packageTreeSHA256"],
    )


def _run_parity_with_package_immutability(
    network,
    runtime_model,
    dataset,
    package,
    provenance,
    parity_runner,
):
    initial_package_hash = package_tree_sha256(package)
    bound_provenance = dict(provenance)
    bound_provenance["packageTreeSHA256"] = initial_package_hash
    parity = parity_runner(
        network,
        runtime_model,
        dataset,
        provenance=bound_provenance,
    )
    if package_tree_sha256(package) != initial_package_hash:
        raise ValueError("Core ML package changed during parity")
    return dict(parity), bound_provenance, initial_package_hash


def export_development_package(
    checkpoint_path,
    evaluation_path,
    dataset,
    output_bundle_path,
):
    output = Path(output_bundle_path)
    if _path_exists(output):
        raise FileExistsError(
            f"refusing conversion because export bundle already exists: {output}"
        )

    bindings = assert_report_passes(checkpoint_path, evaluation_path)
    checkpoint = bindings["checkpoint"]
    network = GolfHeatmapNet(pretrained=False)
    network.load_state_dict(checkpoint["model"], strict=True)
    network.eval()
    converted = convert_development_model(network)
    converted.author = "SwingArc"
    converted.short_description = (
        "Development golf grip, shaft, clubhead, and ball heatmaps"
    )
    metadata = _conversion_contract_metadata(bindings)
    for name, value in metadata.items():
        converted.user_defined_metadata[name] = str(value)
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{output.name}.staging-",
            dir=output.parent,
        )
    )
    package = staging / PACKAGE_NAME
    parity_path = staging / PARITY_NAME
    bundle_manifest_path = staging / BUNDLE_MANIFEST_NAME
    marker_path = staging / COMPLETION_MARKER_NAME
    try:
        converted.save(package)
        runtime_model = load_coreml_model(package)
        spec_hash = hashlib.sha256(
            runtime_model.get_spec().SerializeToString(
                deterministic=True
            )
        ).hexdigest()
        provenance = {
            "checkpointSHA256": bindings["checkpointSHA256"],
            "manifestSHA256": checkpoint["manifestSHA256"],
            "evaluationSHA256": bindings["evaluationSHA256"],
            "modelSHA256": bindings["modelSHA256"],
            "coreMLSpecSHA256": spec_hash,
            "exportProvenanceHash": metadata["exportProvenanceHash"],
        }
        parity, provenance, package_hash = (
            _run_parity_with_package_immutability(
                network,
                runtime_model,
                dataset,
                package,
                provenance,
                run_coreml_parity,
            )
        )
        parity["packageTreeSHA256"] = package_hash
        assert_parity_passes(
            parity,
            expected_provenance=provenance,
            expected_package_tree_sha256=package_hash,
        )
        parity_path.write_text(
            json.dumps(parity, indent=2, sort_keys=True, allow_nan=False) + "\n",
            encoding="utf-8",
        )
        persisted_parity = _read_report(parity_path)
        assert_parity_passes(
            persisted_parity,
            expected_provenance=provenance,
            expected_package_tree_sha256=package_tree_sha256(package),
        )
        parity_hash = file_sha256(parity_path)
        bundle_manifest = {
            "schemaVersion": EXPORT_BUNDLE_SCHEMA_VERSION,
            "promotionStatus": DEVELOPMENT_STATUS,
            "package": {
                "path": PACKAGE_NAME,
                "treeSHA256": package_hash,
                "coreMLSpecSHA256": spec_hash,
            },
            "parity": {
                "path": PARITY_NAME,
                "fileSHA256": parity_hash,
            },
            "exportProvenanceHash": metadata["exportProvenanceHash"],
        }
        bundle_manifest_path.write_text(
            json.dumps(
                bundle_manifest,
                indent=2,
                sort_keys=True,
                allow_nan=False,
            )
            + "\n",
            encoding="utf-8",
        )
        bundle_manifest_hash = file_sha256(bundle_manifest_path)
        marker_path.write_text(
            bundle_manifest_hash + "\n",
            encoding="ascii",
        )
        expected = {
            "packageTreeSHA256": package_hash,
            "provenance": provenance,
            "bundleManifest": bundle_manifest,
            "bundleManifestSHA256": bundle_manifest_hash,
        }
        _validate_staged_bundle(staging, expected)
        _atomic_rename_noreplace(staging, output)
    finally:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
    return {
        "bundle": str(output),
        "package": str(output / PACKAGE_NAME),
        "paritySidecar": str(output / PARITY_NAME),
        "parity": parity,
        "metadata": metadata,
        "coreMLSpecSHA256": spec_hash,
        "packageTreeSHA256": package_hash,
        "bundleManifestSHA256": bundle_manifest_hash,
    }


def build_argument_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--evaluation", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--expected-manifest-sha256", required=True)
    parser.add_argument("--video-root", required=True)
    parser.add_argument("--output", required=True)
    return parser


def main(argv=None):
    parser = build_argument_parser()
    args = parser.parse_args(argv)
    try:
        bindings = assert_report_passes(
            args.checkpoint,
            args.evaluation,
        )
        expected_manifest = args.expected_manifest_sha256
        if expected_manifest != bindings["checkpoint"]["manifestSHA256"]:
            raise ValueError(
                "expected manifest SHA-256 does not match checkpoint"
            )
        if file_sha256(args.manifest) != expected_manifest:
            raise ValueError(
                "manifest bytes do not match expected SHA-256"
            )
        dataset = GolfHeatmapDataset(
            args.manifest,
            args.video_root,
            "validation",
            expected_manifest_sha256=expected_manifest,
        )
        result = export_development_package(
            args.checkpoint,
            args.evaluation,
            dataset,
            args.output,
        )
        print(json.dumps(result, indent=2, sort_keys=True))
    except (
        FileExistsError,
        OSError,
        ReviewedTrainingLabelsRequired,
        RuntimeError,
        ValueError,
    ) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()

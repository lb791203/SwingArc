import copy
import hashlib
import inspect
import json
import subprocess
import sys

import pytest
import torch

from artifact_hashes import file_sha256, package_tree_sha256
from contracts import (
    HEATMAP_SIZE,
    INPUT_SIZE,
    INPUT_TRANSFORM_VERSION,
    LANDMARK_NAMES,
    VISIBILITY_NAMES,
)
from evaluate import (
    ARCHITECTURE,
    DECODER_VERSION,
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
    VIEWS,
    write_evaluation_report,
)
from export_coreml import (
    _atomic_rename_noreplace,
    _run_parity_with_package_immutability,
    _validate_staged_bundle,
    assert_parity_passes,
    assert_release_status_allowed,
    assert_report_passes,
    export_development_package,
    model_state_sha256,
)
from coreml_parity import (
    PARITY_SCHEMA_VERSION,
    _decoded_pixel_differences,
    _require_model_outputs,
    parity_configuration,
    run_coreml_parity,
)
from metrics import canvas_point_is_in_content_rect
from model import GolfHeatmapNet


def _checkpoint():
    return {
        "artifactKind": "development-training-checkpoint",
        "promotionStatus": "development",
        "architecture": ARCHITECTURE,
        "manifestSHA256": "1" * 64,
        "inputTransformVersion": INPUT_TRANSFORM_VERSION,
        "landmarks": list(LANDMARK_NAMES),
        "visibilityClasses": list(VISIBILITY_NAMES),
        "inputSize": INPUT_SIZE,
        "heatmapSize": HEATMAP_SIZE,
        "model": {
            "weight": torch.tensor([[1.0, 2.0]], dtype=torch.float32),
        },
    }


def _passing_landmark_row():
    return {
        "trueVisibleCount": MINIMUM_VISIBLE_SAMPLES,
        "trueNonVisibleCount": MINIMUM_NONVISIBLE_SAMPLES,
        "validLocationCount": MINIMUM_VISIBLE_SAMPLES,
        "paddingCoordinateCount": 0,
        "paddingCoordinateRate": 0.0,
        "paddingPredictionCount": 0,
        "paddingPredictionRate": 0.0,
        "hitErrorThreshold": 0.02,
        "visibleFrameHitRate": MINIMUM_HIT_RATE,
        "medianSourcePixelError": 0.0,
        "p90SourcePixelError": 0.0,
        "medianDiagonalNormalizedError": MAXIMUM_MEDIAN_ERROR,
        "p90DiagonalNormalizedError": MAXIMUM_P90_ERROR,
        "visibleRecall": MINIMUM_VISIBLE_RECALL,
        "falseVisibleRate": 0.0,
        "longestVisibleGap": MAXIMUM_VISIBLE_GAP,
        "denseSampleCount": MINIMUM_VISIBLE_SAMPLES,
        "denseGapSufficient": True,
        "sufficientSamples": True,
    }


def _passing_shaft_row():
    return {
        "eligibleFrameCount": MINIMUM_SHAFT_SAMPLES,
        "predictedDoubleVisibleCount": MINIMUM_SHAFT_SAMPLES,
        "validAngleCount": MINIMUM_SHAFT_SAMPLES,
        "invalidGeometryCount": 0,
        "predictedDoubleVisibleCoverage": 1.0,
        "medianCircularErrorDegrees": MAXIMUM_SHAFT_MEDIAN_DEGREES,
        "p90CircularErrorDegrees": MAXIMUM_SHAFT_P90_DEGREES,
        "sufficientSamples": True,
    }


def _save_checkpoint(tmp_path):
    path = tmp_path / "candidate.pt"
    checkpoint = _checkpoint()
    torch.save(checkpoint, path)
    return path, checkpoint


def _passing_report(checkpoint_path, checkpoint):
    views = {
        view: {
            "sampleCount": 40,
            "landmarks": {
                name: _passing_landmark_row()
                for name in LANDMARK_NAMES
            },
            "shaftAngles": {
                stage: _passing_shaft_row()
                for stage in SHAFT_STAGES
            },
        }
        for view in VIEWS
    }
    return {
        "schemaVersion": 1,
        "decoderVersion": DECODER_VERSION,
        "split": "validation",
        "sampleCount": 80,
        "viewSampleCounts": {view: 40 for view in VIEWS},
        "views": views,
        "failedThresholds": [],
        "developmentPromotionPassed": True,
        "checkpointSHA256": hashlib.sha256(
            checkpoint_path.read_bytes()
        ).hexdigest(),
        "modelSHA256": model_state_sha256(checkpoint["model"]),
        "manifestSHA256": checkpoint["manifestSHA256"],
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


def _write_report(tmp_path, report):
    path = tmp_path / "evaluation.json"
    path.write_text(json.dumps(report), encoding="utf-8")
    return path


def test_complete_development_report_passes(tmp_path):
    checkpoint_path, checkpoint = _save_checkpoint(tmp_path)
    report_path = _write_report(
        tmp_path,
        _passing_report(checkpoint_path, checkpoint),
    )

    result = assert_report_passes(checkpoint_path, report_path)

    assert result["report"]["developmentPromotionPassed"] is True
    assert result["checkpoint"]["promotionStatus"] == "development"


@pytest.mark.parametrize(
    ("mutation", "message"),
    [
        (
            lambda report: report["views"]["dtl"]["landmarks"]["ball"].update(
                {"sufficientSamples": False}
            ),
            "all landmarks and views",
        ),
        (
            lambda report: report["views"]["face-on"]["shaftAngles"]["P8"].update(
                {"p90CircularErrorDegrees": 7.01}
            ),
            "shaft",
        ),
        (
            lambda report: report.update({"failedThresholds": [{"metric": "x"}]}),
            "failed thresholds",
        ),
        (
            lambda report: report.update({"modelSHA256": "f" * 64}),
            "model",
        ),
    ],
)
def test_report_gate_recomputes_every_required_row(
    tmp_path,
    mutation,
    message,
):
    checkpoint_path, checkpoint = _save_checkpoint(tmp_path)
    report = _passing_report(checkpoint_path, checkpoint)
    mutation(report)
    report_path = _write_report(tmp_path, report)

    with pytest.raises(ValueError, match=message):
        assert_report_passes(checkpoint_path, report_path)


@pytest.mark.parametrize(
    "mutation",
    [
        lambda report: report["views"]["dtl"].update(
            {"sampleCount": 40.5}
        ),
        lambda report: report["viewSampleCounts"].update({"dtl": 40.5}),
        lambda report: report["views"]["dtl"]["landmarks"]["grip"].update(
            {"trueVisibleCount": 30.9}
        ),
        lambda report: report["views"]["dtl"]["landmarks"]["grip"].update(
            {"trueNonVisibleCount": 10.9}
        ),
        lambda report: report["views"]["dtl"]["landmarks"]["grip"].update(
            {"validLocationCount": 30.5}
        ),
        lambda report: report["views"]["dtl"]["landmarks"]["grip"].update(
            {"longestVisibleGap": 2.0}
        ),
        lambda report: report["views"]["dtl"]["shaftAngles"]["P6"].update(
            {"eligibleFrameCount": 30.5}
        ),
    ],
)
def test_report_count_fields_reject_fractional_values(
    tmp_path,
    mutation,
):
    checkpoint_path, checkpoint = _save_checkpoint(tmp_path)
    report = _passing_report(checkpoint_path, checkpoint)
    mutation(report)
    with pytest.raises(ValueError, match="integer"):
        assert_report_passes(
            checkpoint_path,
            _write_report(tmp_path, report),
        )


def test_checkpoint_is_loaded_with_weights_only(monkeypatch, tmp_path):
    checkpoint_path, checkpoint = _save_checkpoint(tmp_path)
    report_path = _write_report(
        tmp_path,
        _passing_report(checkpoint_path, checkpoint),
    )
    original_load = torch.load
    observed = {}

    def guarded_load(*args, **kwargs):
        observed["weights_only"] = kwargs.get("weights_only")
        return original_load(*args, **kwargs)

    monkeypatch.setattr(torch, "load", guarded_load)
    assert_report_passes(checkpoint_path, report_path)

    assert observed["weights_only"] is True


def test_model_state_hash_is_order_independent_and_tensor_sensitive():
    first = {
        "z": torch.tensor([1.0, 2.0], dtype=torch.float32),
        "a": torch.tensor([[3]], dtype=torch.int64),
    }
    reordered = {"a": first["a"].clone(), "z": first["z"].clone()}
    changed = {"a": first["a"].clone(), "z": torch.tensor([1.0, 2.1])}
    assert model_state_sha256(first) == model_state_sha256(reordered)
    assert model_state_sha256(first) != model_state_sha256(changed)


def test_evaluation_model_hash_is_mandatory(tmp_path):
    checkpoint_path, checkpoint = _save_checkpoint(tmp_path)
    report = _passing_report(checkpoint_path, checkpoint)
    del report["modelSHA256"]
    with pytest.raises(ValueError, match="modelSHA256"):
        assert_report_passes(
            checkpoint_path,
            _write_report(tmp_path, report),
        )


def test_evaluation_report_atomically_replaces_snapshot_without_temp_leak(
    tmp_path,
):
    output = tmp_path / "evaluation.json"
    output.write_text('{"old":true}', encoding="utf-8")
    write_evaluation_report({"new": True}, output)
    assert json.loads(output.read_text(encoding="utf-8")) == {"new": True}
    assert not list(tmp_path.glob(".evaluation.json.*.tmp"))


def test_only_development_status_is_allowed(tmp_path):
    checkpoint_path, checkpoint = _save_checkpoint(tmp_path)
    report = _passing_report(checkpoint_path, checkpoint)

    with pytest.raises(ValueError, match="only development"):
        assert_release_status_allowed("release", report)

    heldout = copy.deepcopy(report)
    heldout["split"] = "held-out"
    heldout["heldoutEvidence"] = {
        "locked": True,
        "promotionPassed": True,
        "failedThresholds": [],
    }
    with pytest.raises(ValueError, match="only development"):
        assert_release_status_allowed("release", heldout)
    with pytest.raises(ValueError, match="only development"):
        assert_release_status_allowed("candidate", report)


def _passing_parity():
    package_hash = "7" * 64
    provenance = {
        "checkpointSHA256": "1" * 64,
        "modelSHA256": "2" * 64,
        "manifestSHA256": "3" * 64,
        "evaluationSHA256": "4" * 64,
        "coreMLSpecSHA256": "5" * 64,
        "exportProvenanceHash": "6" * 64,
        "packageTreeSHA256": package_hash,
    }
    return {
        "schemaVersion": PARITY_SCHEMA_VERSION,
        "promotionStatus": "development",
        "configuration": parity_configuration(),
        "maximumAllowedDecodedPixelDifference": 1.0,
        "maximumDecodedPixelDifference": 1.0,
        "visibilityClassMatches": True,
        "paddingClassificationMatches": True,
        "sampleCount": 20,
        "viewSampleCounts": {"dtl": 10, "face-on": 10},
        "sampleSetSHA256": "8" * 64,
        "inputTensorSHA256": "9" * 64,
        "packageTreeSHA256": package_hash,
        "provenance": provenance,
    }


@pytest.mark.parametrize(
    "mutation",
    [
        lambda report: report.update(
            {"maximumDecodedPixelDifference": 1.01}
        ),
        lambda report: report.update(
            {"maximumAllowedDecodedPixelDifference": 1.01}
        ),
        lambda report: report.update({"visibilityClassMatches": False}),
        lambda report: report["viewSampleCounts"].update({"face-on": 9}),
        lambda report: report["viewSampleCounts"].update({"face-on": 10.9}),
        lambda report: report.update(
            {"maximumDecodedPixelDifference": float("nan")}
        ),
        lambda report: report.update({"paddingClassificationMatches": False}),
    ],
)
def test_parity_gate_rejects_any_contract_failure(mutation):
    report = _passing_parity()
    mutation(report)

    with pytest.raises(ValueError, match="parity"):
        assert_parity_passes(report)


@pytest.mark.parametrize(
    "mutation",
    [
        lambda report: report.update({"schemaVersion": 1}),
        lambda report: report.update({"promotionStatus": "release"}),
        lambda report: report["configuration"].update(
            {"samplesPerView": 11}
        ),
        lambda report: report["configuration"].update(
            {"samplesPerView": 10.0}
        ),
        lambda report: report.update({"sampleSetSHA256": "bad"}),
        lambda report: report["provenance"].update(
            {"checkpointSHA256": "a" * 64}
        ),
        lambda report: report.update({"packageTreeSHA256": "b" * 64}),
    ],
)
def test_parity_schema_and_provenance_are_fail_closed(mutation):
    report = _passing_parity()
    mutation(report)
    with pytest.raises(ValueError, match="parity"):
        assert_parity_passes(
            report,
            expected_provenance=_passing_parity()["provenance"],
            expected_package_tree_sha256="7" * 64,
        )


@pytest.mark.parametrize(
    ("heatmaps", "visibility"),
    [
        (torch.zeros(5, 128, 128), torch.zeros(1, 5, 3)),
        (torch.zeros(1, 5, 64, 64), torch.zeros(1, 5, 3)),
        (torch.zeros(1, 5, 128, 128), torch.zeros(5, 3)),
        (torch.zeros(1, 5, 128, 128), torch.zeros(1, 5, 4)),
    ],
)
def test_parity_requires_exact_runtime_tensor_shapes(
    heatmaps,
    visibility,
):
    with pytest.raises(ValueError, match="shape"):
        _require_model_outputs(heatmaps, visibility)


def test_existing_formal_output_blocks_before_conversion(tmp_path):
    checkpoint = tmp_path / "missing.pt"
    evaluation = tmp_path / "missing.json"
    output = tmp_path / "GolfKeypoints.export"
    output.mkdir()

    with pytest.raises(FileExistsError, match="already exists"):
        export_development_package(
            checkpoint,
            evaluation,
            object(),
            output,
        )
    assert output.is_dir()


def test_formal_export_api_has_no_runtime_injection_surface():
    signature = inspect.signature(export_development_package)
    assert list(signature.parameters) == [
        "checkpoint_path",
        "evaluation_path",
        "dataset",
        "output_bundle_path",
    ]
    assert "output_path" not in inspect.signature(
        run_coreml_parity
    ).parameters


def test_atomic_bundle_publication_never_replaces_competitor(tmp_path):
    staging = tmp_path / ".staging"
    destination = tmp_path / "GolfKeypoints.export"
    staging.mkdir()
    destination.mkdir()
    (staging / "source").write_text("source", encoding="utf-8")
    (destination / "competitor").write_text(
        "competitor", encoding="utf-8"
    )
    with pytest.raises(FileExistsError):
        _atomic_rename_noreplace(staging, destination)
    assert (staging / "source").read_text(encoding="utf-8") == "source"
    assert (
        destination / "competitor"
    ).read_text(encoding="utf-8") == "competitor"


def test_content_rect_edge_and_one_over_512_pixel_contract():
    metadata = {
        "content_rect": {
            "offset_x": 64,
            "offset_y": 32,
            "width": 384,
            "height": 448,
        }
    }
    assert canvas_point_is_in_content_rect((448 / 512, 480 / 512), metadata)
    assert not canvas_point_is_in_content_rect(
        ((448 + 0.000001) / 512, 480 / 512),
        metadata,
    )
    difference = _decoded_pixel_differences(
        torch.tensor([[[0.0, 0.0]]]),
        torch.tensor([[[1 / 512, 0.0]]]),
    )
    assert difference.item() == pytest.approx(1.0)


def _staged_bundle_fixture(tmp_path):
    bundle = tmp_path / ".Bundle.staging"
    bundle.mkdir()
    package = bundle / "GolfKeypoints.mlpackage"
    package.mkdir()
    (package / "Manifest.json").write_text("{}", encoding="utf-8")
    package_hash = package_tree_sha256(package)
    parity = _passing_parity()
    parity["packageTreeSHA256"] = package_hash
    parity["provenance"]["packageTreeSHA256"] = package_hash
    parity_path = bundle / "coreml-parity.json"
    parity_path.write_text(
        json.dumps(parity, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    manifest = {
        "schemaVersion": 1,
        "promotionStatus": "development",
        "package": {
            "path": "GolfKeypoints.mlpackage",
            "treeSHA256": package_hash,
            "coreMLSpecSHA256": parity["provenance"][
                "coreMLSpecSHA256"
            ],
        },
        "parity": {
            "path": "coreml-parity.json",
            "fileSHA256": file_sha256(parity_path),
        },
        "exportProvenanceHash": parity["provenance"][
            "exportProvenanceHash"
        ],
    }
    manifest_path = bundle / "export-manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    manifest_hash = file_sha256(manifest_path)
    (bundle / "_SUCCESS").write_text(
        manifest_hash + "\n", encoding="ascii"
    )
    expected = {
        "packageTreeSHA256": package_hash,
        "provenance": parity["provenance"],
        "bundleManifest": manifest,
        "bundleManifestSHA256": manifest_hash,
    }
    _validate_staged_bundle(bundle, expected)
    return bundle, expected


def test_bundle_rejects_reformatted_manifest_even_with_updated_marker(
    tmp_path,
):
    bundle, expected = _staged_bundle_fixture(tmp_path)
    manifest_path = bundle / "export-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest_path.write_text(
        json.dumps(manifest, separators=(",", ":")),
        encoding="utf-8",
    )
    (bundle / "_SUCCESS").write_text(
        file_sha256(manifest_path) + "\n", encoding="ascii"
    )
    with pytest.raises(ValueError, match="manifest SHA-256"):
        _validate_staged_bundle(bundle, expected)


@pytest.mark.parametrize("change_metric", [False, True])
def test_bundle_rejects_reformatted_or_changed_parity(
    tmp_path,
    change_metric,
):
    bundle, expected = _staged_bundle_fixture(tmp_path)
    parity_path = bundle / "coreml-parity.json"
    parity = json.loads(parity_path.read_text(encoding="utf-8"))
    if change_metric:
        parity["maximumDecodedPixelDifference"] = 0.5
    parity_path.write_text(
        json.dumps(parity, separators=(",", ":")),
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="parity file SHA-256"):
        _validate_staged_bundle(bundle, expected)


def test_bundle_rejects_extra_root_payload(tmp_path):
    bundle, expected = _staged_bundle_fixture(tmp_path)
    (bundle / "unexpected.bin").write_bytes(b"unexpected")
    with pytest.raises(ValueError, match="root entries"):
        _validate_staged_bundle(bundle, expected)


def test_private_parity_harness_rejects_package_mutation_without_publish(
    tmp_path,
):
    package = tmp_path / "GolfKeypoints.mlpackage"
    package.mkdir()
    payload = package / "Manifest.json"
    payload.write_text("before", encoding="utf-8")
    formal_bundle = tmp_path / "Formal.export"

    def mutating_runner(
        _network,
        _runtime,
        _dataset,
        *,
        provenance,
    ):
        payload.write_text("after", encoding="utf-8")
        report = _passing_parity()
        report["provenance"] = dict(provenance)
        return report

    with pytest.raises(ValueError, match="changed during parity"):
        _run_parity_with_package_immutability(
            object(),
            object(),
            object(),
            package,
            {
                key: value
                for key, value in _passing_parity()["provenance"].items()
                if key != "packageTreeSHA256"
            },
            mutating_runner,
        )
    assert not formal_bundle.exists()


def test_real_formal_export_publishes_one_verified_bundle(tmp_path):
    pytest.importorskip("coremltools")
    import coremltools as ct

    checkpoint_path = tmp_path / "actual-model.pt"
    checkpoint = _checkpoint()
    checkpoint["model"] = GolfHeatmapNet(pretrained=False).state_dict()
    torch.save(checkpoint, checkpoint_path)
    report_path = _write_report(
        tmp_path,
        _passing_report(checkpoint_path, checkpoint),
    )
    image = torch.zeros(3, INPUT_SIZE, INPUT_SIZE)

    class FixedDataset:
        split = "validation"

        def __len__(self):
            return 20

        def __getitem__(self, index):
            view = "dtl" if index < 10 else "face-on"
            metadata = {
                "clip_id": f"{view}-clip",
                "source_frame_index": index,
                "view": view,
                "content_rect": {
                    "offset_x": 0,
                    "offset_y": 0,
                    "width": INPUT_SIZE,
                    "height": INPUT_SIZE,
                },
            }
            return (
                image,
                torch.zeros(5, HEATMAP_SIZE, HEATMAP_SIZE),
                torch.zeros(5, dtype=torch.long),
                torch.ones(5),
                metadata,
            )

    bundle = tmp_path / "GolfKeypoints.export"
    result = export_development_package(
        checkpoint_path,
        report_path,
        FixedDataset(),
        bundle,
    )
    assert set(path.name for path in bundle.iterdir()) == {
        "GolfKeypoints.mlpackage",
        "coreml-parity.json",
        "export-manifest.json",
        "_SUCCESS",
    }
    package = bundle / "GolfKeypoints.mlpackage"
    runtime = ct.models.MLModel(str(package))
    saved_spec_hash = hashlib.sha256(
        runtime.get_spec().SerializeToString(deterministic=True)
    ).hexdigest()
    subprocess_spec_hash = subprocess.check_output(
        [
            sys.executable,
            "-c",
            (
                "import hashlib,sys,coremltools as ct;"
                "spec=ct.models.MLModel(sys.argv[1]).get_spec();"
                "print(hashlib.sha256(spec.SerializeToString("
                "deterministic=True)).hexdigest())"
            ),
            str(package),
        ],
        text=True,
    ).strip()
    parity = json.loads(
        (bundle / "coreml-parity.json").read_text(encoding="utf-8")
    )
    assert saved_spec_hash == result["coreMLSpecSHA256"]
    assert saved_spec_hash == parity["provenance"]["coreMLSpecSHA256"]
    assert subprocess_spec_hash == saved_spec_hash
    assert package_tree_sha256(package) == result["packageTreeSHA256"]
    assert (
        runtime.user_defined_metadata["exportProvenanceHash"]
        == result["metadata"]["exportProvenanceHash"]
    )
    assert "packageTreeSHA256" not in runtime.user_defined_metadata
    assert parity["sampleCount"] == 20
    assert parity["viewSampleCounts"] == {"dtl": 10, "face-on": 10}
    assert not list(tmp_path.glob(".GolfKeypoints.export.staging-*"))
    with pytest.raises(FileExistsError):
        export_development_package(
            tmp_path / "missing.pt",
            tmp_path / "missing.json",
            FixedDataset(),
            bundle,
        )

    class InsufficientFaceOnDataset(FixedDataset):
        def __len__(self):
            return 19

    failed_bundle = tmp_path / "Failed.export"
    with pytest.raises(ValueError, match="fixed validation samples"):
        export_development_package(
            checkpoint_path,
            report_path,
            InsufficientFaceOnDataset(),
            failed_bundle,
        )
    assert not failed_bundle.exists()
    assert not list(tmp_path.glob(".Failed.export.staging-*"))

import hashlib
import numpy as np
import torch
from torchvision.transforms import functional as transforms

from artifact_hashes import canonical_json_sha256
from contracts import (
    HEATMAP_SIZE,
    INPUT_SIZE,
    INPUT_TRANSFORM_VERSION,
    LANDMARK_NAMES,
    VISIBILITY_NAMES,
)
from metrics import canvas_point_is_in_content_rect
from model import heatmap_soft_argmax


REQUIRED_VIEWS = ("dtl", "face-on")
MINIMUM_SAMPLES_PER_VIEW = 10
MAXIMUM_DECODED_PIXEL_DIFFERENCE = 1.0
PARITY_SCHEMA_VERSION = 2


def parity_configuration(per_view=MINIMUM_SAMPLES_PER_VIEW):
    return {
        "requiredViews": list(REQUIRED_VIEWS),
        "samplesPerView": per_view,
        "maximumDecodedPixelDifference": (
            MAXIMUM_DECODED_PIXEL_DIFFERENCE
        ),
        "inputTransformVersion": INPUT_TRANSFORM_VERSION,
        "inputTensorShape": [1, 3, INPUT_SIZE, INPUT_SIZE],
        "heatmapTensorShape": [
            1, len(LANDMARK_NAMES), HEATMAP_SIZE, HEATMAP_SIZE
        ],
        "visibilityTensorShape": [
            1, len(LANDMARK_NAMES), len(VISIBILITY_NAMES)
        ],
    }


def _sample_identity(metadata):
    return {
        "clipID": metadata.get("clip_id"),
        "sourceFrameIndex": metadata.get("source_frame_index"),
        "view": metadata.get("view"),
    }


def _fixed_validation_samples(dataset, per_view):
    if getattr(dataset, "split", None) != "validation":
        raise ValueError("parity requires the validation dataset split")
    selected = {view: [] for view in REQUIRED_VIEWS}
    for index in range(len(dataset)):
        item = dataset[index]
        if not isinstance(item, (tuple, list)) or len(item) != 5:
            raise ValueError("parity dataset item contract mismatch")
        image, _heatmaps, _visibility, _mask, metadata = item
        if not isinstance(metadata, dict):
            raise ValueError("parity sample metadata must be an object")
        view = metadata.get("view")
        if view not in selected:
            raise ValueError(f"unsupported parity view {view!r}")
        if len(selected[view]) < per_view:
            selected[view].append((image, metadata))
        if all(len(values) >= per_view for values in selected.values()):
            break
    counts = {view: len(values) for view, values in selected.items()}
    if any(count < per_view for count in counts.values()):
        raise ValueError(
            "parity requires at least "
            f"{per_view} fixed validation samples per view; got {counts}"
        )
    return [
        item
        for view in REQUIRED_VIEWS
        for item in selected[view]
    ]


def _require_model_outputs(heatmaps, visibility):
    heatmaps = torch.as_tensor(heatmaps).detach().cpu().float()
    visibility = torch.as_tensor(visibility).detach().cpu().float()
    expected_heatmap_shape = (
        1,
        len(LANDMARK_NAMES),
        HEATMAP_SIZE,
        HEATMAP_SIZE,
    )
    expected_visibility_shape = (
        1,
        len(LANDMARK_NAMES),
        len(VISIBILITY_NAMES),
    )
    if tuple(heatmaps.shape) != expected_heatmap_shape:
        raise ValueError("parity heatmap output shape mismatch")
    if tuple(visibility.shape) != expected_visibility_shape:
        raise ValueError("parity visibility output shape mismatch")
    if not torch.isfinite(heatmaps).all().item():
        raise ValueError("parity heatmaps contain non-finite values")
    if not torch.isfinite(visibility).all().item():
        raise ValueError("parity visibility logits contain non-finite values")
    return heatmaps, visibility


def _coreml_outputs(prediction):
    if not isinstance(prediction, dict):
        raise ValueError("Core ML prediction must be a dictionary")
    try:
        heatmaps = prediction["heatmaps"]
        visibility = prediction["visibility"]
    except KeyError as error:
        raise ValueError(
            "Core ML prediction is missing named heatmap/visibility outputs"
        ) from error
    return _require_model_outputs(heatmaps, visibility)


def _decoded_pixel_differences(torch_points, coreml_points):
    return torch.linalg.vector_norm(
        (torch_points - coreml_points) * INPUT_SIZE,
        dim=-1,
    )


def run_coreml_parity(
    torch_model,
    coreml_model,
    dataset,
    *,
    provenance,
    per_view=MINIMUM_SAMPLES_PER_VIEW,
):
    if per_view < MINIMUM_SAMPLES_PER_VIEW:
        raise ValueError(
            "parity requires at least 10 samples per required view"
        )
    samples = _fixed_validation_samples(dataset, per_view)
    if not isinstance(provenance, dict) or not provenance:
        raise ValueError("parity provenance is missing")
    torch_model = torch_model.to("cpu").eval()
    maximum_difference = 0.0
    visibility_matches = True
    padding_matches = True
    view_counts = {view: 0 for view in REQUIRED_VIEWS}
    identities = []
    input_records = []

    with torch.no_grad():
        for image, metadata in samples:
            image = torch.as_tensor(image).detach().cpu().float()
            if tuple(image.shape) != (3, INPUT_SIZE, INPUT_SIZE):
                raise ValueError("parity image shape must be [3, 512, 512]")
            if not torch.isfinite(image).all().item():
                raise ValueError("parity image contains non-finite values")
            if image.min().item() < 0 or image.max().item() > 1:
                raise ValueError("parity image must be in the [0, 1] range")
            identity = _sample_identity(metadata)
            view = identity["view"]
            view_counts[view] += 1
            identities.append(identity)
            input_records.append({
                "identity": identity,
                "tensorSHA256": hashlib.sha256(
                    image.contiguous().numpy().tobytes(order="C")
                ).hexdigest(),
            })

            torch_heatmaps, torch_visibility = _require_model_outputs(
                *torch_model(image.unsqueeze(0))
            )
            pil_image = transforms.to_pil_image(image)
            coreml_heatmaps, coreml_visibility = _coreml_outputs(
                coreml_model.predict({"image": pil_image})
            )
            torch_points = heatmap_soft_argmax(torch_heatmaps)[0]
            coreml_points = heatmap_soft_argmax(coreml_heatmaps)[0]
            differences = _decoded_pixel_differences(
                torch_points, coreml_points
            )
            maximum_difference = max(
                maximum_difference,
                float(differences.max().item()),
            )
            visibility_matches = visibility_matches and torch.equal(
                torch.argmax(torch_visibility, dim=-1),
                torch.argmax(coreml_visibility, dim=-1),
            )
            for landmark_index in range(len(LANDMARK_NAMES)):
                padding_matches = padding_matches and (
                    canvas_point_is_in_content_rect(
                        torch_points[landmark_index].tolist(), metadata
                    )
                    == canvas_point_is_in_content_rect(
                        coreml_points[landmark_index].tolist(), metadata
                    )
                )

    report = {
        "schemaVersion": PARITY_SCHEMA_VERSION,
        "promotionStatus": "development",
        "configuration": parity_configuration(per_view),
        "maximumAllowedDecodedPixelDifference": (
            MAXIMUM_DECODED_PIXEL_DIFFERENCE
        ),
        "maximumDecodedPixelDifference": maximum_difference,
        "visibilityClassMatches": bool(visibility_matches),
        "paddingClassificationMatches": bool(padding_matches),
        "sampleCount": len(samples),
        "viewSampleCounts": view_counts,
        "sampleSetSHA256": canonical_json_sha256(identities),
        "inputTensorSHA256": canonical_json_sha256(input_records),
        "provenance": dict(provenance),
    }
    return report

import torch
import torch.nn.functional as functional

from contracts import LANDMARK_NAMES, VISIBILITY_INDEX, VISIBILITY_NAMES


SHAFT_MIN_NORM_PIXELS = 2.0
SOFT_ARGMAX_UNIFORM_PRIOR_MASS = 1.0


def _zero_loss(reference):
    return reference.sum() * 0.0


def _stable_heatmap_soft_argmax(heatmaps):
    batch, landmark_count, height, width = heatmaps.shape
    nonnegative = heatmaps.clamp_min(0)
    prior_per_pixel = (
        SOFT_ARGMAX_UNIFORM_PRIOR_MASS / (height * width)
    )
    stabilized = nonnegative + prior_per_pixel
    weights = stabilized / stabilized.sum(
        dim=(-2, -1), keepdim=True
    )
    x_axis = torch.linspace(
        0, 1, width, dtype=heatmaps.dtype, device=heatmaps.device
    )
    y_axis = torch.linspace(
        0, 1, height, dtype=heatmaps.dtype, device=heatmaps.device
    )
    y_grid, x_grid = torch.meshgrid(y_axis, x_axis, indexing="ij")
    x = (weights * x_grid).sum(dim=(-2, -1))
    y = (weights * y_grid).sum(dim=(-2, -1))
    return torch.stack((x, y), dim=-1).reshape(
        batch, landmark_count, 2
    )


def _safe_unit_vector(vector, minimum_norm):
    norm = torch.linalg.vector_norm(vector, dim=-1, keepdim=True)
    return vector / norm.clamp_min(minimum_norm)


def _shaft_angle_loss(
    predicted_heatmaps,
    target_heatmaps,
    visibility_targets,
    coordinate_mask,
):
    shaft_start = LANDMARK_NAMES.index("shaft_start")
    shaft_end = LANDMARK_NAMES.index("shaft_end")
    visible = VISIBILITY_INDEX["visible"]
    shaft_mask = (
        coordinate_mask[:, shaft_start]
        & coordinate_mask[:, shaft_end]
        & visibility_targets[:, shaft_start].eq(visible)
        & visibility_targets[:, shaft_end].eq(visible)
    )
    if not torch.any(shaft_mask):
        return _zero_loss(predicted_heatmaps)

    # GolfHeatmapNet has already applied sigmoid. Normalize non-negative mass
    # directly and add one pixel-equivalent of uniform prior mass so empty or
    # near-empty maps have bounded derivatives.
    predicted_points = _stable_heatmap_soft_argmax(predicted_heatmaps)
    target_points = _stable_heatmap_soft_argmax(target_heatmaps)
    predicted_shaft = (
        predicted_points[:, shaft_end] - predicted_points[:, shaft_start]
    )
    target_shaft = target_points[:, shaft_end] - target_points[:, shaft_start]
    minimum_norm = SHAFT_MIN_NORM_PIXELS / (
        max(predicted_heatmaps.shape[-2:]) - 1
    )
    predicted_direction = _safe_unit_vector(
        predicted_shaft[shaft_mask], minimum_norm
    )
    target_direction = _safe_unit_vector(
        target_shaft[shaft_mask], minimum_norm
    )
    cosine = (predicted_direction * target_direction).sum(dim=-1)
    return (1.0 - cosine).mean()


def _balanced_heatmap_mse(
    predicted_heatmaps,
    target_heatmaps,
    coordinate_mask,
):
    if not torch.any(coordinate_mask):
        return _zero_loss(predicted_heatmaps)

    squared_error = (predicted_heatmaps - target_heatmaps).square()
    foreground_weight = target_heatmaps.clamp(0, 1)
    background_weight = 1.0 - foreground_weight
    foreground = (
        squared_error * foreground_weight
    ).sum(dim=(-2, -1)) / foreground_weight.sum(
        dim=(-2, -1)
    ).clamp_min(
        torch.finfo(predicted_heatmaps.dtype).eps
    )
    background = (
        squared_error * background_weight
    ).sum(dim=(-2, -1)) / background_weight.sum(
        dim=(-2, -1)
    ).clamp_min(
        torch.finfo(predicted_heatmaps.dtype).eps
    )
    per_heatmap = 0.5 * (foreground + background)
    return per_heatmap[coordinate_mask].mean()


def golf_keypoint_loss(
    predicted_heatmaps,
    visibility_logits,
    target_heatmaps,
    visibility_targets,
    coordinate_mask,
    visibility_class_weights=None,
):
    """Compute coordinate-masked heatmap, visibility, and shaft losses."""
    if predicted_heatmaps.shape != target_heatmaps.shape:
        raise ValueError("predicted and target heatmaps must have the same shape")
    if predicted_heatmaps.ndim != 4:
        raise ValueError("heatmaps must have shape [batch, landmarks, height, width]")
    if coordinate_mask.shape != predicted_heatmaps.shape[:2]:
        raise ValueError("coordinate mask must have shape [batch, landmarks]")
    if visibility_targets.shape != predicted_heatmaps.shape[:2]:
        raise ValueError("visibility targets must have shape [batch, landmarks]")
    expected_visibility_shape = (
        *predicted_heatmaps.shape[:2],
        len(VISIBILITY_NAMES),
    )
    if visibility_logits.shape != expected_visibility_shape:
        raise ValueError(
            "visibility logits must have shape [batch, landmarks, classes]"
        )

    heatmap_error = _balanced_heatmap_mse(
        predicted_heatmaps,
        target_heatmaps,
        coordinate_mask,
    )

    valid_visibility = visibility_targets.ne(-100)
    if torch.any(valid_visibility):
        class_weights = visibility_class_weights
        if class_weights is not None:
            class_weights = torch.as_tensor(
                class_weights,
                dtype=visibility_logits.dtype,
                device=visibility_logits.device,
            )
        visibility_error = functional.cross_entropy(
            visibility_logits.reshape(-1, len(VISIBILITY_NAMES)),
            visibility_targets.reshape(-1),
            ignore_index=-100,
            weight=class_weights,
        )
    else:
        visibility_error = _zero_loss(visibility_logits)

    shaft_angle = _shaft_angle_loss(
        predicted_heatmaps,
        target_heatmaps,
        visibility_targets,
        coordinate_mask,
    )
    total = heatmap_error + 0.25 * visibility_error + 0.10 * shaft_angle
    return {
        "total": total,
        "heatmap": heatmap_error,
        "visibility": visibility_error,
        "shaft_angle": shaft_angle,
    }

import math

import torch

from contracts import INPUT_SIZE, INPUT_TRANSFORM_VERSION

CONTENT_RECT_TOLERANCE = 1e-9
SHAFT_LENGTH_EPSILON_PIXELS = 1e-9


def deterministic_percentile(values, percentile):
    """Return the deterministic nearest-rank percentile, or ``None``."""
    if not 0 <= percentile <= 100:
        raise ValueError("percentile must be between 0 and 100")
    tensor = torch.as_tensor(values, dtype=torch.float64).reshape(-1)
    tensor = tensor[torch.isfinite(tensor)]
    if tensor.numel() == 0:
        return None
    ordered = torch.sort(tensor).values
    if percentile == 0:
        index = 0
    else:
        index = math.ceil(percentile / 100.0 * ordered.numel()) - 1
    return float(ordered[index].item())


def canvas_to_source_normalized(point, metadata):
    """Invert the frozen full-frame aspect-fit transform in sample metadata."""
    if metadata.get("input_transform_version") != INPUT_TRANSFORM_VERSION:
        raise ValueError("evaluation metadata input transform version mismatch")
    content_rect = metadata.get("content_rect")
    if not isinstance(content_rect, dict):
        raise ValueError("evaluation metadata content rectangle is missing")
    try:
        width = float(content_rect["width"])
        height = float(content_rect["height"])
        offset_x = float(content_rect["offset_x"])
        offset_y = float(content_rect["offset_y"])
        canvas_x = float(point[0])
        canvas_y = float(point[1])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("invalid evaluation coordinate metadata") from error
    if (
        not all(math.isfinite(value) for value in (
            width,
            height,
            offset_x,
            offset_y,
            canvas_x,
            canvas_y,
        ))
        or width <= 0
        or height <= 0
    ):
        raise ValueError("invalid evaluation coordinate metadata")
    return (
        (canvas_x * INPUT_SIZE - offset_x) / width,
        (canvas_y * INPUT_SIZE - offset_y) / height,
    )


def canvas_point_is_in_content_rect(
    point,
    metadata,
    tolerance=CONTENT_RECT_TOLERANCE,
):
    """Check the closed aspect-fit content rectangle before inversion."""
    content_rect = metadata.get("content_rect")
    if not isinstance(content_rect, dict):
        raise ValueError("evaluation metadata content rectangle is missing")
    try:
        canvas_x = float(point[0]) * INPUT_SIZE
        canvas_y = float(point[1]) * INPUT_SIZE
        offset_x = float(content_rect["offset_x"])
        offset_y = float(content_rect["offset_y"])
        width = float(content_rect["width"])
        height = float(content_rect["height"])
        tolerance = float(tolerance)
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("invalid evaluation coordinate metadata") from error
    if not all(math.isfinite(value) for value in (
        canvas_x,
        canvas_y,
        offset_x,
        offset_y,
        width,
        height,
        tolerance,
    )):
        raise ValueError("invalid evaluation coordinate metadata")
    if width <= 0 or height <= 0 or not 0 <= tolerance <= 1e-9:
        raise ValueError("invalid content rectangle or tolerance")
    return (
        offset_x - tolerance
        <= canvas_x
        <= offset_x + width + tolerance
        and offset_y - tolerance
        <= canvas_y
        <= offset_y + height + tolerance
    )


def source_normalized_to_pixels(point, metadata):
    try:
        width = int(metadata["source_oriented_width"])
        height = int(metadata["source_oriented_height"])
        source_x = float(point[0])
        source_y = float(point[1])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("oriented source dimensions are missing") from error
    if (
        width <= 0
        or height <= 0
        or not math.isfinite(source_x)
        or not math.isfinite(source_y)
    ):
        raise ValueError("invalid oriented source coordinate metadata")
    return source_x * width, source_y * height


def source_pixel_error(predicted_canvas, target_canvas, metadata):
    predicted_source = canvas_to_source_normalized(
        predicted_canvas, metadata
    )
    target_source = canvas_to_source_normalized(target_canvas, metadata)
    predicted_pixels = source_normalized_to_pixels(
        predicted_source, metadata
    )
    target_pixels = source_normalized_to_pixels(target_source, metadata)
    error_pixels = math.hypot(
        predicted_pixels[0] - target_pixels[0],
        predicted_pixels[1] - target_pixels[1],
    )
    diagonal = math.hypot(
        metadata["source_oriented_width"],
        metadata["source_oriented_height"],
    )
    normalized = error_pixels / diagonal
    # Exact target coordinates pass through float32 model tensors in tests and
    # inference. Suppress only representation noise far below every gate.
    if normalized < 1e-7:
        error_pixels = 0.0
        normalized = 0.0
    return {
        "predictedSourceNormalized": predicted_source,
        "targetSourceNormalized": target_source,
        "predictedSourcePixels": predicted_pixels,
        "targetSourcePixels": target_pixels,
        "sourcePixelError": error_pixels,
        "diagonalNormalizedError": normalized,
    }


def dense_longest_visible_gap(records):
    """Return a gap only when a dense clip has contiguous source frames."""
    grouped = {}
    for (
        clip_id,
        source_frame_index,
        true_visible,
        missed,
        is_dense,
    ) in records:
        if not is_dense:
            continue
        grouped.setdefault(str(clip_id), []).append((
            int(source_frame_index),
            bool(true_visible),
            bool(missed),
        ))
    dense_count = sum(len(values) for values in grouped.values())
    eligible_groups = []
    has_three_frame_visible_run = False
    for values in grouped.values():
        ordered = sorted(values)
        indexes = [item[0] for item in ordered]
        is_unique = len(indexes) == len(set(indexes))
        is_contiguous = is_unique and all(
            current == previous + 1
            for previous, current in zip(indexes, indexes[1:])
        )
        if is_contiguous and len(ordered) >= 3:
            eligible_groups.append(ordered)
            current_visible = 0
            for _, true_visible, _ in ordered:
                current_visible = current_visible + 1 if true_visible else 0
                has_three_frame_visible_run = (
                    has_three_frame_visible_run or current_visible >= 3
                )
    # A partial/non-contiguous dense declaration is not auditable. Require
    # every declared dense clip to be a complete contiguous sequence.
    sufficient = (
        bool(grouped)
        and len(eligible_groups) == len(grouped)
        and has_three_frame_visible_run
    )
    if not sufficient:
        return None, False, dense_count
    longest = 0
    for ordered in eligible_groups:
        current = 0
        for _, true_visible, missed in ordered:
            if true_visible and missed:
                current += 1
                longest = max(longest, current)
            else:
                current = 0
    return longest, True, dense_count


def shaft_angle_degrees(start, end):
    start_tensor = torch.as_tensor(start)
    end_tensor = torch.as_tensor(end)
    delta = end_tensor - start_tensor
    return torch.rad2deg(torch.atan2(delta[..., 1], delta[..., 0]))


def circular_angle_error_degrees(predicted, target):
    predicted_tensor = torch.as_tensor(predicted)
    target_tensor = torch.as_tensor(target)
    return torch.abs((predicted_tensor - target_tensor + 180) % 360 - 180)

import math
import hashlib


LANDMARK_NAMES = (
    "grip",
    "shaft_start",
    "shaft_end",
    "clubhead",
    "ball",
)
MANIFEST_NAMES = {
    "grip": "grip",
    "shaft_start": "shaftStart",
    "shaft_end": "shaftEnd",
    "clubhead": "clubhead",
    "ball": "ball",
}
VISIBILITY_NAMES = ("visible", "occluded", "out-of-frame")
VISIBILITY_INDEX = {
    name: index for index, name in enumerate(VISIBILITY_NAMES)
}
INPUT_SIZE = 512
HEATMAP_SIZE = 128
IGNORE_VISIBILITY = -100
INPUT_TRANSFORM_VERSION = "full-frame-aspect-fit-v1"


class ReviewedTrainingLabelsRequired(ValueError):
    """The supplied export is not eligible to produce training samples."""


def require_finite_number(value, field):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ReviewedTrainingLabelsRequired(f"{field} must be a finite number")
    number = float(value)
    if not math.isfinite(number):
        raise ReviewedTrainingLabelsRequired(f"{field} must be a finite number")
    return number


def aspect_fit_transform(source_width, source_height):
    if (
        isinstance(source_width, bool)
        or isinstance(source_height, bool)
        or not isinstance(source_width, int)
        or not isinstance(source_height, int)
        or source_width <= 0
        or source_height <= 0
    ):
        raise ReviewedTrainingLabelsRequired(
            "oriented source dimensions must be positive integers"
        )
    if source_width >= source_height:
        content_width = INPUT_SIZE
        rounded_height = (
            2 * INPUT_SIZE * source_height + source_width
        ) // (2 * source_width)
        content_height = max(1, rounded_height)
    else:
        rounded_width = (
            2 * INPUT_SIZE * source_width + source_height
        ) // (2 * source_height)
        content_width = max(1, rounded_width)
        content_height = INPUT_SIZE
    offset_x = (INPUT_SIZE - content_width) // 2
    offset_y = (INPUT_SIZE - content_height) // 2
    return {
        "version": INPUT_TRANSFORM_VERSION,
        "sourceOrientedWidth": source_width,
        "sourceOrientedHeight": source_height,
        "canvasWidth": INPUT_SIZE,
        "canvasHeight": INPUT_SIZE,
        "contentWidth": content_width,
        "contentHeight": content_height,
        "offsetX": offset_x,
        "offsetY": offset_y,
        "forward": {
            "scaleX": content_width / INPUT_SIZE,
            "scaleY": content_height / INPUT_SIZE,
            "translateX": offset_x / INPUT_SIZE,
            "translateY": offset_y / INPUT_SIZE,
        },
        "inverse": {
            "scaleX": INPUT_SIZE / content_width,
            "scaleY": INPUT_SIZE / content_height,
            "translateX": -offset_x / content_width,
            "translateY": -offset_y / content_height,
        },
    }


def input_transform_sha256(transform):
    fields = (
        transform["version"],
        transform["sourceOrientedWidth"],
        transform["sourceOrientedHeight"],
        transform["canvasWidth"],
        transform["canvasHeight"],
        transform["contentWidth"],
        transform["contentHeight"],
        transform["offsetX"],
        transform["offsetY"],
    )
    canonical = "|".join(str(value) for value in fields).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def source_to_canvas(x, y, transform):
    source_x = require_finite_number(x, "source x")
    source_y = require_finite_number(y, "source y")
    if not (0 <= source_x <= 1 and 0 <= source_y <= 1):
        raise ReviewedTrainingLabelsRequired(
            "visible point is outside the full frame"
        )
    canvas_x = (
        transform["offsetX"] + source_x * transform["contentWidth"]
    ) / INPUT_SIZE
    canvas_y = (
        transform["offsetY"] + source_y * transform["contentHeight"]
    ) / INPUT_SIZE
    if not (0 <= canvas_x <= 1 and 0 <= canvas_y <= 1):
        raise ReviewedTrainingLabelsRequired(
            "visible point is outside the input canvas"
        )
    return canvas_x, canvas_y


def canvas_to_source(x, y, transform):
    canvas_x = require_finite_number(x, "canvas x")
    canvas_y = require_finite_number(y, "canvas y")
    return (
        (canvas_x * INPUT_SIZE - transform["offsetX"])
        / transform["contentWidth"],
        (canvas_y * INPUT_SIZE - transform["offsetY"])
        / transform["contentHeight"],
    )

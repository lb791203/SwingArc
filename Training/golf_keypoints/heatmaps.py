import math

import torch

from contracts import (
    HEATMAP_SIZE,
    ReviewedTrainingLabelsRequired,
)


def gaussian_heatmap(x, y, size=HEATMAP_SIZE, sigma=1.5):
    if (
        not (math.isfinite(x) and math.isfinite(y))
        or not (0 <= x <= 1 and 0 <= y <= 1)
    ):
        raise ReviewedTrainingLabelsRequired(
            "visible point is outside the input canvas"
        )
    if not isinstance(size, int) or size <= 0:
        raise ValueError("heatmap size must be a positive integer")
    if not math.isfinite(sigma) or sigma <= 0:
        raise ValueError("heatmap sigma must be positive and finite")

    xs = torch.arange(size, dtype=torch.float32)
    ys = torch.arange(size, dtype=torch.float32)
    grid_y, grid_x = torch.meshgrid(ys, xs, indexing="ij")
    center_x = x * (size - 1)
    center_y = y * (size - 1)
    return torch.exp(
        -((grid_x - center_x) ** 2 + (grid_y - center_y) ** 2)
        / (2 * sigma ** 2)
    )

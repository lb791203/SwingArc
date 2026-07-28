import torch
import torch.nn.functional as functional
from torch import nn
from torchvision.models import MobileNet_V3_Small_Weights, mobilenet_v3_small

from contracts import LANDMARK_NAMES, VISIBILITY_NAMES


class GolfHeatmapNet(nn.Module):
    """Five-landmark heatmap model backed by a MobileNetV3-Small FPN."""

    FEATURE_INDICES = (1, 3, 8, 12)
    FEATURE_CHANNELS = (16, 24, 48, 576)

    def __init__(self, pretrained=True):
        super().__init__()
        weights = MobileNet_V3_Small_Weights.DEFAULT if pretrained else None
        self.features = mobilenet_v3_small(weights=weights).features
        self.lateral = nn.ModuleList(
            nn.Conv2d(channels, 64, kernel_size=1)
            for channels in self.FEATURE_CHANNELS
        )
        self.smooth = nn.ModuleList(
            nn.Conv2d(64, 64, kernel_size=3, padding=1)
            for _ in range(len(self.FEATURE_CHANNELS) - 1)
        )
        self.heatmap_head = nn.Sequential(
            nn.Conv2d(64, 64, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            nn.Conv2d(64, len(LANDMARK_NAMES), kernel_size=1),
        )
        self.visibility_head = nn.Sequential(
            nn.AdaptiveAvgPool2d(1),
            nn.Flatten(),
            nn.Linear(
                self.FEATURE_CHANNELS[-1],
                len(LANDMARK_NAMES) * len(VISIBILITY_NAMES),
            ),
        )
        self.register_buffer(
            "image_mean",
            torch.tensor([0.485, 0.456, 0.406]).reshape(1, 3, 1, 1),
        )
        self.register_buffer(
            "image_std",
            torch.tensor([0.229, 0.224, 0.225]).reshape(1, 3, 1, 1),
        )

    def forward(self, image):
        normalized = (image - self.image_mean) / self.image_std
        captured = []
        feature = normalized
        capture_index = 0
        for index, layer in enumerate(self.features):
            feature = layer(feature)
            if index == self.FEATURE_INDICES[capture_index]:
                captured.append(feature)
                capture_index += 1
                if capture_index == len(self.FEATURE_INDICES):
                    break

        pyramid = self.lateral[-1](captured[-1])
        for level in range(len(captured) - 2, -1, -1):
            pyramid = self.lateral[level](captured[level]) + functional.interpolate(
                pyramid,
                scale_factor=2.0,
                mode="bilinear",
                align_corners=False,
            )
            pyramid = self.smooth[level](pyramid)

        heatmaps = torch.sigmoid(self.heatmap_head(pyramid))
        visibility = self.visibility_head(captured[-1]).reshape(
            -1,
            len(LANDMARK_NAMES),
            len(VISIBILITY_NAMES),
        )
        return heatmaps, visibility


def heatmap_soft_argmax(heatmaps, input_is_logits=False):
    """Decode heatmaps to normalized ``(x, y)`` coordinates."""
    if heatmaps.ndim != 4:
        raise ValueError("heatmaps must have shape [batch, landmarks, height, width]")

    batch, landmark_count, height, width = heatmaps.shape
    flattened = heatmaps.reshape(batch, landmark_count, height * width)
    if input_is_logits:
        weights = torch.softmax(flattened, dim=-1)
    else:
        weights = flattened.clamp_min(0)
        weights = weights / weights.sum(dim=-1, keepdim=True).clamp_min(
            torch.finfo(weights.dtype).eps
        )

    x_axis = torch.linspace(0, 1, width, dtype=heatmaps.dtype, device=heatmaps.device)
    y_axis = torch.linspace(0, 1, height, dtype=heatmaps.dtype, device=heatmaps.device)
    y_grid, x_grid = torch.meshgrid(y_axis, x_axis, indexing="ij")
    x = torch.sum(weights * x_grid.reshape(1, 1, -1), dim=-1)
    y = torch.sum(weights * y_grid.reshape(1, 1, -1), dim=-1)
    return torch.stack((x, y), dim=-1)


class GolfKeypointNet:
    """Rejected compatibility surface for the removed coordinate model."""

    def __init__(self, *args, **kwargs):
        raise RuntimeError(
            "legacy coordinate API removed; use GolfHeatmapNet heatmap outputs"
        )

import torch
from torch import nn
from torchvision.models import MobileNet_V3_Small_Weights, mobilenet_v3_small


LANDMARK_NAMES = ("grip", "shaft_start", "shaft_end", "clubhead", "ball")


class GolfKeypointNet(nn.Module):
    def __init__(self, pretrained=True):
        super().__init__()
        weights = MobileNet_V3_Small_Weights.DEFAULT if pretrained else None
        network = mobilenet_v3_small(weights=weights)
        input_features = network.classifier[-1].in_features
        network.classifier[-1] = nn.Linear(input_features, len(LANDMARK_NAMES) * 3)
        self.network = network
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
        output = self.network(normalized)
        coordinate_count = len(LANDMARK_NAMES) * 2
        coordinates = torch.sigmoid(output[:, :coordinate_count]).reshape(
            -1, len(LANDMARK_NAMES), 2
        )
        visibility = output[:, coordinate_count:]
        return coordinates, visibility

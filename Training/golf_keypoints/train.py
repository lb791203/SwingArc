import argparse
import hashlib
from datetime import datetime, timezone
from pathlib import Path

import torch
from torch.utils.data import DataLoader

from dataset import GolfKeypointDataset, ReviewedTrainingLabelsRequired
from model import GolfKeypointNet, LANDMARK_NAMES


def masked_keypoint_loss(
    predicted_coordinates,
    visibility_logits,
    coordinate_targets,
    visibility_targets,
):
    visible = visibility_targets.unsqueeze(-1)
    coordinate_error = torch.nn.functional.smooth_l1_loss(
        predicted_coordinates * visible,
        coordinate_targets * visible,
        reduction="sum",
    ) / visible.sum().clamp_min(1.0)
    visibility_error = torch.nn.functional.binary_cross_entropy_with_logits(
        visibility_logits,
        visibility_targets,
    )
    return coordinate_error + 0.25 * visibility_error


def manifest_sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--video-root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--learning-rate", type=float, default=1e-4)
    args = parser.parse_args()

    try:
        dataset = GolfKeypointDataset(args.manifest, args.video_root, "training")
    except ReviewedTrainingLabelsRequired as error:
        parser.error(str(error))
    loader = DataLoader(dataset, batch_size=args.batch_size, shuffle=True)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    model = GolfKeypointNet().to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.learning_rate)

    model.train()
    for _epoch in range(args.epochs):
        for images, coordinates, visibility in loader:
            images = images.to(device)
            coordinates = coordinates.to(device)
            visibility = visibility.to(device)
            predicted, visibility_logits = model(images)
            loss = masked_keypoint_loss(
                predicted,
                visibility_logits,
                coordinates,
                visibility,
            )
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            optimizer.step()

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    torch.save({
        "model": model.to("cpu").state_dict(),
        "manifestSHA256": manifest_sha256(args.manifest),
        "landmarks": list(LANDMARK_NAMES),
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "epochs": args.epochs,
    }, output)


if __name__ == "__main__":
    main()

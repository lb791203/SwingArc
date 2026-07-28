import argparse
import hashlib
import json
import math
from pathlib import Path

import torch
from torch.utils.data import DataLoader

from dataset import GolfKeypointDataset, ReviewedTrainingLabelsRequired
from model import GolfKeypointNet, LANDMARK_NAMES


HIT_ERROR_THRESHOLD = 0.02
CLUBHEAD_PROMOTION_HIT_RATE = 0.90


def build_evaluation_report(
    predicted_coordinates,
    coordinate_targets,
    visibility_targets,
    predicted_visibility_logits=None,
):
    errors = torch.linalg.vector_norm(
        predicted_coordinates - coordinate_targets,
        dim=-1,
    ) / math.sqrt(2.0)
    visible_targets = visibility_targets >= 0.5
    predicted_visible = (
        torch.ones_like(visible_targets)
        if predicted_visibility_logits is None
        else torch.sigmoid(predicted_visibility_logits) >= 0.5
    )
    landmarks = {}
    for index, name in enumerate(LANDMARK_NAMES):
        visible = visible_targets[:, index]
        visible_count = int(visible.sum().item())
        if visible_count == 0:
            hit_rate = 0.0
            mean_error = None
        else:
            landmark_errors = errors[:, index][visible]
            landmark_visibility = predicted_visible[:, index][visible]
            hits = (landmark_errors <= HIT_ERROR_THRESHOLD) & landmark_visibility
            hit_rate = float(hits.float().mean().item())
            mean_error = float(landmark_errors.mean().item())
        landmarks[name] = {
            "visibleFrameCount": visible_count,
            "visibleFrameHitRate": hit_rate,
            "diagonalNormalizedError": mean_error,
            "hitErrorThreshold": HIT_ERROR_THRESHOLD,
        }
    report = {"landmarks": landmarks}
    report["promotionPassed"] = promotion_passed(report)
    return report


def promotion_passed(report):
    clubhead = report.get("landmarks", {}).get("clubhead", {})
    hit_rate = clubhead.get("visibleFrameHitRate", 0)
    error = clubhead.get("diagonalNormalizedError")
    return (
        hit_rate >= CLUBHEAD_PROMOTION_HIT_RATE
        and error is not None
        and error <= HIT_ERROR_THRESHOLD
    )


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--video-root", required=True)
    parser.add_argument("--split", default="validation")
    parser.add_argument("--output", required=True)
    parser.add_argument("--batch-size", type=int, default=16)
    args = parser.parse_args()

    try:
        dataset = GolfKeypointDataset(args.manifest, args.video_root, args.split)
    except ReviewedTrainingLabelsRequired as error:
        parser.error(str(error))
    checkpoint = torch.load(args.checkpoint, map_location="cpu")
    current_manifest_hash = sha256(args.manifest)
    if checkpoint.get("manifestSHA256") != current_manifest_hash:
        parser.error("checkpoint manifest SHA-256 does not match evaluation manifest")
    model = GolfKeypointNet(pretrained=False)
    model.load_state_dict(checkpoint["model"])
    model.eval()

    predicted_batches = []
    coordinate_batches = []
    visibility_batches = []
    visibility_logit_batches = []
    with torch.no_grad():
        for images, coordinates, visibility in DataLoader(
            dataset,
            batch_size=args.batch_size,
            shuffle=False,
        ):
            predicted, visibility_logits = model(images)
            predicted_batches.append(predicted)
            coordinate_batches.append(coordinates)
            visibility_batches.append(visibility)
            visibility_logit_batches.append(visibility_logits)
    report = build_evaluation_report(
        torch.cat(predicted_batches),
        torch.cat(coordinate_batches),
        torch.cat(visibility_batches),
        torch.cat(visibility_logit_batches),
    )
    report.update({
        "checkpointSHA256": sha256(args.checkpoint),
        "manifestSHA256": current_manifest_hash,
        "split": args.split,
        "sampleCount": len(dataset),
    })
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

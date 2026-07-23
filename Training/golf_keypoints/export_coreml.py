import argparse
import hashlib
import json
from pathlib import Path

import torch

from evaluate import promotion_passed
from model import GolfKeypointNet


def file_sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def assert_report_passes(checkpoint_path, evaluation_path):
    report = json.loads(Path(evaluation_path).read_text(encoding="utf-8"))
    if report.get("split") != "validation":
        raise ValueError("a validation split report is required for Core ML export")
    if not promotion_passed(report):
        raise ValueError("validation gate failed; Core ML export is blocked")
    if report.get("checkpointSHA256") != file_sha256(checkpoint_path):
        raise ValueError("evaluation report does not match checkpoint")
    checkpoint = torch.load(checkpoint_path, map_location="cpu")
    if report.get("manifestSHA256") != checkpoint.get("manifestSHA256"):
        raise ValueError("evaluation report manifest does not match checkpoint")
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--evaluation", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    assert_report_passes(args.checkpoint, args.evaluation)
    import coremltools as ct

    checkpoint = torch.load(args.checkpoint, map_location="cpu")
    network = GolfKeypointNet(pretrained=False)
    network.load_state_dict(checkpoint["model"])
    network.eval()
    example = torch.zeros(1, 3, 256, 256)
    traced = torch.jit.trace(network, example)
    converted = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        inputs=[ct.ImageType(name="image", shape=example.shape, scale=1 / 255.0)],
        outputs=[
            ct.TensorType(name="coordinates"),
            ct.TensorType(name="visibility"),
        ],
    )
    converted.author = "SwingArc"
    converted.short_description = "Golf grip, shaft, clubhead, and ball keypoints"
    converted.user_defined_metadata["manifestSHA256"] = checkpoint["manifestSHA256"]
    converted.save(args.output)


if __name__ == "__main__":
    main()

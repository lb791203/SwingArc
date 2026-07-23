import torch
from PIL import Image

from dataset import GolfKeypointDataset, ReviewedTrainingLabelsRequired
from evaluate import build_evaluation_report, promotion_passed
from export_coreml import assert_report_passes, file_sha256
from model import GolfKeypointNet
from train import masked_keypoint_loss


def test_output_contract():
    coordinates, visibility = GolfKeypointNet(pretrained=False)(
        torch.zeros(2, 3, 256, 256)
    )
    assert coordinates.shape == (2, 5, 2)
    assert visibility.shape == (2, 5)
    assert torch.all((coordinates >= 0) & (coordinates <= 1))


def test_dataset_requires_authorized_reviewed_labels(tmp_path):
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        """
        [{
          "clipID": "clip-1",
          "golferID": "golfer-1",
          "fileName": "clip.mov",
          "split": "training",
          "authorization": "training-allowed",
          "sourceFrameRate": 30,
          "frameLabels": [{
            "sourceFrameIndex": 12,
            "reviewer": "reviewer-a",
            "reviewed": true,
            "landmarks": {
              "grip": {"x": 0.1, "y": 0.2, "visibility": "visible"},
              "shaftStart": {"x": 0.2, "y": 0.3, "visibility": "visible"},
              "shaftEnd": {"x": 0.4, "y": 0.5, "visibility": "visible"},
              "clubhead": {"x": 0.6, "y": 0.7, "visibility": "visible"},
              "ball": {"x": 0.8, "y": 0.9, "visibility": "occluded"}
            }
          }]
        }]
        """,
        encoding="utf-8",
    )
    dataset = GolfKeypointDataset(
        manifest_path=manifest,
        video_root=tmp_path,
        split="training",
        image_loader=lambda _sample: Image.new("RGB", (320, 180), "black"),
    )
    image, coordinates, visibility = dataset[0]
    assert image.shape == (3, 256, 256)
    assert coordinates.shape == (5, 2)
    assert visibility.tolist() == [1, 1, 1, 1, 0]

    manifest.write_text(
        manifest.read_text(encoding="utf-8").replace('"reviewed": true', '"reviewed": false'),
        encoding="utf-8",
    )
    try:
        GolfKeypointDataset(manifest, tmp_path, "training")
    except ReviewedTrainingLabelsRequired as error:
        assert "reviewed training labels required" in str(error)
    else:
        raise AssertionError("unreviewed labels must be rejected")

    manifest.write_text(
        manifest.read_text(encoding="utf-8")
        .replace('"reviewed": false', '"reviewed": true')
        .replace('"visibility": "occluded"', '"visibility": "visble"'),
        encoding="utf-8",
    )
    try:
        GolfKeypointDataset(manifest, tmp_path, "training")
    except ReviewedTrainingLabelsRequired as error:
        assert "visibility" in str(error)
    else:
        raise AssertionError("unknown visibility values must be rejected")


def test_masked_coordinate_loss_ignores_hidden_points():
    predicted = torch.tensor([[[0.2, 0.2], [0.9, 0.9]]])
    target = torch.tensor([[[0.1, 0.1], [0.0, 0.0]]])
    visibility = torch.tensor([[1.0, 0.0]])
    visibility_logits = torch.zeros(1, 2)
    first = masked_keypoint_loss(predicted, visibility_logits, target, visibility)
    predicted[:, 1, :] = 0.1
    second = masked_keypoint_loss(predicted, visibility_logits, target, visibility)
    assert torch.allclose(first, second)


def test_evaluation_and_promotion_gate():
    predicted = torch.zeros(2, 5, 2)
    target = torch.zeros(2, 5, 2)
    visibility = torch.ones(2, 5)
    report = build_evaluation_report(predicted, target, visibility)
    assert report["landmarks"]["clubhead"]["visibleFrameHitRate"] == 1.0
    assert report["landmarks"]["clubhead"]["diagonalNormalizedError"] == 0.0
    assert promotion_passed(report)

    report["landmarks"]["clubhead"]["visibleFrameHitRate"] = 0.89
    assert not promotion_passed(report)


def test_export_requires_matching_manifest_hash(tmp_path):
    checkpoint = tmp_path / "candidate.pt"
    torch.save({"manifestSHA256": "manifest-a"}, checkpoint)
    evaluation = tmp_path / "evaluation.json"
    evaluation.write_text(
        __import__("json").dumps({
            "checkpointSHA256": file_sha256(checkpoint),
            "manifestSHA256": "manifest-b",
            "split": "validation",
            "landmarks": {
                "clubhead": {
                    "visibleFrameHitRate": 0.95,
                    "diagonalNormalizedError": 0.01,
                }
            },
        }),
        encoding="utf-8",
    )
    try:
        assert_report_passes(checkpoint, evaluation)
    except ValueError as error:
        assert "manifest" in str(error)
    else:
        raise AssertionError("export must reject a report from another manifest")


def test_export_requires_validation_split(tmp_path):
    checkpoint = tmp_path / "candidate.pt"
    torch.save({"manifestSHA256": "manifest-a"}, checkpoint)
    evaluation = tmp_path / "evaluation.json"
    evaluation.write_text(
        __import__("json").dumps({
            "checkpointSHA256": file_sha256(checkpoint),
            "manifestSHA256": "manifest-a",
            "split": "training",
            "landmarks": {
                "clubhead": {
                    "visibleFrameHitRate": 0.95,
                    "diagonalNormalizedError": 0.01,
                }
            },
        }),
        encoding="utf-8",
    )
    try:
        assert_report_passes(checkpoint, evaluation)
    except ValueError as error:
        assert "validation" in str(error)
    else:
        raise AssertionError("export must only accept validation reports")

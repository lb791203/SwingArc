import torch
from PIL import Image

from contracts import HEATMAP_SIZE, INPUT_SIZE, LANDMARK_NAMES
from dataset import GolfHeatmapDataset, ReviewedTrainingLabelsRequired
from evaluate import build_evaluation_report, promotion_passed
from export_coreml import assert_report_passes, file_sha256
from model import GolfKeypointNet
from test_dataset_heatmaps import _write_export
from train import masked_keypoint_loss


def test_output_contract():
    coordinates, visibility = GolfKeypointNet(pretrained=False)(
        torch.zeros(2, 3, 256, 256)
    )
    assert coordinates.shape == (2, 5, 2)
    assert visibility.shape == (2, 5)
    assert torch.all((coordinates >= 0) & (coordinates <= 1))


def test_dataset_requires_authorized_reviewed_labels(tmp_path):
    manifest_sha = _write_export(tmp_path)
    dataset = GolfHeatmapDataset(
        export_path=tmp_path / "manifest.json",
        video_root=tmp_path,
        split="training",
        expected_manifest_sha256=manifest_sha,
        image_loader=lambda _sample: Image.new("RGB", (180, 320), "black"),
    )
    image, heatmaps, visibility, coordinate_mask, metadata = dataset[0]
    assert image.shape == (3, INPUT_SIZE, INPUT_SIZE)
    assert heatmaps.shape == (len(LANDMARK_NAMES), HEATMAP_SIZE, HEATMAP_SIZE)
    assert visibility.shape == (len(LANDMARK_NAMES),)
    assert coordinate_mask.shape == (len(LANDMARK_NAMES),)
    assert metadata["manifest_sha256"] == manifest_sha


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

from pathlib import Path

import pytest
import torch
from torch import nn
from torch.utils.data import Dataset

from contracts import (
    HEATMAP_SIZE,
    INPUT_SIZE,
    INPUT_TRANSFORM_VERSION,
    LANDMARK_NAMES,
    VISIBILITY_NAMES,
)
from train import (
    ARCHITECTURE,
    NonFiniteTrainingError,
    build_argument_parser,
    compute_visibility_class_weights,
    train_model,
)


class SyntheticGolfDataset(Dataset):
    manifest_sha256 = "a" * 64
    input_transform_version = INPUT_TRANSFORM_VERSION

    def __len__(self):
        return 2

    def __getitem__(self, index):
        image = torch.full(
            (3, INPUT_SIZE, INPUT_SIZE),
            index / 10,
            dtype=torch.float32,
        )
        heatmaps = torch.zeros(
            len(LANDMARK_NAMES),
            HEATMAP_SIZE,
            HEATMAP_SIZE,
        )
        heatmaps[:, 32 + index, 48 + index] = 1
        if index == 0:
            visibility = torch.tensor([0, 0, 0, 1, 2])
            coordinate_mask = torch.tensor(
                [1, 1, 1, 0, 0], dtype=torch.bool
            )
        else:
            visibility = torch.tensor([0, 1, 2, -100, -100])
            coordinate_mask = torch.tensor(
                [1, 0, 0, 0, 0], dtype=torch.bool
            )
        metadata = {
            "clip_id": "clip-synthetic",
            "source_frame_index": index,
            "stage_codes": [f"P{index + 1}"],
            "variable_keys": {"only_first": True} if index == 0 else {},
        }
        return image, heatmaps, visibility, coordinate_mask, metadata


class TinyHeatmapNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.heatmap_logits = nn.Parameter(
            torch.zeros(1, len(LANDMARK_NAMES), 1, 1)
        )
        self.visibility_logits = nn.Parameter(
            torch.zeros(1, len(LANDMARK_NAMES), len(VISIBILITY_NAMES))
        )

    def forward(self, images):
        batch_size = images.shape[0]
        heatmaps = torch.sigmoid(self.heatmap_logits).expand(
            batch_size,
            -1,
            HEATMAP_SIZE,
            HEATMAP_SIZE,
        )
        visibility = self.visibility_logits.expand(batch_size, -1, -1)
        return heatmaps, visibility


class NaNHeatmapNet(TinyHeatmapNet):
    def forward(self, images):
        heatmaps, visibility = super().forward(images)
        return heatmaps * torch.tensor(float("nan")), visibility


class NaNGradientHeatmapNet(TinyHeatmapNet):
    def __init__(self):
        super().__init__()
        self.heatmap_logits.register_hook(
            lambda gradient: torch.full_like(gradient, float("nan"))
        )


class NaNUpdatedParameterNet(TinyHeatmapNet):
    def __init__(self):
        super().__init__()

        def corrupt_parameter(gradient):
            with torch.no_grad():
                self.heatmap_logits.fill_(float("nan"))
            return gradient

        self.heatmap_logits.register_hook(corrupt_parameter)


def test_visibility_weights_are_inverse_frequency_and_mean_normalized():
    counts, weights = compute_visibility_class_weights(
        SyntheticGolfDataset()
    )

    assert counts == {
        "visible": 4,
        "occluded": 2,
        "out-of-frame": 2,
    }
    assert torch.allclose(weights, torch.tensor([0.6, 1.2, 1.2]))
    assert torch.allclose(weights.mean(), torch.tensor(1.0))


def test_visibility_weights_reject_missing_training_class():
    class MissingClassDataset(SyntheticGolfDataset):
        def __getitem__(self, index):
            image, heatmaps, _, _, metadata = super().__getitem__(index)
            return (
                image,
                heatmaps,
                torch.tensor([0, 0, 1, -100, -100]),
                torch.tensor([1, 1, 0, 0, 0], dtype=torch.bool),
                metadata,
            )

    with pytest.raises(ValueError, match="out-of-frame.*zero samples"):
        compute_visibility_class_weights(MissingClassDataset())


def test_expected_manifest_sha256_is_required_by_cli():
    parser = build_argument_parser()
    required = [
        "--manifest", "manifest.json",
        "--video-root", "videos",
        "--output", "candidate.pt",
    ]

    with pytest.raises(SystemExit):
        parser.parse_args(required)

    args = parser.parse_args(
        required + ["--expected-manifest-sha256", "a" * 64]
    )
    assert args.expected_manifest_sha256 == "a" * 64
    assert args.seed == 1729


def test_two_sample_epoch_writes_auditable_checkpoint(tmp_path):
    output = tmp_path / "candidate.pt"
    history = train_model(
        dataset=SyntheticGolfDataset(),
        output=output,
        expected_manifest_sha256="a" * 64,
        epochs=1,
        batch_size=2,
        learning_rate=1e-3,
        seed=1729,
        device=torch.device("cpu"),
        model=TinyHeatmapNet(),
        pretrained=False,
    )

    assert output.is_file()
    assert len(history) == 1
    checkpoint = torch.load(output, map_location="cpu")
    assert checkpoint["architecture"] == ARCHITECTURE
    assert checkpoint["manifestSHA256"] == "a" * 64
    assert checkpoint["inputTransformVersion"] == INPUT_TRANSFORM_VERSION
    assert checkpoint["landmarks"] == list(LANDMARK_NAMES)
    assert checkpoint["visibilityClasses"] == list(VISIBILITY_NAMES)
    assert checkpoint["inputSize"] == INPUT_SIZE
    assert checkpoint["heatmapSize"] == HEATMAP_SIZE
    assert checkpoint["seed"] == 1729
    assert checkpoint["epochs"] == 1
    assert checkpoint["requestedEpochs"] == 1
    assert checkpoint["completedEpochs"] == 1
    assert checkpoint["epochRecords"] == 1
    assert checkpoint["partialEpoch"] is False
    assert checkpoint["partialEpochSteps"] == 0
    assert checkpoint["completedBatchesInCurrentEpoch"] == 0
    assert checkpoint["maxSteps"] is None
    assert checkpoint["completedSteps"] == 1
    assert checkpoint["stopReason"] == "completed-epochs"
    assert checkpoint["learningRate"] == 1e-3
    assert checkpoint["batchSize"] == 2
    assert checkpoint["pretrainedWeights"] is False
    assert checkpoint["device"] == "cpu"
    assert checkpoint["determinismMode"] == "torch-deterministic-algorithms"
    assert checkpoint["resumeSupported"] is False
    assert checkpoint["artifactKind"] == "development-training-checkpoint"
    assert checkpoint["promotionStatus"] == "development"
    assert checkpoint["visibilityClassCounts"] == {
        "visible": 4,
        "occluded": 2,
        "out-of-frame": 2,
    }
    assert checkpoint["visibilityClassWeights"] == {
        "visible": pytest.approx(0.6),
        "occluded": pytest.approx(1.2),
        "out-of-frame": pytest.approx(1.2),
    }
    assert set(checkpoint["environment"]) == {
        "pythonVersion",
        "torchVersion",
        "torchvisionVersion",
        "macOSVersion",
        "machine",
        "deviceType",
        "deviceName",
    }
    assert checkpoint["createdAt"].endswith("+00:00")
    assert set(checkpoint["model"]) == {
        "heatmap_logits",
        "visibility_logits",
    }
    assert "optimizer" not in checkpoint
    assert checkpoint["history"] == history
    assert set(history[0]) == {
        "epoch",
        "steps",
        "total",
        "heatmap",
        "visibility",
        "shaft_angle",
    }
    assert not Path(f"{output}.tmp").exists()


def test_max_steps_records_early_stop_metadata(tmp_path):
    output = tmp_path / "early-stop.pt"
    history = train_model(
        dataset=SyntheticGolfDataset(),
        output=output,
        expected_manifest_sha256="a" * 64,
        epochs=4,
        batch_size=1,
        max_steps=1,
        seed=1729,
        device=torch.device("cpu"),
        model=TinyHeatmapNet(),
        pretrained=False,
    )

    checkpoint = torch.load(output, map_location="cpu")
    assert len(history) == 1
    assert checkpoint["epochs"] == 0
    assert checkpoint["requestedEpochs"] == 4
    assert checkpoint["completedEpochs"] == 0
    assert checkpoint["epochRecords"] == 1
    assert checkpoint["partialEpoch"] is True
    assert checkpoint["partialEpochSteps"] == 1
    assert checkpoint["completedBatchesInCurrentEpoch"] == 1
    assert checkpoint["maxSteps"] == 1
    assert checkpoint["completedSteps"] == 1
    assert checkpoint["stopReason"] == "max-steps"


def test_max_steps_at_epoch_boundary_counts_completed_epoch(tmp_path):
    output = tmp_path / "epoch-boundary.pt"
    history = train_model(
        dataset=SyntheticGolfDataset(),
        output=output,
        expected_manifest_sha256="a" * 64,
        epochs=4,
        batch_size=1,
        max_steps=2,
        seed=1729,
        device=torch.device("cpu"),
        model=TinyHeatmapNet(),
        pretrained=False,
    )

    checkpoint = torch.load(output, map_location="cpu")
    assert len(history) == 1
    assert checkpoint["epochs"] == 1
    assert checkpoint["requestedEpochs"] == 4
    assert checkpoint["completedEpochs"] == 1
    assert checkpoint["epochRecords"] == 1
    assert checkpoint["partialEpoch"] is False
    assert checkpoint["partialEpochSteps"] == 0
    assert checkpoint["completedBatchesInCurrentEpoch"] == 0
    assert checkpoint["maxSteps"] == 2
    assert checkpoint["completedSteps"] == 2
    assert checkpoint["stopReason"] == "max-steps"


def test_nonfinite_loss_fails_with_batch_identity(tmp_path):
    output = tmp_path / "nan.pt"
    with pytest.raises(
        NonFiniteTrainingError,
        match=r"loss.*clip-synthetic.*source_frame_index=.*stage_codes=",
    ):
        train_model(
            dataset=SyntheticGolfDataset(),
            output=output,
            expected_manifest_sha256="a" * 64,
            epochs=1,
            batch_size=2,
            device=torch.device("cpu"),
            model=NaNHeatmapNet(),
            pretrained=False,
        )
    assert not output.exists()


@pytest.mark.parametrize(
    ("network", "failure"),
    [
        (NaNGradientHeatmapNet, "gradient"),
        (NaNUpdatedParameterNet, "updated parameter"),
    ],
)
def test_nonfinite_gradient_or_update_fails_with_batch_identity(
    tmp_path, network, failure
):
    output = tmp_path / f"{failure}.pt"
    with pytest.raises(
        NonFiniteTrainingError,
        match=rf"{failure}.*clip-synthetic.*source_frame_index=.*stage_codes=",
    ):
        train_model(
            dataset=SyntheticGolfDataset(),
            output=output,
            expected_manifest_sha256="a" * 64,
            epochs=1,
            batch_size=2,
            device=torch.device("cpu"),
            model=network(),
            pretrained=False,
        )
    assert not output.exists()


def test_manifest_mismatch_is_rejected_before_training(tmp_path):
    with pytest.raises(ValueError, match="manifest SHA-256"):
        train_model(
            dataset=SyntheticGolfDataset(),
            output=tmp_path / "candidate.pt",
            expected_manifest_sha256="b" * 64,
            epochs=1,
            batch_size=2,
            device=torch.device("cpu"),
            model=TinyHeatmapNet(),
        )

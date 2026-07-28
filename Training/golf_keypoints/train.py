import argparse
import os
import platform
import random
from datetime import datetime, timezone
from pathlib import Path

import torch
import torchvision
from torch.utils.data import DataLoader, default_collate

from contracts import (
    HEATMAP_SIZE,
    INPUT_SIZE,
    INPUT_TRANSFORM_VERSION,
    LANDMARK_NAMES,
    VISIBILITY_INDEX,
    VISIBILITY_NAMES,
)
from dataset import GolfHeatmapDataset, ReviewedTrainingLabelsRequired
from losses import golf_keypoint_loss
from model import GolfHeatmapNet


ARCHITECTURE = "mobilenet-v3-small-fpn-heatmap-v1"
DEFAULT_SEED = 1729


class NonFiniteTrainingError(RuntimeError):
    """A traceable non-finite value invalidated a training batch."""


def build_argument_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--expected-manifest-sha256", required=True)
    parser.add_argument("--video-root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--learning-rate", type=float, default=1e-4)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument(
        "--max-steps",
        type=int,
        default=None,
        help="Optional development-smoke limit across all epochs.",
    )
    parser.add_argument(
        "--no-pretrained",
        action="store_true",
        help="Do not load pretrained MobileNetV3 weights.",
    )
    return parser


def _seed_everything(seed):
    random.seed(seed)
    torch.manual_seed(seed)


def _selected_device():
    return torch.device("mps" if torch.backends.mps.is_available() else "cpu")


def _configure_determinism(device):
    if device.type == "mps":
        # torch 2.13 does not support strict deterministic algorithms for the
        # complete MPS training graph.
        torch.use_deterministic_algorithms(False)
        return "seeded-best-effort"
    torch.use_deterministic_algorithms(True)
    return "torch-deterministic-algorithms"


def _input_transform_version(dataset):
    version = getattr(dataset, "input_transform_version", None)
    if version is None and getattr(dataset, "samples", None):
        version = dataset.samples[0].training_input_transform.get("version")
    if version != INPUT_TRANSFORM_VERSION:
        raise ValueError(
            "training dataset input transform version does not match contract"
        )
    return version


def _cpu_tree(value):
    if torch.is_tensor(value):
        return value.detach().cpu()
    if isinstance(value, dict):
        return {key: _cpu_tree(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_cpu_tree(item) for item in value]
    if isinstance(value, tuple):
        return tuple(_cpu_tree(item) for item in value)
    return value


def _atomic_torch_save(value, output):
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(f"{output}.tmp")
    try:
        torch.save(value, temporary)
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()


def _collate_golf_samples(samples):
    images, heatmaps, visibility, coordinate_masks, metadata = zip(*samples)
    return (
        default_collate(images),
        default_collate(heatmaps),
        default_collate(visibility),
        default_collate(coordinate_masks),
        list(metadata),
    )


def _visibility_indexes_from_dataset(dataset):
    samples = getattr(dataset, "samples", None)
    if samples is not None:
        for sample in samples:
            for label in sample.landmarks.values():
                yield VISIBILITY_INDEX[label["visibility"]]
        return
    for index in range(len(dataset)):
        visibility_targets = dataset[index][2].reshape(-1)
        for value in visibility_targets.tolist():
            if value != -100:
                yield int(value)


def compute_visibility_class_weights(dataset):
    counts_by_index = [0] * len(VISIBILITY_NAMES)
    for class_index in _visibility_indexes_from_dataset(dataset):
        if not 0 <= class_index < len(VISIBILITY_NAMES):
            raise ValueError(
                f"invalid visibility class index in training data: {class_index}"
            )
        counts_by_index[class_index] += 1
    for class_index, count in enumerate(counts_by_index):
        if count == 0:
            raise ValueError(
                f"visibility class {VISIBILITY_NAMES[class_index]!r} "
                "has zero samples in training split"
            )
    inverse_frequency = torch.tensor(
        [1.0 / count for count in counts_by_index],
        dtype=torch.float32,
    )
    weights = inverse_frequency / inverse_frequency.mean()
    counts = {
        name: counts_by_index[index]
        for index, name in enumerate(VISIBILITY_NAMES)
    }
    return counts, weights


def _batch_identity(metadata):
    records = []
    for item in metadata:
        if not isinstance(item, dict):
            records.append(repr(item))
            continue
        records.append(
            "clip_id={clip_id!r}, source_frame_index={frame!r}, "
            "stage_codes={stages!r}".format(
                clip_id=item.get("clip_id"),
                frame=item.get("source_frame_index"),
                stages=item.get("stage_codes"),
            )
        )
    return "[" + "; ".join(records) + "]"


def _require_finite(tensor, description, metadata):
    if not torch.isfinite(tensor).all().item():
        raise NonFiniteTrainingError(
            f"non-finite {description}; batch metadata: "
            f"{_batch_identity(metadata)}"
        )


def _require_finite_gradients(network, metadata):
    for name, parameter in network.named_parameters():
        if parameter.grad is not None:
            _require_finite(
                parameter.grad,
                f"gradient for parameter {name}",
                metadata,
            )


def _require_finite_parameters(network, metadata):
    for name, parameter in network.named_parameters():
        _require_finite(
            parameter,
            f"updated parameter {name}",
            metadata,
        )


def _environment_metadata(device):
    device_name = (
        "Apple Metal Performance Shaders"
        if device.type == "mps"
        else (platform.processor() or platform.machine() or "CPU")
    )
    return {
        "pythonVersion": platform.python_version(),
        "torchVersion": str(torch.__version__),
        "torchvisionVersion": str(torchvision.__version__),
        "macOSVersion": platform.mac_ver()[0],
        "machine": platform.machine(),
        "deviceType": device.type,
        "deviceName": device_name,
    }


def train_model(
    dataset,
    output,
    expected_manifest_sha256,
    *,
    epochs=20,
    batch_size=16,
    learning_rate=1e-4,
    seed=DEFAULT_SEED,
    max_steps=None,
    device=None,
    model=None,
    pretrained=True,
):
    if epochs <= 0:
        raise ValueError("epochs must be positive")
    if batch_size <= 0:
        raise ValueError("batch size must be positive")
    if learning_rate <= 0:
        raise ValueError("learning rate must be positive")
    if max_steps is not None and max_steps <= 0:
        raise ValueError("max steps must be positive")
    if dataset.manifest_sha256 != expected_manifest_sha256:
        raise ValueError(
            "training dataset manifest SHA-256 does not match expected value"
        )
    input_transform_version = _input_transform_version(dataset)
    visibility_counts, visibility_weights = (
        compute_visibility_class_weights(dataset)
    )

    _seed_everything(seed)
    generator = torch.Generator()
    generator.manual_seed(seed)
    loader = DataLoader(
        dataset,
        batch_size=batch_size,
        shuffle=True,
        generator=generator,
        collate_fn=_collate_golf_samples,
    )
    selected_device = device or _selected_device()
    determinism_mode = _configure_determinism(selected_device)
    print(f"selected device: {selected_device}")
    network = model or GolfHeatmapNet(pretrained=pretrained)
    network = network.to(selected_device)
    visibility_weights = visibility_weights.to(selected_device)
    optimizer = torch.optim.AdamW(
        network.parameters(), lr=learning_rate
    )

    history = []
    completed_steps = 0
    completed_epochs = 0
    hit_max_steps = False
    partial_epoch = False
    partial_epoch_steps = 0
    batches_per_epoch = len(loader)
    network.train()
    for epoch_index in range(epochs):
        component_sums = {
            "total": 0.0,
            "heatmap": 0.0,
            "visibility": 0.0,
            "shaft_angle": 0.0,
        }
        epoch_steps = 0
        for (
            images,
            target_heatmaps,
            visibility_targets,
            coordinate_mask,
            metadata,
        ) in loader:
            images = images.to(selected_device)
            target_heatmaps = target_heatmaps.to(selected_device)
            visibility_targets = visibility_targets.to(selected_device)
            coordinate_mask = coordinate_mask.to(selected_device)
            predicted_heatmaps, visibility_logits = network(images)
            losses = golf_keypoint_loss(
                predicted_heatmaps,
                visibility_logits,
                target_heatmaps,
                visibility_targets,
                coordinate_mask,
                visibility_class_weights=visibility_weights,
            )
            for name, value in losses.items():
                _require_finite(value, f"loss component {name}", metadata)
            optimizer.zero_grad(set_to_none=True)
            losses["total"].backward()
            _require_finite_gradients(network, metadata)
            optimizer.step()
            _require_finite_parameters(network, metadata)

            completed_steps += 1
            epoch_steps += 1
            for name in component_sums:
                component_sums[name] += float(losses[name].detach().cpu())
            if max_steps is not None and completed_steps >= max_steps:
                hit_max_steps = True
                break

        history.append({
            "epoch": epoch_index + 1,
            "steps": epoch_steps,
            **{
                name: total / max(epoch_steps, 1)
                for name, total in component_sums.items()
            },
        })
        epoch_was_complete = epoch_steps == batches_per_epoch
        if epoch_was_complete:
            completed_epochs += 1
        if hit_max_steps and not epoch_was_complete:
            partial_epoch = True
            partial_epoch_steps = epoch_steps
        print(
            f"epoch {epoch_index + 1}/{epochs} "
            f"steps={epoch_steps} "
            f"total={history[-1]['total']:.6f} "
            f"heatmap={history[-1]['heatmap']:.6f} "
            f"visibility={history[-1]['visibility']:.6f} "
            f"shaft_angle={history[-1]['shaft_angle']:.6f}"
        )
        if max_steps is not None and completed_steps >= max_steps:
            break

    network = network.to("cpu")
    visibility_weight_values = visibility_weights.detach().cpu().tolist()
    checkpoint = {
        "artifactKind": "development-training-checkpoint",
        "promotionStatus": "development",
        "architecture": ARCHITECTURE,
        "manifestSHA256": dataset.manifest_sha256,
        "inputTransformVersion": input_transform_version,
        "landmarks": list(LANDMARK_NAMES),
        "visibilityClasses": list(VISIBILITY_NAMES),
        "inputSize": INPUT_SIZE,
        "heatmapSize": HEATMAP_SIZE,
        "seed": seed,
        "epochs": completed_epochs,
        "requestedEpochs": epochs,
        "completedEpochs": completed_epochs,
        "epochRecords": len(history),
        "partialEpoch": partial_epoch,
        "partialEpochSteps": partial_epoch_steps,
        "completedBatchesInCurrentEpoch": partial_epoch_steps,
        "maxSteps": max_steps,
        "completedSteps": completed_steps,
        "stopReason": "max-steps" if hit_max_steps else "completed-epochs",
        "learningRate": learning_rate,
        "batchSize": batch_size,
        "pretrainedWeights": (
            "MobileNet_V3_Small_Weights.DEFAULT"
            if model is None and pretrained
            else False
        ),
        "device": str(selected_device),
        "determinismMode": determinism_mode,
        "resumeSupported": False,
        "environment": _environment_metadata(selected_device),
        "visibilityClassCounts": visibility_counts,
        "visibilityClassWeights": {
            name: visibility_weight_values[index]
            for index, name in enumerate(VISIBILITY_NAMES)
        },
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "model": _cpu_tree(network.state_dict()),
        "history": history,
    }
    _atomic_torch_save(checkpoint, output)
    return history


def main(argv=None):
    parser = build_argument_parser()
    args = parser.parse_args(argv)
    try:
        dataset = GolfHeatmapDataset(
            args.manifest,
            args.video_root,
            "training",
            expected_manifest_sha256=args.expected_manifest_sha256,
        )
        train_model(
            dataset,
            args.output,
            args.expected_manifest_sha256,
            epochs=args.epochs,
            batch_size=args.batch_size,
            learning_rate=args.learning_rate,
            seed=args.seed,
            max_steps=args.max_steps,
            pretrained=not args.no_pretrained,
        )
    except ReviewedTrainingLabelsRequired as error:
        parser.error(str(error))
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()

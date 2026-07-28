import pytest
import torch

from contracts import LANDMARK_NAMES, VISIBILITY_NAMES
from model import GolfHeatmapNet, GolfKeypointNet, heatmap_soft_argmax


def test_heatmap_output_contract():
    model = GolfHeatmapNet(pretrained=False).eval()
    with torch.no_grad():
        heatmaps, visibility = model(torch.zeros(2, 3, 512, 512))

    assert heatmaps.shape == (2, len(LANDMARK_NAMES), 128, 128)
    assert visibility.shape == (
        2,
        len(LANDMARK_NAMES),
        len(VISIBILITY_NAMES),
    )
    assert torch.all((heatmaps >= 0) & (heatmaps <= 1))


def test_soft_argmax_returns_normalized_xy():
    heatmap_logits = torch.zeros(1, len(LANDMARK_NAMES), 128, 128)
    heatmap_logits[:, :, 32, 96] = 20

    points = heatmap_soft_argmax(heatmap_logits, input_is_logits=True)

    assert points.shape == (1, len(LANDMARK_NAMES), 2)
    assert torch.allclose(
        points[0, 0],
        torch.tensor([96 / 127, 32 / 127]),
        atol=1e-2,
    )


def test_legacy_coordinate_model_api_is_rejected():
    with pytest.raises(RuntimeError, match="legacy coordinate API"):
        GolfKeypointNet(pretrained=False)


def test_batch_two_backward_reaches_every_trainable_parameter():
    previous_thread_count = torch.get_num_threads()
    torch.set_num_threads(1)
    try:
        model = GolfHeatmapNet(pretrained=False).train()
        heatmaps, visibility = model(torch.zeros(2, 3, 512, 512))
        (heatmaps.mean() + visibility.mean()).backward()
    finally:
        torch.set_num_threads(previous_thread_count)

    missing_gradients = [
        name
        for name, parameter in model.named_parameters()
        if parameter.requires_grad and parameter.grad is None
    ]
    assert missing_gradients == []


def test_coreml_mlprogram_conversion_preserves_output_contract():
    import coremltools as ct

    model = GolfHeatmapNet(pretrained=False).eval()
    example = torch.zeros(1, 3, 512, 512)
    traced = torch.jit.trace(model, example)
    converted = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        inputs=[ct.TensorType(name="image", shape=example.shape)],
        outputs=[
            ct.TensorType(name="heatmaps"),
            ct.TensorType(name="visibility"),
        ],
    )

    outputs = {
        output.name: tuple(output.type.multiArrayType.shape)
        for output in converted.get_spec().description.output
    }
    assert outputs == {
        "heatmaps": (1, len(LANDMARK_NAMES), 128, 128),
        "visibility": (
            1,
            len(LANDMARK_NAMES),
            len(VISIBILITY_NAMES),
        ),
    }

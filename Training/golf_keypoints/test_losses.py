import torch

from contracts import LANDMARK_NAMES
from losses import golf_keypoint_loss


def _point_heatmaps(points):
    heatmaps = torch.zeros(1, len(LANDMARK_NAMES), 128, 128)
    for landmark_index, (x, y) in points.items():
        heatmaps[0, landmark_index, y, x] = 1
    return heatmaps


def test_balanced_heatmap_mse_has_order_one_scale_and_no_zero_collapse():
    target = _point_heatmaps({0: (48, 32)})
    coordinate_mask = torch.tensor([[1, 0, 0, 0, 0]], dtype=torch.bool)
    visibility_targets = torch.tensor([[0, -100, -100, -100, -100]])
    visibility_logits = torch.zeros(1, len(LANDMARK_NAMES), 3)

    random_baseline = golf_keypoint_loss(
        torch.full_like(target, 0.5),
        visibility_logits,
        target,
        visibility_targets,
        coordinate_mask,
    )["heatmap"]
    zero_prediction = golf_keypoint_loss(
        torch.zeros_like(target),
        visibility_logits,
        target,
        visibility_targets,
        coordinate_mask,
    )["heatmap"]
    correct_prediction = golf_keypoint_loss(
        target,
        visibility_logits,
        target,
        visibility_targets,
        coordinate_mask,
    )["heatmap"]

    assert torch.allclose(random_baseline, torch.tensor(0.25))
    assert zero_prediction >= 0.49
    assert correct_prediction == 0


def test_hidden_and_unresolved_points_have_no_heatmap_gradient():
    predicted = torch.zeros(
        1, len(LANDMARK_NAMES), 128, 128, requires_grad=True
    )
    target = torch.ones_like(predicted)
    mask = torch.tensor([[1, 0, 0, 1, 0]], dtype=torch.bool)
    visibility_logits = torch.zeros(
        1, len(LANDMARK_NAMES), 3, requires_grad=True
    )
    visibility_targets = torch.tensor([[0, 1, 2, 0, -100]])

    losses = golf_keypoint_loss(
        predicted,
        visibility_logits,
        target,
        visibility_targets,
        mask,
    )
    losses["total"].backward()

    assert predicted.grad[0, 0].abs().sum() > 0
    assert predicted.grad[0, 1].abs().sum() == 0
    assert predicted.grad[0, 2].abs().sum() == 0
    assert predicted.grad[0, 3].abs().sum() > 0
    assert predicted.grad[0, 4].abs().sum() == 0
    assert visibility_logits.grad[0, 4].abs().sum() == 0


def test_rotating_only_visible_shaft_end_increases_angle_loss():
    shaft_start = LANDMARK_NAMES.index("shaft_start")
    shaft_end = LANDMARK_NAMES.index("shaft_end")
    target = _point_heatmaps({
        shaft_start: (24, 64),
        shaft_end: (104, 64),
    })
    aligned = target.clone()
    rotated = _point_heatmaps({
        shaft_start: (24, 64),
        shaft_end: (24, 104),
    })
    coordinate_mask = torch.zeros(
        1, len(LANDMARK_NAMES), dtype=torch.bool
    )
    coordinate_mask[:, shaft_start] = True
    coordinate_mask[:, shaft_end] = True
    visibility_targets = torch.full(
        (1, len(LANDMARK_NAMES)), -100, dtype=torch.long
    )
    visibility_targets[:, shaft_start] = 0
    visibility_targets[:, shaft_end] = 0
    visibility_logits = torch.zeros(1, len(LANDMARK_NAMES), 3)

    aligned_loss = golf_keypoint_loss(
        aligned,
        visibility_logits,
        target,
        visibility_targets,
        coordinate_mask,
    )
    rotated_loss = golf_keypoint_loss(
        rotated,
        visibility_logits,
        target,
        visibility_targets,
        coordinate_mask,
    )

    assert aligned_loss["shaft_angle"].item() < 1e-6
    assert rotated_loss["shaft_angle"] > aligned_loss["shaft_angle"] + 0.9


def test_uniform_shaft_has_finite_bounded_gradient_that_separates_endpoints():
    shaft_start = LANDMARK_NAMES.index("shaft_start")
    shaft_end = LANDMARK_NAMES.index("shaft_end")
    target = _point_heatmaps({
        shaft_start: (24, 64),
        shaft_end: (104, 64),
    })
    predicted = torch.full_like(target, 0.5, requires_grad=True)
    coordinate_mask = torch.zeros(
        1, len(LANDMARK_NAMES), dtype=torch.bool
    )
    coordinate_mask[:, shaft_start] = True
    coordinate_mask[:, shaft_end] = True
    visibility_targets = torch.full(
        (1, len(LANDMARK_NAMES)), -100, dtype=torch.long
    )
    visibility_targets[:, shaft_start] = 0
    visibility_targets[:, shaft_end] = 0
    visibility_logits = torch.zeros(1, len(LANDMARK_NAMES), 3)

    shaft_angle = golf_keypoint_loss(
        predicted,
        visibility_logits,
        target,
        visibility_targets,
        coordinate_mask,
    )["shaft_angle"]
    shaft_angle.backward()

    assert torch.isfinite(shaft_angle)
    assert torch.isfinite(predicted.grad).all()
    assert predicted.grad.abs().max() < 1
    # Gradient descent raises mass at the desired start/end locations.
    assert predicted.grad[0, shaft_start, 64, 24] < 0
    assert predicted.grad[0, shaft_end, 64, 104] < 0


def test_near_empty_predictions_and_zero_length_target_remain_finite():
    shaft_start = LANDMARK_NAMES.index("shaft_start")
    shaft_end = LANDMARK_NAMES.index("shaft_end")
    target = _point_heatmaps({
        shaft_start: (64, 64),
        shaft_end: (64, 64),
    })
    predicted = torch.full_like(target, 1e-12, requires_grad=True)
    coordinate_mask = torch.zeros(
        1, len(LANDMARK_NAMES), dtype=torch.bool
    )
    coordinate_mask[:, shaft_start] = True
    coordinate_mask[:, shaft_end] = True
    visibility_targets = torch.full(
        (1, len(LANDMARK_NAMES)), -100, dtype=torch.long
    )
    visibility_targets[:, shaft_start] = 0
    visibility_targets[:, shaft_end] = 0

    losses = golf_keypoint_loss(
        predicted,
        torch.zeros(1, len(LANDMARK_NAMES), 3),
        target,
        visibility_targets,
        coordinate_mask,
    )
    losses["shaft_angle"].backward()

    assert torch.isfinite(losses["shaft_angle"])
    assert torch.isfinite(predicted.grad).all()
    assert predicted.grad.abs().max() < 100


def test_total_uses_documented_component_weights():
    predicted = torch.full(
        (1, len(LANDMARK_NAMES), 128, 128), 0.25
    )
    target = torch.zeros_like(predicted)
    coordinate_mask = torch.tensor([[1, 0, 0, 0, 0]], dtype=torch.bool)
    visibility_logits = torch.zeros(1, len(LANDMARK_NAMES), 3)
    visibility_targets = torch.tensor([[0, 1, 2, -100, -100]])

    losses = golf_keypoint_loss(
        predicted,
        visibility_logits,
        target,
        visibility_targets,
        coordinate_mask,
    )

    expected = (
        losses["heatmap"]
        + 0.25 * losses["visibility"]
        + 0.10 * losses["shaft_angle"]
    )
    assert torch.allclose(losses["total"], expected)


def test_weighted_loss_components_start_within_two_orders_of_magnitude():
    shaft_start = LANDMARK_NAMES.index("shaft_start")
    shaft_end = LANDMARK_NAMES.index("shaft_end")
    target = _point_heatmaps({
        shaft_start: (24, 64),
        shaft_end: (104, 64),
    })
    coordinate_mask = torch.zeros(
        1, len(LANDMARK_NAMES), dtype=torch.bool
    )
    coordinate_mask[:, shaft_start] = True
    coordinate_mask[:, shaft_end] = True
    visibility_targets = torch.tensor([[0, 0, 0, 1, 2]])
    losses = golf_keypoint_loss(
        torch.full_like(target, 0.5),
        torch.zeros(1, len(LANDMARK_NAMES), 3),
        target,
        visibility_targets,
        coordinate_mask,
    )
    weighted = torch.stack((
        losses["heatmap"],
        0.25 * losses["visibility"],
        0.10 * losses["shaft_angle"],
    ))

    assert torch.isfinite(weighted).all()
    assert weighted.min() > 0
    assert weighted.max() / weighted.min() < 100

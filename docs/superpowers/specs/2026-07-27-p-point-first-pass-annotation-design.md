# P1–P8 First-Pass Annotation Mode

## Problem

The current SwingArcDataset workspace opens the expanded training queue by
default. For the eight development clips this produces 707 reviewed frames and
up to 3,535 manual landmark decisions. The first clip alone presents 135 frames.
That queue is useful for later model training, but it is not an acceptable first
human pass.

## Considered Approaches

1. Tune the existing stride and dense-window constants. This lowers the count,
   but the resulting workload is still hard to explain and varies by clip.
2. Make the eight authoritative P1–P8 frames the default first pass and retain
   the current queue as an explicit expanded mode. This is deterministic,
   auditable, and immediately reduces the eight-clip first pass to 64 frames.
3. Add optical-flow propagation and bulk acceptance now. This can reduce clicks
   further, but it introduces suggestion provenance, confidence thresholds, and
   new review semantics. It should be a separate assisted-annotation task after
   the seed labels exist.

Approach 2 is selected. Approach 3 remains follow-up work and must never write
propagated coordinates as human truth without explicit review.

## User Experience

The workspace has two queue modes:

- **P1–P8 首轮** — the default. It contains the exact eight P-stage source
  frames from the immutable `p-point-truth.json`.
- **扩展训练队列** — the existing sparse/dense queue produced by
  `GolfAnnotationFrameQueueBuilder`.

The mode selector is visible above the timeline. The queue summary includes the
active mode so `队列 1/8` cannot be mistaken for the expanded queue. Selecting a
new clip preserves the active mode. A new app session defaults to the P1–P8
first pass.

Changing modes:

- does not modify annotation decisions;
- does not delete revision history;
- recalculates progress against the active queue only;
- opens the first incomplete frame in the newly selected queue, or its first
  frame if all frames are complete.

The sidebar shows progress for the active queue mode. Existing decisions on
frames outside the active queue remain stored and reappear when expanded mode
is selected.

## Queue Construction

Add a small queue-mode type owned by the dataset workspace:

- `pPointFirstPass`
- `expandedTraining`

The P1–P8 queue builder:

1. reads all eight stages from the already validated
   `GolfPPointTruthDocument`;
2. uses their exact source frame indices;
3. sorts by P-stage order/source frame;
4. deduplicates defensively while retaining all associated stage labels;
5. marks every first-pass item protected.

The expanded builder remains unchanged to avoid silently changing the existing
training sampling contract.

## Data Integrity

`p-point-truth.json`, prediction runs, anchors, and annotation revisions remain
immutable. Queue mode is presentation/work-selection state, not label truth.
No migration deletes or rewrites existing data.

All annotation actions continue to create atomic revision snapshots. A frame is
complete only after all five landmarks have explicit decisions. `unresolved`
counts as reviewed but not trainable, matching the existing contract.

## Failure Handling

- Missing, duplicated, out-of-range, or unordered P-stage truth continues to
  block clip loading through the existing truth validator.
- An empty first-pass queue makes the workspace read-only with a specific
  reason.
- Switching modes while a frame is loading invalidates the old frame-load
  generation so stale pixels cannot replace the selected frame.

## Verification

Tests must prove:

1. a valid document produces exactly eight first-pass items at P1–P8;
2. first-pass items are ordered, protected, and deterministic;
3. expanded mode still produces the existing queue unchanged;
4. mode switching retains decisions and chooses the first incomplete frame;
5. progress is recalculated against the active mode;
6. app relaunch defaults to first-pass mode;
7. the real eight clips each show `8` queue frames, for `64` total;
8. macOS build and existing dataset regression suites pass.

## Out of Scope

This change does not implement optical-flow propagation, model inference,
multi-frame bulk acceptance, deletion of expanded samples, or a claim that 64
frames are sufficient to train the final model.

# SwingArc Precision Swing Development Baseline — 2026-07-23

Status: **development-only / release failed**

This report records the first complete algorithm run against the eight
consented practice-range clips in `/Users/liangbo/Desktop/test`. It is a
development baseline, not a held-out accuracy claim and not training
authorization.

## Dataset identity and timing

- Dataset SHA-256: `06ef5671e33c5463525f9d6d839f7f01c615a555704de0dd72fe037a4bd7cfd1`
- Clips: `IMG_4691.MOV` through `IMG_4698.MOV`
- Golfers: 2
- Views: 5 DTL, 3 face-on / near-face-on
- Capture device: iPhone 16 Pro
- Capture rate reported by the owner: 240 FPS slow motion
- Exported track used by this run: H.264, 1080×1920, 30 FPS
- Timeline interpretation: Photos-exported slow-motion playback timeline
- Authorization: internal review only

Capture rate and exported source-track rate are intentionally separate.
The exported clips contain 497–1365 source frames on a 30 FPS playback
timeline. The unmodified 240 FPS originals are still required for paired
testing of identical swings.

The reference P frames came from two independent AI-assisted visual passes
and a third dispute-resolution pass. They are useful development labels but
are not yet locked human-expert ground truth. Exact first-frame review
overturned the earlier coarse-contact-sheet assessment of `IMG_4697`: it
does contain address through impact and must not be treated as a negative
clip.

## Diagnostic policy

The existing full-frame blur score incorrectly rejected five visibly sharp
clips because it measures a 32-pixel scene-texture signal rather than golfer
motion blur. This baseline therefore used a development-only mode in which
that uncalibrated blur result remains a warning but does not stop P1–P8
analysis. Production behavior remains blocking until real clear/blurred
reference pairs calibrate a replacement metric.

## Per-clip result

`U` means unresolved. Frame errors are automatic minus adjudicated reference.

| Clip | View | Adjudicated reference | Automatic result | Outcome |
| --- | --- | --- | --- | --- |
| IMG_4691 | DTL | P1 441, P2 475, P3 520, P4 614, P5 652, P6 660, P7 674, P8 U | No stages | Failed: `incompleteSwingClip` |
| IMG_4692 | Face-on | 249, 306, 334, 382, 398, U, U, U | 257, U, 335, 390, 400, U, U, U | Completed in 17.38 s |
| IMG_4693 | DTL | 441, 455, 480, 519, 533, 540, 547, 553 | No stages | Failed: `insufficientPoseEvidence` |
| IMG_4694 | DTL | 706, 734, 768, 855, 884, 894, 908, 918 | No stages | Failed: `incompleteSwingClip`; wall time exceeded four minutes |
| IMG_4695 | Face-on | 97, 142, 168, 211, 233, U, U, U | 110, U, 171, 224, 235, U, U, U | Completed in 24.54 s |
| IMG_4696 | Face-on | 487, 527, 550, 595, 615, U, U, U | 486, U, 556, 603, 610, U, U, U | Completed in 24.79 s |
| IMG_4697 | DTL | 1, 4, 8, 19, 22, 24, 28, U | No stages | Failed: `incompleteSwingClip` |
| IMG_4698 | DTL | 10, 24, 41, 120, 144, 152, 163, U | No stages | Failed: `insufficientPoseEvidence` |

Completion:

- Overall: 3/8 clips (37.5%)
- DTL: 0/5 clips (0%)
- Face-on / near-face-on: 3/3 clips (100%), but with unresolved and inaccurate stages

## P1–P8 frame accuracy

Only the three completed face-on clips can currently be scored. P6–P8 do
not have resolved reference labels in these clips, so they are unavailable
rather than counted as successes.

| Stage | IMG_4692 error | IMG_4695 error | IMG_4696 error | Within ±2 frames |
| --- | ---: | ---: | ---: | ---: |
| P1 | +8 | +13 | -1 | 1/3 (33.3%) |
| P2 | U | U | U | 0/3 (0%) |
| P3 | +1 | +3 | +6 | 1/3 (33.3%) |
| P4 | +8 | +13 | +8 | 0/3 (0%) |
| P5 | +2 | +2 | -5 | 2/3 (66.7%) |
| P6 | reference U | reference U | reference U | unavailable |
| P7 | reference U | reference U | reference U | unavailable |
| P8 | reference U | reference U | reference U | unavailable |

No scored stage reaches the required 90% held-out hit rate.

## Body, shaft, and clubhead evidence

Apple Vision body-pose coverage is not the main failure in the three
completed clips:

- Head, hips, knees, ankles, and hand center are present in almost every one
  of the 192–204 analyzed frames.
- Individual wrists are measured in approximately 87–98% of frames.
- Individual elbows are measured in approximately 87–96% of frames.

These are coverage figures, not coordinate-accuracy measurements. No
human-labelled landmark coordinates exist yet, so body trajectory error,
spine-angle error, median error, and P90 error remain unavailable.

Golf-object evidence is not usable:

- Measured clubhead frames: 0 in all three completed clips.
- Measured grip frames: 0 in all three completed clips.
- Shaft endpoints: only 5, 5, and 1 frames respectively.
- No `GolfKeypoints.mlmodel` or compiled model is bundled in the project.
  The current run therefore falls back to a sparse contour detector on
  images downscaled to at most 256 pixels.

Consequently, SwingArc cannot currently claim accurate shaft or clubhead
trajectory, and P2/P6/P8 cannot receive the required shaft-parallel
evidence.

## Root-cause decision

The evidence separates the failures:

1. Apple Vision is supplying dense body landmarks for the completed clips.
2. P1–P8 failures are primarily in SwingArc's attempt segmentation,
   slow-motion time-scale assumptions, stage geometry, and constrained
   solver.
3. Clubhead/shaft failure is a SwingArc model and image-resolution gap:
   the model integration exists, but the trained model asset does not.
4. A fixed 8-second adaptive window is incompatible with at least some
   Photos slow-motion timelines; a blanket “240 FPS means 8× slower” rule
   is also unsafe because the edited slow-motion region can vary by clip.

## Required next work

1. Export and pair the unmodified 240 FPS originals with these 30 FPS
   playback-timeline files; compare frame count, bitrate, source-frame
   identity, solver output, and runtime.
2. Infer or read the effective time scale for each swing attempt instead of
   applying normal-speed second-based limits to every clip.
3. Preserve Vision for body landmarks, then correct P1–P8 from source-frame
   geometry and tempo-normalized ordering.
4. Label grip, shaft endpoints, clubhead, and ball on authorized high-rate
   frames; train and bundle a real replaceable Core ML golf-keypoint model.
5. Run golf-object inference on a high-resolution golfer/club ROI and track
   it bidirectionally with hand-anchor, shaft-length, and acceleration
   constraints. Missing evidence must remain missing.
6. Add human-reviewed body and clubhead coordinates before calculating
   trajectory accuracy.
7. Lock a golfer-separated held-out set with at least 10 golfers and both
   DTL and face-on coverage before any release accuracy claim.

## Release decision

`releasePassed = false`

Failed gates:

- No locked held-out split and fewer than 10 held-out golfers.
- No successful DTL result.
- Every scored P stage is below the 90% within-±2-frame threshold.
- Human-reviewed body-landmark error is unavailable.
- Clubhead visible-frame hit rate is 0% in completed clips.
- Clubhead error and gap metrics are unavailable.
- The development labels are not yet locked human-expert truth.
- The unmodified 240 FPS originals have not yet been paired and tested.

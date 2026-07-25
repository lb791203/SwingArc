# Mac golf keypoint annotation validation

Validation executed on 2026-07-25 for Plan 2 / Task 6 and extended on
2026-07-26 after the user supplied the anonymous golfer mapping. This record
keeps measured results separate from the remaining ROI and prediction-readiness
gates. No source video or truth JSON was modified.

## Current gate

Task 6 is **not fully green**:

- all 8 video/truth pairs match by media SHA-256, source-timeline SHA-256, and
  exact frame count;
- the inventory contains 5 DTL and 3 Face-on clips;
- the user-confirmed mapping is locked as 6 `golfer-001` training clips and
  2 `golfer-002` validation clips; both golfers are right-handed and no golfer
  appears in more than one split;
- all 8 clips were imported through `SwingArcDataset.app`, and every
  app-created security-scoped bookmark reopens after relaunch and passes media,
  timeline, and frame-count verification;
- 5 DTL clips pass the current automatic primary-track and stable-ROI path;
- 2 Face-on clips require a manual primary-subject anchor;
- 1 Face-on clip remains below the identity-stability threshold;
- the imported clips do not yet have immutable prediction runs, so the
  annotation workspace correctly remains read-only with
  `缺少可追溯的预测运行 ID。`; no prediction or reviewed keypoint label was
  fabricated to bypass that provenance gate.

## Reproducible inputs

- Videos: `/tmp/SwingArc-8-videos-20260724-153013`
- P1-P8 truth: `/Users/liangbo/Desktop/test/P 点`
- Pair verifier: `.superpowers/sdd/task6-verify-eight.swift`
- ROI verifier: `.superpowers/sdd/task6-real-roi-report.swift`
- Pair output: `/tmp/task6-verify-eight.tsv`
- ROI output: `/tmp/task6-real-roi-report.tsv`

Both helpers use the repository's exact-frame, identity, queue, Vision-track,
and stable-ROI implementations. The ROI run decoded every source frame. It did
not use P-point labels to construct the ROI.

## Confirmed identity, split, and live import

The A-H labels below are the visual-comparison labels shown to the user. Their
mapping was supplied explicitly; it was not inferred from filenames, clothing,
or pose similarity.

| Label | Video | Imported clip ID | Golfer | Split | Handedness |
|---|---|---|---|---|---|
| A | `imported-334AD734-3E15-4673-A0DA-B87AE2DCE123.mp4` | `golfer-001-dtl-001` | `golfer-001` | training | right |
| B | `imported-4BC8E027-63AB-4EB7-870C-9386EF721E04.mp4` | `golfer-001-face-on-001` | `golfer-001` | training | right |
| C | `imported-B3ADCDD3-EFA6-47CF-83D8-C0821A8EEC01.mp4` | `golfer-001-face-on-002` | `golfer-001` | training | right |
| D | `imported-C2BEA6B0-133C-446E-874B-F175365D88F4.mp4` | `golfer-001-dtl-002` | `golfer-001` | training | right |
| E | `imported-CC52F22C-4662-4ACC-B943-BFF5F426DC0E.mp4` | `golfer-002-dtl-001` | `golfer-002` | validation | right |
| F | `imported-D0CDADE8-A0F8-4BB7-A847-0FD9E8094255.mp4` | `golfer-002-dtl-002` | `golfer-002` | validation | right |
| G | `imported-E26D3E11-B7A1-459A-91A9-1D342E673397.mp4` | `golfer-001-face-on-003` | `golfer-001` | training | right |
| H | `imported-E37467FC-4653-4E32-A7E4-B758BC71CE43.mp4` | `golfer-001-dtl-003` | `golfer-001` | training | right |

The live dataset is stored under
`~/Library/Application Support/SwingArcDataset/golf-keypoints-v1`. The registry
contains exactly `golfer-001 -> training` and
`golfer-002 -> validation`; all eight clip records carry `right`,
`training-allowed`, the verified media identity, and the P-point truth SHA-256.
`GolfDatasetValidator` reported:

```text
dataset contract passed: golfers=2 clips=8 training=6 validation=2
```

A command-line preflight initially produced non-empty bookmarks that were
scoped to the helper executable and therefore could not be resolved by the
app. This was detected by opening a real clip in the UI. The final import was
then repeated through the app itself without weakening the security-scoped
bookmark contract. Each of the eight rows was selected after import and again
after process relaunch. Every row passed bookmark and media identity opening
and stopped only at the expected missing-prediction-run gate.

## Media and queue inventory

`trainingQueue` and `validationQueue` below are deterministic queue-builder
results without anomaly frames or explicit negative samples. They are not
presented as a final imported production queue. `p6Dense` and `p8Dense` are the
25-frame dense windows requested around each truth stage.

| Video | Truth JSON | View | Frames | Media | Timeline | Training queue | Validation queue | P6 dense | P8 dense |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `imported-334AD734-3E15-4673-A0DA-B87AE2DCE123.mp4` | `p-points-6a4f3e116f68-dtl.json` | DTL | 1157 | OK | OK | 135 | 146 | 25 | 25 |
| `imported-4BC8E027-63AB-4EB7-870C-9386EF721E04.mp4` | `p-points-e7c85e30554c-face-on.json` | Face-on | 496 | OK | OK | 77 | 83 | 25 | 25 |
| `imported-B3ADCDD3-EFA6-47CF-83D8-C0821A8EEC01.mp4` | `p-points-a58bb2f53f44-face-on.json` | Face-on | 723 | OK | OK | 76 | 81 | 25 | 25 |
| `imported-C2BEA6B0-133C-446E-874B-F175365D88F4.mp4` | `p-points-3088c3ebf3d0-dtl.json` | DTL | 757 | OK | OK | 71 | 78 | 25 | 25 |
| `imported-CC52F22C-4662-4ACC-B943-BFF5F426DC0E.mp4` | `p-points-8251675efa2f-dtl.json` | DTL | 629 | OK | OK | 38 | 41 | 25 | 25 |
| `imported-D0CDADE8-A0F8-4BB7-A847-0FD9E8094255.mp4` | `p-points-aa5f312d231e-dtl.json` | DTL | 647 | OK | OK | 88 | 102 | 25 | 25 |
| `imported-E26D3E11-B7A1-459A-91A9-1D342E673397.mp4` | `p-points-60bdcbda9842-face-on.json` | Face-on | 638 | OK | OK | 80 | 86 | 25 | 25 |
| `imported-E37467FC-4653-4E32-A7E4-B758BC71CE43.mp4` | `p-points-1a14208a29b0-dtl.json` | DTL | 1365 | OK | OK | 125 | 137 | 25 | 25 |

## Stable ROI results

The five passing clips use a fixed clip-level stable ROI after identity
resolution. Therefore their measured frame-to-frame ROI jitter is exactly zero;
this is an implementation property, not a rounded or fabricated score.

| Video | Pose frames | Candidates | ROI coverage | Jitter P95 | Max round-trip error (px) | Result |
|---|---:|---:|---:|---:|---:|---|
| `imported-334AD734-3E15-4673-A0DA-B87AE2DCE123.mp4` | 1157 | 1157 | 1157/1157 | 0.0000 | 0.00000000 | OK |
| `imported-4BC8E027-63AB-4EB7-870C-9386EF721E04.mp4` | 0 | 720 | 0/0 | — | — | Manual anchor required to resolve identity |
| `imported-B3ADCDD3-EFA6-47CF-83D8-C0821A8EEC01.mp4` | 723 | 723 | 0/0 | — | — | Identity confidence below stability threshold |
| `imported-C2BEA6B0-133C-446E-874B-F175365D88F4.mp4` | 757 | 757 | 757/757 | 0.0000 | 0.00000000 | OK |
| `imported-CC52F22C-4662-4ACC-B943-BFF5F426DC0E.mp4` | 629 | 629 | 629/629 | 0.0000 | 0.00000000 | OK |
| `imported-D0CDADE8-A0F8-4BB7-A847-0FD9E8094255.mp4` | 647 | 647 | 647/647 | 0.0000 | 0.00000000 | OK |
| `imported-E26D3E11-B7A1-459A-91A9-1D342E673397.mp4` | 0 | 727 | 0/0 | — | — | Manual anchor required to resolve identity |
| `imported-E37467FC-4653-4E32-A7E4-B758BC71CE43.mp4` | 1365 | 1365 | 1365/1365 | 0.0000 | 0.00000000 | OK |

No threshold was lowered to turn the three Face-on failures into passes.

## Controller and blind-mode proof

`Tests/MacDatasetBlindModeSmoke.swift` passed on 2026-07-25. Its store rejects
the broad snapshot API by construction; the controller protocol exposes only
narrow clip, registry, revision, prediction-ID, and single-prediction reads.
The smoke verified:

- one append-only atomic full revision snapshot per explicit landmark decision;
- frame stepping persists only the session cursor;
- relaunch restores the exact clip, source frame, filter, and revision;
- a missing persisted revision opens read-only and does not substitute or erase
  it;
- bookmarks remain independently restorable for multiple clips;
- media SHA, timeline SHA, or frame-count mismatch opens read-only;
- held-out restore and clip selection do not decode or load prediction content;
- save failure opens read-only without claiming the revision was saved.
- out-of-order A→B media open and frame completion cannot publish stale A data;
- unreadable revision history opens read-only instead of appearing empty;
- multiple prediction runs require an explicit persisted run ID rather than
  filename-order selection.

Observed output:

```text
All Mac dataset blind-mode/controller tests passed.
```

The production binding also passes the source contract smoke: an import receipt
is handed to the retained controller, the bookmark is saved under its clip ID,
the sidebar calls the controller's asynchronous clip selection, and the canvas
uses the selected media/image dimensions. The behavior smoke uses an injected
media-access implementation. The 2026-07-26 live pass additionally verified
real app-created security-scoped bookmarks for all eight imported clips.

## Build and launch proof

Both repository build gates passed with Xcode beta:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -jobs 1 -project SwingArcProject.xcodeproj \
  -scheme SwingArcDataset -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -jobs 1 -project SwingArcProject.xcodeproj \
  -scheme SwingArcProject -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Each command ended with `** BUILD SUCCEEDED **`. Logs:

- `/tmp/task6-final-mac-build.log`
- `/tmp/task6-final-ios-build.log`

The Mac artifact was launched locally:

`/Users/liangbo/Library/Developer/Xcode/DerivedData/SwingArcProject-aijrnhkjftwshkduecqdvwnfxtwf/Build/Products/Debug/SwingArcDataset.app`

`pgrep` confirmed the app executable remained running as PID 41095 after
launch. This proves process launch, not a completed visual/manual import pass.

Additional passing checks:

- `MacDatasetAnnotationStateSmoke`
- `MacDatasetWorkspaceSourceSmoke`
- `GolfAnnotationFrameQueueSmoke`
- `MacDatasetImportContractSmoke`
- `GolfKeypointAnnotationContractSmoke`
- `git diff --check`
- `plutil -lint SwingArcProject.xcodeproj/project.pbxproj`

The standalone blind smoke compiler reports existing AVFoundation deprecation
warnings from `ExactVideoFrameProvider.swift`; no warning was introduced by the
Task 6 controller, and no test or build failed.

The mapping follow-up also passed both isolated builds:

- `/tmp/task6-mapping-mac-build.log`
- `/tmp/task6-mapping-ios-build.log`

The Mac artifact used for the live eight-clip import and relaunch check was:

`/tmp/SwingArc-Task6-Mapping-Mac/Build/Products/Debug/SwingArcDataset.app`

## Closed identity input and remaining gates

The former anonymous identity, golfer-level split, and handedness blocker is
closed. It must not be reopened or recomputed from filenames:

- `golfer-001`: A, B, C, D, G, H; right-handed; training.
- `golfer-002`: E, F; right-handed; validation.

The remaining real-data work is independent of that mapping:

1. add a traceable immutable prediction run for each imported clip;
2. obtain manual primary-subject anchors for B and G, and resolve C's
   identity-stability failure without lowering the threshold;
3. complete and review the five-keypoint annotation revisions, then freeze a
   resolved training/validation export;
4. retain the development-only label: two golfers and no held-out golfers
   cannot support a release-accuracy claim.

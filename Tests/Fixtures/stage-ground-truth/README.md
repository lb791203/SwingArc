# Swing Stage Ground-Truth Fixtures

Each JSON manifest admitted to this directory describes one locally retained
source video. The video itself is never committed unless it is synthetic and
contains no person.

For a canonical `p-system-v1` fixture record:

- video filename, duration and source frame rate;
- camera view (`DTL` or `Face-on`), handedness and lighting in the companion
  field-test checklist;
- one strictly increasing source-frame index for P1 through P8;
- at least two independent annotation passes; and
- the precise canonical P-stage definitions used by
  `GroundTruthManifestValidator`.

`legacy-named-keyframes-v1` is allowed only to preserve existing human
annotations that predate the standard P1–P8 migration. It must name its final
three frames `impact`, `followThrough`, and `finish`; it must never relabel
those frames as P6, P7, or P8. Legacy manifests are comparison data, not
canonical P-stage calibration and cannot establish a delivery P6 frame.

When a stage cannot be identified unambiguously, exclude that clip from
automatic-marker calibration and retain it as a negative/low-confidence test
case. Do not invent a frame index to make the report complete.

Before promoting a detector change, evaluate the same manifest set with both
the candidate and the committed baseline. The candidate must not add unresolved
stages or false confirmations and must not worsen median source-frame error.

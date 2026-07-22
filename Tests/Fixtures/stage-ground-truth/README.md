# P1–P8 Ground-Truth Fixtures

Each JSON manifest admitted to this directory describes one locally retained
source video. The video itself is never committed unless it is synthetic and
contains no person.

For each fixture record:

- video filename, duration and source frame rate;
- camera view (`DTL` or `Face-on`), handedness and lighting in the companion
  field-test checklist;
- one strictly increasing source-frame index for P1 through P8;
- at least two independent annotation passes; and
- the precise canonical P-stage definitions used by
  `GroundTruthManifestValidator`.

When a stage cannot be identified unambiguously, exclude that clip from
automatic-marker calibration and retain it as a negative/low-confidence test
case. Do not invent a frame index to make the report complete.

Before promoting a detector change, evaluate the same manifest set with both
the candidate and the committed baseline. The candidate must not add unresolved
stages or false confirmations and must not worsen median source-frame error.

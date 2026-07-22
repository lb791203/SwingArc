# Home and Manual Capture UI Refinement

**Date:** 2026-07-22

## Goal

Restore a clear SwingArc brand rhythm on the practice home screen and make the
manual capture action visually consistent with the automatic-practice primary
control, without changing navigation or recording behavior.

## Manual Capture Primary Action

- Keep the existing full-width rounded rectangle, theme signal fill, immediate
  recording behavior, stop behavior, and 15-second cap.
- Center the complete button content horizontally.
- Present the record/stop icon and primary title as one centered row, with the
  supporting line centered underneath.
- Match the automatic-practice action hierarchy: 20-point black rounded title,
  compact secondary line, 24-point corner radius, and at least 78 points of
  touch height.
- Do not retain the current trailing `Spacer`, which makes the label appear
  left-aligned.

## History Entry

- Keep history as a secondary action in the upper-right header.
- Increase the label to 14 points and provide a minimum 48-point touch height.
- Use `proTourSignal` for the history icon only.
- Use `proTourPrimaryText` for the “记录” label.
- Retain a `proTourSurface` capsule with a 25%-opacity `proTourSignal` border.
- Do not fill the whole capsule with the signal color; the history entry must
  remain subordinate to the mode cards and primary recording action.

## Mode Card Brand Rhythm

- Keep card order and behavior unchanged: DTL, FACE-ON, manual capture, import.
- Keep DTL as the deep-green hero card.
- Render every `01`–`04` index as the same branded signal badge instead of
  leaving `02`–`04` gray.
- Use `proTourSignal` for every mode icon and northeast arrow.
- Keep `02`–`04` on the dark surface, with a low-opacity signal border so the
  four cards read as one designed family.
- Do not introduce four unrelated accent colors; SwingArc retains one signal
  color and differentiates modes through iconography, text, and the DTL hero
  surface.

## Accessibility and Scope

- Preserve existing accessibility labels and increase, rather than reduce,
  touch targets.
- Do not change camera, persistence, automatic capture, import, history, or
  analysis logic.
- Verify the home screen and manual capture screen at the physical iPhone
  resolution after simulator build succeeds.

## Acceptance Criteria

1. “开始录像” and “结束录制” are optically centered.
2. “记录” is clearly readable at normal phone distance and uses the approved
   icon-only signal emphasis.
3. `01`–`04`, all four mode icons, and all four arrows share the SwingArc signal
   color while DTL remains the only fully green card.
4. Navigation and recording behavior remain unchanged.
5. Simulator and signed physical-device builds succeed, and screenshots show
   the intended hierarchy without clipping.

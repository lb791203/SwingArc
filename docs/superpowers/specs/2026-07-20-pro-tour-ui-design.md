# SwingArc Modern Pro Tour UI Design

## Purpose

Replace the current generic card-based home and practice presentation with a
premium, modern professional-tour training product. Browser mockups are not an
acceptance artifact: all UI decisions are reviewed in the actual SwiftUI app
running on the iPhone simulator before any physical-device installation.

## Confirmed Product Direction

- Brand character: modern professional-tour technology, not traditional club
  luxury and not a generic Apple utility interface.
- Primary user context: a golfer standing beside a tripod, potentially wearing
  a glove and reading the phone from roughly two metres away.
- MVP views: single-phone DTL and face-on sessions; they are separate practice
  modes, never simultaneous capture.
- Existing video import, slow motion, P1–P8 analysis and manual annotation
  remain available as secondary tools.

## Visual System

### Palette

- Base: graphite-black surfaces with restrained tonal separation.
- Brand: course green for stable, passive brand surfaces.
- State: fluorescent yellow-green only for an actionable ready/confirmed/shot
  state. Orange remains reserved for an interruption or pause state.
- Text: warm white for primary reading, muted cool grey for context.

The state colour is never used decoratively. This makes the one required
action legible at a distance and keeps a positive training result distinct
from non-actionable information.

### Typography and Layout

- Use wide, bold numerals and short verbs for states a golfer reads from the
  ball position.
- On a practice screen, no paragraph may compete with the main state label.
- The main control is at least 76 pt tall; all other controls are visibly
  secondary and separated from it.
- Home options are mode selectors, not equal white informational cards.

## Information Architecture

### Home

1. One large `开始练习` hero area establishes the product purpose.
2. `正后方 DTL` and `正面 Face-on` are two explicit selectable practice
   modes, using concise labels and visual mode affordances.
3. `导入挥杆影片` and `历史分析` appear below the primary training decision as
   secondary utility actions. They must not resemble disabled controls.

### Practice Session

```
Home
  -> choose DTL or Face-on
  -> alignment screen
  -> one tap: 开始自动练习
  -> waiting state
  -> detected impact / clip capture / local analysis
  -> brief priority-result ribbon
  -> automatically re-arm and return to waiting
```

- The full-screen live camera is the primary surface.
- The header contains only selected view and a quiet exit control.
- The centre contains a large status: alignment, ready, waiting, analysing, or
  one result phrase. It must remain readable without approaching the phone.
- `暂停自动练习` is the only primary alternative while waiting.
- `查看上一球慢动作` appears only after a retained clip exists and stays
  secondary.

### Analysis Workspace

- Retain the existing frame-by-frame toolset.
- Present a priority feedback card before optional overlays only when the
  evidence requirements are satisfied.
- The card links to its supporting P stages. A drill appears only for a
  confirmed evidence-backed finding.
- A manual P-point edit remains local truth. If its exact source frame lacks a
  usable pose sample, the technique judgement becomes unavailable rather than
  guessed.

## Acceptance Rules

1. Inspect and approve the actual iPhone simulator screenshots and interaction
   flow for Home, alignment, waiting, result ribbon, import and analysis.
2. Verify touch hierarchy in the simulator: no accidental action can outrank
   the one intended practice control.
3. Do not call the UI ready based on a browser prototype or an Xcode build.
4. Only after simulator approval, install on the physical iPhone and validate
   camera, microphone, capture loop, outdoor legibility and heat.

## Out of Scope for This UI Pass

- Cloud accounts, leaderboards and scoring.
- Simultaneous two-angle recording.
- Growth diary/calendar; it remains a later phase after automatic practice
  and evidence-backed single-shot analysis are accepted.

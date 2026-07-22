# Home Single-Screen Visual Hierarchy Design

**Date:** 2026-07-22

## Goal

Create a restrained portrait home screen that shows the brand header, title, all four practice entries, and the bottom safe area at once on every supported iPhone. The page must have no vertical scrolling or bounce space.

## Approved Card Direction

Remove the four colored card surfaces. All cards use `AnalysisTheme.proTourSurface` over the existing `proTourBackground`, with opacity providing a subtle top-to-bottom hierarchy:

| Mode | Role | Surface opacity |
| --- | --- | --- |
| 01 | Down the Line | `0.85` |
| 02 | Face-On | `0.70` |
| 03 | Manual Capture | `0.55` |
| 04 | Import Video | `0.40` |

Only the surface changes opacity. Text, badges, icons, arrows, and hit targets remain fully opaque so lower entries never look disabled.

## Shared Card Treatment

- Keep the existing card order, titles, details, icons, navigation, corner radius, accessibility labels, and press behavior.
- Use `proTourPrimaryText` for titles and `proTourSecondaryText` for eyebrow/detail text.
- Keep the `01`-`04` badges identical: `proTourSignal` fill with `proTourBackground` text.
- Keep every mode icon and northeast arrow in `proTourSignal`.
- Use `proTourSignal.opacity(0.14)` for every card border.
- Do not use a unique hue or full-card hero treatment for any mode.

## History Entry

- Remove the history button's capsule background and border completely.
- Use a 14-point `proTourSignal` history icon and 13-point `proTourPrimaryText` label.
- Keep the visible icon-and-label content no taller than the SWINGARC wordmark beside it.
- Preserve a minimum 44-point invisible touch target and the existing accessibility label without adding visible padding, fill, or stroke.

## Portrait Single-Screen Layout

- Remove `ScrollView` from `PracticeHomeView`; the page must not scroll or vertically bounce.
- Use the safe-area height from `GeometryReader` to choose one of three metric tiers rather than scaling the whole view:

| Available height | Card height | Card gap | Main title size |
| --- | --- | --- | --- |
| `>= 820` | `126` | `12` | `38` |
| `700...819` | `108` | `10` | `34` |
| `< 700` | `92` | `8` | `30` |

- Compact the title-to-card spacing and card typography with the same tier so the whole page fits. Regular card title/detail sizes are 24/14 points, compact sizes are 22/13 points, and tight sizes are 20/12 points.
- Keep horizontal padding at 20 points and respect top and bottom safe areas.
- Do not use `scaleEffect` to make the page fit; text and touch targets must remain crisp and independently sized.
- The bottom of card 04 must remain visible with no clipping and no extra draggable space.

## Implementation Boundaries

- Replace the four temporary `practice*Surface` color tokens with a shared opacity value passed to `PracticeModeSelector`.
- Keep the adaptive layout metrics local to the home-screen presentation; do not change global typography or other screens.

## Scope and Non-Goals

This change is presentation-only. It does not modify camera behavior, recording timing, automatic capture, video import, history data, persistence, analysis, or navigation.

## Verification

- Extend the home styling smoke test so it requires the four opacity values, the adaptive metric tiers, and the absence of `ScrollView` and colored practice-surface tokens.
- Build and inspect regular and compact portrait simulator layouts.
- Build and install on the connected wireless iPhone.
- Capture the physical home screen and verify all content fits at once, no vertical drag space exists, the history entry has no capsule, and the four restrained surface levels remain distinguishable.

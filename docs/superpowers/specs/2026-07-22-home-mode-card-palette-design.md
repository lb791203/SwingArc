# Home Mode Card Palette Design

**Date:** 2026-07-22

## Goal

Give all four practice-mode cards a visible colored surface while keeping them inside one SwingArc professional green-to-teal brand family. No entry should look disabled or visually unfinished.

## Approved Direction

Use four neighboring brand hues instead of one green hero card plus three near-black cards:

| Mode | Role | Surface direction |
| --- | --- | --- |
| 01 | Down the Line | Forest green, anchored to the existing `proTourGreen` |
| 02 | Face-On | Deep teal green |
| 03 | Manual Capture | Olive green |
| 04 | Import Video | Blue green |

The surfaces must be visibly colored at normal screen brightness. They must not collapse into four black or charcoal cards, and they must not introduce unrelated orange, purple, or saturated rainbow colors.

## Shared Card Treatment

- Keep the existing card order, titles, details, icons, navigation, sizing, corner radius, and press behavior.
- Use `proTourPrimaryText` for all titles.
- Use `proTourPrimaryText` at reduced opacity for eyebrow and detail text on every colored surface.
- Keep the `01`-`04` badges identical: `proTourSignal` fill with `proTourBackground` text.
- Keep every mode icon and northeast arrow in `proTourSignal`.
- Use the same low-opacity `proTourSignal` border on all four cards so the palette reads as one system.
- Do not preserve a unique full-card hero treatment for `01`; hierarchy comes from position and content, not from making the other three cards look inactive.

## Theme Architecture

Add four semantic surface tokens to `AnalysisTheme` rather than placing raw RGB values in `PracticeHomeView`. `PracticeModeSelector` receives one surface color and no longer branches through `usesBrandSurface`.

Use these approved starting values:

| Token | RGB |
| --- | --- |
| `practiceDTLSurface` | `(0.12, 0.37, 0.27)` |
| `practiceFaceOnSurface` | `(0.08, 0.32, 0.34)` |
| `practiceManualSurface` | `(0.29, 0.32, 0.12)` |
| `practiceImportSurface` | `(0.12, 0.27, 0.34)` |

Verify the values on the physical iPhone against these acceptance criteria:

1. clear separation between neighboring cards;
2. readable white secondary text;
3. a cohesive green-to-teal family;
4. sufficient visibility without competing with the bright signal color.

## Scope and Non-Goals

This change is presentation-only. It does not modify camera behavior, recording timing, automatic capture, video import, history, persistence, accessibility labels, or navigation.

## Verification

- Extend the home styling smoke test so it requires four semantic card-surface tokens and rejects the old `usesBrandSurface` branch.
- Build the simulator app.
- Build and install on the connected wireless iPhone.
- Capture the home screen and verify all four cards have visible, distinct brand-family surfaces; text does not clip; lime badges and glyphs remain readable.

# SwingArc DTL / FO Fullscreen Replay Design

## Purpose

Make replay a full-screen video-review experience for a golfer, while keeping
measurement selection and configuration separate. The interface must remain
legible from a tripod distance and must not fabricate a swing finding when the
video evidence is incomplete.

This design applies to imported videos and captured practice clips. It extends
the existing P1–P8 timeline; it does not change the conservative stage-detection
or manual-stage-editing evidence rules.

## Confirmed Interaction Model

### Fullscreen replay

- The video uses the maximum available screen area.
- Tapping anywhere on the visible video, except an interactive overlay, toggles
  play and pause. There is no permanent play or pause button.
- The replay surface does not display start time, end time, elapsed time, or a
  `反馈设置` button.
- A quiet dismissal control and help control may appear with the transient
  chrome, then fade with the other overlays after inactivity.
- The current feedback is represented by a central, compact feedback pill,
  for example `◉ 脊柱侧倾`. It contains no instructional helper text.
- Tapping the feedback pill opens a separate `挥杆反馈` configuration page.
  This is the only configuration entry inside replay; it is an information
  object and a direct selector, not an additional toolbar button.

### Phase navigation

- The scrub line remains near the bottom of replay, without visible time
  strings.
- P1–P8 are represented by eight compact swing-pose silhouettes rather than
  prominent text buttons or generic dots.
- Each silhouette is an independent, minimum 44 pt touch target. Selecting it
  seeks to the resolved stage frame and pauses playback at that frame.
- The selected stage gets only a thin circular highlight. Confirmed stages use
  normal opacity; low-confidence stages are subdued; missing stages are omitted
  rather than invented.
- The phase strip is navigational. It never creates a technical diagnosis by
  itself.

### Feedback selection

```
Fullscreen replay
  -> tap current feedback pill
  -> full-page 挥杆反馈
  -> choose view, metric, and applicable stages
  -> close
  -> replay returns with the selected feedback pill and matching overlay
```

- `挥杆反馈` is a full-page sheet. It never shares the screen with a half-height
  video.
- Changing DTL / 正面视角 replaces the whole feedback matrix, not merely the
  title or camera preview.
- The active metric determines which evidence-backed visual overlay and spoken
  explanation are eligible during replay.
- A metric whose required pose, club, or impact evidence is absent stays
  unavailable with a concise reason. It must not show an inferred score or an
  `In Zone` conclusion.

## Measurement Profiles

The UI uses Chinese names. English abbreviations are limited to the small
view identifier when useful: `DTL` and `FO`.

### DTL — 目标线视角

| Group | Metrics / stages |
| --- | --- |
| 准备姿势 | 瞄准、髋部前倾、髋部深度、膝屈、手位 |
| 挥杆平面 | 起杆、上杆半程、下杆半程、送杆位 |
| 手部路径 | 起杆、上杆半程、顶点、下杆半程、送杆位、击球 |
| 脊柱稳定 | 起杆、上杆半程、顶点、下杆半程、送杆位、击球 |
| 头部位置 | 仅显示有可靠姿态证据的阶段 |

### FO — 正面视角

| Group | Metrics / stages |
| --- | --- |
| 准备姿势 | 髋位、胸位、手位、站距 |
| 释放 | 下杆滞后、击球杆身前倾 |
| 脊柱侧倾 | 起杆、上杆半程、顶点、下杆半程、送杆位、击球 |
| 前导肩 | 顶点、击球 |
| 前导髋 | 起杆、上杆半程、顶点、下杆半程、送杆位、击球 |
| 头部位置 | 仅显示有可靠姿态证据的阶段 |

`下杆滞后` and `击球杆身前倾` require reliable club and impact evidence.
2D body pose alone may not make either conclusion.

## View and Data Boundaries

Introduce a view-keyed analysis profile, conceptually:

```swift
AnalysisProfile
  view: .downTheLine | .faceOn
  groups: [FeedbackGroup]

FeedbackGroup
  title: String
  metrics: [FeedbackMetric]

FeedbackMetric
  title: String
  eligibleStages: [SwingStage]
  requiredEvidence: EvidenceRequirement
  overlay: OverlayKind
```

- `AnalysisProfile` owns labels, allowed stage selection, evidence requirements,
  overlay kind, and drill linkage.
- Existing pose/stage detection remains the source of truth. The profile reads
  its result; it does not overwrite stages or confidence.
- The replay view owns only playback, transient chrome, feedback-pill routing,
  phase seeking, and overlay presentation.
- The feedback sheet owns selection state. It writes a selected metric ID and
  returns to replay; it does not instantiate or retain a second video player.

## Overlay and Error Behaviour

- An active metric may render only its relevant line, angle, path, or joint
  markers. Full-club trace, checkpoint pause, and feedback visuals remain
  separate replay-display preferences.
- The selected feedback pill remains available even if an individual current
  frame has no evidence. In that case the overlay is hidden and the result
  states `当前画面证据不足`.
- An incomplete clip keeps its actual detected stages. No missing silhouette,
  impact point, score, or coaching phrase is synthesized.
- Manual P-point edits continue to take precedence for navigation. A manually
  edited frame with no usable pose data can be viewed and annotated, but cannot
  create an automated technique finding.

## Acceptance Criteria

1. Simulator replay uses the full screen without permanent transport controls,
   time labels, or a feedback-settings button.
2. A video-area tap toggles play/pause; a feedback-pill tap instead opens the
   full-page `挥杆反馈` sheet; a silhouette tap instead seeks to that stage.
3. The sheet visibly changes its entire group and stage matrix between DTL and
   FO.
4. The silhouette rail has 44 pt targets, subtle selected styling, and correct
   confirmed / low-confidence / missing rendering.
5. DTL and FO labels use the terminology in this document throughout replay,
   feedback configuration, results, and VoiceOver labels.
6. The replay overlay displays only evidence-supported results. Simulator
   approval remains required before any physical-device installation.

## Out of Scope

- Two-angle synchronization or simultaneous capture.
- A universal numerical score, elite target calibration, or inferred club data.
- Altering the existing stage solver, audio trigger, or video trimming rules.
- Changing the home, automatic-practice, history, or drill-library navigation
  in this pass.

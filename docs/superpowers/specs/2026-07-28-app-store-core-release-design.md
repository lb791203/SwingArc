# SwingArc 1.0 App Store Core Release Design

## Goal

Publish a focused iPhone 1.0 whose product promise is limited to:

1. importing or manually recording a golf swing video;
2. slow-motion and frame-by-frame review;
3. conservative automatic P1–P8 stage detection with manual correction;
4. professional drawing annotations;
5. local project persistence and annotated media export.

The release must not advertise or expose automatic practice, technique scoring,
drills, swing-trajectory coaching, or pose-assistance overlays.

## Product Positioning

SwingArc 1.0 is an offline golf swing video review and annotation tool. It is
not a coach, a medical product, or a source of guaranteed swing diagnoses.
Automatic P-point results are suggestions backed by observed video frames.
Missing evidence is reported as unresolved rather than replaced with a
fabricated answer.

## Release Approach

Use the existing SwingArc iPhone target and narrow its public navigation and
presentation.

- Keep the existing automatic-practice and feedback source code in the
  repository for possible later releases.
- Remove all user-accessible 1.0 routes, buttons, copy, screenshots, and review
  instructions for those deferred features.
- Do not create a second Lite target and do not delete the deferred modules.
- Keep the 1.0 release binary account-free, network-independent, and free of
  third-party analytics or tracking.

This approach minimizes signing and regression risk while preserving later
development work.

## User Flow

### Home

The launch screen contains only three actions:

- **手动录像** — open the existing manual camera flow.
- **导入视频** — choose one video through the system Photos picker.
- **记录** — reopen or delete locally stored projects.

There is no DTL or Face-on mode selector and no automatic-practice entry.

### Import and Capture

The selected or recorded video is validated, copied into SwingArc's private
project storage, and opened in the same analysis workspace. A successful new
media load automatically starts P1–P8 analysis.

An import or capture failure must not create an empty project.

### Analysis Workspace

The 1.0 workspace contains:

- play, pause, scrub, slow-motion, and exact frame stepping;
- an eight-position P1–P8 strip;
- automatic stage status and confidence presentation;
- a full-screen frame correction workspace for manual P-point selection;
- selection, line, arrow, circle, angle, and freehand tools;
- drawing color and line-width controls where applicable;
- undo, clear-all confirmation, element movement, and control-point adjustment;
- local save status;
- annotated frame and annotated video save/share actions.

The workspace does not contain:

- technique scores or coaching conclusions;
- practice drills or voice feedback;
- swing trajectory coaching;
- pose skeleton, head-stability, spine-angle, or grid switches;
- automatic-practice session controls.

## P1–P8 Detection Contract

Automatic detection uses actual decoded source frames. Each P stage is shown as
one of:

- **已识别** — sufficient evidence supports the selected source frame;
- **待核对** — a low-confidence candidate is available for review;
- **未识别** — no reliable source frame has been established.

The App must never fill missing stages from fixed video percentages. P6 and P8
remain unresolved without trustworthy shaft evidence.

The user can open P-point correction, step through exact source frames, and set
any missing or incorrect stage. P1–P8 manual frames must remain strictly
ordered. Manual corrections are stored separately from automatic predictions
and must survive:

- reanalysis;
- leaving and reopening the project;
- App termination and relaunch.

If the video is playable but automatic analysis is incomplete, playback,
drawing, and manual P-point correction remain available.

## Drawing Contract

Drawing points are stored in normalized video coordinates, not screen
coordinates. Annotations must stay aligned across portrait, landscape,
fullscreen, project reopen, and export.

Selection mode supports whole-element movement. Where a drawing type has
editable control points, the user can adjust those points independently.
Coordinates are clamped to the rendered video area.

Keyframe-specific drawings appear only at their saved video time according to
the existing display policy. Global drawings remain visible throughout
playback.

## Local Data and Privacy

The App requires no account. Videos, automatic predictions, manual corrections,
projects, and drawings remain in the App's local container.

- Camera permission is requested only after the user selects manual recording.
- Photos import uses the system picker.
- Photo-library add permission is requested only when saving exported media.
- No microphone permission or microphone usage description is included.
- No video, pose, project, or annotation data is uploaded.

The home or records area includes a small **关于与隐私** entry containing:

- App name and version;
- privacy policy link;
- support link and contact method;
- a short statement that analysis is local sports-training reference and may be
  incomplete.

The privacy policy must describe local storage, deletion through project
removal or App uninstall, permission use, and the absence of tracking.

## Error Handling

All failures use a specific, recoverable message:

- camera denied: explain how to grant camera access in Settings;
- Photos selection or copy failed: stay on the previous screen and allow retry;
- unreadable or damaged video: do not create a project;
- no stable person or incomplete swing: keep the playable project and allow
  drawing/manual P points;
- unresolved P stage: show the unresolved state and offer correction;
- export or low-storage failure: keep the source project unchanged and allow
  retry;
- analysis cancellation: stop publication of the old result without deleting
  video or annotations.

No failure path creates invented P points, a fake success state, or data loss.

## App Store Presentation

All 1.0 metadata and screenshots must describe only the approved scope:

- manual recording;
- video import;
- slow-motion/frame review;
- P1–P8 automatic detection and manual correction;
- professional drawing;
- local records and annotated export.

Remove claims and screenshots for automatic practice, technique scoring,
coaching feedback, drills, swing trajectories, and pose-assistance overlays.
The description must say that camera position, lighting, occlusion, motion blur,
and video completeness affect automatic detection.

App Review notes use the deterministic path:

1. import a human-motion or golf-swing video from Photos, or make a short manual
   recording;
2. wait for local P1–P8 analysis;
3. inspect detected and unresolved stages;
4. correct a stage frame;
5. draw and move an annotation;
6. save or share an annotated frame;
7. reopen and delete the local project from Records.

The screenshots use an accepted current 6.9-inch iPhone size, contain real App
UI, and avoid personal notifications, debug controls, and unsupported accuracy
claims.

## Build and Submission Constraints

- Marketing version: `1.0`.
- Bundle identifier: `com.liangbo.swingarc`.
- Device family: iPhone only.
- Minimum deployment target: iOS 17.
- App Store submission build: a public App Store-supported Xcode release using
  the iOS 26 SDK or later.
- Do not submit a customer-distribution archive produced by a beta Xcode.
- The release archive must include the App icon, launch screen, privacy
  manifest, and required camera/Photos usage descriptions.
- Validate the archive before upload, process it in App Store Connect, and test
  the processed build through TestFlight before App Review submission.

Apple references:

- [Submitting to the App Store](https://developer.apple.com/app-store/submitting/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)

## Verification

### Automated

Run the focused test suites for:

- project persistence and deletion;
- media import and capture persistence;
- P1–P8 stage semantics and conservative solver behavior;
- P-point correction ordering, persistence, and reanalysis merging;
- drawing geometry, movement, control-point editing, and display policy;
- annotated frame/video export;
- release source contracts that exclude deferred UI routes and microphone
  permission.

Then run a Release configuration build and App Store archive validation.

### Physical iPhone

Verify on supported physical iPhones:

- clean installation and first launch;
- camera approval and denial/recovery;
- manual recording and stop;
- Photos import;
- normal, slow, and frame-by-frame playback;
- complete and incomplete P1–P8 outcomes;
- manual correction of an unresolved or incorrect stage;
- drawing creation, movement, endpoint adjustment, undo, and clear confirmation;
- project save, termination, relaunch, reopen, and deletion;
- annotated image and video save/share;
- low-storage/export failure recovery;
- absence of microphone prompts, network requests, debug UI, and crashes.

Repeat the core flow on the processed TestFlight build. Automated tests,
successful signing, and archive validation do not replace this device
acceptance.

## Release Acceptance

SwingArc 1.0 is ready to submit only when:

1. the published UI exposes exactly the approved core workflow and the required
   privacy/support surface;
2. automatic analysis is conservative and every unresolved stage is honest and
   correctable;
3. manual P points and drawings persist and export correctly;
4. the focused automated suite, Release build, archive validation, and
   TestFlight processing pass;
5. the complete physical-device checklist passes on the exact TestFlight build;
6. App Store metadata, screenshots, privacy answers, review notes, price,
   territories, age rating, agreements, and contact information are complete.

## Out of Scope for 1.0

- automatic practice and visual swing-trigger capture;
- DTL/Face-on practice modes;
- technique scoring, coaching advice, drills, or speech;
- trajectory coaching and pose-assistance overlays;
- accounts, cloud sync, social sharing services, analytics, ads, purchases, or
  subscriptions;
- claims of coach-level or universally accurate P1–P8 detection.

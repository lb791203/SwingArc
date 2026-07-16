# Two-Stage P1–P8 Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the full-video 12 FPS wrist-driven main path with a coarse swing-window scan followed by source-frame sampling and an ordered P1–P8 solver that fuses pose, hand/hip geometry, club-shaft and ball evidence.

**Architecture:** `CustomVideoPlayer` performs an 8 FPS coarse pass, asks `SwingWindowLocator` for one bounded swing window, then samples only that window at the real source frame rate (capped at 120 FPS). `SwingFeatureExtractor` freezes the lead arm for the window and produces per-frame evidence; `OrderedStageSolver` chooses one globally ordered path and caps P2/P6 confidence when club/ball evidence is absent. The current wrist detector remains callable only as a compatibility fallback and is no longer used by the main analysis path.

**Tech Stack:** Swift 6, AVFoundation, Apple Vision body pose and contour requests, SwiftUI, standalone Swift smoke tests.

## Global Constraints

- Support the confirmed front or near-front, fixed-camera view only.
- Every automatic marker must reference a decoded source-video frame; do not interpolate frames or fill stages with fixed video percentages.
- Coarse scanning runs near 8 FPS; fine scanning uses the real source frame rate capped at 120 FPS and a window no longer than 6 seconds.
- P1–P8 markers are strictly increasing; unresolved stages have no timestamp.
- P6 cannot be `confirmed` without both a tracked ball and club-shaft evidence near that ball.
- P8 is the first stable finish lasting at least 0.25 seconds, never the last video frame by default.
- Manual stage locks retain priority through reruns and persistence.
- Analysis stays on-device, exposes real locating/extracting/solving progress, and stale runs cannot write results.

---

### Task 1: Locate a unique swing window and plan exact source frames

**Files:**
- Modify: `SwingArc/Services/SwingStageDetector.swift`
- Test: `Tests/SwingWindowLocatorSmoke.swift`
- Test: `Tests/FineSwingSamplingPlanSmoke.swift`

**Interfaces:**
- Produces: `CoarseSwingSample`, `SwingWindow`, `SwingWindowLocationResult`, `SwingWindowLocator.locate(samples:)`, `FineFrameReference`, and `FineSwingSamplingPlan.frames(window:sourceFrameRate:duration:)`.

- [ ] **Step 1: Write failing locator and source-frame tests**

Create a long coarse fixture containing one short high-energy hand/shoulder sequence and assert its padded window encloses the sequence and is at most six seconds. Create a second fixture with two equal, separated motion bursts and assert `.ambiguousCandidates`. Assert a 59.94 FPS window produces strictly increasing real frame indices, no interval below the source-frame duration, and that 240 FPS input is capped at 120 samples per second.

- [ ] **Step 2: Run tests and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/SwingWindowLocatorSmoke.swift -o /tmp/window-locator && /tmp/window-locator
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/FineSwingSamplingPlanSmoke.swift -o /tmp/fine-plan && /tmp/fine-plan
```

Expected: compilation fails because the two-stage contracts do not exist.

- [ ] **Step 3: Implement the locator and frame plan**

Compute coarse-frame hand velocity plus shoulder/hip rotation change, bridge gaps no longer than 0.5 seconds, score each continuous burst, reject a second candidate within 15% of the best score, and pad the selected burst by 0.6 seconds before and 1.0 second after. Generate fine frame indices using `ceil(window.startTime * sourceFrameRate)` through `floor(window.endTime * sourceFrameRate)` and stride by `max(1, ceil(sourceFrameRate / 120))`.

- [ ] **Step 4: Run both tests and verify GREEN**

Run the Step 2 commands. Expected: both exit 0.

### Task 2: Build lead-arm, club-shaft and ball evidence

**Files:**
- Modify: `SwingArc/Services/SwingStageDetector.swift`
- Modify: `SwingArc/Services/VisionPoseDetector.swift`
- Test: `Tests/SwingFeatureGeometrySmoke.swift`
- Test: `Tests/SwingObjectEvidenceSmoke.swift`

**Interfaces:**
- Produces: `LeadArmSide`, `ClubShaftEvidence`, `BallEvidence`, `SwingObjectEvidence`, `SwingFrameSample`, `SwingFrameEvidence`, `SwingFeatureExtractor.extract(frames:)`, and `SwingObjectDetector.detect(in:pose:)`.

- [ ] **Step 1: Write failing evidence tests**

Assert fixed joint coordinates produce a near-horizontal lead-arm angle, a near-180-degree extension angle, correct shoulder/hip line angles, and a stable lead arm chosen once for the entire window. Assert a shaft line touching the hands reports a small extension distance to a tracked ball, while a disconnected line is rejected. Assert the ball tracker holds a stable location through short contour misses and reports local change when the ball disappears near impact.

- [ ] **Step 2: Run tests and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/SwingFeatureGeometrySmoke.swift -o /tmp/feature-geometry && /tmp/feature-geometry
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift SwingArc/Services/VisionPoseDetector.swift Tests/SwingObjectEvidenceSmoke.swift -o /tmp/object-evidence && /tmp/object-evidence
```

Expected: compilation fails because the evidence types and geometry do not exist.

- [ ] **Step 3: Implement pose geometry and the replaceable object detector**

Extend `SwingPoseSample` with source-frame index, knees and ankles while preserving all current initializers. Extract Vision contours at a bounded image dimension, rank long thin contours connected to the hands as shaft candidates, rank small near-circular lower-frame contours as ball candidates, and use a rolling tracker to stabilize ball position. Keep contour/image work behind `SwingObjectDetector` so a future offline Core ML detector can replace it without changing the solver.

- [ ] **Step 4: Run both evidence tests and existing pose tests**

Run Step 2 plus `Tests/PoseSampleFactorySmoke.swift`. Expected: all exit 0.

### Task 3: Solve P1–P8 as one ordered path

**Files:**
- Modify: `SwingArc/Services/SwingStageDetector.swift`
- Test: `Tests/OrderedStageSolverSmoke.swift`
- Modify: `Tests/MultiJointStageDetectorSmoke.swift`

**Interfaces:**
- Consumes: Task 2 `[SwingFrameEvidence]`.
- Produces: `OrderedStageSolver.solve(evidence:) -> SwingAnalysisResult` and `SwingStageDetector.detect(frames:)`.

- [ ] **Step 1: Write failing ordered-path tests**

Build a synthetic swing with misleading local maxima out of chronological order and assert the solver chooses the globally ordered real-frame path. Assert P5 is the descending lead-arm-parallel frame rather than the first post-P4 frame; P6 is within the shaft/ball event; missing shaft or ball caps P6 at `lowConfidence`; and P8 is the first 0.25-second stable finish rather than later walking frames.

- [ ] **Step 2: Run test and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/OrderedStageSolverSmoke.swift -o /tmp/ordered-solver && /tmp/ordered-solver
```

Expected: compilation fails because the ordered solver does not exist.

- [ ] **Step 3: Implement stage scoring and dynamic programming**

Score each frame independently for P1 through P8 using stage-specific pose, velocity, stability, rotation and object requirements. Use dynamic programming with strictly increasing frame indices and transition penalties to select a single path. Derive status from stage score, joint/object coverage and best-path margin; emit no time for scores below the minimum threshold and cap P2/P6 confidence when required object evidence is absent.

- [ ] **Step 4: Run ordered, multi-joint and legacy regression tests**

Run Step 2 plus `Tests/MultiJointStageDetectorSmoke.swift`, `Tests/SwingPhaseTransitionSmoke.swift`, and `Tests/SwingStageDetectorSmoke.swift`. Expected: all exit 0; the legacy wrist API remains degraded and is not used by the main path.

### Task 4: Connect the two passes to the app and expose truthful failures

**Files:**
- Modify: `SwingArc/Views/CustomVideoPlayer.swift`
- Modify: `SwingArc/Models/WorkspaceModels.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `README.md`
- Test: `Tests/SwingAnalysisSamplingPlanSmoke.swift`
- Test: `Tests/AnalysisSessionStateSmoke.swift`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: the production two-pass `analyzeSwing`, real phase progress, explicit window failures and source-frame diagnostics.

- [ ] **Step 1: Write failing integration-policy tests**

Replace the 12 FPS expectation with 8 FPS coarse sampling and add progress/failure assertions for locating, exact-frame extracting, ambiguous windows, no stable golfer and overlong windows.

- [ ] **Step 2: Run tests and verify RED**

Run the affected smoke commands. Expected: assertions fail against the old one-pass policies.

- [ ] **Step 3: Implement the production pipeline**

Coarse-scan the full asset, locate one window, seed the stable ball tracker, fine-scan exact source frames in that window, extract evidence and solve the ordered path. Check `AnalysisRunGate` before and after every frame request and before the final write. Map progress to locating, extracting and solving phases, return explicit failure messages, merge automatic markers without overwriting manual locks, and remove the hard-coded 14–18 second debug dump.

- [ ] **Step 4: Run the full smoke suite and iOS builds**

Run every `Tests/*Smoke.swift` command with its required source files, then build both simulator and connected-device targets through `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj`. Expected: all tests and both builds exit 0.

- [ ] **Step 5: Install and launch the device build**

Install the fresh `Debug-iphoneos/SwingArcProject.app` on device `ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3`, launch `com.liangbo.swingarc`, and verify the UI reports locating, extracting and solving instead of the former full-video 12 FPS scan.

# Modern Pro Tour UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a premium modern-tour SwingArc interface whose actual SwiftUI simulator screens make practice actions readable, glove-safe and evidence-first.

**Architecture:** Preserve all local capture, Vision, P1–P8 and project-storage code. Add a small Pro Tour token/presentation layer, then recompose the existing home, live practice screen and evidence card. Every visual task ends with a real iPhone 17 simulator build, install, launch and screenshot; browser mockups never count as acceptance.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Vision, Foundation, existing smoke tests, Xcode Beta iPhone 17 simulator (`90A656D1-01D1-44FB-B9D2-2FFD811F24C3`).

## Global Constraints

- All media, analysis, calibration and clips remain on-device. Do not add accounts, cloud inference or rankings.
- DTL and face-on remain separate single-phone modes. Imported video, slow motion, P1–P8 and manual annotation remain secondary tools.
- Use graphite black base, course green brand surface, fluorescent yellow-green only for ready/confirmed/action, and orange only for pause/interruption.
- Practice has one primary control at a time, a minimum 76 pt height, and no paragraph may compete with the central status.
- Drills appear only for evidence-backed findings. A manual P-point lacking its exact usable pose sample must withhold the finding.
- Validate actual SwiftUI runtime screens with `xcrun simctl`; no physical device installation until the user accepts the simulator pass.

## File Structure

- `SwingArc/Design/AnalysisTheme.swift` — Pro Tour colours and surface tokens.
- `SwingArc/Models/PracticeModels.swift` — home hierarchy and short practice state copy.
- `SwingArc/Views/PracticeHomeView.swift` — training-mode entry and secondary tools.
- `SwingArc/Views/PracticeSessionView.swift` — camera-first remote practice surface.
- `SwingArc/Views/WorkspaceComponents.swift` — compact dark evidence feedback.
- `SwingArc/Views/AnalysisWorkspaceView.swift` — evidence-card placement.
- `Tests/ProTourPresentationSmoke.swift` — pure presentation-policy coverage.
- `docs/validation/pro-tour-simulator-review.md` — simulator screenshots and review record.

### Task 1: Add Pro Tour tokens and pure hierarchy policy

**Files:**
- Modify: `SwingArc/Design/AnalysisTheme.swift`
- Modify: `SwingArc/Models/PracticeModels.swift`
- Create: `Tests/ProTourPresentationSmoke.swift`

**Interfaces:**
- Produces `AnalysisTheme.proTourBackground`, `proTourSurface`, `proTourGreen`, `proTourSignal`, `proTourPaused`.
- Produces `PracticeHomeAction` and `PracticeHomePresentation`.

- [ ] **Step 1: Write the failing policy test.**

```swift
precondition(PracticeHomePresentation.modeOrder == [.downTheLine, .faceOn])
precondition(PracticeHomePresentation.secondaryActions == [.importVideo, .history])
precondition(PracticePresentationPolicy.primaryControl(
    for: .waitingForImpact(view: .downTheLine, swingCount: 0)
) == .pause)
```

- [ ] **Step 2: Verify RED.**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/StageCalibration.swift SwingArc/Services/SwingTechniqueEvaluator.swift \
  SwingArc/Models/PracticeModels.swift Tests/ProTourPresentationSmoke.swift \
  -o /tmp/swingarc-pro-tour-presentation && /tmp/swingarc-pro-tour-presentation
```

Expected: compilation fails because the new policy does not yet exist.

- [ ] **Step 3: Implement the minimal policy and named tokens.**

```swift
enum PracticeHomeAction: Equatable { case downTheLine, faceOn, importVideo, history }
enum PracticeHomePresentation {
    static let modeOrder: [PracticeHomeAction] = [.downTheLine, .faceOn]
    static let secondaryActions: [PracticeHomeAction] = [.importVideo, .history]
}
```

Place exact colours in `AnalysisTheme`; views must not embed RGB values.

- [ ] **Step 4: Verify GREEN and simulator build.**

Run the Step 2 command, then:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -jobs 1 -quiet \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=90A656D1-01D1-44FB-B9D2-2FFD811F24C3' build CODE_SIGNING_ALLOWED=NO
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit.**

```bash
git add SwingArc/Design/AnalysisTheme.swift SwingArc/Models/PracticeModels.swift Tests/ProTourPresentationSmoke.swift && git commit -m "feat: add pro tour presentation tokens"
```

### Task 2: Rebuild the home as a training-mode selector

**Files:**
- Modify: `SwingArc/Views/PracticeHomeView.swift`
- Modify: `SwingArc/Views/ContentView.swift`
- Modify: `Tests/ProTourPresentationSmoke.swift`

**Interfaces:**
- Consumes `PracticeHomePresentation`.
- Preserves `onStartPractice`, `onImport` and `onOpenLibrary`.
- Produces training-first navigation in which import/history are available secondary actions.

- [ ] **Step 1: Write the failing order assertion.**

```swift
precondition(PracticeHomePresentation.modeOrder == [.downTheLine, .faceOn])
precondition(PracticeHomePresentation.secondaryActions == [.importVideo, .history])
```

- [ ] **Step 2: Verify RED, then implement the actual composition.**

Run the Task 1 smoke command. Render a dark full-height home, a concise `TRAINING MODE` label, two selectable DTL/Face-on modes, and compact import/history actions below. Remove white card shells, explanatory paragraphs and any history control resembling disabled UI.

- [ ] **Step 3: Build, install, launch and screenshot the actual simulator home.**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -jobs 1 -quiet -derivedDataPath /tmp/SwingArcSimDerivedData \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj -scheme SwingArcProject \
  -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=90A656D1-01D1-44FB-B9D2-2FFD811F24C3' build CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun simctl install 90A656D1-01D1-44FB-B9D2-2FFD811F24C3 /tmp/SwingArcSimDerivedData/Build/Products/Debug-iphonesimulator/SwingArcProject.app
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun simctl launch 90A656D1-01D1-44FB-B9D2-2FFD811F24C3 com.liangbo.swingarc
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun simctl io 90A656D1-01D1-44FB-B9D2-2FFD811F24C3 screenshot /tmp/swingarc-pro-tour-home.png
```

Expected: the screenshot has a dark training-mode home with no generic white-card library layout. Present it to the user before Task 3.

- [ ] **Step 4: Commit the approved home.**

```bash
git add SwingArc/Views/PracticeHomeView.swift SwingArc/Views/ContentView.swift Tests/ProTourPresentationSmoke.swift && git commit -m "feat: redesign pro tour practice home"
```

### Task 3: Rebuild live practice for two-metre readability

**Files:**
- Modify: `SwingArc/Views/PracticeSessionView.swift`
- Modify: `SwingArc/Models/PracticeModels.swift`
- Modify: `Tests/ProTourPresentationSmoke.swift`

**Interfaces:**
- Consumes existing `PracticeSessionState`, `PracticePresentationPolicy` and capture/analysis engine.
- Produces camera-first alignment, ready, waiting, analysing, result and pause states with exactly one main action.

- [ ] **Step 1: Write the failing copy test.**

```swift
precondition(PracticePresentationPolicy.remoteStatus(for: .readyToStart(view: .faceOn)) == "READY")
precondition(PracticePresentationPolicy.remoteStatus(for: .processing(view: .downTheLine, swingCount: 3)) == "ANALYSING · SHOT 03")
```

- [ ] **Step 2: Verify RED, then implement.**

Run the Task 1 smoke command. Use live camera as the dominant surface; header contains only view and exit; centre has large condensed state; result is a short bottom ribbon. Use signal colour only for ready/start and orange only for pause. Keep previous clip secondary and visible only after clip retention.

- [ ] **Step 3: Validate real simulator states.**

Build/install with Task 2 commands, select DTL, then capture `/tmp/swingarc-pro-tour-alignment.png` and `/tmp/swingarc-pro-tour-ready.png`. Expected: alignment has one `我已站好` action, ready has one fluorescent `开始自动练习` action. Do not claim microphone or camera trigger success from simulator.

- [ ] **Step 4: Commit.**

```bash
git add SwingArc/Views/PracticeSessionView.swift SwingArc/Models/PracticeModels.swift Tests/ProTourPresentationSmoke.swift && git commit -m "feat: restyle pro tour practice session"
```

### Task 4: Restyle evidence feedback without weakening truth gates

**Files:**
- Modify: `SwingArc/Views/WorkspaceComponents.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `Tests/TechniqueFeedbackPresentationSmoke.swift`

**Interfaces:**
- Consumes existing `TechniqueFeedbackPresentation` and `TechniqueFeedbackCard`.
- Produces a graphite report card with P-stage evidence chips; unresolved feedback has no drill.

- [ ] **Step 1: Add the failing unresolved assertion.**

```swift
let unresolved = TechniqueFeedbackPresentation.make(feedback: .unresolved, analysis: unresolvedAnalysis)
precondition(unresolved.drill == nil)
precondition(!unresolved.showsEvidence)
```

- [ ] **Step 2: Verify RED, then implement.**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift SwingArc/Services/StageCalibration.swift \
  SwingArc/Models/PracticeModels.swift SwingArc/Services/SwingTechniqueEvaluator.swift Tests/TechniqueFeedbackPresentationSmoke.swift \
  -o /tmp/swingarc-feedback-presentation && /tmp/swingarc-feedback-presentation
```

Use deep graphite surface, restrained green evidence label and compact P chips. Keep card below video and above optional tools; never display pseudo-score or drill for unresolved feedback.

- [ ] **Step 3: Verify GREEN and commit.**

Run the Step 2 test and Task 2 simulator build, then:

```bash
git add SwingArc/Views/WorkspaceComponents.swift SwingArc/Views/AnalysisWorkspaceView.swift Tests/TechniqueFeedbackPresentationSmoke.swift && git commit -m "feat: restyle evidence feedback for pro tour UI"
```

### Task 5: Record simulator-only acceptance before device installation

**Files:**
- Create: `docs/validation/pro-tour-simulator-review.md`
- Modify: `README.md`

**Interfaces:**
- Produces review rows for home, DTL, face-on, import, history, alignment, ready, waiting, pause, result ribbon, previous clip, evidence finding and unresolved evidence.

- [ ] **Step 1: Create the review checklist and record every `/tmp/swingarc-pro-tour-*.png` screenshot path.**

- [ ] **Step 2: Run final build, launch and screenshot.**

Use the exact Task 2 build/install/launch commands and capture `/tmp/swingarc-pro-tour-final.png`. Expected: every command exits 0.

- [ ] **Step 3: Present actual simulator screenshots and obtain user approval.**

Do not install on a physical iPhone until the user explicitly accepts this simulator review.

- [ ] **Step 4: Commit after acceptance.**

```bash
git add docs/validation/pro-tour-simulator-review.md README.md && git commit -m "docs: record pro tour simulator acceptance"
```

## Plan Self-Review

- Spec coverage: Tasks 1–2 enforce brand/hierarchy; Task 3 enforces remote operation; Task 4 preserves evidence-first feedback; Task 5 enforces simulator-before-device acceptance.
- Placeholder scan: no task accepts browser output as proof or defers an interface decision.
- Type consistency: all tasks consume existing `PracticeSessionState`, `PriorityFeedback`, `TechniqueFeedbackPresentation` and `PracticeSessionEngine`; Vision and capture interfaces are unchanged.


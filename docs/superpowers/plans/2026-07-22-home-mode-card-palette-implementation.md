# Home Mode Card Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give all four home-screen mode cards distinct colored surfaces from one SwingArc green-to-teal brand family.

**Architecture:** Add four semantic practice-card surface tokens to `AnalysisTheme`, then pass the appropriate token into the shared `PracticeModeSelector`. Remove the binary `usesBrandSurface` branch so every card follows the same text, signal-accent, border, and interaction rules.

**Tech Stack:** Swift 5, SwiftUI, standalone Swift source smoke tests, Xcode-beta, `xcodebuild`, `devicectl`.

## Global Constraints

- Preserve mode order, titles, detail copy, icons, navigation, sizing, corner radius, accessibility labels, and press behavior.
- Use `practiceDTLSurface = Color(red: 0.12, green: 0.37, blue: 0.27)`.
- Use `practiceFaceOnSurface = Color(red: 0.08, green: 0.32, blue: 0.34)`.
- Use `practiceManualSurface = Color(red: 0.29, green: 0.32, blue: 0.12)`.
- Use `practiceImportSurface = Color(red: 0.12, green: 0.27, blue: 0.34)`.
- Keep every badge, mode icon, arrow, and card border in `AnalysisTheme.proTourSignal`.
- Use `proTourPrimaryText` for titles and `proTourPrimaryText.opacity(0.72)` for eyebrow/detail text on every card.
- Do not modify camera, recording, automatic capture, import, history, persistence, or analysis behavior.
- `SwingArc/Views/PracticeHomeView.swift` already contains user-owned uncommitted feature work. Do not stage or commit that whole file; preserve all pre-existing changes.
- Source is `/Users/liangbo/Documents/SwingArc/SwingArc`; the build project is `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj`.

---

## Planned File Structure

- Modify `Tests/HomeManualStylingSmoke.swift`: lock the four semantic token names and removal of the binary card-surface branch.
- Modify `SwingArc/Design/AnalysisTheme.swift`: own the four reusable practice-card surface colors.
- Modify `SwingArc/Views/PracticeHomeView.swift`: map each mode to a semantic surface and render all cards through one shared style.

---

### Task 1: Lock the Four-Color Contract

**Files:**
- Modify: `Tests/HomeManualStylingSmoke.swift`

**Interfaces:**
- Consumes: source paths for `PracticeHomeView.swift`, `CameraView.swift`, and `AnalysisTheme.swift` as command-line arguments.
- Produces: a smoke executable that fails if any semantic card color or the shared surface API disappears.

- [ ] **Step 1: Extend the smoke test with a theme argument**

After loading `home` and `camera`, add:

```swift
let theme = try String(
    contentsOfFile: CommandLine.arguments[3],
    encoding: .utf8
)

let surfaceTokens = [
    "practiceDTLSurface",
    "practiceFaceOnSurface",
    "practiceManualSurface",
    "practiceImportSurface"
]

for token in surfaceTokens {
    precondition(theme.contains("static let \\(token)"))
    precondition(home.contains("AnalysisTheme.\\(token)"))
}

precondition(home.contains("let surface: Color"))
precondition(home.contains(".background(surface,"))
precondition(!home.contains("usesBrandSurface"))
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
swiftc -parse-as-library Tests/HomeManualStylingSmoke.swift \
  -o /tmp/home-manual-styling-smoke
/tmp/home-manual-styling-smoke \
  SwingArc/Views/PracticeHomeView.swift \
  SwingArc/Views/CameraView.swift \
  SwingArc/Design/AnalysisTheme.swift
```

Expected: nonzero exit because the four semantic tokens do not exist and `PracticeHomeView` still contains `usesBrandSurface`.

- [ ] **Step 3: Keep the failing test uncommitted until Task 2 is green**

Do not stage the test independently; it depends on the production changes in Task 2.

---

### Task 2: Add Semantic Surfaces and Unify Card Rendering

**Files:**
- Modify: `SwingArc/Design/AnalysisTheme.swift`
- Modify: `SwingArc/Views/PracticeHomeView.swift`
- Test: `Tests/HomeManualStylingSmoke.swift`

**Interfaces:**
- Consumes: four `Color` tokens from `AnalysisTheme`.
- Produces: `PracticeModeSelector(surface: Color, action: () -> Void)` with no `usesBrandSurface` branch.

- [ ] **Step 1: Add the four semantic theme tokens**

Insert after `proTourGreen` in `AnalysisTheme.swift`:

```swift
static let practiceDTLSurface = Color(red: 0.12, green: 0.37, blue: 0.27)
static let practiceFaceOnSurface = Color(red: 0.08, green: 0.32, blue: 0.34)
static let practiceManualSurface = Color(red: 0.29, green: 0.32, blue: 0.12)
static let practiceImportSurface = Color(red: 0.12, green: 0.27, blue: 0.34)
```

- [ ] **Step 2: Map every home entry to its semantic surface**

Replace each `usesBrandSurface` argument in `modeSelector(for:)`:

```swift
surface: AnalysisTheme.practiceDTLSurface
surface: AnalysisTheme.practiceFaceOnSurface
surface: AnalysisTheme.practiceManualSurface
surface: AnalysisTheme.practiceImportSurface
```

Use the token matching each card's `01` through `04` index.

- [ ] **Step 3: Replace the binary selector property**

In `PracticeModeSelector`, replace:

```swift
let usesBrandSurface: Bool
```

with:

```swift
let surface: Color
```

- [ ] **Step 4: Apply one text and surface treatment to all four cards**

Use these exact modifiers:

```swift
.foregroundStyle(AnalysisTheme.proTourPrimaryText.opacity(0.72))
```

for both eyebrow and detail text, then replace the background and border with:

```swift
.background(
    surface,
    in: RoundedRectangle(cornerRadius: 26, style: .continuous)
)
.overlay(
    RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(modeAccent.opacity(0.32), lineWidth: 1)
)
```

Keep `modeAccent` unchanged as `AnalysisTheme.proTourSignal`.

- [ ] **Step 5: Run the focused smoke test to verify GREEN**

Run:

```bash
swiftc -parse-as-library Tests/HomeManualStylingSmoke.swift \
  -o /tmp/home-manual-styling-smoke
/tmp/home-manual-styling-smoke \
  SwingArc/Views/PracticeHomeView.swift \
  SwingArc/Views/CameraView.swift \
  SwingArc/Design/AnalysisTheme.swift
```

Expected: exit 0.

- [ ] **Step 6: Run the existing manual-recording regression**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
  -parse-as-library \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/SwingTechniqueEvaluator.swift \
  SwingArc/Models/PracticeModels.swift \
  Tests/ManualCaptureTimingSmoke.swift \
  -o /tmp/manual-capture-smoke
/tmp/manual-capture-smoke SwingArc/Views/CameraView.swift
```

Expected: exit 0; the 15-second manual capture limit remains intact.

- [ ] **Step 7: Preserve the existing dirty working tree**

Run:

```bash
git diff --check -- \
  SwingArc/Design/AnalysisTheme.swift \
  SwingArc/Views/PracticeHomeView.swift \
  Tests/HomeManualStylingSmoke.swift
git status --short
```

Expected: no whitespace errors. Do not stage `PracticeHomeView.swift` as a whole because its diff includes pre-existing user work; leave the three implementation files together in the current working tree.

---

### Task 3: Simulator and Wireless iPhone Verification

**Files:**
- Modify only if visual verification reveals a contrast or clipping defect.

**Interfaces:**
- Consumes: the four-color SwiftUI implementation from Task 2.
- Produces: successful simulator/device builds, a refreshed installed app, and a physical home-screen screenshot.

- [ ] **Step 1: Build the simulator target**

Run:

```bash
xcodebuild \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Build the connected iPhone target**

Run:

```bash
xcodebuild \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -configuration Debug \
  -destination 'id=00008140-001C20102493C01C' \
  -derivedDataPath /tmp/SwingArcPaletteDerived \
  build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Install and launch the refreshed app**

Run:

```bash
xcrun devicectl device install app \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 \
  /tmp/SwingArcPaletteDerived/Build/Products/Debug-iphoneos/SwingArcProject.app

xcrun devicectl device process launch \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 \
  --terminate-existing \
  --activate \
  com.liangbo.swingarc
```

Expected: installation reports bundle ID `com.liangbo.swingarc`; launch succeeds.

- [ ] **Step 4: Capture and inspect the physical home screen**

Run:

```bash
xcrun devicectl device capture screenshot \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 \
  --destination /tmp/swingarc-device-home-four-color.png
```

Verify all of the following:

- `01` is forest green, `02` is teal green, `03` is olive green, and `04` is blue green.
- All four surfaces are visibly colored rather than charcoal.
- White titles/details and lime badges/icons/arrows remain readable.
- No text or card edge clips at the physical phone width.
- The app remains on the normal home screen after verification.

- [ ] **Step 5: Run final repository safety checks**

Run:

```bash
git diff --check
git status --short
git log --oneline -5
```

Expected: no whitespace errors; all unrelated pre-existing changes remain present and unstaged.

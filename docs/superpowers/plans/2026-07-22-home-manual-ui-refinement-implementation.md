# Home and Manual Capture UI Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Center the manual-recording primary action, strengthen the history entry, and restore a consistent SwingArc signal-color rhythm across mode cards.

**Architecture:** Keep the existing SwiftUI navigation and capture behavior intact. Refine only presentation in `PracticeHomeView` and the top-level `CameraView`, with a source-level smoke test that locks the approved hierarchy before simulator and physical-device screenshot verification.

**Tech Stack:** Swift 5, SwiftUI, standalone Swift source smoke tests, Xcode-beta, `xcodebuild`, `devicectl`.

## Global Constraints

- Keep card order and behavior unchanged: DTL, FACE-ON, manual capture, import.
- Keep DTL as the only fully deep-green hero card.
- Use `AnalysisTheme.proTourSignal` for every `01`–`04` badge, mode icon, and northeast arrow.
- The history icon uses `proTourSignal`; its text uses `proTourPrimaryText`; its surface remains dark with a 25%-opacity signal border.
- Manual capture remains immediate, stops on the second tap, and retains the 15-second maximum.
- Do not change camera, persistence, automatic capture, import, history, or analysis behavior.
- Preserve existing accessibility labels and keep all affected touch targets at least 48 points high.
- Source is `/Users/liangbo/Documents/SwingArc/SwingArc`; the buildable project is `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj`.

---

## Planned File Structure

- Create `Tests/HomeManualStylingSmoke.swift`: verifies the approved SwiftUI vocabulary without launching camera hardware.
- Modify `SwingArc/Views/PracticeHomeView.swift`: history capsule and the shared four-card visual language.
- Modify `SwingArc/Views/CameraView.swift`: centered manual record/stop primary action.
- Modify no model, service, capture, persistence, or navigation file.

---

### Task 1: Lock the Approved Visual Contract

**Files:**
- Create: `Tests/HomeManualStylingSmoke.swift`

**Interfaces:**
- Consumes: source paths for `PracticeHomeView.swift` and `CameraView.swift` from command-line arguments.
- Produces: one standalone executable that exits nonzero when the approved styling contract is missing.

- [ ] **Step 1: Write the failing source smoke test**

```swift
import Foundation

@main
struct HomeManualStylingSmoke {
    static func main() throws {
        let home = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let camera = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)

        precondition(home.contains(".font(.system(size: 14, weight: .bold, design: .monospaced))"))
        precondition(home.contains("AnalysisTheme.proTourSignal.opacity(0.25)"))
        precondition(home.contains(".frame(minHeight: 48)"))
        precondition(home.contains(".frame(width: 38, height: 38)"))
        precondition(home.contains("RoundedRectangle(cornerRadius: 12"))
        precondition(home.contains("modeAccent"))

        guard let controlStart = camera.range(of: "private var captureControl") else {
            preconditionFailure("Manual capture control missing")
        }
        let control = camera[controlStart.lowerBound...]
        precondition(control.contains("VStack(spacing: 4)"))
        precondition(control.contains(".multilineTextAlignment(.center)"))
        precondition(!control.prefix(1_800).contains("Spacer()"))
    }
}
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
swiftc -parse-as-library Tests/HomeManualStylingSmoke.swift -o /tmp/home-manual-styling-smoke
/tmp/home-manual-styling-smoke SwingArc/Views/PracticeHomeView.swift SwingArc/Views/CameraView.swift
```

Expected: the executable fails because the current history label is 11 points, indexes have no 38-point badge, and the manual button still contains a trailing `Spacer`.

- [ ] **Step 3: Keep the test uncommitted until Tasks 2 and 3 are green**

No production code changes belong to this task. The test is committed with the implementation it verifies.

---

### Task 2: Restore the Home Screen Brand Rhythm

**Files:**
- Modify: `SwingArc/Views/PracticeHomeView.swift`
- Test: `Tests/HomeManualStylingSmoke.swift`

**Interfaces:**
- Consumes: `AnalysisTheme.proTourSignal`, `proTourPrimaryText`, `proTourSecondaryText`, `proTourSurface`, `proTourGreen`, and `proTourRaisedSurface`.
- Produces: the unchanged `PracticeHomeView` callback interface and a shared `PracticeModeSelector` visual treatment.

- [ ] **Step 1: Enlarge and recolor the history capsule**

Replace the existing history label styling with:

```swift
HStack(spacing: 8) {
    Image(systemName: "clock.arrow.circlepath")
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(AnalysisTheme.proTourSignal)
    Text("记录")
        .font(.system(size: 14, weight: .bold, design: .monospaced))
        .tracking(0.5)
        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
}
.padding(.horizontal, 14)
.frame(minHeight: 48)
.background(AnalysisTheme.proTourSurface, in: Capsule())
.overlay(
    Capsule().stroke(
        AnalysisTheme.proTourSignal.opacity(0.25),
        lineWidth: 1
    )
)
```

Keep `.accessibilityLabel("打开挥杆记录")` unchanged.

- [ ] **Step 2: Convert every mode index into the same signal badge**

Inside `PracticeModeSelector`, replace the index styling with:

```swift
Text(index)
    .font(.system(size: 13, weight: .black, design: .monospaced))
    .foregroundStyle(AnalysisTheme.proTourBackground)
    .frame(width: 38, height: 38)
    .background(
        AnalysisTheme.proTourSignal,
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
```

The badge must be identical for `01`, `02`, `03`, and `04`.

- [ ] **Step 3: Give all mode glyphs one branded accent**

Add this local property to `PracticeModeSelector`:

```swift
private var modeAccent: Color {
    AnalysisTheme.proTourSignal
}
```

Apply `modeAccent` to both the mode icon and northeast arrow. Keep the DTL background green; keep other backgrounds on `proTourSurface`. Use one low-opacity brand border family:

```swift
.overlay(
    RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(
            modeAccent.opacity(usesBrandSurface ? 0.42 : 0.18),
            lineWidth: 1
        )
)
```

- [ ] **Step 4: Run the smoke test and verify the home assertions are green**

Run:

```bash
swiftc -parse-as-library Tests/HomeManualStylingSmoke.swift -o /tmp/home-manual-styling-smoke
/tmp/home-manual-styling-smoke SwingArc/Views/PracticeHomeView.swift SwingArc/Views/CameraView.swift
```

Expected: the test still fails only on the manual capture control assertions.

---

### Task 3: Center the Manual Capture Primary Action

**Files:**
- Modify: `SwingArc/Views/CameraView.swift`
- Test: `Tests/HomeManualStylingSmoke.swift`

**Interfaces:**
- Consumes: existing `isRecording`, `startRecording()`, `stopRecording()`, `ManualCapturePresentation`, and theme tokens.
- Produces: the same button actions and recording timing with centered presentation.

- [ ] **Step 1: Replace the left-aligned button label**

Use a centered stack without a trailing spacer:

```swift
VStack(spacing: 4) {
    Label(
        isRecording ? "结束录制" : "开始录像",
        systemImage: isRecording ? "stop.fill" : "record.circle"
    )
    .font(.system(size: 20, weight: .black, design: .rounded))

    Text(isRecording ? "保存当前挥杆影片" : "点击立即录制")
        .font(.system(size: 13, weight: .bold))
        .opacity(0.68)
}
.multilineTextAlignment(.center)
.frame(maxWidth: .infinity, minHeight: 84)
```

Keep the existing foreground and background state colors, corner radius, button action, and `.buttonStyle(.plain)`.

- [ ] **Step 2: Run the source smoke and verify GREEN**

Run:

```bash
swiftc -parse-as-library Tests/HomeManualStylingSmoke.swift -o /tmp/home-manual-styling-smoke
/tmp/home-manual-styling-smoke SwingArc/Views/PracticeHomeView.swift SwingArc/Views/CameraView.swift
```

Expected: exit 0.

- [ ] **Step 3: Run existing presentation and timing regressions**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Services/SwingStageDetector.swift SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/SwingTechniqueEvaluator.swift SwingArc/Models/PracticeModels.swift \
  Tests/ManualCaptureTimingSmoke.swift -o /tmp/manual-capture-smoke
/tmp/manual-capture-smoke SwingArc/Views/CameraView.swift
```

Expected: exit 0, proving no countdown returned and the 15-second cap remains.

- [ ] **Step 4: Commit only the focused UI files and test**

Because both production files already contain user-owned uncommitted work, inspect and stage only the exact styling hunks:

```bash
git add Tests/HomeManualStylingSmoke.swift
git add -p SwingArc/Views/PracticeHomeView.swift SwingArc/Views/CameraView.swift
git diff --cached --check
git commit -m "fix: restore branded practice action hierarchy"
```

---

### Task 4: Build and Physical-Device Verification

**Files:**
- Modify only if the screenshots reveal clipping or alignment defects.

**Interfaces:**
- Consumes: the completed SwiftUI styling changes.
- Produces: simulator and signed iPhone builds plus physical screenshots of home and manual capture.

- [ ] **Step 1: Build the simulator app**

Run:

```bash
xcodebuild \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject -sdk iphonesimulator -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Capture simulator previews**

Launch the normal home screen and `-swingarc-preview-manual-capture`. Verify:

- the history entry is readable and remains secondary;
- every index, icon, and arrow uses the signal color;
- the manual recording button is optically centered;
- no text clips at the iPhone simulator width.

- [ ] **Step 3: Build and install the signed physical app**

Run:

```bash
xcodebuild \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject -configuration Debug \
  -destination 'id=00008140-001C20102493C01C' \
  -derivedDataPath /tmp/SwingArcVisualDerived build

xcrun devicectl device install app \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 \
  /tmp/SwingArcVisualDerived/Build/Products/Debug-iphoneos/SwingArcProject.app
```

Expected: signed build succeeds and `App installed` reports `com.liangbo.swingarc`.

- [ ] **Step 4: Launch and capture physical screenshots**

Launch the home screen, then the manual preview. Save screenshots with `devicectl device capture screenshot` and visually compare them against the approved design. Leave the final installed app on the home screen.

- [ ] **Step 5: Run the final repository safety check**

Run:

```bash
git diff --check
git status --short
git log --oneline -5
```

Expected: no whitespace errors; unrelated pre-existing user changes remain preserved.

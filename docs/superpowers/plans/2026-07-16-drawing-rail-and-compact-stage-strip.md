# Drawing Rail and Compact P1–P8 Stage Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the drawing rail unambiguous, add a contextual color palette and arrow annotations, and replace the compact-width two-row P1–P8 cards with a single always-visible eight-stage strip.

**Architecture:** Add small pure policies to `WorkspaceModels.swift` so destructive drawing intent, stage indicator mapping and size constraints can be smoke-tested without SwiftUI. `DrawingToolRail` remains a 56pt right-edge overlay but separates scope, undo and clear semantics. `StageTimelineView` becomes one equal-width `HStack` shared by iPhone and iPad, while the existing result inspector retains detailed names, times and statuses.

**Tech Stack:** Swift 5, SwiftUI, AVFoundation, iOS 17+, repository smoke executables, Xcode 27 beta build harness.

## Global Constraints

- The drawing rail remains inside the video’s right edge, 10pt from the edge, vertically centered, with maximum width 56pt.
- The P1–P8 strip shows all eight stages simultaneously on iPhone and iPad; it never scrolls and never returns to two rows.
- Stage buttons are 44pt high and the time slider plus stage strip targets a total height of 72–80pt.
- Clearing all drawings requires a long press on undo followed by explicit confirmation.
- Selecting line or arrow opens a five-color palette to the left of the 56pt rail; other drawing tools reuse the last color without opening it.
- This work changes presentation and interaction only; it does not alter P1–P8 detection data or claim the parked two-stage detector is implemented.
- The final source commit includes the previously dirty P1–P8 detector/debug changes together with the Studio Focus UI implementation, as the user requested.

---

### Task 1: Add Testable Drawing and Stage-Strip Policies

**Files:**
- Modify: `SwingArc/Models/WorkspaceModels.swift`
- Modify: `Tests/WorkspaceModelsSmoke.swift`

**Interfaces:**
- Produces: `DrawingUndoIntent`, `DrawingRailPolicy.undoIntent(isLongPress:)`, `StageStripIndicator`, and `StageStripPolicy`.
- Consumed by: `DrawingUndoControl` and `StageTimelineView` in Task 2 and Task 3.

- [ ] **Step 1: Write the failing policy assertions**

Add to `WorkspaceModelsSmoke.main()`:

```swift
precondition(DrawingRailPolicy.undoIntent(isLongPress: false) == .undoLast)
precondition(DrawingRailPolicy.undoIntent(isLongPress: true) == .confirmClearAll)

precondition(StageStripPolicy.buttonHeight == 44)
precondition(StageStripPolicy.maximumTotalHeight == 80)
precondition(StageStripPolicy.indicator(for: .confirmed) == .filledCircle)
precondition(StageStripPolicy.indicator(for: .review) == .filledCircle)
precondition(StageStripPolicy.indicator(for: .unresolved) == .hollowCircle)
precondition(StageStripPolicy.indicator(for: .manual) == .lock)
```

- [ ] **Step 2: Run the policy smoke test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/WorkspaceModels.swift Tests/WorkspaceModelsSmoke.swift \
  -o /tmp/workspace-models-red
```

Expected: compilation fails because `DrawingRailPolicy` and `StageStripPolicy` do not exist.

- [ ] **Step 3: Implement the minimal pure policies**

Add to `WorkspaceModels.swift`:

```swift
enum DrawingUndoIntent: Equatable {
    case undoLast
    case confirmClearAll
}

enum DrawingRailPolicy {
    static func undoIntent(isLongPress: Bool) -> DrawingUndoIntent {
        isLongPress ? .confirmClearAll : .undoLast
    }
}

enum StageStripIndicator: String, Equatable {
    case filledCircle = "circle.fill"
    case hollowCircle = "circle"
    case lock = "lock.fill"
}

enum StageStripPolicy {
    static let buttonHeight: CGFloat = 44
    static let maximumTotalHeight: CGFloat = 80

    static func indicator(for state: StageResultState) -> StageStripIndicator {
        switch state {
        case .confirmed, .review: return .filledCircle
        case .unresolved: return .hollowCircle
        case .manual: return .lock
        }
    }
}
```

- [ ] **Step 4: Run the policy smoke test and verify GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/WorkspaceModels.swift Tests/WorkspaceModelsSmoke.swift \
  -o /tmp/workspace-models && /tmp/workspace-models
```

Expected: exit 0 with no output.

---

### Task 2: Separate Drawing Rail Actions

**Files:**
- Modify: `SwingArc/Models/DrawingModels.swift`
- Modify: `SwingArc/Views/WorkspaceComponents.swift`

**Interfaces:**
- Consumes: `DrawingRailPolicy.undoIntent(isLongPress:)` from Task 1.
- Produces: visible selection and single-line icons, direct scope toggle, tap-to-undo, and long-press-to-confirm-clear behavior.

- [ ] **Step 1: Make tool symbols explicit and platform-safe**

Set the relevant `DrawingTool.iconName` cases to:

```swift
case .select: return "hand.tap"
case .line: return "minus"
```

The selection symbol must remain visible on iOS 17 and the line symbol must render exactly one line.

- [ ] **Step 2: Replace the scope menu with a direct toggle**

Replace the existing range `Menu` in `DrawingToolRail` with:

```swift
Button {
    isKeyframeMode.toggle()
} label: {
    Image(systemName: isKeyframeMode ? "pin.fill" : "rectangle.inset.filled")
        .frame(width: 44, height: 44)
        .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 11))
}
.foregroundStyle(.white)
.accessibilityLabel(isKeyframeMode ? "仅当前 P 点显示" : "全视频显示")
.accessibilityHint(isKeyframeMode ? "切换为全视频显示" : "切换为仅当前 P 点显示")
```

Remove “清除所有标注” from this control entirely.

- [ ] **Step 3: Add an exclusive undo/clear control**

Replace the generic undo rail button with a private `DrawingUndoControl` that distinguishes tap from long press:

```swift
private struct DrawingUndoControl: View {
    let onUndo: () -> Void
    let onRequestClear: () -> Void

    var body: some View {
        Image(systemName: "arrow.uturn.backward")
            .frame(width: 44, height: 44)
            .foregroundStyle(.white)
            .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.6)
                    .exclusively(before: TapGesture())
                    .onEnded { value in
                        switch value {
                        case .first(true):
                            if DrawingRailPolicy.undoIntent(isLongPress: true) == .confirmClearAll {
                                onRequestClear()
                            }
                        case .second:
                            if DrawingRailPolicy.undoIntent(isLongPress: false) == .undoLast {
                                onUndo()
                            }
                        default:
                            break
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("撤销")
            .accessibilityHint("轻点撤销最后一笔，长按清除全部标注")
            .accessibilityAction(onUndo)
            .accessibilityAction(named: "清除全部标注", onRequestClear)
    }
}
```

Keep the existing destructive confirmation dialog. `onRequestClear` only opens it; `onClear` runs only from the confirmed destructive button.

- [ ] **Step 4: Verify the drawing rail implementation structurally**

Run:

```bash
rg -n 'hand.tap|case \.line: return "minus"|LongPressGesture|清除全部标注|isKeyframeMode.toggle' \
  SwingArc/Models/DrawingModels.swift SwingArc/Views/WorkspaceComponents.swift
```

Expected: the select and line symbols, exclusive long press, confirmation copy and direct scope toggle are present; the range control contains no destructive menu item.

---

### Task 2B: Add Arrow Drawing and the Contextual Color Palette

**Files:**
- Modify: `SwingArc/Models/DrawingModels.swift`
- Modify: `SwingArc/Views/DrawingOverlay.swift`
- Modify: `SwingArc/Services/MediaExportService.swift`
- Modify: `SwingArc/Views/WorkspaceComponents.swift`
- Modify: `Tests/DrawingDisplayPolicySmoke.swift`

**Interfaces:**
- Produces: `DrawingTool.arrow`, `DrawingTool.revealsColorPalette`, and `ArrowGeometry.headPoints(start:end:length:spread:)`.
- Preserves: normalized drawing coordinates, selection handles, project Codable storage and annotated export.

- [ ] **Step 1: Add failing arrow and palette assertions**

Assert that line and arrow reveal the palette, circle does not, and a horizontal arrow produces two head points behind its end. Compile `DrawingModels.swift` with `DrawingDisplayPolicySmoke.swift`; expected result before implementation is failure because `.arrow`, `revealsColorPalette` and `ArrowGeometry` are missing.

- [ ] **Step 2: Implement the arrow model and geometry**

Add `.arrow = "箭头"`, use `arrow.up.right`, and return `true` from `revealsColorPalette` only for line and arrow. `ArrowGeometry.headPoints` computes the two arrowhead endpoints from `atan2`, `cos` and `sin`, returning `nil` for a zero-length segment.

- [ ] **Step 3: Render, edit, persist and export arrows**

Treat arrow drag points like line points. Draw a shaft plus two 14pt arrowhead segments in the normal canvas, magnifier and export path. Selection continues to expose both stored endpoints; Codable persistence continues through `DrawingElement.tool`.

- [ ] **Step 4: Add the anchored five-color palette**

Place red, yellow, green, blue and white buttons in an overlay offset 52pt left of the active line or arrow button. Selecting a color updates `selectedColor` and closes the palette. Selecting any other tool, toggling scope or tapping the top `xmark` closes it. Replace the bottom green completion button with the top `xmark`.

- [ ] **Step 5: Verify arrow policy and full iOS type checking**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift Tests/DrawingDisplayPolicySmoke.swift \
  -o /tmp/drawing-arrow && /tmp/drawing-arrow

SDK=$(DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun --sdk iphonesimulator --show-sdk-path)
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
  -target arm64-apple-ios27.0-simulator -sdk "$SDK" -typecheck \
  SwingArc/Models/*.swift SwingArc/Services/*.swift SwingArc/Views/*.swift \
  SwingArc/Design/*.swift SwingArc/SwingArcApp.swift
```

Expected: both commands exit 0; existing SDK deprecation warnings are allowed.

---

### Task 3: Replace the Two-Row P1–P8 Grid with One Stage Strip

**Files:**
- Modify: `SwingArc/Views/WorkspaceComponents.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `docs/superpowers/plans/2026-07-16-studio-focus-universal-ui.md`

**Interfaces:**
- Consumes: `StageStripPolicy.buttonHeight`, `StageStripPolicy.maximumTotalHeight`, and `StageStripPolicy.indicator(for:)` from Task 1.
- Preserves: `onStageTap(SwingStage, KeyframeMarker?)`, existing seek behavior, and inline manual adjustment for unresolved stages.
- Removes: compact/regular grid-column branching from `StageTimelineView`.

- [ ] **Step 1: Replace `LazyVGrid` with an eight-item `HStack`**

Render all `SwingStage.allCases` in one equal-width row:

```swift
HStack(spacing: 3) {
    ForEach(SwingStage.allCases) { stage in
        let descriptor = StageDisplayDescriptor(
            stage: stage,
            keyframes: keyframes,
            presentation: presentation,
            currentTime: playbackManager.currentTime,
            frameDuration: VideoFramePolicy.frameDuration(
                sourceFrameRate: playbackManager.sourceFrameRate
            )
        )

        Button {
            onStageTap(stage, descriptor.marker)
        } label: {
            VStack(spacing: 3) {
                Text(stage.pNumber)
                    .font(.caption2.weight(.bold))
                Image(systemName: StageStripPolicy.indicator(for: descriptor.resultState).rawValue)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(descriptor.stageStripColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: StageStripPolicy.buttonHeight)
            .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                if descriptor.isCurrent {
                    Capsule()
                        .fill(AnalysisTheme.current)
                        .frame(height: 3)
                        .padding(.horizontal, 5)
                        .padding(.bottom, 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(descriptor.accessibilityLabel)
    }
}
```

- [ ] **Step 2: Map status colors without replacing the status symbol**

Add to `StageDisplayDescriptor`:

```swift
var stageStripColor: Color {
    switch resultState {
    case .confirmed, .manual: return AnalysisTheme.confirmed
    case .review: return AnalysisTheme.current
    case .unresolved: return .white.opacity(0.42)
    }
}
```

The current stage uses only the yellow underline. It must not overwrite a confirmed, review, unresolved or manual status symbol.

- [ ] **Step 3: Enforce the compact height and shared iPhone/iPad layout**

Set `StageTimelineView` to `VStack(spacing: 6)` with `.padding(.vertical, 6)`, remove its `isRegularLayout` property, and remove that argument at the `AnalysisWorkspaceView` call site. Apply:

```swift
.frame(maxHeight: StageStripPolicy.maximumTotalHeight)
```

Update the older Studio Focus implementation plan so every “2x4/1x8” reference says “single-row 1x8 stage strip”; the latest approved spec must not conflict with the plan committed alongside the code.

- [ ] **Step 4: Run relevant smoke and complete-source checks**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
  SwingArc/Models/WorkspaceModels.swift Tests/WorkspaceModelsSmoke.swift \
  -o /tmp/workspace-models && /tmp/workspace-models

SDK=$(DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun --sdk iphonesimulator --show-sdk-path)
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
  -target arm64-apple-ios27.0-simulator -sdk "$SDK" -typecheck \
  SwingArc/Models/*.swift SwingArc/Services/*.swift SwingArc/Views/*.swift \
  SwingArc/Design/*.swift SwingArc/SwingArcApp.swift
```

Expected: both commands exit 0. Existing AVFoundation deprecation warnings are allowed; new errors are not.

---

### Task 4: Build, Install, Visually Verify and Commit the Complete Scope

**Files:**
- Build harness outside repository: `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj`
- Include in final source commit: `SwingArc/`, `Tests/`, `README.md`, and both implementation plans.

**Interfaces:**
- The external Xcode project is used for build/install only and is not committed in this repository.
- The final commit includes `SwingStageDetector.swift` and `CustomVideoPlayer.swift` P1–P8/debug changes together with the Studio Focus UI implementation.

- [ ] **Step 1: Run the full repository smoke suite**

Run each executable with its exact dependencies:

```bash
set -e
run_smoke() {
  local name="$1"
  shift
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
    -parse-as-library "$@" -o "/tmp/swingarc-$name"
  "/tmp/swingarc-$name"
}

run_smoke analysis-session SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/AnalysisSessionStateSmoke.swift
run_smoke theme SwingArc/Design/AnalysisTheme.swift Tests/AnalysisThemeSmoke.swift
run_smoke presentation SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/AnalysisWorkspacePresentationSmoke.swift
run_smoke drawing-policy SwingArc/Models/DrawingModels.swift Tests/DrawingDisplayPolicySmoke.swift
run_smoke manual-lock SwingArc/Models/DrawingModels.swift Tests/ManualStageLockSmoke.swift
run_smoke media-export SwingArc/Models/DrawingModels.swift SwingArc/Services/MediaExportService.swift Tests/MediaExportFormatSmoke.swift
run_smoke multijoint-detector SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/MultiJointStageDetectorSmoke.swift
run_smoke multijoint-model SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/MultiJointStageModelSmoke.swift
run_smoke pose-sample SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift SwingArc/Services/VisionPoseDetector.swift Tests/PoseSampleFactorySmoke.swift
run_smoke project-library SwingArc/Models/DrawingModels.swift SwingArc/Models/WorkspaceModels.swift SwingArc/Services/LocalProjectStore.swift Tests/ProjectLibraryStoreSmoke.swift
run_smoke project-persistence SwingArc/Models/DrawingModels.swift SwingArc/Models/WorkspaceModels.swift SwingArc/Services/LocalProjectStore.swift Tests/ProjectPersistenceSmoke.swift
run_smoke sampling SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/SwingAnalysisSamplingPlanSmoke.swift
run_smoke phase SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/SwingPhaseTransitionSmoke.swift
run_smoke stage-detector SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/SwingStageDetectorSmoke.swift
run_smoke video-zoom SwingArc/Models/DrawingModels.swift Tests/VideoZoomPolicySmoke.swift
run_smoke workspace-models SwingArc/Models/WorkspaceModels.swift Tests/WorkspaceModelsSmoke.swift
```

Required result: all 16 commands exit 0; no failure is ignored.

- [ ] **Step 2: Build for simulator and physical iPhone**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -quiet \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/SwingArcStudioFocusFinalSim build

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -quiet \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -destination 'id=ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3' \
  -derivedDataPath /tmp/SwingArcStudioFocusFinalDevice \
  -allowProvisioningUpdates build
```

Expected: both builds end with exit 0.

- [ ] **Step 3: Install, launch and visually inspect the iPhone build**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun devicectl device install app \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 \
  /tmp/SwingArcStudioFocusFinalDevice/Build/Products/Debug-iphoneos/SwingArcProject.app

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun devicectl device process launch \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 --terminate-existing \
  com.liangbo.swingarc
```

Verify on the connected mirror or a device screenshot: the rail is 56pt wide, selection and single-line symbols are visible, the scope button toggles directly, long-press undo asks before clearing, P1–P8 occupy one row, and manual adjustment remains inline rather than covering the video.

- [ ] **Step 4: Verify Git scope and make the requested combined source commit**

Run:

```bash
git diff --check
git status --short
git add README.md SwingArc Tests \
  docs/superpowers/plans/2026-07-16-studio-focus-universal-ui.md \
  docs/superpowers/plans/2026-07-16-drawing-rail-and-compact-stage-strip.md
git diff --cached --check
git commit -m "feat: implement Studio Focus universal workspace"
```

Confirm the repository is clean after the commit. Do not push unless the user separately requests it.

## Self-review

- Spec coverage: Task 2 covers drawing-rail action separation; Task 2B covers the contextual palette and arrow; Task 3 covers every single-row stage-strip requirement; Task 4 covers real builds, installation and the requested combined commit.
- Placeholder scan: every code-editing step contains concrete code or an exact command; no unfinished marker remains.
- Type consistency: `DrawingRailPolicy`, `StageStripPolicy`, `StageStripIndicator`, `DrawingUndoControl` and `stageStripColor` use the same names from tests through SwiftUI consumers.
- Scope consistency: the design-document commits remain separate, while the final source commit deliberately combines UI implementation with the already dirty P1–P8 debug changes, matching the user’s instruction.

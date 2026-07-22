# Home Single-Screen Visual Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the colorful four-card home screen with a restrained opacity hierarchy, a compact capsule-free history entry, and a portrait layout that never scrolls on supported iPhones.

**Architecture:** Keep the existing home actions and shared card component. Pass a `surfaceOpacity` plus height-dependent `PracticeHomeMetrics` into each card, use `GeometryReader` to select regular/compact/tight metrics, and remove `ScrollView` so the safe-area content is a single fixed page.

**Tech Stack:** Swift 5, SwiftUI, standalone Swift source smoke tests, Xcode-beta, `xcodebuild`, `simctl`, `devicectl`.

## Global Constraints

- Preserve mode order, titles, details, icons, callbacks, navigation, accessibility labels, corner radii, and press behavior.
- Use `AnalysisTheme.proTourSurface` for every card with opacities `0.85`, `0.70`, `0.55`, and `0.40` for modes 01 through 04.
- Opacity applies only to the surface; card content and hit targets remain fully opaque.
- Use `proTourPrimaryText` for card titles, `proTourSecondaryText` for eyebrow/detail text, and `proTourSignal.opacity(0.14)` for every card border.
- Keep badges, mode icons, and arrows in `proTourSignal`.
- Remove the history capsule, background, and border. Use a 14-point signal icon and 13-point primary-text label with visible content no taller than the wordmark and an invisible 44-point touch target.
- Remove `ScrollView`; the page must have no vertical scrolling or bounce space.
- Choose regular metrics at heights `>= 820`, compact metrics at `700...819`, and tight metrics below `700`.
- Use card heights `126`, `108`, and `92`; gaps `12`, `10`, and `8`; main title sizes `38`, `34`, and `30` for regular, compact, and tight tiers.
- Use card title/detail sizes `24/14`, `22/13`, and `20/12` for regular, compact, and tight tiers.
- Keep horizontal padding at 20 points, respect safe areas, and do not use `scaleEffect` to fit the page.
- Do not modify camera, recording, automatic capture, import behavior, history data, persistence, analysis, or other screens.
- `SwingArc/Views/PracticeHomeView.swift` contains user-owned uncommitted feature work. Do not stage or commit the whole file; preserve all pre-existing changes.
- Source is `/Users/liangbo/Documents/SwingArc/SwingArc`; the build project is `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj`.

---

## Planned File Structure

- Modify `Tests/HomeManualStylingSmoke.swift`: replace the superseded four-color assertions with the final opacity, history, and no-scroll adaptive-layout contract.
- Modify `SwingArc/Design/AnalysisTheme.swift`: remove the four temporary `practice*Surface` tokens; no new global theme token is needed.
- Modify `SwingArc/Views/PracticeHomeView.swift`: render the history entry without a capsule, pass mode opacities, define local layout metrics, and replace `ScrollView` with a fixed `GeometryReader` layout.

---

### Task 1: Lock the Final Home Contract

**Files:**
- Modify: `Tests/HomeManualStylingSmoke.swift`

**Interfaces:**
- Consumes: source paths for `PracticeHomeView.swift`, `CameraView.swift`, and `AnalysisTheme.swift` as command-line arguments.
- Produces: a smoke executable that fails if colorful surfaces, the history capsule, `ScrollView`, or adaptive metrics regress.

- [ ] **Step 1: Replace the superseded card-surface assertions**

Keep the existing `home`, `camera`, and `theme` loads. Replace the `surfaceTokens` loop plus the `let surface: Color` assertions with:

```swift
let opacityArguments = [
    "surfaceOpacity: 0.85",
    "surfaceOpacity: 0.70",
    "surfaceOpacity: 0.55",
    "surfaceOpacity: 0.40"
]

for argument in opacityArguments {
    precondition(home.contains(argument))
}

precondition(home.contains("let surfaceOpacity: Double"))
precondition(
    home.contains(
        "AnalysisTheme.proTourSurface.opacity(surfaceOpacity)"
    )
)
precondition(home.contains("modeAccent.opacity(0.14)"))
precondition(!home.contains("usesBrandSurface"))

let removedSurfaceTokens = [
    "practiceDTLSurface",
    "practiceFaceOnSurface",
    "practiceManualSurface",
    "practiceImportSurface"
]

for token in removedSurfaceTokens {
    precondition(!theme.contains(token))
    precondition(!home.contains(token))
}
```

- [ ] **Step 2: Replace the old history-capsule assertions**

Remove assertions for the 14-point history text, 48-point visible height, and 25%-signal capsule stroke. Add:

```swift
precondition(
    home.contains(
        ".font(.system(size: 13, weight: .bold, design: .monospaced))"
    )
)
precondition(home.contains(".font(.system(size: 14, weight: .bold))"))
precondition(home.contains(".frame(minWidth: 44, minHeight: 44)"))
precondition(!home.contains("Capsule()"))
```

- [ ] **Step 3: Add the adaptive single-screen assertions**

Add:

```swift
precondition(home.contains("GeometryReader"))
precondition(!home.contains("ScrollView"))
precondition(home.contains("private struct PracticeHomeMetrics"))
precondition(home.contains("if height >= 820"))
precondition(home.contains("if height >= 700"))
precondition(home.contains("cardHeight = 126"))
precondition(home.contains("cardHeight = 108"))
precondition(home.contains("cardHeight = 92"))
precondition(home.contains("cardSpacing = 12"))
precondition(home.contains("cardSpacing = 10"))
precondition(home.contains("cardSpacing = 8"))
```

- [ ] **Step 4: Run the smoke test to verify RED**

Run:

```bash
swiftc -parse-as-library Tests/HomeManualStylingSmoke.swift \
  -o /tmp/home-manual-styling-smoke
/tmp/home-manual-styling-smoke \
  SwingArc/Views/PracticeHomeView.swift \
  SwingArc/Views/CameraView.swift \
  SwingArc/Design/AnalysisTheme.swift
```

Expected: nonzero exit at the first missing `surfaceOpacity` argument. The failure must be caused by the superseded colorful implementation, not by a compile error.

- [ ] **Step 5: Keep the failing test uncommitted until Tasks 2 and 3 are green**

Do not stage this test independently because it describes production code not yet implemented.

---

### Task 2: Remove Colorful Surfaces and Compact the History Entry

**Files:**
- Modify: `SwingArc/Design/AnalysisTheme.swift`
- Modify: `SwingArc/Views/PracticeHomeView.swift`
- Test: `Tests/HomeManualStylingSmoke.swift`

**Interfaces:**
- Consumes: existing `AnalysisTheme.proTourSurface`, `proTourSignal`, `proTourPrimaryText`, and `proTourSecondaryText`.
- Produces: `PracticeModeSelector(surfaceOpacity: Double, metrics: PracticeHomeMetrics, action: () -> Void)`.

- [ ] **Step 1: Remove the temporary colored theme tokens**

Delete these lines from `AnalysisTheme.swift`:

```swift
static let practiceDTLSurface = Color(red: 0.12, green: 0.37, blue: 0.27)
static let practiceFaceOnSurface = Color(red: 0.08, green: 0.32, blue: 0.34)
static let practiceManualSurface = Color(red: 0.29, green: 0.32, blue: 0.12)
static let practiceImportSurface = Color(red: 0.12, green: 0.27, blue: 0.34)
```

- [ ] **Step 2: Replace mode surfaces with opacity arguments**

Change `modeSelector(for:)` to accept metrics:

```swift
private func modeSelector(
    for action: PracticeHomeAction,
    metrics: PracticeHomeMetrics
) -> some View
```

Pass these exact pairs to the four selectors:

```swift
surfaceOpacity: 0.85,
metrics: metrics,
```

```swift
surfaceOpacity: 0.70,
metrics: metrics,
```

```swift
surfaceOpacity: 0.40,
metrics: metrics,
```

```swift
surfaceOpacity: 0.55,
metrics: metrics,
```

The call order in source remains 01, 02, 04, 03 because of the existing switch; the opacity must match the visible index rather than source order.

- [ ] **Step 3: Replace `surface` with the shared opacity API**

In `PracticeModeSelector`, use:

```swift
let surfaceOpacity: Double
let metrics: PracticeHomeMetrics
```

Replace the text and surface modifiers with:

```swift
.foregroundStyle(AnalysisTheme.proTourSecondaryText)
```

for eyebrow/detail text, and:

```swift
.background(
    AnalysisTheme.proTourSurface.opacity(surfaceOpacity),
    in: RoundedRectangle(cornerRadius: 26, style: .continuous)
)
.overlay(
    RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(modeAccent.opacity(0.14), lineWidth: 1)
)
```

- [ ] **Step 4: Remove the history capsule and constrain visible content**

Replace the history label styling with:

```swift
HStack(spacing: 6) {
    Image(systemName: "clock.arrow.circlepath")
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(AnalysisTheme.proTourSignal)
    Text("记录")
        .font(.system(size: 13, weight: .bold, design: .monospaced))
        .tracking(0.4)
        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
}
.frame(height: 30)
.contentShape(Rectangle())
```

Apply this invisible target to the button after `.buttonStyle(.plain)`:

```swift
.frame(minWidth: 44, minHeight: 44)
```

Keep `.accessibilityLabel("打开挥杆记录")`. Do not add any background, capsule, overlay, or visible padding.

- [ ] **Step 5: Run the smoke test and verify only layout assertions remain RED**

Run:

```bash
swiftc -parse-as-library Tests/HomeManualStylingSmoke.swift \
  -o /tmp/home-manual-styling-smoke
/tmp/home-manual-styling-smoke \
  SwingArc/Views/PracticeHomeView.swift \
  SwingArc/Views/CameraView.swift \
  SwingArc/Design/AnalysisTheme.swift
```

Expected: nonzero exit at the `GeometryReader` assertion because Task 3 has not removed `ScrollView` yet.

---

### Task 3: Build the Adaptive Non-Scrolling Portrait Layout

**Files:**
- Modify: `SwingArc/Views/PracticeHomeView.swift`
- Test: `Tests/HomeManualStylingSmoke.swift`

**Interfaces:**
- Consumes: `PracticeHomeMetrics(height:)` values in `PracticeHomeView` and `PracticeModeSelector`.
- Produces: a fixed safe-area page with no `ScrollView` or vertical bounce.

- [ ] **Step 1: Add the local metric type**

Add before `PracticeModeSelector`:

```swift
private struct PracticeHomeMetrics {
    let cardHeight: CGFloat
    let cardSpacing: CGFloat
    let mainTitleSize: CGFloat
    let cardTitleSize: CGFloat
    let cardDetailSize: CGFloat
    let trainingTopPadding: CGFloat
    let cardsTopPadding: CGFloat
    let headerTopPadding: CGFloat
    let bottomPadding: CGFloat

    init(height: CGFloat) {
        if height >= 820 {
            cardHeight = 126
            cardSpacing = 12
            mainTitleSize = 38
            cardTitleSize = 24
            cardDetailSize = 14
            trainingTopPadding = 34
            cardsTopPadding = 24
            headerTopPadding = 12
            bottomPadding = 8
        } else if height >= 700 {
            cardHeight = 108
            cardSpacing = 10
            mainTitleSize = 34
            cardTitleSize = 22
            cardDetailSize = 13
            trainingTopPadding = 24
            cardsTopPadding = 18
            headerTopPadding = 8
            bottomPadding = 6
        } else {
            cardHeight = 92
            cardSpacing = 8
            mainTitleSize = 30
            cardTitleSize = 20
            cardDetailSize = 12
            trainingTopPadding = 16
            cardsTopPadding = 12
            headerTopPadding = 4
            bottomPadding = 4
        }
    }
}
```

- [ ] **Step 2: Replace `ScrollView` with a safe-area `GeometryReader`**

Inside the existing background `ZStack`, use:

```swift
GeometryReader { proxy in
    let metrics = PracticeHomeMetrics(height: proxy.size.height)

    VStack(alignment: .leading, spacing: 0) {
        header
            .padding(.top, metrics.headerTopPadding)

        Text("TRAINING MODE")
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .tracking(1.8)
            .foregroundStyle(AnalysisTheme.proTourSignal)
            .padding(.top, metrics.trainingTopPadding)

        Text("选择机位")
            .font(
                .system(
                    size: metrics.mainTitleSize,
                    weight: .bold,
                    design: .rounded
                )
            )
            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
            .padding(.top, 6)

        Text("单机位自动练习 · 架好手机后再开始")
            .font(.system(size: metrics.cardDetailSize + 2, weight: .medium))
            .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            .padding(.top, 4)

        Spacer(minLength: metrics.cardsTopPadding)

        VStack(spacing: metrics.cardSpacing) {
            ForEach(
                Array(PracticeHomePresentation.modeOrder.enumerated()),
                id: \.offset
            ) { _, action in
                modeSelector(for: action, metrics: metrics)
            }
        }

        Spacer(minLength: metrics.bottomPadding)
    }
    .padding(.horizontal, 20)
    .frame(
        width: proxy.size.width,
        height: proxy.size.height,
        alignment: .top
    )
}
```

Delete the old `ScrollView`, its inner duplicate `VStack`, `.padding(.bottom, 38)`, and fixed top/card padding values.

- [ ] **Step 3: Apply adaptive card typography and height**

Inside `PracticeModeSelector`, replace fixed title/detail sizes and minimum height with:

```swift
.font(
    .system(
        size: metrics.cardTitleSize,
        weight: .bold,
        design: .rounded
    )
)
```

```swift
.font(.system(size: metrics.cardDetailSize, weight: .medium))
```

```swift
.frame(maxWidth: .infinity, height: metrics.cardHeight, alignment: .leading)
```

For tight screens, keep the eyebrow at 11 points and badges at 38 points; these remain legible and do not affect total card height.
Keep the existing `ProTourPressStyle` scale animation; the prohibition on `scaleEffect` applies to fitting the whole page, not to the brief press feedback on an individual card.

- [ ] **Step 4: Run the complete smoke test to verify GREEN**

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

- [ ] **Step 5: Run the manual-recording regression**

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

Expected: exit 0; the 15-second manual capture limit remains unchanged.

- [ ] **Step 6: Preserve the existing dirty working tree**

Run:

```bash
git diff --check -- \
  SwingArc/Design/AnalysisTheme.swift \
  SwingArc/Views/PracticeHomeView.swift \
  Tests/HomeManualStylingSmoke.swift
git status --short
```

Expected: no whitespace errors. Do not stage `PracticeHomeView.swift` as a whole because its diff contains pre-existing user work; leave the implementation files together in the current working tree.

---

### Task 4: Simulator and Wireless iPhone Verification

**Files:**
- Modify only if visual verification reveals clipping, excessive blank space, or insufficient surface separation.

**Interfaces:**
- Consumes: the completed single-screen SwiftUI layout.
- Produces: successful simulator/device builds, portrait screenshots, and the refreshed app installed on the physical phone.

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

- [ ] **Step 2: Verify regular and compact portrait layouts**

Launch the existing iPhone simulator normally and capture the home screen. Verify the current simulator uses the appropriate tier, all four cards and bottom safe area are visible, and a vertical swipe does not move the page.

Also validate the tight tier structurally through `HomeManualStylingSmoke`; if an available simulator has a safe-area height below 700 points, capture it as an additional visual check.

- [ ] **Step 3: Build the connected iPhone target**

Run:

```bash
xcodebuild \
  -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -configuration Debug \
  -destination 'id=00008140-001C20102493C01C' \
  -derivedDataPath /tmp/SwingArcHomeSingleScreenDerived \
  build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Install and launch the refreshed app**

Run:

```bash
xcrun devicectl device install app \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 \
  /tmp/SwingArcHomeSingleScreenDerived/Build/Products/Debug-iphoneos/SwingArcProject.app

xcrun devicectl device process launch \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 \
  --terminate-existing \
  --activate \
  com.liangbo.swingarc
```

Expected: installation reports bundle ID `com.liangbo.swingarc`; launch succeeds.

- [ ] **Step 5: Capture and inspect the physical home screen**

Run:

```bash
xcrun devicectl device capture screenshot \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 \
  --destination /tmp/swingarc-device-home-single-screen.png
```

Verify all of the following:

- Brand header, title, subtitle, cards 01 through 04, and bottom safe area appear at once.
- The history entry has no capsule and its visible content is no taller than the wordmark.
- All cards use the same near-black hue with restrained top-to-bottom opacity differences.
- Lime badges/icons/arrows and white/gray text remain readable.
- No text or card edge clips.
- The page has no vertical scroll or bounce space.
- Leave the app on the normal home screen.

- [ ] **Step 6: Run final repository safety checks**

Run:

```bash
git diff --check
git status --short
git log --oneline -5
```

Expected: no whitespace errors; unrelated pre-existing user changes remain present and unstaged.

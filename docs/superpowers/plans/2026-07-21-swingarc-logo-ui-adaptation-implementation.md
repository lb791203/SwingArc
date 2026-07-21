# SwingArc Logo UI Adaptation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing cartoon-like icon with a precise Tour-style SwingArc mark and apply it consistently to the native iOS icon, practice home, library empty state, and launch experience.

**Architecture:** A deterministic SVG is the visual source of truth for the mark geometry and palette. Raster App Icon variants are rendered from that source, while a focused SwiftUI `BrandMarkView` recreates the same normalized geometry for crisp in-app rendering at every scale. Existing theme tokens remain authoritative and no logo is placed over camera or video content.

**Tech Stack:** SVG, ImageMagick, Xcode asset catalogs, SwiftUI, XCTest-free Swift smoke checks, `xcodebuild`, `simctl`.

## Global Constraints

- Preserve the existing S-shaped swing-path plus ball recognition cue.
- Use `#090D0C`, `#131917`, `#F2F5ED`, `#C7F038`, and `#1F5E45`; do not introduce blue.
- Remove the explicit club head, grooves, glow, gradients, baked rounded corners, and white corner pixels.
- App Icon output must include standard, dark, and tinted 1024×1024 variants.
- Keep branding off all camera and video playback surfaces.
- Verify native simulator rendering at 29 pt, 40 pt, 60 pt, and 120 pt equivalents before completion.

---

### Task 1: Deterministic Logo Source and App Icon Variants

**Files:**
- Create: `BrandAssets/SwingArcMark.svg`
- Create: `BrandAssets/SwingArcMark-dark.svg`
- Create: `BrandAssets/SwingArcMark-tinted.svg`
- Modify: `SwingArc/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- Create: `SwingArc/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-dark.png`
- Create: `SwingArc/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-tinted.png`
- Modify: `SwingArc/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Tests/BrandAssetSmoke.sh`

**Interfaces:**
- Consumes: Color and geometry requirements from `docs/superpowers/specs/2026-07-21-swingarc-logo-ui-adaptation-design.md`.
- Produces: Three full-bleed 1024×1024 PNG files referenced by the App Icon asset catalog.

- [x] **Step 1: Write the failing asset smoke check**

```bash
#!/bin/zsh
set -euo pipefail
icon_dir="SwingArc/Assets.xcassets/AppIcon.appiconset"
for name in AppIcon-1024.png AppIcon-1024-dark.png AppIcon-1024-tinted.png; do
  test -f "$icon_dir/$name"
  test "$(sips -g pixelWidth "$icon_dir/$name" | awk '/pixelWidth/ {print $2}')" = "1024"
  test "$(sips -g pixelHeight "$icon_dir/$name" | awk '/pixelHeight/ {print $2}')" = "1024"
done
magick "$icon_dir/AppIcon-1024.png" -format '%[pixel:p{0,0}]' info: | grep -qi '090d0c'
! grep -RqiE 'gradient|filter|#0[0-9a-f]{5}ff' BrandAssets/SwingArcMark*.svg
```

- [x] **Step 2: Run the check and confirm it fails for missing variants**

Run: `zsh Tests/BrandAssetSmoke.sh`

Expected: non-zero exit because `AppIcon-1024-dark.png` and `AppIcon-1024-tinted.png` do not exist.

- [x] **Step 3: Create the normalized SVG geometry**

Use a 1024×1024 view box with a full-bleed ink background, an ivory tapered S ribbon centered in the safe zone, and one chartreuse ball at the lower exit. The standard source must contain only flat fills; dark and tinted sources reuse the same path coordinates and change only palette values.

- [x] **Step 4: Render the three production PNGs**

Run:

```bash
magick -background none BrandAssets/SwingArcMark.svg -resize 1024x1024 SwingArc/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
magick -background none BrandAssets/SwingArcMark-dark.svg -resize 1024x1024 SwingArc/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-dark.png
magick -background none BrandAssets/SwingArcMark-tinted.svg -resize 1024x1024 SwingArc/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-tinted.png
```

- [x] **Step 5: Register luminosity appearances**

Set `Contents.json` to one universal standard entry plus `luminosity=dark` and `luminosity=tinted` entries, each at `1024x1024` for platform `ios`.

- [x] **Step 6: Run the asset check**

Run: `zsh Tests/BrandAssetSmoke.sh`

Expected: PASS with exit code 0.

### Task 2: Reusable Native Brand Mark

**Files:**
- Create: `SwingArc/Views/BrandMarkView.swift`
- Modify: `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj`
- Create: `Tests/BrandMarkSourceSmoke.swift`

**Interfaces:**
- Consumes: `AnalysisTheme.proTourBackground`, `proTourPrimaryText`, and `proTourSignal`.
- Produces: `BrandMarkView(size: Double, showsWordmark: Bool)` and internal `SwingArcRibbonShape`.

- [x] **Step 1: Write the failing source smoke check**

```swift
import Foundation

let source = try String(contentsOfFile: "SwingArc/Views/BrandMarkView.swift")
precondition(source.contains("struct BrandMarkView"))
precondition(source.contains("struct SwingArcRibbonShape"))
precondition(source.contains("accessibilityLabel(\"SwingArc\")"))
precondition(!source.contains("figure.golf"))
print("Brand mark source smoke passed")
```

- [x] **Step 2: Run it and verify missing-file failure**

Run: `swift Tests/BrandMarkSourceSmoke.swift`

Expected: non-zero exit because `BrandMarkView.swift` does not exist.

- [x] **Step 3: Implement the reusable component**

Create `BrandMarkView` with an aspect-ratio-preserving square canvas, the same normalized tapered ribbon path used by the SVG, and a chartreuse ball. `showsWordmark` appends the uppercase SwingArc wordmark without adding a surrounding badge.

- [x] **Step 4: Add the source to the Xcode target**

Add one `PBXFileReference`, one `PBXBuildFile`, one Views-group entry, and one Sources-phase entry for `BrandMarkView.swift`; do not modify signing settings or unrelated source membership.

- [x] **Step 5: Run the source check**

Run: `swift Tests/BrandMarkSourceSmoke.swift`

Expected: `Brand mark source smoke passed`.

### Task 3: Native UI Placement and Device-Scale Verification

**Files:**
- Modify: `SwingArc/Views/PracticeHomeView.swift`
- Modify: `SwingArc/Views/ProjectLibraryView.swift`
- Modify: `SwingArc/SwingArcApp.swift`
- Create: `SwingArc/LaunchScreen.storyboard`
- Create: `SwingArc/Assets.xcassets/LaunchMark.imageset/`
- Create: `SwingArc/Assets.xcassets/LaunchBackground.colorset/`
- Create: `Tests/BrandPlacementSmoke.swift`
- Create: `Tests/LaunchBrandSmoke.sh`
- Create: `docs/validation/screenshots/swingarc-brand-practice-home.png`
- Create: `docs/validation/screenshots/swingarc-brand-library-empty.png`

**Interfaces:**
- Consumes: `BrandMarkView(size:showsWordmark:)` from Task 2.
- Produces: 30 pt header mark, 60 pt library empty-state mark, and a short native launch transition with a 96 pt mark.

- [x] **Step 1: Write the failing placement check**

```swift
import Foundation

let home = try String(contentsOfFile: "SwingArc/Views/PracticeHomeView.swift")
let library = try String(contentsOfFile: "SwingArc/Views/ProjectLibraryView.swift")
let app = try String(contentsOfFile: "SwingArc/SwingArcApp.swift")
precondition(home.contains("BrandMarkView(size: 30"))
precondition(library.contains("BrandMarkView(size: 60"))
precondition(app.contains("BrandLaunchView"))
precondition(!home.contains("Image(systemName: \"figure.golf\")\n                    .font(.system(size: 17"))
print("Brand placement smoke passed")
```

- [x] **Step 2: Run it and verify failure**

Run: `swift Tests/BrandPlacementSmoke.swift`

Expected: non-zero exit because the three placements are not present.

- [x] **Step 3: Apply the brand to non-video surfaces**

Replace the home header golf SF Symbol with `BrandMarkView(size: 30, showsWordmark: true)`. Replace the library empty-state film badge with `BrandMarkView(size: 60, showsWordmark: false)`, and add a 20 pt mark to the populated library navigation title. Add `BrandLaunchView` at 96 pt with no progress spinner or text animation. Configure a real `LaunchScreen.storyboard` with the same 96 pt vector mark and `LaunchBackground` color so the system launch phase cannot flash white before SwiftUI appears.

- [x] **Step 4: Run source and asset checks**

Run:

```bash
zsh Tests/BrandAssetSmoke.sh
zsh Tests/LaunchBrandSmoke.sh
swift Tests/BrandMarkSourceSmoke.swift
swift Tests/BrandPlacementSmoke.swift
```

Expected: all commands exit 0.

- [x] **Step 5: Build the simulator app**

Run:

```bash
xcodebuild -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj -scheme SwingArcProject -destination 'platform=iOS Simulator,id=867A3106-4032-4F9C-8BB5-E4B8C14F0780' -derivedDataPath /tmp/SwingArcBrandDerivedData build
```

Expected: `** BUILD SUCCEEDED **` and no asset-catalog warnings.

- [x] **Step 6: Capture real simulator screens**

Install and launch the built app with the normal home arguments, then with `-swingarc-preview-library`; save screenshots to the two validation paths. Inspect the mark for clean silhouette, no white corners, no logo over video, and legibility at the actual header and empty-state sizes.

- [ ] **Step 7: Commit only the brand implementation**

```bash
git add BrandAssets SwingArc/Assets.xcassets/AppIcon.appiconset SwingArc/Views/BrandMarkView.swift SwingArc/Views/PracticeHomeView.swift SwingArc/Views/ProjectLibraryView.swift SwingArc/SwingArcApp.swift Tests/BrandAssetSmoke.sh Tests/BrandMarkSourceSmoke.swift Tests/BrandPlacementSmoke.swift docs/superpowers/plans/2026-07-21-swingarc-logo-ui-adaptation-implementation.md
git commit -m "feat: redraw SwingArc brand mark"
```

# SwingArc 1.0 App Store Core Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an iPhone-only SwingArc 1.0 whose public workflow is limited to manual recording, Photos import, video review, conservative P1–P8 detection with manual correction, drawing, local records, and annotated export.

**Architecture:** Keep the existing target and deferred automatic-practice/coaching source modules, but remove every public route and presentation surface for them. Preserve the existing local project, P-point correction, drawing, and export data paths; add a small About/Privacy surface and explicit camera-permission recovery. Finish with source contracts, focused smoke tests, a public-Xcode Release archive, TestFlight device acceptance, and App Store Connect submission.

**Tech Stack:** Swift 5, SwiftUI, AVFoundation, PhotosUI, Photos, Apple Vision, local JSON/UserDefaults persistence, standalone `swiftc` smoke executables, `xcodebuild`, App Store Connect, and TestFlight.

## Global Constraints

- Design authority: `docs/superpowers/specs/2026-07-28-app-store-core-release-design.md`.
- Baseline branch: `codex/precision-swing-analysis`; approved design commit: `1ea6e1c`.
- Preserve unrelated untracked files; stage only the exact files listed in each task.
- Marketing version is `1.0`; initial build number is `1`.
- Bundle identifier is `com.liangbo.swingarc`.
- Device family is iPhone only; minimum deployment target is iOS 17.
- Keep the App account-free, ad-free, analytics-free, tracking-free, and independent of an in-App network service.
- Public 1.0 entry points are exactly manual recording, Photos import, and local records.
- Public analysis surfaces are exactly playback/frame stepping, P1–P8 status and correction, drawing, local persistence, and annotated export.
- Keep automatic-practice, DTL/Face-on practice selection, technique scoring, coaching, drills, speech, trajectory coaching, and pose-assistance overlays out of the public 1.0 UI and metadata.
- Keep deferred module source code in the repository; do not create a Lite target and do not delete the deferred subsystems.
- Automatic P points must refer to observed source frames. P6/P8 remain unresolved without reliable shaft evidence.
- Manual P-point corrections remain separate from automatic predictions and survive reanalysis and project reopen.
- Release price is free, with no In-App Purchase or subscription.
- Target worldwide public availability, but do not enable China mainland until a valid ICP filing number has been obtained and verified against the Simplified Chinese metadata.
- Complete the EU DSA trader/non-trader declaration truthfully before enabling EU availability; do not infer the user's legal status.
- Development builds may use the installed Xcode 27 beta. The App Store customer-distribution archive must use a public App Store-supported Xcode with the iOS 26 SDK or later.
- The GitHub Pages site is not configured at plan time and both public policy URLs return `404`; deploy `main:/docs` and verify the live content before submission.
- Automated tests, successful signing, and archive validation do not replace physical-iPhone acceptance of the exact processed TestFlight build.

---

## File Map

### New files

- `SwingArc/Models/AppInformation.swift` — canonical privacy/support URLs, App version formatting, and local-analysis disclaimer.
- `SwingArc/Views/AboutPrivacyView.swift` — in-App About, Privacy, and Support surface.
- `Tests/CoreReleaseHomeSurfaceSmoke.swift` — source contract for the three-action public home flow.
- `Tests/AppInformationSmoke.swift` — pure model contract for release URLs and version formatting.
- `Tests/AboutPrivacySourceSmoke.swift` — source and project-membership contract for the in-App policy links.
- `Tests/CoreAnalysisSurfaceSmoke.swift` — source contract for the reduced analysis workspace.
- `Tests/CameraAccessPolicySmoke.swift` — pure camera-access presentation contract.
- `Tests/CameraAccessSourceSmoke.swift` — source contract for denied-permission recovery.
- `docs/validation/app-store-core-release-2026-07-28.md` — actual automated, archive, TestFlight, device, screenshot, and submission evidence; create only when real results are available.

### Existing files to modify

- `SwingArc/Models/PracticeModels.swift` — public home action ordering only.
- `SwingArc/Models/CameraRecordingReadiness.swift` — pure camera-access UI policy alongside recording readiness.
- `SwingArc/Views/PracticeHomeView.swift` — two primary media cards plus Records and About.
- `SwingArc/Views/ContentView.swift` — remove automatic-practice navigation; present About; preserve import/capture/correction/export.
- `SwingArc/Views/AnalysisWorkspaceView.swift` — remove coaching/results/trajectory/view-selection routes and expose only core analysis controls.
- `SwingArc/Views/WorkspaceComponents.swift` — remove results buttons and pose overlay controls from public header, playback controls, and inspector.
- `SwingArc/Views/CameraView.swift` — request camera permission and provide Settings recovery.
- `SwingArcProject.xcodeproj/project.pbxproj` — add the two new production Swift files to their groups and Sources phase.
- `Tests/HomeManualStylingSmoke.swift` — update the old four-card visual contract to the two-card core home.
- `Tests/PhoneCorrectionIntegrationSourceSmoke.swift` — preserve correction assertions while reversing old camera-view/coaching expectations.
- `Tests/AppStoreReleaseReadinessSmoke.sh` — enforce core metadata, in-App policy links, version, device family, permissions, and forbidden-claim absence.
- `docs/app-store/metadata/zh-Hans.md` — core-only product-page copy.
- `docs/app-store/metadata/review-notes.md` — deterministic core review path.
- `docs/app-store/privacy/index.html` — core local-data wording without coaching/automatic-practice claims.
- `docs/app-store/support/index.html` — core FAQ without automatic-practice claims.
- `docs/app-store/submission-checklist.md` — core screenshots, free pricing, public-Xcode gate, TestFlight gate, DSA gate, and China ICP gate.

---

### Task 1: Reduce the Public Home to Manual Recording, Import, and Records

**Files:**
- Create: `Tests/CoreReleaseHomeSurfaceSmoke.swift`
- Modify: `SwingArc/Models/PracticeModels.swift:3-15`
- Modify: `SwingArc/Views/PracticeHomeView.swift:7-150`
- Modify: `SwingArc/Views/ContentView.swift:33-59`
- Modify: `SwingArc/Views/ContentView.swift:97-102`
- Modify: `SwingArc/Views/ContentView.swift:136-152`
- Modify: `Tests/HomeManualStylingSmoke.swift:5-72`

**Interfaces:**
- Consumes: existing `PracticeHomeAction.manualCapture`, `PracticeHomeAction.importVideo`, `ContentView.showManualCapture`, `ContentView.showVideoPicker`, and `ContentView.showProjectLibrary`.
- Produces: `PracticeHomePresentation.modeOrder == [.manualCapture, .importVideo]` and a `PracticeHomeView` initializer with `onManualCapture`, `onImport`, and `onOpenLibrary`.

- [ ] **Step 1: Write the failing release-home source contract**

Create `Tests/CoreReleaseHomeSurfaceSmoke.swift`:

```swift
import Foundation

@main
struct CoreReleaseHomeSurfaceSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let models = try read(root, "SwingArc/Models/PracticeModels.swift")
        let home = try read(root, "SwingArc/Views/PracticeHomeView.swift")
        let content = try read(root, "SwingArc/Views/ContentView.swift")

        let orderStart = models.range(
            of: "static let modeOrder: [PracticeHomeAction] = ["
        )!.upperBound
        let orderTail = models[orderStart...]
        let orderEnd = orderTail.range(of: "]")!.lowerBound
        let order = String(orderTail[..<orderEnd])

        precondition(order.contains(".manualCapture"))
        precondition(order.contains(".importVideo"))
        precondition(!order.contains(".downTheLine"))
        precondition(!order.contains(".faceOn"))

        precondition(home.contains("Text(\"挥杆视频分析\")"))
        precondition(home.contains("title: \"手动录像\""))
        precondition(home.contains("title: \"导入视频\""))
        precondition(!home.contains("正后方 · DTL"))
        precondition(!home.contains("正面 · FACE-ON"))
        precondition(!home.contains("选择机位"))

        precondition(!content.contains("onStartPractice:"))
        precondition(!content.contains("PracticeSessionView("))
        precondition(content.contains("showManualCapture = true"))
        precondition(content.contains("showVideoPicker = true"))
        precondition(content.contains("showProjectLibrary = true"))
    }

    private static func read(_ root: URL, _ path: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
```

- [ ] **Step 2: Run the home contract and verify RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  Tests/CoreReleaseHomeSurfaceSmoke.swift \
  -o /tmp/swingarc-core-home-smoke
/tmp/swingarc-core-home-smoke
```

Expected: the executable traps because the current mode order includes DTL and Face-on, the home says `选择机位`, and `ContentView` constructs `PracticeSessionView`.

- [ ] **Step 3: Narrow the home action order**

Replace the `PracticeHomePresentation.modeOrder` declaration in `SwingArc/Models/PracticeModels.swift` with:

```swift
enum PracticeHomePresentation {
    static let modeOrder: [PracticeHomeAction] = [
        .manualCapture,
        .importVideo
    ]
    static let secondaryActions: [PracticeHomeAction] = []
}
```

Keep the deferred enum cases and automatic-practice models intact.

- [ ] **Step 4: Replace the public home copy and cards**

Change the `PracticeHomeView` initializer to:

```swift
struct PracticeHomeView: View {
    let onManualCapture: () -> Void
    let onImport: () -> Void
    let onOpenLibrary: () -> Void
```

Replace the current training heading with:

```swift
Text("SWING ANALYSIS")
    .font(.system(size: 13, weight: .bold, design: .monospaced))
    .tracking(1.8)
    .foregroundStyle(AnalysisTheme.proTourSignal)
    .padding(.top, metrics.trainingTopPadding)

Text("挥杆视频分析")
    .font(
        .system(
            size: metrics.mainTitleSize,
            weight: .bold,
            design: .rounded
        )
    )
    .foregroundStyle(AnalysisTheme.proTourPrimaryText)
    .padding(.top, 6)

Text("录制或导入视频，开始 P1–P8 识别与画线")
    .font(.system(size: metrics.cardDetailSize + 2, weight: .medium))
    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
    .padding(.top, 4)
```

Replace `modeSelector(for:metrics:)` with:

```swift
@ViewBuilder
private func modeSelector(
    for action: PracticeHomeAction,
    metrics: PracticeHomeMetrics
) -> some View {
    switch action {
    case .manualCapture:
        PracticeModeSelector(
            index: "01",
            eyebrow: "MANUAL CAPTURE",
            title: "手动录像",
            detail: "点击即录 · 最长 15 秒",
            systemImage: "record.circle",
            surfaceOpacity: 0.70,
            metrics: metrics,
            action: onManualCapture
        )
    case .importVideo:
        PracticeModeSelector(
            index: "02",
            eyebrow: "IMPORT VIDEO",
            title: "导入视频",
            detail: "从相册选择 · 自动定位 P1–P8",
            systemImage: "photo.on.rectangle",
            surfaceOpacity: 0.50,
            metrics: metrics,
            action: onImport
        )
    case .downTheLine, .faceOn, .history:
        EmptyView()
    }
}
```

Change the card accessibility label from:

```swift
.accessibilityLabel("开始\(title)练习")
```

to:

```swift
.accessibilityLabel(title)
```

- [ ] **Step 5: Remove the automatic-practice navigation route**

In `SwingArc/Views/ContentView.swift`:

1. Delete `@State private var selectedPracticeView: PracticeCameraView?`.
2. Delete the DEBUG initializer branch that assigns `_selectedPracticeView`.
3. Construct the home with:

```swift
PracticeHomeView(
    onManualCapture: { showManualCapture = true },
    onImport: { showVideoPicker = true },
    onOpenLibrary: { showProjectLibrary = true }
)
```

4. Delete the complete `.fullScreenCover(item: $selectedPracticeView)` block.
5. Keep `PracticeSessionView.swift` and the deferred automatic-practice services in the repository and Xcode target.

- [ ] **Step 6: Update the two-card styling smoke**

In `Tests/HomeManualStylingSmoke.swift`, replace the four expected opacity arguments with:

```swift
let opacityArguments = [
    "surfaceOpacity: 0.70",
    "surfaceOpacity: 0.50"
]
```

Add:

```swift
precondition(home.contains("Text(\"挥杆视频分析\")"))
precondition(home.contains("录制或导入视频，开始 P1–P8 识别与画线"))
precondition(!home.contains("选择机位"))
precondition(!home.contains("正后方 · DTL"))
precondition(!home.contains("正面 · FACE-ON"))
```

Remove assertions that require the old `0.85`, `0.55`, or `0.40` cards.

- [ ] **Step 7: Run focused tests and build**

Run:

```bash
xcrun swiftc -parse-as-library \
  Tests/CoreReleaseHomeSurfaceSmoke.swift \
  -o /tmp/swingarc-core-home-smoke
/tmp/swingarc-core-home-smoke

xcrun swiftc -parse-as-library \
  Tests/HomeManualStylingSmoke.swift \
  -o /tmp/swingarc-home-styling-smoke
/tmp/swingarc-home-styling-smoke \
  SwingArc/Views/PracticeHomeView.swift \
  SwingArc/Views/CameraView.swift \
  SwingArc/Design/AnalysisTheme.swift

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -jobs 1 \
  -project SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/SwingArcCoreHomeDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: both smoke executables exit `0`; Xcode prints `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit the public-home reduction**

```bash
git add \
  SwingArc/Models/PracticeModels.swift \
  SwingArc/Views/PracticeHomeView.swift \
  SwingArc/Views/ContentView.swift \
  Tests/CoreReleaseHomeSurfaceSmoke.swift \
  Tests/HomeManualStylingSmoke.swift
git commit -m "feat: focus release home on video analysis"
```

---

### Task 2: Add an In-App About, Privacy, and Support Surface

**Files:**
- Create: `SwingArc/Models/AppInformation.swift`
- Create: `SwingArc/Views/AboutPrivacyView.swift`
- Create: `Tests/AppInformationSmoke.swift`
- Create: `Tests/AboutPrivacySourceSmoke.swift`
- Modify: `SwingArc/Views/PracticeHomeView.swift:55-87`
- Modify: `SwingArc/Views/ContentView.swift:33-43`
- Modify: `SwingArc/Views/ContentView.swift:97-103`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj:8-78`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj:80-128`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj:220-253`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj:322-390`

**Interfaces:**
- Consumes: approved privacy URL `https://lb791203.github.io/SwingArc/app-store/privacy/` and support URL `https://lb791203.github.io/SwingArc/app-store/support/`.
- Produces: `AppInformation.privacyURL`, `AppInformation.supportURL`, `AppInformation.version(marketingVersion:buildNumber:)`, `AboutPrivacyView`, and `PracticeHomeView.onOpenAbout`.

- [ ] **Step 1: Write failing App information tests**

Create `Tests/AppInformationSmoke.swift`:

```swift
import Foundation

@main
struct AppInformationSmoke {
    static func main() {
        precondition(AppInformation.privacyURL.scheme == "https")
        precondition(AppInformation.supportURL.scheme == "https")
        precondition(AppInformation.privacyURL.host == "lb791203.github.io")
        precondition(AppInformation.supportURL.host == "lb791203.github.io")
        precondition(
            AppInformation.version(
                marketingVersion: "1.0",
                buildNumber: "1"
            ) == "1.0 (1)"
        )
        precondition(
            AppInformation.version(
                marketingVersion: nil,
                buildNumber: nil
            ) == "版本未知"
        )
        precondition(AppInformation.analysisDisclaimer.contains("运动训练参考"))
        precondition(AppInformation.analysisDisclaimer.contains("可能不完整"))
    }
}
```

Create `Tests/AboutPrivacySourceSmoke.swift`:

```swift
import Foundation

@main
struct AboutPrivacySourceSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let content = try read(root, "SwingArc/Views/ContentView.swift")
        let home = try read(root, "SwingArc/Views/PracticeHomeView.swift")
        let about = try read(root, "SwingArc/Views/AboutPrivacyView.swift")
        let project = try read(root, "SwingArcProject.xcodeproj/project.pbxproj")

        precondition(content.contains("showAboutPrivacy"))
        precondition(content.contains("AboutPrivacyView()"))
        precondition(home.contains("onOpenAbout"))
        precondition(home.contains("关于与隐私"))
        precondition(about.contains("AppInformation.privacyURL"))
        precondition(about.contains("AppInformation.supportURL"))
        precondition(project.contains("AppInformation.swift in Sources"))
        precondition(project.contains("AboutPrivacyView.swift in Sources"))
    }

    private static func read(_ root: URL, _ path: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
```

- [ ] **Step 2: Run both tests and verify RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  Tests/AppInformationSmoke.swift \
  -o /tmp/swingarc-app-information-smoke

xcrun swiftc -parse-as-library \
  Tests/AboutPrivacySourceSmoke.swift \
  -o /tmp/swingarc-about-source-smoke
/tmp/swingarc-about-source-smoke
```

Expected: the model test fails to compile because `AppInformation` does not exist; the source smoke fails because the About file and route do not exist.

- [ ] **Step 3: Implement the pure App information model**

Create `SwingArc/Models/AppInformation.swift`:

```swift
import Foundation

enum AppInformation {
    static let privacyURL = URL(
        string: "https://lb791203.github.io/SwingArc/app-store/privacy/"
    )!

    static let supportURL = URL(
        string: "https://lb791203.github.io/SwingArc/app-store/support/"
    )!

    static let analysisDisclaimer =
        "P1–P8 自动识别仅供运动训练参考，结果可能不完整；请使用逐帧修正核对关键位置。"

    static var currentVersion: String {
        version(
            marketingVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            buildNumber: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String
        )
    }

    static func version(
        marketingVersion: String?,
        buildNumber: String?
    ) -> String {
        guard let marketingVersion,
              !marketingVersion.isEmpty,
              let buildNumber,
              !buildNumber.isEmpty else {
            return "版本未知"
        }
        return "\(marketingVersion) (\(buildNumber))"
    }
}
```

- [ ] **Step 4: Implement the About and Privacy view**

Create `SwingArc/Views/AboutPrivacyView.swift`:

```swift
import SwiftUI

struct AboutPrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("SwingArc") {
                    LabeledContent("版本", value: AppInformation.currentVersion)
                    Text(AppInformation.analysisDisclaimer)
                        .foregroundStyle(.secondary)
                }

                Section("隐私与支持") {
                    Link(destination: AppInformation.privacyURL) {
                        Label("隐私政策", systemImage: "hand.raised")
                    }
                    Link(destination: AppInformation.supportURL) {
                        Label("支持与联系", systemImage: "questionmark.circle")
                    }
                }

                Section {
                    Text("视频、P 点、画线和项目均保存在此设备；SwingArc 不要求账号，也不会上传您的挥杆视频。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("关于与隐私")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
```

- [ ] **Step 5: Make About reachable from the home**

Add to `PracticeHomeView`:

```swift
let onOpenAbout: () -> Void
```

Add this button beside Records in the home header:

```swift
Button(action: onOpenAbout) {
    Image(systemName: "info.circle")
        .font(.system(size: 17, weight: .bold))
        .frame(width: 44, height: 44)
}
.buttonStyle(.plain)
.foregroundStyle(AnalysisTheme.proTourPrimaryText)
.accessibilityLabel("关于与隐私")
```

Add to `ContentView` state:

```swift
@State private var showAboutPrivacy = false
```

Pass the action:

```swift
onOpenAbout: { showAboutPrivacy = true }
```

Add after the existing sheets/covers:

```swift
.sheet(isPresented: $showAboutPrivacy) {
    AboutPrivacyView()
}
```

- [ ] **Step 6: Add both production files to the Xcode project**

Use the following unused object IDs:

```text
C90000000000000000000001 AppInformation.swift in Sources
C90000000000000000000002 AppInformation.swift file reference
C90000000000000000000003 AboutPrivacyView.swift in Sources
C90000000000000000000004 AboutPrivacyView.swift file reference
```

Add these entries to `PBXBuildFile`:

```text
C90000000000000000000001 /* AppInformation.swift in Sources */ = {isa = PBXBuildFile; fileRef = C90000000000000000000002 /* AppInformation.swift */; };
C90000000000000000000003 /* AboutPrivacyView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C90000000000000000000004 /* AboutPrivacyView.swift */; };
```

Add these entries to `PBXFileReference`:

```text
C90000000000000000000002 /* AppInformation.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppInformation.swift; sourceTree = "<group>"; };
C90000000000000000000004 /* AboutPrivacyView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AboutPrivacyView.swift; sourceTree = "<group>"; };
```

Add `AppInformation.swift` to the Models group, `AboutPrivacyView.swift` to the Views group, and both build-file IDs to the app Sources phase.

- [ ] **Step 7: Run model, source, and local build verification**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AppInformation.swift \
  Tests/AppInformationSmoke.swift \
  -o /tmp/swingarc-app-information-smoke
/tmp/swingarc-app-information-smoke

xcrun swiftc -parse-as-library \
  Tests/AboutPrivacySourceSmoke.swift \
  -o /tmp/swingarc-about-source-smoke
/tmp/swingarc-about-source-smoke

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -jobs 1 \
  -project SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/SwingArcAboutDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: both smoke executables exit `0`; Xcode prints `** BUILD SUCCEEDED **`. The URLs remain a Task 6 gate because GitHub Pages is not yet deployed.

- [ ] **Step 8: Commit the About and Privacy surface**

```bash
git add \
  SwingArc/Models/AppInformation.swift \
  SwingArc/Views/AboutPrivacyView.swift \
  SwingArc/Views/PracticeHomeView.swift \
  SwingArc/Views/ContentView.swift \
  SwingArcProject.xcodeproj/project.pbxproj \
  Tests/AppInformationSmoke.swift \
  Tests/AboutPrivacySourceSmoke.swift
git commit -m "feat: add in-app privacy and support access"
```

---

### Task 3: Reduce the Analysis Workspace to P1–P8 and Drawing

**Files:**
- Create: `Tests/CoreAnalysisSurfaceSmoke.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift:3-171`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift:204-365`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift:472-659`
- Modify: `SwingArc/Views/WorkspaceComponents.swift:3-87`
- Modify: `SwingArc/Views/WorkspaceComponents.swift:555-626`
- Modify: `SwingArc/Views/WorkspaceComponents.swift:935-990`
- Modify: `SwingArc/Views/ContentView.swift:64-87`
- Modify: `Tests/PhoneCorrectionIntegrationSourceSmoke.swift:5-44`

**Interfaces:**
- Consumes: `AnalysisWorkspacePresentation`, `StageTimelineView`, `MobileReplayTimelineView`, `PPointCorrectionWorkspace`, `DrawingToolRail`, `StageInspectorView`, and the existing `onAnalyze`, `onCancelAnalysis`, `onSetManualStage`, `onCorrectPPoints`, and `onExport` callbacks.
- Produces: a public `AnalysisWorkspaceView` initializer without pose-overlay or camera-view bindings, a stage-only inspector, and analysis/reanalysis controls without coaching results.

- [ ] **Step 1: Write the failing core-analysis source contract**

Create `Tests/CoreAnalysisSurfaceSmoke.swift`:

```swift
import Foundation

@main
struct CoreAnalysisSurfaceSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try read(root, "SwingArc/Views/AnalysisWorkspaceView.swift")
        let components = try read(root, "SwingArc/Views/WorkspaceComponents.swift")
        let content = try read(root, "SwingArc/Views/ContentView.swift")

        let workspace = prefix(source, before: "struct FullscreenVideoPlaybackView")
        let header = section(
            components,
            from: "struct WorkspaceHeaderView",
            to: "struct StageTimelineView"
        )
        let controls = section(
            components,
            from: "struct PlaybackControlsView",
            to: "struct DrawingToolRail"
        )
        let inspector = section(
            components,
            from: "struct WorkspaceInspectorView",
            to: "struct StageAdjustmentBar"
        )

        precondition(workspace.contains("DrawingToolRail("))
        precondition(workspace.contains("StageTimelineView("))
        precondition(workspace.contains("MobileReplayTimelineView("))
        precondition(workspace.contains("onCorrectPPoints"))
        precondition(workspace.contains("onExport"))
        precondition(workspace.contains("重新分析"))

        for forbidden in [
            "SimplifiedSwingFeedbackView(",
            "simplifiedFeedback",
            "SwingTrajectoryOverlay(",
            "trajectoryCategory:",
            "选择拍摄视角",
            "cameraViewButton(",
            "showResults("
        ] {
            precondition(!workspace.contains(forbidden))
        }

        precondition(!header.contains("onShowResults"))
        precondition(!header.contains("hasResults"))
        precondition(!controls.contains("onShowResults"))
        precondition(controls.contains("重新分析"))
        precondition(inspector.contains("StageInspectorView("))
        precondition(!inspector.contains("Toggle("))
        precondition(!inspector.contains("showPoseSkeleton"))
        precondition(!content.contains("showPoseSkeleton: $showPoseSkeleton"))
        precondition(!content.contains("practiceCameraView: $practiceCameraView"))
    }

    private static func read(_ root: URL, _ path: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static func prefix(_ source: String, before marker: String) -> String {
        String(source[..<source.range(of: marker)!.lowerBound])
    }

    private static func section(
        _ source: String,
        from start: String,
        to end: String
    ) -> String {
        let startIndex = source.range(of: start)!.lowerBound
        let tail = source[startIndex...]
        let endIndex = tail.range(of: end)!.lowerBound
        return String(tail[..<endIndex])
    }
}
```

- [ ] **Step 2: Run the source contract and verify RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  Tests/CoreAnalysisSurfaceSmoke.swift \
  -o /tmp/swingarc-core-analysis-surface-smoke
/tmp/swingarc-core-analysis-surface-smoke
```

Expected: the executable traps on existing feedback, camera-view, trajectory, results, and pose-overlay surfaces.

- [ ] **Step 3: Remove deferred state and routes from `AnalysisWorkspaceView`**

Remove these public bindings:

```swift
@Binding var showPoseSkeleton: Bool
@Binding var showHeadStability: Bool
@Binding var showSpineAngle: Bool
@Binding var showGrid: Bool
@Binding var practiceCameraView: PracticeCameraView?
```

Remove:

```swift
@State private var showsResultsSheet = false
@State private var expandedFeedbackCategory: SwingFeedbackCategory?
```

Delete the `simplifiedFeedback`, `trajectoryStageTimes`, and `trajectoryFrames` computed properties; delete the complete results sheet; delete `showResults`, `selectStage`, and `cameraViewButton`.

Keep the DEBUG automatic-analysis preview only:

```swift
.task(id: project.id) {
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    guard PracticePreviewConfiguration.autoAnalyzes(
        for: arguments
    ) else { return }
    try? await Task.sleep(for: .milliseconds(250))
    onAnalyze()
    #endif
}
```

Every `VideoCanvasView` construction in the public workspace must use:

```swift
showPoseSkeleton: false,
showHeadStability: false,
showSpineAngle: false,
showGrid: false,
```

and must omit `trajectoryCategory`, `trajectoryFrames`, and `trajectoryStageTimes`.

- [ ] **Step 4: Make public headers and playback controls stage-only**

Construct the regular inspector with:

```swift
WorkspaceInspectorView(
    playbackManager: playbackManager,
    presentation: presentation,
    keyframes: keyframes,
    onCancelAnalysis: onCancelAnalysis,
    onSeek: playbackManager.seek,
    onAdjust: openAdjustment
)
```

Construct `WorkspaceHeaderView` without `hasResults` or `onShowResults`.

Construct `PlaybackControlsView` with:

```swift
PlaybackControlsView(
    playbackManager: playbackManager,
    interactionMode: $interactionMode,
    hasResults: playbackManager.analysisState.hasCompletedResult,
    onToggleDrawing: toggleDrawingMode,
    onAnalyze: {
        interactionMode = .idle
        onAnalyze()
    }
)
```

In the mobile action row, make the left button always analyze/reanalyze:

```swift
Button {
    interactionMode = .idle
    onAnalyze()
} label: {
    Image(
        systemName: playbackManager.analysisState.hasCompletedResult
            ? "arrow.clockwise"
            : "sparkles"
    )
    .font(.system(size: 18, weight: .semibold))
    .frame(width: 48, height: 48)
    .background(.black.opacity(0.46), in: Circle())
    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
}
.buttonStyle(.plain)
.foregroundStyle(
    playbackManager.isScanning ? .white.opacity(0.58) : .white
)
.disabled(playbackManager.isScanning)
.accessibilityLabel(
    playbackManager.analysisState.hasCompletedResult
        ? "重新分析"
        : "开始 P1–P8 分析"
)
```

Fix the duplicated outer `if playbackManager.isScanning` so `mobileAnalysisStatus` has exactly:

```swift
if playbackManager.isScanning {
    // existing progress card
} else if let failure = playbackManager.analysisFailure {
    // existing failure card
}
```

This is required so a non-scanning analysis failure remains visible while drawing and correction stay available.

- [ ] **Step 5: Simplify shared workspace components**

In `WorkspaceHeaderView`, remove `hasResults`, `onShowResults`, and the results button.

Change `PlaybackControlsView` to:

```swift
struct PlaybackControlsView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    @Binding var interactionMode: WorkspaceInteractionMode
    let hasResults: Bool
    let onToggleDrawing: () -> Void
    let onAnalyze: () -> Void
```

Replace its results/analysis button with:

```swift
Button(action: onAnalyze) {
    VStack(spacing: 1) {
        Image(systemName: hasResults ? "arrow.clockwise" : "sparkles")
        Text(hasResults ? "重新分析" : "分析")
            .font(.caption2.weight(.semibold))
    }
    .frame(width: 58, height: 44)
    .background(
        hasResults ? AnalysisTheme.proTourSurface : AnalysisTheme.proTourSignal,
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
    .foregroundStyle(
        hasResults
            ? AnalysisTheme.proTourPrimaryText
            : AnalysisTheme.proTourBackground
    )
}
.disabled(playbackManager.isScanning)
.accessibilityLabel(hasResults ? "重新分析" : "开始 P1–P8 分析")
```

Change `WorkspaceInspectorView` to:

```swift
struct WorkspaceInspectorView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    let presentation: AnalysisWorkspacePresentation
    let keyframes: [KeyframeMarker]
    let onCancelAnalysis: () -> Void
    let onSeek: (Double) -> Void
    let onAdjust: (SwingStage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if playbackManager.isScanning {
                AnalysisProgressCard(
                    phase: playbackManager.analysisProgressPhase,
                    progress: playbackManager.scanProgress,
                    onCancel: onCancelAnalysis
                )
            } else {
                StageInspectorView(
                    presentation: presentation,
                    keyframes: keyframes,
                    sourceFrameRate: playbackManager.sourceFrameRate,
                    onSeek: onSeek,
                    onAdjust: onAdjust
                )
            }

            if let failure = playbackManager.analysisFailure {
                AnalysisFailureBanner(failure: failure)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .foregroundStyle(.white)
        .background(AnalysisTheme.chrome)
    }
}
```

- [ ] **Step 6: Update `ContentView` and correction integration**

Stop passing the five removed bindings to `AnalysisWorkspaceView`. Preserve the private legacy project fields in `ContentView` and `LocalAnalysisProject` so reopening an old project does not destroy stored data.

Update `Tests/PhoneCorrectionIntegrationSourceSmoke.swift` by keeping its correction assertions and replacing the old view-selection assertions with:

```swift
let fullscreenStart = workspace.range(
    of: "struct FullscreenVideoPlaybackView"
)!.lowerBound
let publicWorkspace = String(workspace[..<fullscreenStart])

precondition(publicWorkspace.contains("let onCorrectPPoints: () -> Void"))
precondition(publicWorkspace.contains("Text(\"修正 P 点\")"))
precondition(publicWorkspace.contains("Text(\"画线\")"))
precondition(!publicWorkspace.contains("选择拍摄视角"))
precondition(!publicWorkspace.contains("title: \"正后方 DTL\""))
precondition(!publicWorkspace.contains("title: \"正面 Face-on\""))
precondition(!publicWorkspace.contains("SimplifiedSwingFeedbackView("))
precondition(!publicWorkspace.contains("trajectoryCategory:"))
```

- [ ] **Step 7: Run core surface, P-point, drawing, and build regressions**

Run:

```bash
xcrun swiftc -parse-as-library \
  Tests/CoreAnalysisSurfaceSmoke.swift \
  -o /tmp/swingarc-core-analysis-surface-smoke
/tmp/swingarc-core-analysis-surface-smoke

xcrun swiftc -parse-as-library \
  Tests/PhoneCorrectionIntegrationSourceSmoke.swift \
  -o /tmp/swingarc-phone-correction-source-smoke
/tmp/swingarc-phone-correction-source-smoke

xcrun swiftc -parse-as-library \
  SwingArc/Models/PPointCorrectionState.swift \
  Tests/PPointCorrectionStateSmoke.swift \
  -o /tmp/swingarc-p-point-correction-smoke
/tmp/swingarc-p-point-correction-smoke

xcrun swiftc -parse-as-library -framework SwiftUI \
  SwingArc/Models/DrawingModels.swift \
  Tests/DrawingDisplayPolicySmoke.swift \
  -o /tmp/swingarc-drawing-display-smoke
/tmp/swingarc-drawing-display-smoke

xcrun swiftc -parse-as-library -framework SwiftUI \
  SwingArc/Models/DrawingModels.swift \
  Tests/DrawingInteractionPolicySmoke.swift \
  -o /tmp/swingarc-drawing-interaction-smoke
/tmp/swingarc-drawing-interaction-smoke

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -jobs 1 \
  -project SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/SwingArcCoreAnalysisDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: all smoke executables exit `0`; Xcode prints `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit the core analysis surface**

```bash
git add \
  SwingArc/Views/AnalysisWorkspaceView.swift \
  SwingArc/Views/WorkspaceComponents.swift \
  SwingArc/Views/ContentView.swift \
  Tests/CoreAnalysisSurfaceSmoke.swift \
  Tests/PhoneCorrectionIntegrationSourceSmoke.swift
git commit -m "feat: focus analysis workspace on P points and drawing"
```

---

### Task 4: Add Camera Permission Recovery

**Files:**
- Create: `Tests/CameraAccessPolicySmoke.swift`
- Create: `Tests/CameraAccessSourceSmoke.swift`
- Modify: `SwingArc/Models/CameraRecordingReadiness.swift:1-16`
- Modify: `SwingArc/Views/CameraView.swift:1-220`
- Modify: `SwingArc/Views/CameraView.swift:225-310`
- Modify: `SwingArc/Views/ContentView.swift:1-45`
- Modify: `SwingArc/Views/ContentView.swift:176-190`
- Modify: `SwingArc/Views/ContentView.swift:530-565`

**Interfaces:**
- Consumes: `AVCaptureDevice.authorizationStatus(for:)`, `AVCaptureDevice.requestAccess(for:)`, `UIApplication.openSettingsURLString`, and the existing serialized `CameraRecordingReadiness`.
- Produces: `CameraAccessState`, `CameraAccessPresentation.canRecord(_:)`, `CameraAccessPresentation.title(for:)`, `CameraAccessPresentation.detail(for:)`, `CameraStateModel.accessState`, and Settings recovery for both camera denial and Photos add-only denial.

- [ ] **Step 1: Write failing camera-access tests**

Create `Tests/CameraAccessPolicySmoke.swift`:

```swift
import Foundation

@main
struct CameraAccessPolicySmoke {
    static func main() {
        precondition(!CameraAccessPresentation.canRecord(.checking))
        precondition(CameraAccessPresentation.canRecord(.ready))
        precondition(!CameraAccessPresentation.canRecord(.denied))
        precondition(!CameraAccessPresentation.canRecord(.unavailable))
        precondition(
            CameraAccessPresentation.title(for: .denied)
                == "需要相机权限"
        )
        precondition(
            CameraAccessPresentation.detail(for: .denied)
                .contains("设置")
        )
        precondition(
            CameraAccessPresentation.title(for: .unavailable)
                == "无法使用相机"
        )
    }
}
```

Create `Tests/CameraAccessSourceSmoke.swift`:

```swift
import Foundation

@main
struct CameraAccessSourceSmoke {
    static func main() throws {
        let camera = try String(
            contentsOfFile: "SwingArc/Views/CameraView.swift",
            encoding: .utf8
        )
        let content = try String(
            contentsOfFile: "SwingArc/Views/ContentView.swift",
            encoding: .utf8
        )

        precondition(camera.contains("AVCaptureDevice.authorizationStatus"))
        precondition(camera.contains("AVCaptureDevice.requestAccess"))
        precondition(camera.contains("UIApplication.openSettingsURLString"))
        precondition(camera.contains("CameraAccessPresentation.canRecord"))
        precondition(camera.contains("需要相机权限"))
        precondition(camera.contains("打开设置"))
        precondition(content.contains("showsSettingsAction"))
        precondition(content.contains("MediaExportError.photoPermissionDenied"))
        precondition(content.contains("UIApplication.openSettingsURLString"))
        precondition(content.contains("Button(\"打开设置\")"))
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/CameraRecordingReadiness.swift \
  Tests/CameraAccessPolicySmoke.swift \
  -o /tmp/swingarc-camera-access-policy-smoke

xcrun swiftc -parse-as-library \
  Tests/CameraAccessSourceSmoke.swift \
  -o /tmp/swingarc-camera-access-source-smoke
/tmp/swingarc-camera-access-source-smoke
```

Expected: the policy test fails to compile because camera-access types do not exist; the source test traps because permission request and Settings recovery are absent.

- [ ] **Step 3: Add the pure camera-access presentation policy**

Append to `SwingArc/Models/CameraRecordingReadiness.swift`:

```swift
enum CameraAccessState: Equatable {
    case checking
    case ready
    case denied
    case unavailable
}

enum CameraAccessPresentation {
    static func canRecord(_ state: CameraAccessState) -> Bool {
        state == .ready
    }

    static func title(for state: CameraAccessState) -> String {
        switch state {
        case .checking:
            return "正在检查相机权限"
        case .ready:
            return "相机已就绪"
        case .denied:
            return "需要相机权限"
        case .unavailable:
            return "无法使用相机"
        }
    }

    static func detail(for state: CameraAccessState) -> String {
        switch state {
        case .checking:
            return "请稍候"
        case .ready:
            return "可以开始录像"
        case .denied:
            return "请前往 iOS 设置允许 SwingArc 使用相机。"
        case .unavailable:
            return "此设备没有可用于录像的相机。"
        }
    }
}
```

- [ ] **Step 4: Request authorization before configuring the session**

Add to `CameraStateModel`:

```swift
@Published private(set) var accessState: CameraAccessState = .checking
```

Change `setupSession()` to:

```swift
func setupSession() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
        accessState = .ready
        configureSessionIfNeeded()
    case .notDetermined:
        accessState = .checking
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.accessState = .ready
                    self.configureSessionIfNeeded()
                } else {
                    self.accessState = .denied
                }
            }
        }
    case .denied, .restricted:
        accessState = .denied
    @unknown default:
        accessState = .unavailable
    }
}
```

Move the existing session setup body into:

```swift
private func configureSessionIfNeeded() {
    guard session.inputs.isEmpty else { return }

    session.beginConfiguration()
    session.sessionPreset = .high

    guard let camera = AVCaptureDevice.default(
        .builtInWideAngleCamera,
        for: .video,
        position: .back
    ) else {
        session.commitConfiguration()
        accessState = .unavailable
        return
    }

    do {
        let input = try AVCaptureDeviceInput(device: camera)
        if session.canAddInput(input) {
            session.addInput(input)
            activeVideoInput = input
        }
        configureHighFrameRate(for: camera)
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        configureVisualOutput()
        session.commitConfiguration()
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    } catch {
        session.commitConfiguration()
        accessState = .unavailable
    }
}
```

Remove the duplicated `guard session.inputs.isEmpty`.

- [ ] **Step 5: Present denial and Settings recovery in `CameraView`**

Add:

```swift
import UIKit
```

Add:

```swift
@Environment(\.openURL) private var openURL
```

Place this above the capture guide:

```swift
if cameraState.accessState != .ready {
    Color.black.opacity(0.72).ignoresSafeArea()
    VStack(spacing: 16) {
        if cameraState.accessState == .checking {
            ProgressView()
                .tint(AnalysisTheme.proTourSignal)
        } else {
            Image(systemName: "camera.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AnalysisTheme.proTourSignal)
        }

        Text(CameraAccessPresentation.title(for: cameraState.accessState))
            .font(.title2.bold())

        Text(CameraAccessPresentation.detail(for: cameraState.accessState))
            .multilineTextAlignment(.center)
            .foregroundStyle(AnalysisTheme.proTourSecondaryText)

        if cameraState.accessState == .denied {
            Button("打开设置") {
                guard let url = URL(
                    string: UIApplication.openSettingsURLString
                ) else { return }
                openURL(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(AnalysisTheme.proTourSignal)
        }
    }
    .foregroundStyle(AnalysisTheme.proTourPrimaryText)
    .padding(28)
    .background(
        AnalysisTheme.proTourSurface,
        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
    .padding(24)
    .zIndex(10)
}
```

Add to the capture button:

```swift
.disabled(!CameraAccessPresentation.canRecord(cameraState.accessState))
```

Guard `startRecording()`:

```swift
guard CameraAccessPresentation.canRecord(cameraState.accessState) else {
    return
}
```

- [ ] **Step 6: Add Photos export permission recovery**

In `ContentView`, add:

```swift
import UIKit
```

Add:

```swift
@Environment(\.openURL) private var openURL
@State private var showsSettingsAction = false
```

Replace the alert buttons with:

```swift
if showsSettingsAction {
    Button("打开设置") {
        guard let url = URL(
            string: UIApplication.openSettingsURLString
        ) else { return }
        openURL(url)
    }
}
Button("好", role: .cancel) {
    showsSettingsAction = false
}
```

In the `performMediaAction` catch block, use:

```swift
} catch {
    if case MediaExportError.photoPermissionDenied = error {
        showsSettingsAction = true
    } else {
        showsSettingsAction = false
    }
    statusMessage = error.localizedDescription
}
```

Every unrelated status-message assignment must set `showsSettingsAction = false` before presenting its alert so a previous permission denial cannot leak a Settings button into a later error.

- [ ] **Step 7: Run access, readiness, timing, and build regressions**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/CameraRecordingReadiness.swift \
  Tests/CameraAccessPolicySmoke.swift \
  -o /tmp/swingarc-camera-access-policy-smoke
/tmp/swingarc-camera-access-policy-smoke

xcrun swiftc -parse-as-library \
  Tests/CameraAccessSourceSmoke.swift \
  -o /tmp/swingarc-camera-access-source-smoke
/tmp/swingarc-camera-access-source-smoke

xcrun swiftc -parse-as-library \
  SwingArc/Models/CameraRecordingReadiness.swift \
  Tests/CameraRecordingReadinessSmoke.swift \
  -o /tmp/swingarc-camera-readiness-smoke
/tmp/swingarc-camera-readiness-smoke

xcrun swiftc -parse-as-library -framework SwiftUI \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  SwingArc/Services/SwingInputQualityEvaluator.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingTechniqueEvaluator.swift \
  SwingArc/Models/PracticeModels.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Models/WorkspaceModels.swift \
  Tests/ManualCaptureTimingSmoke.swift \
  -o /tmp/swingarc-manual-capture-timing-smoke
/tmp/swingarc-manual-capture-timing-smoke \
  SwingArc/Views/CameraView.swift

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -jobs 1 \
  -project SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/SwingArcCameraAccessDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: all smoke executables exit `0`; Xcode prints `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit camera and export permission recovery**

```bash
git add \
  SwingArc/Models/CameraRecordingReadiness.swift \
  SwingArc/Views/CameraView.swift \
  SwingArc/Views/ContentView.swift \
  Tests/CameraAccessPolicySmoke.swift \
  Tests/CameraAccessSourceSmoke.swift
git commit -m "fix: recover from denied media permissions"
```

---

### Task 5: Align App Store Metadata, Privacy, Support, and Readiness Contracts

**Files:**
- Modify: `Tests/AppStoreReleaseReadinessSmoke.sh:1-76`
- Modify: `docs/app-store/metadata/zh-Hans.md:1-76`
- Modify: `docs/app-store/metadata/review-notes.md:1-28`
- Modify: `docs/app-store/privacy/index.html:21-71`
- Modify: `docs/app-store/support/index.html:20-46`
- Modify: `docs/app-store/submission-checklist.md:1-57`

**Interfaces:**
- Consumes: `AppInformation.privacyURL`, `AppInformation.supportURL`, approved core release scope, free price, iPhone-only target, iOS 17 floor, and current Apple submission constraints.
- Produces: core-only Simplified Chinese metadata, deterministic review notes, accurate public policy/support pages, and a readiness smoke that rejects deferred-feature claims.

- [ ] **Step 1: Strengthen the readiness smoke first**

After the existing path declarations in `Tests/AppStoreReleaseReadinessSmoke.sh`, add:

```bash
about_model="$root/SwingArc/Models/AppInformation.swift"
about_view="$root/SwingArc/Views/AboutPrivacyView.swift"
review_notes="$root/docs/app-store/metadata/review-notes.md"
checklist="$root/docs/app-store/submission-checklist.md"
```

Add file checks:

```bash
test -f "$about_model"
test -f "$about_view"
test -f "$review_notes"
test -f "$checklist"
```

Add build setting checks:

```bash
grep -q 'MARKETING_VERSION = 1.0;' "$project"
grep -q 'CURRENT_PROJECT_VERSION = 1;' "$project"
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.liangbo.swingarc;' "$project"
grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 17.0;' "$project"
grep -q 'INFOPLIST_KEY_CFBundleDisplayName = SwingArc;' "$project"
```

Add About link checks:

```bash
grep -q 'https://lb791203.github.io/SwingArc/app-store/privacy/' "$about_model"
grep -q 'https://lb791203.github.io/SwingArc/app-store/support/' "$about_model"
grep -q 'AboutPrivacyView.swift in Sources' "$project"
grep -q 'AppInformation.swift in Sources' "$project"
```

Add core metadata checks:

```bash
grep -q '手动录像' "$metadata"
grep -q 'P1–P8' "$metadata"
grep -q '专业画线' "$metadata"
grep -q '人工修正' "$metadata"
grep -q '免费' "$checklist"
grep -q 'ICP' "$checklist"
grep -q 'DSA' "$checklist"
```

Add forbidden-claim checks:

```bash
for file in "$metadata" "$review_notes" "$privacy_page" "$support_page"; do
  for forbidden in \
    '自动练习' \
    '技术评分' \
    '练习建议' \
    '挥杆轨迹' \
    '动作反馈' \
    '语音反馈'; do
    if grep -q "$forbidden" "$file"; then
      echo "Deferred feature claim '$forbidden' remains in $file" >&2
      exit 1
    fi
  done
done
```

- [ ] **Step 2: Run readiness and verify RED**

Run:

```bash
Tests/AppStoreReleaseReadinessSmoke.sh .
```

Expected: FAIL because current metadata/review/support pages still advertise automatic practice, technique feedback, or other deferred surfaces.

- [ ] **Step 3: Replace Simplified Chinese App Store positioning**

Keep the existing identifiers and URLs, but set:

```markdown
- 副标题：`专业画线与P1–P8分析`
```

Use this promotional text:

```markdown
用 iPhone 录制或导入挥杆视频，逐帧查看 P1–P8，并用直线、箭头、圆圈、量角器和手绘完成专业标注。所有视频与分析均保留在设备本地。
```

The description's exact core feature headings must be:

```markdown
• 手动录像与视频导入
• 慢动作与逐帧回放
• P1–P8 本地识别
• P 点人工修正
• 专业画线
• 本地记录与标注导出
```

The description must explicitly say:

```markdown
P6 和 P8 缺少可靠杆身证据时会显示“未识别”，SwingArc 不会用固定时间或视频百分比生成假结果。
```

Use these keywords:

```markdown
`高尔夫,挥杆分析,慢动作,P1P8,画线,量角器,录像,逐帧`
```

Set release notes to:

```markdown
首次发布：支持手动录像、视频导入、慢动作与逐帧回放、P1–P8 本地识别和人工修正、专业画线、本地项目记录及标注图片/视频导出。
```

Keep the no-account, no-tracking, on-device-processing, sports-reference, and automatic-result limitation statements. Remove every deferred-feature claim.

- [ ] **Step 4: Replace App Review notes with the deterministic core path**

The review path must be:

```markdown
1. Launch SwingArc.
2. Choose **手动录像** (Manual Recording), grant camera access, record a short clip, and stop; or choose **导入视频** (Import Video) and select a human-motion or golf-swing video from Photos.
3. The local P1–P8 analysis starts automatically.
4. Use the P1–P8 strip to inspect recognized and unresolved stages.
5. Tap **修正 P 点** to choose an exact source frame for a stage.
6. Tap **画线**, create a line or circle, switch to **选择**, and move the annotation.
7. Use **导出** to save/share an annotated frame or video.
8. Return home, open **记录**, reopen the project, and verify the correction and drawing remain; the project can also be deleted there.
```

State that the App uses no login, subscription, IAP, external hardware, microphone, analytics, tracking, or in-App network service. Remove the automatic-practice section.

- [ ] **Step 5: Update public privacy and support pages**

In both Chinese and English privacy sections:

- Change the effective date to July 28, 2026.
- Describe only user-started manual recording and user-selected Photos import/export.
- Replace “技术反馈 / technique analysis” with “P1–P8 阶段识别 / P1–P8 stage detection”.
- Keep local processing, project deletion, uninstall deletion, permission revocation, and contact details.

In Support:

- Change the camera answer to manual recording only.
- State that denied camera access can be restored through iOS Settings.
- Describe unresolved P points and manual correction.
- Keep the no-upload and no-microphone statements.
- Remove automatic-practice wording.

- [ ] **Step 6: Update the submission checklist**

The checklist must require:

```markdown
- [x] 首发范围：手动录像、视频导入、回放、P1–P8、人工修正、画线、记录和导出。
- [x] 价格：免费；无内购、订阅或付费墙。
- [ ] 欧盟销售范围启用前，账号持有人已完成真实的 DSA trader / non-trader 声明。
- [ ] 中国大陆暂不启用：尚无有效 ICP 备案号；取得备案并核对简体中文元数据后再开放。
- [ ] 使用公开版、App Store 支持的 Xcode 和 iOS 26 SDK 或更高版本归档。
- [ ] TestFlight 处理后的同一构建已完成真机全流程验收。
```

Replace screenshot suggestions with:

1. two-card home plus Records;
2. P1–P8 analysis strip;
3. exact-frame P-point correction;
4. drawing and selection/movement;
5. local Records and annotated export.

Remove automatic-practice, DTL/Face-on, technique-feedback, trajectory, and pose-overlay screenshot suggestions.

- [ ] **Step 7: Run readiness and local page validation**

Run:

```bash
Tests/AppStoreReleaseReadinessSmoke.sh .

rg -n \
  'SwingArc 隐私政策|SwingArc Privacy Policy' \
  docs/app-store/privacy/index.html
rg -n \
  '手动录像|Manual Recording|打开设置' \
  docs/app-store/support/index.html

git diff --check -- \
  Tests/AppStoreReleaseReadinessSmoke.sh \
  docs/app-store
```

Expected: readiness prints `App Store release readiness smoke: PASS`; both local HTML files contain the required core wording; `git diff --check` prints nothing. Live URL verification happens after the main-branch Pages deployment in Task 6.

- [ ] **Step 8: Commit the App Store package**

```bash
git add \
  Tests/AppStoreReleaseReadinessSmoke.sh \
  docs/app-store/metadata/zh-Hans.md \
  docs/app-store/metadata/review-notes.md \
  docs/app-store/privacy/index.html \
  docs/app-store/support/index.html \
  docs/app-store/submission-checklist.md
git commit -m "docs: align App Store package with core release"
```

---

### Task 6: Complete Release Verification, TestFlight, and App Store Submission

**Files:**
- Create after evidence exists: `docs/validation/app-store-core-release-2026-07-28.md`
- Modify after actual completion: `docs/app-store/submission-checklist.md`

**Interfaces:**
- Consumes: all Tasks 1–5, public Xcode with iOS 26 SDK or later, Apple Developer team `RCP42Y96T8`, App Store Connect app record for `com.liangbo.swingarc`, a physical iPhone, and account-holder compliance answers.
- Produces: validated Release archive, processed TestFlight build `1.0 (1)`, physical-device evidence, five core screenshots, completed metadata, submitted App Review version, and explicit China-mainland ICP status.

- [ ] **Step 1: Run the complete focused automated gate**

Run every smoke introduced by Tasks 1–5, followed by the existing critical regressions:

```bash
Tests/AppStoreReleaseReadinessSmoke.sh .

xcrun swiftc -parse-as-library \
  Tests/CoreReleaseHomeSurfaceSmoke.swift \
  -o /tmp/swingarc-core-home-smoke &&
  /tmp/swingarc-core-home-smoke

xcrun swiftc -parse-as-library \
  SwingArc/Models/AppInformation.swift \
  Tests/AppInformationSmoke.swift \
  -o /tmp/swingarc-app-information-smoke &&
  /tmp/swingarc-app-information-smoke

xcrun swiftc -parse-as-library \
  Tests/AboutPrivacySourceSmoke.swift \
  -o /tmp/swingarc-about-source-smoke &&
  /tmp/swingarc-about-source-smoke

xcrun swiftc -parse-as-library \
  Tests/CoreAnalysisSurfaceSmoke.swift \
  -o /tmp/swingarc-core-analysis-surface-smoke &&
  /tmp/swingarc-core-analysis-surface-smoke

xcrun swiftc -parse-as-library \
  Tests/PhoneCorrectionIntegrationSourceSmoke.swift \
  -o /tmp/swingarc-phone-correction-source-smoke &&
  /tmp/swingarc-phone-correction-source-smoke

xcrun swiftc -parse-as-library \
  SwingArc/Models/PPointCorrectionState.swift \
  Tests/PPointCorrectionStateSmoke.swift \
  -o /tmp/swingarc-p-point-correction-smoke &&
  /tmp/swingarc-p-point-correction-smoke

xcrun swiftc -parse-as-library -framework SwiftUI \
  SwingArc/Models/DrawingModels.swift \
  Tests/DrawingDisplayPolicySmoke.swift \
  -o /tmp/swingarc-drawing-display-smoke &&
  /tmp/swingarc-drawing-display-smoke

xcrun swiftc -parse-as-library -framework SwiftUI \
  SwingArc/Models/DrawingModels.swift \
  Tests/DrawingInteractionPolicySmoke.swift \
  -o /tmp/swingarc-drawing-interaction-smoke &&
  /tmp/swingarc-drawing-interaction-smoke

xcrun swiftc -parse-as-library \
  SwingArc/Models/CameraRecordingReadiness.swift \
  Tests/CameraAccessPolicySmoke.swift \
  -o /tmp/swingarc-camera-access-policy-smoke &&
  /tmp/swingarc-camera-access-policy-smoke

xcrun swiftc -parse-as-library \
  Tests/CameraAccessSourceSmoke.swift \
  -o /tmp/swingarc-camera-access-source-smoke &&
  /tmp/swingarc-camera-access-source-smoke

xcrun swiftc -parse-as-library \
  SwingArc/Models/CameraRecordingReadiness.swift \
  Tests/CameraRecordingReadinessSmoke.swift \
  -o /tmp/swingarc-camera-readiness-smoke &&
  /tmp/swingarc-camera-readiness-smoke

xcrun swiftc -parse-as-library -framework SwiftUI \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  SwingArc/Services/SwingInputQualityEvaluator.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingTechniqueEvaluator.swift \
  SwingArc/Models/PracticeModels.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Services/LocalProjectStore.swift \
  Tests/ProjectPersistenceSmoke.swift \
  -o /tmp/swingarc-project-persistence-smoke &&
  /tmp/swingarc-project-persistence-smoke

xcrun swiftc -parse-as-library -framework SwiftUI \
  SwingArc/Models/DrawingModels.swift \
  Tests/ManualStageLockSmoke.swift \
  -o /tmp/swingarc-manual-stage-lock-smoke &&
  /tmp/swingarc-manual-stage-lock-smoke

xcrun swiftc -parse-as-library -framework SwiftUI \
  SwingArc/Models/DrawingModels.swift \
  Tests/PStageSemanticsSmoke.swift \
  -o /tmp/swingarc-p-stage-semantics-smoke &&
  /tmp/swingarc-p-stage-semantics-smoke

xcrun swiftc -parse-as-library \
  Tests/AnalysisFailureSourceContractSmoke.swift \
  -o /tmp/swingarc-analysis-failure-source-smoke &&
  /tmp/swingarc-analysis-failure-source-smoke

xcrun swiftc -parse-as-library -framework SwiftUI \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Services/MediaExportService.swift \
  Tests/MediaExportFormatSmoke.swift \
  -o /tmp/swingarc-media-export-smoke &&
  /tmp/swingarc-media-export-smoke

xcrun swiftc -parse-as-library -framework SwiftUI \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  SwingArc/Services/SwingInputQualityEvaluator.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingTechniqueEvaluator.swift \
  SwingArc/Models/PracticeModels.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Models/WorkspaceModels.swift \
  Tests/MultiJointStageDetectorSmoke.swift \
  -o /tmp/swingarc-multijoint-stage-smoke &&
  /tmp/swingarc-multijoint-stage-smoke
```

Expected: every focused smoke exits `0`; readiness prints PASS.

- [ ] **Step 2: Run a clean development Release build**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -jobs 1 \
  -project SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/SwingArcCoreReleaseDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`. This proves compilation only; it is not the App Store archive.

- [ ] **Step 3: Integrate the release branch and deploy the public policy pages**

First require a clean tracked worktree while preserving unrelated untracked files:

```bash
test -z "$(git status --porcelain --untracked-files=no)"
git fetch origin
git merge --no-edit origin/main
```

If the merge reports a conflict, resolve only the conflicting tracked release files, preserve both the approved core-release intent and newer `main` changes, then rerun Step 1 and Step 2 before continuing.

Push the complete release branch and open a reviewed pull request:

```bash
git push origin codex/precision-swing-analysis
gh pr create \
  --base main \
  --head codex/precision-swing-analysis \
  --title "Release SwingArc 1.0 core analysis scope" \
  --body "Limits the public App Store surface to manual recording, video import, local records, P1-P8 detection and correction, drawing, and export. Includes local privacy/support pages and release gates."
gh pr checks codex/precision-swing-analysis --watch
gh pr merge codex/precision-swing-analysis \
  --merge \
  --delete-branch=false
git fetch origin
git merge-base --is-ancestor HEAD origin/main
```

Expected: the pull request is merged, every required check passes, and the release branch tip is an ancestor of `origin/main`.

Enable GitHub Pages from `main:/docs`. Use `PUT` if the site now exists, otherwise create it with `POST`:

```bash
if gh api repos/lb791203/SwingArc/pages \
  >/tmp/swingarc-pages-state.json 2>/dev/null; then
  gh api --method PUT repos/lb791203/SwingArc/pages \
    -f 'source[branch]=main' \
    -f 'source[path]=/docs'
else
  gh api --method POST repos/lb791203/SwingArc/pages \
    -f 'source[branch]=main' \
    -f 'source[path]=/docs'
fi

for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
  pages_status="$(
    gh api repos/lb791203/SwingArc/pages --jq '.status'
  )"
  test "$pages_status" = "built" && break
  sleep 10
done
test "$(
  gh api repos/lb791203/SwingArc/pages --jq '.status'
)" = "built"
```

Verify the live URLs and their actual content:

```bash
curl -fsS \
  https://lb791203.github.io/SwingArc/app-store/privacy/ \
  | rg 'SwingArc 隐私政策'
curl -fsS \
  https://lb791203.github.io/SwingArc/app-store/support/ \
  | rg '手动录像'
if curl -fsS \
  https://lb791203.github.io/SwingArc/app-store/support/ \
  | rg -q '自动练习'; then
  echo "Deferred automatic-practice claim remains on the live support page." >&2
  exit 1
fi
```

Expected: both URLs return successful content from the merged release commit, and the live support page contains no automatic-practice claim. Do not submit App Store Connect URLs while they return `404`.

- [ ] **Step 4: Install and verify a public submission toolchain**

The current machine has only `/Applications/Xcode-beta.app` (`Xcode 27.0`, build `27A5228h`). Before archiving, install a public App Store-supported Xcode at `/Applications/Xcode.app`.

Run:

```bash
test -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -version
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun --sdk iphoneos --show-sdk-version
```

Expected: a public Xcode release and iPhoneOS SDK `26.0` or later. Confirm the exact Xcode release is listed by Apple for App Store customer distribution. Do not proceed with the beta archive.

- [ ] **Step 5: Create and validate the signed archive**

Refuse to overwrite an existing archive path:

```bash
test ! -e /tmp/SwingArc-1.0-build1.xcarchive || {
  echo "/tmp/SwingArc-1.0-build1.xcarchive already exists; choose a new explicit archive path." >&2
  exit 1
}
```

Archive:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -jobs 1 \
  -project SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/SwingArc-1.0-build1.xcarchive \
  archive
```

Inspect:

```bash
plutil -p \
  /tmp/SwingArc-1.0-build1.xcarchive/Products/Applications/SwingArcProject.app/Info.plist
codesign -dvvv \
  /tmp/SwingArc-1.0-build1.xcarchive/Products/Applications/SwingArcProject.app \
  2>&1
```

Expected:

- archive succeeds;
- display name `SwingArc`;
- `CFBundleShortVersionString` is `1.0`;
- `CFBundleVersion` is `1`;
- bundle identifier is `com.liangbo.swingarc`;
- minimum OS is iOS 17;
- archive is signed for team `RCP42Y96T8`;
- no microphone usage description exists;
- `PrivacyInfo.xcprivacy`, App icon, and Launch Screen are present.

Open the archive in the public Xcode Organizer, choose **Validate App**, and require `Validation Successful` with no unresolved errors.

- [ ] **Step 6: Upload build 1 to App Store Connect and wait for processing**

Upload with the checked-in configuration:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -exportArchive \
  -archivePath /tmp/SwingArc-1.0-build1.xcarchive \
  -exportOptionsPlist docs/app-store/ExportOptions-TestFlight.plist \
  -exportPath /tmp/SwingArc-1.0-build1-upload
```

Expected: upload succeeds. Wait until App Store Connect shows build `1.0 (1)` as processed with no invalid-binary state. If Apple fully processes build 1 and a replacement is needed, increment `CURRENT_PROJECT_VERSION` before the next upload; never overwrite a processed build number.

- [ ] **Step 7: Perform physical-iPhone acceptance on the processed TestFlight build**

Install the processed TestFlight build, not a local development build. Verify and record:

1. clean install and launch;
2. exactly Manual Recording, Import Video, Records, and About/Privacy are reachable from home;
3. camera allow path;
4. camera deny path and **打开设置** recovery;
5. manual record, early stop, and automatic 15-second stop;
6. Photos video import;
7. automatic P1–P8 analysis begins after both capture and import;
8. complete, low-confidence, and unresolved P stages display honestly;
9. unresolved P6/P8 are not fabricated when shaft evidence is absent;
10. exact-frame P-point correction;
11. reanalysis preserves manual P points;
12. line, arrow, circle, angle, and freehand creation;
13. selection, whole-element movement, supported control-point adjustment, undo, and clear confirmation;
14. normal playback, slow playback, scrub, and exact frame stepping;
15. save/share annotated frame and annotated video;
16. project persistence after App termination and relaunch;
17. project deletion removes the local project/video;
18. privacy and support links open the correct pages;
19. no microphone prompt, coaching UI, automatic-practice UI, trajectory UI, pose switches, debug UI, network upload, or crash.

Repeat export with Photos permission denied and repeat a save with constrained device storage if safely reproducible. The original project must remain intact.

- [ ] **Step 8: Capture the five App Store screenshots**

Use a supported 6.9-inch screenshot size listed by Apple, with PNG/JPEG and no alpha. Capture real release UI:

1. two-card home with Records;
2. P1–P8 analysis strip with a mix of recognized/unresolved states;
3. exact-frame P-point correction;
4. drawing plus selection/movement;
5. local Records and export.

Do not show personal notifications, third-party videos without rights, debug controls, automatic practice, coaching, or unsupported accuracy claims.

- [ ] **Step 9: Complete App Store Connect**

The Account Holder/Admin/App Manager must:

1. create or verify the SwingArc iOS App record;
2. set Bundle ID `com.liangbo.swingarc`, version `1.0`, and a unique SKU;
3. select build `1.0 (1)`;
4. set price to Free with no IAP/subscriptions;
5. select Public Distribution;
6. enable all intended countries/regions except China mainland;
7. complete the actual EU DSA trader/non-trader declaration before enabling EU regions;
8. keep China mainland disabled because no valid ICP filing exists;
9. set primary category Sports and secondary category Photo & Video;
10. paste the checked-in Simplified Chinese metadata;
11. upload the five screenshots;
12. set the privacy answer to no data collection only after confirming the binary has no analytics/tracking SDK;
13. complete the current age-rating questionnaire truthfully;
14. enter a reachable App Review contact phone directly in App Store Connect; do not store it in the repository;
15. paste the checked-in review notes;
16. accept current agreements and complete required tax/banking/compliance screens;
17. select manual release after approval.

For China mainland, record this explicit state: `Blocked — valid ICP filing number not yet available`. After obtaining the ICP number, verify that the filing entity, App name, and Simplified Chinese metadata match, enter it under App Information, wait for Apple verification, then enable China mainland. Apple permits availability changes after release; no fake ICP data is allowed.

- [ ] **Step 10: Submit for App Review and record the exact result**

In App Store Connect:

1. click **Add for Review**;
2. review the draft submission;
3. click **Submit for Review**;
4. record the resulting status and submission timestamp;
5. monitor App Review messages and respond only with evidence-backed statements from the release build.

Expected initial state: `Waiting for Review` or the current equivalent. China mainland remains unavailable until ICP verification.

- [ ] **Step 11: Write and commit actual release evidence**

Create `docs/validation/app-store-core-release-2026-07-28.md` only after the preceding steps have real evidence. It must contain:

- commit SHA and clean/dirty worktree inventory;
- public Xcode version/build and SDK version;
- every automated command and pass/fail result;
- archive path, bundle/version/build/team inspection;
- validation and upload result;
- App Store Connect processing state;
- physical iPhone model, iOS version, TestFlight build, and each acceptance result;
- screenshot filenames, dimensions, and content;
- metadata/privacy/age/price/territory/DSA completion;
- App Review submission status and timestamp;
- China mainland status exactly as blocked or verified, with no invented filing number;
- a clear separation of confirmed, partial, blocked, and not tested.

Then update only completed boxes in `docs/app-store/submission-checklist.md`.

Commit:

```bash
git add \
  docs/validation/app-store-core-release-2026-07-28.md \
  docs/app-store/submission-checklist.md
git commit -m "docs: record SwingArc 1.0 release evidence"
```

Do not mark physical-device, TestFlight, App Review, DSA, or China ICP gates complete without direct evidence.

---

## Plan Self-Review

- Spec coverage: home, import/capture, core workspace, conservative P1–P8 behavior, manual correction, drawing, persistence/export, privacy/support, errors, metadata, build, TestFlight, device acceptance, pricing, regions, DSA, and China ICP are each assigned to a task.
- Scope: one coordinated iPhone 1.0 release; deferred modules remain in source but leave the public UI and metadata.
- Type consistency: `AppInformation`, `AboutPrivacyView`, `CameraAccessState`, `CameraAccessPresentation`, and all callback names are introduced before later use.
- Current blockers are explicit rather than hidden: only Xcode 27 beta is installed; public Xcode is required for the customer archive; GitHub Pages is not configured and the proposed URLs currently return `404`; China mainland cannot be enabled until a valid ICP filing is verified.
- No task authorizes fake P points, fake compliance data, unsupported accuracy claims, or marking tests complete without evidence.

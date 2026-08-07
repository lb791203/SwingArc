# DTL / FO Fullscreen Replay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver full-screen replay with a central Chinese feedback pill, a tappable silhouette phase rail, and a separate DTL / FO configuration page without weakening evidence rules.

**Architecture:** Keep `VideoPlaybackManager` as the only `AVPlayer` owner. Persist feedback configuration in the existing local project payload; place pure profile, availability, phase-appearance and tap-routing policy in `WorkspaceModels.swift`; compose UI in the existing `WorkspaceComponents.swift` and `AnalysisWorkspaceView.swift` so the external Xcode project needs no new file references.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Vision, Foundation, Xcode Beta iPhone 17 simulator (`90A656D1-01D1-44FB-B9D2-2FFD811F24C3`).

## Global Constraints

- Keep all media and analysis on-device. Do not add cloud inference, accounts, scores, or rankings.
- DTL and FO are separate profiles; changing the view replaces groups, metrics, stages and evidence requirements.
- Use only approved labels: 瞄准、髋部前倾、髋部深度、膝屈、手位、挥杆平面、手部路径、脊柱稳定、头部位置、髋位、胸位、站距、释放、脊柱侧倾、前导肩、前导髋。
- Replay has no permanent play/pause button, time strings, start/end times, or standalone feedback-settings button.
- Video tap toggles playback; feedback-pill tap opens configuration; silhouette tap seeks to a stage. Each target must be at least 44 pt and must not overlap another target.
- Confirmed phases are normal opacity, low-confidence phases are subdued, and missing phases are omitted. No technical result is inferred from an omitted phase.
- `下杆滞后` and `击球杆身前倾` require club-and-impact evidence; 2D body pose alone must leave them unavailable.
- Keep manual P-point navigation and drawing. A manual frame without usable pose evidence cannot create a technique finding.
- Simulator review is mandatory before physical-device installation.

## File Structure

- `SwingArc/Models/DrawingModels.swift` — make `SwingStage` Codable without changing existing raw values.
- `SwingArc/Models/WorkspaceModels.swift` — profiles, labels, availability, rail appearance and input routing.
- `SwingArc/Services/LocalProjectStore.swift` — optional feedback-configuration persistence.
- `SwingArc/Views/ContentView.swift` — restore and save configuration and camera-view context.
- `SwingArc/Views/WorkspaceComponents.swift` — feedback configuration screen and silhouette rail.
- `SwingArc/Views/AnalysisWorkspaceView.swift` — true full-screen player composition.
- `Tests/FeedbackProfileSmoke.swift` — profiles, terminology, evidence availability and persistence DTO coverage.
- `Tests/FullscreenReplayPolicySmoke.swift` — phase appearance and tap routing.
- `Tests/ProjectPersistenceSmoke.swift` — legacy and configured project round trips.
- `docs/validation/dtl-fo-fullscreen-replay-simulator.md` — real simulator validation record.

---

### Task 1: Create profiles and persist feedback configuration

**Files:**
- Modify: `SwingArc/Models/DrawingModels.swift`
- Modify: `SwingArc/Models/WorkspaceModels.swift`
- Modify: `SwingArc/Services/LocalProjectStore.swift`
- Create: `Tests/FeedbackProfileSmoke.swift`
- Modify: `Tests/ProjectPersistenceSmoke.swift`

**Interfaces:**
- Produces `FeedbackMetric`, `FeedbackEvidenceRequirement`, `FeedbackProfile`, `FeedbackCheckpoint`, `FeedbackConfiguration`, `FeedbackAvailability` and `SwingFeedbackProfiles.profile(for:)`.
- Extends `LocalAnalysisProject` with `feedbackConfiguration: FeedbackConfiguration?`.

- [ ] **Step 1: Write the failing profile test.**

Create `Tests/FeedbackProfileSmoke.swift`:

```swift
import Foundation

@main
struct FeedbackProfileSmoke {
    static func main() {
        let dtl = SwingFeedbackProfiles.profile(for: .downTheLine)
        precondition(dtl.groups[0].title == "准备姿势")
        precondition(dtl.metric(.swingPlane)?.title == "挥杆平面")
        precondition(dtl.metric(.swingPlane)?.stages == [.takeaway, .leadArmParallelBackswing, .leadArmParallelDownswing, .followThrough])
        precondition(dtl.metric(.spineStability)?.title == "脊柱稳定")

        let faceOn = SwingFeedbackProfiles.profile(for: .faceOn)
        precondition(faceOn.metric(.spineTilt)?.title == "脊柱侧倾")
        precondition(faceOn.metric(.leadShoulder)?.stages == [.top, .impact])
        precondition(faceOn.metric(.clubRelease)?.title == "释放")

        let configuration = FeedbackConfiguration.defaultValue(for: .faceOn)
        precondition(configuration.activeMetric == .spineTilt)
        precondition(configuration.enabledCheckpoints.contains(.init(metric: .spineTilt, stage: .top)))
        precondition(FeedbackAvailability.resolve(metric: .clubRelease, analysis: .idle, sourceFrameRate: 240) == .unavailable("需要可靠的杆头与击球证据"))
    }
}
```

Append this to `Tests/ProjectPersistenceSmoke.swift` after its existing save/load assertion:

```swift
let configuration = FeedbackConfiguration.defaultValue(for: .downTheLine)
let configured = LocalAnalysisProject(
    drawings: [], keyframes: [], isKeyframeMode: false,
    showPoseSkeleton: false, showHeadStability: false,
    showSpineAngle: false, showGrid: false,
    practiceCameraView: .downTheLine, stageCorrections: [],
    feedbackConfiguration: configuration
)
precondition(LocalProjectStore.save(configured, for: url, defaults: defaults))
precondition(LocalProjectStore.load(for: url, defaults: defaults)?.feedbackConfiguration == configuration)
```

- [ ] **Step 2: Verify RED.**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift SwingArc/Services/StageCalibration.swift SwingArc/Models/WorkspaceModels.swift Tests/FeedbackProfileSmoke.swift -o /tmp/swingarc-feedback-profile-red`

Expected: compilation fails because profile and configuration types do not exist.

- [ ] **Step 3: Implement types and fixed labels.**

Change only the declaration of the existing stage enum:

```swift
enum SwingStage: String, CaseIterable, Identifiable, Codable {
    // retain all existing cases and raw values unchanged
}
```

Append the following model types to `WorkspaceModels.swift`:

```swift
enum FeedbackMetric: String, CaseIterable, Codable, Equatable, Identifiable {
    case alignment, hipBend, hipDepth, kneeFlex, handPosition
    case swingPlane, handPath, spineStability, headPosition
    case hipPosition, chestPosition, stanceWidth, clubRelease
    case spineTilt, leadShoulder, leadHip
    var id: String { rawValue }
    var title: String {
        switch self {
        case .alignment: return "瞄准"
        case .hipBend: return "髋部前倾"
        case .hipDepth: return "髋部深度"
        case .kneeFlex: return "膝屈"
        case .handPosition: return "手位"
        case .swingPlane: return "挥杆平面"
        case .handPath: return "手部路径"
        case .spineStability: return "脊柱稳定"
        case .headPosition: return "头部位置"
        case .hipPosition: return "髋位"
        case .chestPosition: return "胸位"
        case .stanceWidth: return "站距"
        case .clubRelease: return "释放"
        case .spineTilt: return "脊柱侧倾"
        case .leadShoulder: return "前导肩"
        case .leadHip: return "前导髋"
        }
    }
}
enum FeedbackEvidenceRequirement: Equatable { case pose, clubAndImpact }
struct FeedbackMetricDefinition: Equatable { let metric: FeedbackMetric; let stages: [SwingStage]; let evidence: FeedbackEvidenceRequirement; var title: String { metric.title } }
struct FeedbackGroup: Equatable { let title: String; let metrics: [FeedbackMetricDefinition] }
struct FeedbackProfile: Equatable {
    let view: PracticeCameraView
    let groups: [FeedbackGroup]
    func metric(_ metric: FeedbackMetric) -> FeedbackMetricDefinition? { groups.lazy.flatMap(\.metrics).first { $0.metric == metric } }
}
struct FeedbackCheckpoint: Codable, Hashable, Equatable { let metric: FeedbackMetric; let stage: SwingStage }
struct FeedbackConfiguration: Codable, Equatable {
    var activeMetric: FeedbackMetric
    var enabledCheckpoints: Set<FeedbackCheckpoint>
    static func defaultValue(for view: PracticeCameraView) -> FeedbackConfiguration {
        switch view {
        case .downTheLine: return .init(activeMetric: .swingPlane, enabledCheckpoints: [.init(metric: .swingPlane, stage: .takeaway), .init(metric: .swingPlane, stage: .leadArmParallelDownswing)])
        case .faceOn: return .init(activeMetric: .spineTilt, enabledCheckpoints: [.init(metric: .spineTilt, stage: .top), .init(metric: .spineTilt, stage: .impact)])
        }
    }
}
enum FeedbackAvailability: Equatable {
    case available
    case unavailable(String)
    static func resolve(metric: FeedbackMetric, analysis: SwingAnalysisState, sourceFrameRate: Double) -> FeedbackAvailability {
        guard metric != .clubRelease else { return .unavailable("需要可靠的杆头与击球证据") }
        guard case let .completed(result) = analysis, result.detections.contains(where: { $0.status == .confirmed }), sourceFrameRate > 0 else { return .unavailable("当前画面证据不足") }
        return .available
    }
}
```

Implement `SwingFeedbackProfiles.profile(for:)` with this exact matrix:

| View | Group | Metrics | stages |
| --- | --- | --- | --- |
| DTL | 准备姿势 | 瞄准、髋部前倾、髋部深度、膝屈、手位 | P1 |
| DTL | 挥杆平面 | 挥杆平面 | P2、P3、P5、P7 |
| DTL | 手部路径、脊柱稳定 | one metric per group | P2、P3、P4、P5、P6、P7 |
| DTL | 头部位置 | 头部位置 | P1–P7 |
| FO | 准备姿势 | 髋位、胸位、手位、站距 | P1 |
| FO | 释放 | 释放 | P5、P6; `.clubAndImpact` |
| FO | 脊柱侧倾、前导髋 | one metric per group | P2、P3、P4、P5、P6、P7 |
| FO | 前导肩 | 前导肩 | P4、P6 |
| FO | 头部位置 | 头部位置 | P1–P7 |

Extend `LocalAnalysisProject` with this backward-compatible pattern:

```swift
var feedbackConfiguration: FeedbackConfiguration?
// add `case feedbackConfiguration` to CodingKeys
feedbackConfiguration: try container.decodeIfPresent(FeedbackConfiguration.self, forKey: .feedbackConfiguration)
try container.encodeIfPresent(feedbackConfiguration, forKey: .feedbackConfiguration)
```

Add `feedbackConfiguration: FeedbackConfiguration? = nil` to the initializer and assign it.

- [ ] **Step 4: Verify GREEN and commit.**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift SwingArc/Services/StageCalibration.swift SwingArc/Models/WorkspaceModels.swift Tests/FeedbackProfileSmoke.swift -o /tmp/swingarc-feedback-profile && /tmp/swingarc-feedback-profile`

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift SwingArc/Services/StageCalibration.swift SwingArc/Models/WorkspaceModels.swift SwingArc/Services/LocalProjectStore.swift Tests/ProjectPersistenceSmoke.swift -o /tmp/swingarc-project-persistence && /tmp/swingarc-project-persistence`

Run: `git add SwingArc/Models/DrawingModels.swift SwingArc/Models/WorkspaceModels.swift SwingArc/Services/LocalProjectStore.swift Tests/FeedbackProfileSmoke.swift Tests/ProjectPersistenceSmoke.swift && git commit -m "feat: add DTL FO feedback profiles"`

Expected: both test executables exit 0; old payloads decode with `feedbackConfiguration == nil` and configured payloads round-trip exactly.

### Task 2: Add replay routing and phase appearance policy

**Files:**
- Modify: `SwingArc/Models/WorkspaceModels.swift`
- Create: `Tests/FullscreenReplayPolicySmoke.swift`

**Interfaces:**
- Produces `FullscreenReplayTap`, `FullscreenReplayAction`, `FullscreenReplayPolicy.action(for:)`, `SwingPhaseAppearance`, and `SwingPhaseRailPolicy.appearance(for:hasMarker:)`.

- [ ] **Step 1: Write the failing policy test.**

```swift
import Foundation

@main
struct FullscreenReplayPolicySmoke {
    static func main() {
        precondition(FullscreenReplayPolicy.action(for: .video) == .togglePlayback)
        precondition(FullscreenReplayPolicy.action(for: .feedbackPill) == .openFeedback)
        precondition(FullscreenReplayPolicy.action(for: .phase(.top)) == .seek(.top))
        precondition(FullscreenReplayPolicy.action(for: .dismiss) == .dismiss)
        precondition(SwingPhaseRailPolicy.appearance(for: .confirmed, hasMarker: true) == .confirmed)
        precondition(SwingPhaseRailPolicy.appearance(for: .review, hasMarker: true) == .subdued)
        precondition(SwingPhaseRailPolicy.appearance(for: .unresolved, hasMarker: false) == .hidden)
        precondition(FullscreenPlaybackPolicy.minimumTouchTarget == 44)
        precondition(!FullscreenPlaybackPolicy.showsTimeLabels)
        precondition(!FullscreenPlaybackPolicy.showsTransportButtons)
    }
}
```

- [ ] **Step 2: Verify RED.**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift SwingArc/Services/StageCalibration.swift SwingArc/Models/WorkspaceModels.swift Tests/FullscreenReplayPolicySmoke.swift -o /tmp/swingarc-fullscreen-policy-red`

Expected: compilation fails because the new policy types and display flags do not exist.

- [ ] **Step 3: Implement the policy.**

```swift
enum FullscreenReplayTap: Equatable { case video, feedbackPill, phase(SwingStage), dismiss }
enum FullscreenReplayAction: Equatable { case togglePlayback, openFeedback, seek(SwingStage), dismiss }
enum FullscreenReplayPolicy {
    static func action(for tap: FullscreenReplayTap) -> FullscreenReplayAction {
        switch tap {
        case .video: return .togglePlayback
        case .feedbackPill: return .openFeedback
        case let .phase(stage): return .seek(stage)
        case .dismiss: return .dismiss
        }
    }
}
enum SwingPhaseAppearance: Equatable { case confirmed, subdued, hidden }
enum SwingPhaseRailPolicy {
    static func appearance(for state: StageResultState, hasMarker: Bool) -> SwingPhaseAppearance {
        guard hasMarker else { return .hidden }
        switch state {
        case .confirmed, .manual: return .confirmed
        case .review: return .subdued
        case .unresolved: return .hidden
        }
    }
}
```

Replace the full-screen policy with:

```swift
enum FullscreenPlaybackPolicy {
    static let autoHideDelay: TimeInterval = 2.5
    static let minimumTouchTarget: CGFloat = 44
    static let allowsDrawing = false
    static let showsWorkspaceChrome = false
    static let showsTimeLabels = false
    static let showsTransportButtons = false
}
```

- [ ] **Step 4: Verify GREEN and commit.**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift SwingArc/Services/StageCalibration.swift SwingArc/Models/WorkspaceModels.swift Tests/FullscreenReplayPolicySmoke.swift -o /tmp/swingarc-fullscreen-policy && /tmp/swingarc-fullscreen-policy`

Run: `git add SwingArc/Models/WorkspaceModels.swift Tests/FullscreenReplayPolicySmoke.swift && git commit -m "feat: define fullscreen replay interaction policy"`

Expected: smoke exits 0 and only policy/test files are committed.

### Task 3: Bind configuration through existing projects and build the feedback sheet

**Files:**
- Modify: `SwingArc/Views/ContentView.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `SwingArc/Views/WorkspaceComponents.swift`
- Modify: `Tests/ProjectPersistenceSmoke.swift`

**Interfaces:**
- `ContentView` owns `@State private var feedbackConfiguration: FeedbackConfiguration?`.
- `AnalysisWorkspaceView` and `FullscreenVideoPlaybackView` receive bindings to `practiceCameraView` and `feedbackConfiguration`.
- Produces `SwingFeedbackConfigurationView` with no embedded player.

- [ ] **Step 1: Write the failing legacy assertion.**

```swift
let legacy = LocalAnalysisProject(
    drawings: [], keyframes: [], isKeyframeMode: false,
    showPoseSkeleton: false, showHeadStability: false,
    showSpineAngle: false, showGrid: false
)
precondition(legacy.feedbackConfiguration == nil)
```

- [ ] **Step 2: Verify RED.**

Run the Task 1 persistence command. Expected: compilation fails until the optional field and initializer default exist.

- [ ] **Step 3: Wire state and implement the full-page configuration UI.**

In `ContentView`, add state beside `practiceCameraView`, reset it at the start of `loadVideoFromURL`, restore `saved.feedbackConfiguration`, and pass it to `LocalAnalysisProject` when persisting:

```swift
@State private var feedbackConfiguration: FeedbackConfiguration?

feedbackConfiguration = nil
feedbackConfiguration = saved.feedbackConfiguration
feedbackConfiguration: feedbackConfiguration
```

Pass `$practiceCameraView` and `$feedbackConfiguration` into `AnalysisWorkspaceView`, then forward the same bindings into `FullscreenVideoPlaybackView`. Do not infer the view from an imported file; if it is nil, configuration must require an explicit DTL or FO selection.

Add this public interface to `WorkspaceComponents.swift`:

```swift
struct SwingFeedbackConfigurationView: View {
    @Binding var practiceCameraView: PracticeCameraView?
    @Binding var configuration: FeedbackConfiguration?
    let analysisState: SwingAnalysisState
    let sourceFrameRate: Double
    let onDismiss: () -> Void
}
```

The body must use a full-page graphite layout with `关闭` and `帮助`, segmented labels `目标线视角` / `正面视角`, and no video. Changing the segment assigns `practiceCameraView`; if configuration is nil or its active metric is absent from the new profile, assign `FeedbackConfiguration.defaultValue(for: selectedView)`. Render each profile group and its metrics using `definition.title`; tapping a metric assigns it to `configuration.activeMetric`; render only its allowed stages as 44 pt checkpoint chips. Disable the `释放` chips when `FeedbackAvailability` is unavailable and show exactly `需要可靠的杆头与击球证据`.

Use this exact checkpoint helper:

```swift
private func toggle(_ checkpoint: FeedbackCheckpoint, for view: PracticeCameraView) {
    var value = configuration ?? FeedbackConfiguration.defaultValue(for: view)
    if value.enabledCheckpoints.contains(checkpoint) { value.enabledCheckpoints.remove(checkpoint) }
    else { value.enabledCheckpoints.insert(checkpoint) }
    configuration = value
}
```

- [ ] **Step 4: Verify GREEN and commit.**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift SwingArc/Services/StageCalibration.swift SwingArc/Models/WorkspaceModels.swift SwingArc/Services/LocalProjectStore.swift Tests/ProjectPersistenceSmoke.swift -o /tmp/swingarc-project-persistence && /tmp/swingarc-project-persistence`

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -jobs 1 -quiet -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj -scheme SwingArcProject -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=90A656D1-01D1-44FB-B9D2-2FFD811F24C3' build CODE_SIGNING_ALLOWED=NO`

Run: `git add SwingArc/Views/ContentView.swift SwingArc/Views/AnalysisWorkspaceView.swift SwingArc/Views/WorkspaceComponents.swift Tests/ProjectPersistenceSmoke.swift && git commit -m "feat: add full-page swing feedback configuration"`

Expected: existing projects still load, view choice remains explicit, and the full app builds.

### Task 4: Build the silhouette rail and pure full-screen replay

**Files:**
- Modify: `SwingArc/Views/WorkspaceComponents.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `Tests/FullscreenReplayPolicySmoke.swift`

**Interfaces:**
- Produces `SwingPhaseRailView(presentation:keyframes:currentTime:frameDuration:onSelect:)`.
- Fullscreen consumes the shared player, existing drawing bindings, feedback bindings and `onDismiss`.

- [ ] **Step 1: Add a policy assertion for no chrome controls.**

```swift
precondition(FullscreenReplayPolicy.action(for: .video) == .togglePlayback)
precondition(FullscreenReplayPolicy.action(for: .feedbackPill) == .openFeedback)
precondition(!FullscreenPlaybackPolicy.showsTimeLabels)
precondition(!FullscreenPlaybackPolicy.showsTransportButtons)
```

- [ ] **Step 2: Implement `SwingPhaseRailView`.**

For every `SwingStage.allCases`, build the existing `StageDisplayDescriptor`, map state through `SwingPhaseRailPolicy`, omit `.hidden`, render `.subdued` at opacity `0.45`, and render `.confirmed` with normal opacity. Each 44 pt `SwingPhaseSilhouette` button calls `onSelect(stage, descriptor.marker)`. Only `descriptor.isCurrent` receives a 1 pt white circular outline. Use `stage.shortName` only for VoiceOver; do not display P1–P8 text in the rail.

- [ ] **Step 3: Replace only full-screen replay controls.**

In `FullscreenVideoPlaybackView`, delete backward-frame, play/pause and forward-frame buttons. Keep transient close/help chrome, a feedback-pill button, and the silhouette rail. The pill body is:

```swift
Label(activeMetricTitle, systemImage: "ear.and.waveform")
    .font(.system(size: 18, weight: .semibold))
    .padding(.horizontal, 18)
    .frame(minHeight: 52)
    .background(AnalysisTheme.proTourSurface.opacity(0.92), in: Capsule())
    .accessibilityLabel("查看\(activeMetricTitle)参数")
```

`activeMetricTitle` returns the selected metric title when both view and configuration exist, otherwise `选择分析视角`. Pill tap presents `SwingFeedbackConfigurationView` in a `fullScreenCover`. Video tap remains behind overlays and performs:

```swift
if playbackManager.isPlaying { playbackManager.pause() } else { playbackManager.play() }
```

Silhouette selection pauses, seeks to an existing marker, and leaves transient chrome visible. Do not call manual adjustment or synthesize a missing phase. Keep drawing disabled in full screen and never create another player instance.

- [ ] **Step 4: Verify GREEN and commit.**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library SwingArc/Models/DrawingModels.swift SwingArc/Models/WorkspaceModels.swift Tests/FullscreenReplayPolicySmoke.swift -o /tmp/swingarc-fullscreen-policy && /tmp/swingarc-fullscreen-policy`

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -jobs 1 -quiet -derivedDataPath /tmp/SwingArcReplayDerivedData -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj -scheme SwingArcProject -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=90A656D1-01D1-44FB-B9D2-2FFD811F24C3' build CODE_SIGNING_ALLOWED=NO`

Run: `git add SwingArc/Views/WorkspaceComponents.swift SwingArc/Views/AnalysisWorkspaceView.swift Tests/FullscreenReplayPolicySmoke.swift && git commit -m "feat: deliver fullscreen replay controls"`

Expected: replay has no time strings or transport controls, but video, pill and silhouettes each retain their exclusive action.

### Task 5: Simulator-only acceptance record

**Files:**
- Create: `docs/validation/dtl-fo-fullscreen-replay-simulator.md`

**Interfaces:**
- Produces actual screenshot paths and pass/fail rows for replay interaction.

- [ ] **Step 1: Install the simulator build and capture evidence.**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun simctl install 90A656D1-01D1-44FB-B9D2-2FFD811F24C3 /tmp/SwingArcReplayDerivedData/Build/Products/Debug-iphonesimulator/SwingArcProject.app`

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun simctl launch 90A656D1-01D1-44FB-B9D2-2FFD811F24C3 com.liangbo.swingarc`

Capture these paths using `xcrun simctl io ... screenshot`:

```text
/tmp/swingarc-replay-fullscreen.png
/tmp/swingarc-replay-feedback-dtl.png
/tmp/swingarc-replay-feedback-faceon.png
/tmp/swingarc-replay-evidence-insufficient.png
```

- [ ] **Step 2: Record exact acceptance rows.**

Create a Markdown table for: video tap toggles play/pause; feedback pill opens the full-page sheet; no time labels or transport controls; DTL groups differ from FO groups; visible silhouettes seek to their marker; low-confidence silhouettes are subdued; missing stages are omitted; club release is unavailable without club/impact proof; configuration survives sheet dismissal; no physical-device installation occurred.

- [ ] **Step 3: Present simulator screenshots to the user and commit only after acceptance.**

Run: `git add docs/validation/dtl-fo-fullscreen-replay-simulator.md && git commit -m "docs: record fullscreen replay simulator review"`

Expected: user approval of the actual simulator UI precedes any real-device test.

## Plan Self-Review

- **Spec coverage:** Task 1 delivers Chinese DTL/FO profiles and evidence gates; Task 2 protects input and phase semantics; Task 3 preserves configuration with existing projects and delivers a no-video configuration page; Task 4 implements pure full-screen replay; Task 5 requires simulator evidence before device installation.
- **Placeholder scan:** Types, labels, profile matrix, exact unavailable message, input paths, commands, screenshots and commit scopes are all defined.
- **Type consistency:** `FeedbackConfiguration` is created in Task 1, owned by `ContentView` in Task 3, shown by `SwingFeedbackConfigurationView` in Task 3, and consumed by `FullscreenVideoPlaybackView` in Task 4. `SwingStage` remains the shared persistence/navigation identifier.

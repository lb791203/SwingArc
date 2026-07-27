# P1–P8 First-Pass Annotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the eight authoritative P1–P8 frames the default annotation queue for every clip while retaining the existing expanded training queue as an explicit option.

**Architecture:** Add a focused Mac-workspace queue-mode model/factory that produces either eight protected P-stage items or delegates unchanged to `GolfAnnotationFrameQueueBuilder`. The retained workspace controller owns the active mode, rebuilds queue/progress without changing decisions, and exposes a segmented mode selector through the timeline view.

**Tech Stack:** Swift 6, SwiftUI, Foundation, existing smoke-test executables compiled with `xcrun swiftc`, Xcode macOS application build.

## Global Constraints

- `p-point-truth.json`, prediction runs, anchors, and annotation revisions remain immutable.
- A new app session defaults to `pPointFirstPass`; changing clips preserves the in-memory active mode.
- Existing decisions outside the active queue remain stored and reappear in expanded mode.
- The existing expanded queue algorithm and sampling policy remain unchanged.
- No propagated coordinate may be written as human truth by this change.
- Every first-pass frame still requires explicit decisions for all five landmarks.

---

### Task 1: Deterministic Queue Modes

**Files:**
- Create: `SwingArcDataset/Models/DatasetAnnotationQueueMode.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`
- Create: `Tests/MacDatasetAnnotationQueueModeSmoke.swift`

**Interfaces:**
- Consumes: `GolfPPointTruthDocument`, `GolfPPointStageCode`, `GolfAnnotationQueueItem`, `GolfAnnotationFrameQueueBuilder`.
- Produces: `DatasetAnnotationQueueMode`, `DatasetAnnotationQueueFactory.make(mode:truth:split:totalFrames:)`.

- [ ] **Step 1: Write the failing queue-mode smoke test**

```swift
let stages = GolfPPointStageCode.allCases.enumerated().map {
    GolfPPointTruthStage(code: $0.element, sourceFrameIndex: 100 + $0.offset * 10)
}
let truth = GolfPPointTruthDocument(
    media: GolfPPointTruthMedia(
        sha256: String(repeating: "a", count: 64),
        timelineSHA256: String(repeating: "b", count: 64),
        frameCount: 300
    ),
    view: .dtl,
    stages: stages
)
let firstPass = DatasetAnnotationQueueFactory.make(
    mode: .pPointFirstPass,
    truth: truth,
    split: .training,
    totalFrames: 300
)
precondition(firstPass.map(\.sourceFrameIndex) == [100, 110, 120, 130, 140, 150, 160, 170])
precondition(firstPass.allSatisfy(\.isProtected))

let expanded = DatasetAnnotationQueueFactory.make(
    mode: .expandedTraining,
    truth: truth,
    split: .training,
    totalFrames: 300
)
let authoritativeExpanded = GolfAnnotationFrameQueueBuilder.build(
    input: GolfAnnotationQueueInput(
        split: .training,
        p1: 100,
        p5: 140,
        p6: 150,
        p8: 170,
        totalFrames: 300,
        anomalyFrames: [],
        preSwingNegativeSamples: [],
        postSwingNegativeSamples: []
    )
)
precondition(expanded == authoritativeExpanded)
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/GolfDatasetIdentity.swift \
  SwingArc/Services/GolfAnnotationFrameQueueBuilder.swift \
  SwingArcDataset/Models/DatasetAnnotationQueueMode.swift \
  Tests/MacDatasetAnnotationQueueModeSmoke.swift \
  -o /private/tmp/MacDatasetAnnotationQueueModeSmoke
```

Expected: compile failure because `DatasetAnnotationQueueMode.swift` and its types do not exist.

- [ ] **Step 3: Implement the minimal mode/factory**

```swift
import Foundation

public enum DatasetAnnotationQueueMode: String, CaseIterable, Sendable {
    case pPointFirstPass
    case expandedTraining

    public var displayName: String {
        switch self {
        case .pPointFirstPass: "P1–P8 首轮"
        case .expandedTraining: "扩展训练队列"
        }
    }
}

public enum DatasetAnnotationQueueFactory {
    public static func make(
        mode: DatasetAnnotationQueueMode,
        truth: GolfPPointTruthDocument,
        split: GolfDatasetSplit,
        totalFrames: Int
    ) -> [GolfAnnotationQueueItem] {
        switch mode {
        case .pPointFirstPass:
            let validStages = truth.stages.filter {
                (0..<totalFrames).contains($0.sourceFrameIndex)
            }
            let grouped = Dictionary(grouping: validStages, by: \.sourceFrameIndex)
            return grouped.keys.sorted().map {
                GolfAnnotationQueueItem(
                    sourceFrameIndex: $0,
                    reasons: [],
                    isProtected: true
                )
            }
        case .expandedTraining:
            return GolfAnnotationFrameQueueBuilder.build(
                input: GolfAnnotationQueueInput(
                    split: split,
                    p1: truth.frame(for: .p1),
                    p5: truth.frame(for: .p5),
                    p6: truth.frame(for: .p6),
                    p8: truth.frame(for: .p8),
                    totalFrames: totalFrames,
                    anomalyFrames: [],
                    preSwingNegativeSamples: [],
                    postSwingNegativeSamples: []
                )
            )
        }
    }
}
```

The store validator already requires exactly one ordered P1–P8 stage, so eight
items are mandatory for persisted production truth. The defensive grouping
prevents duplicate frame items if a synthetic caller supplies repeated indices.

- [ ] **Step 4: Add the new source to `SwingArcDataset` and run GREEN**

Add one `PBXFileReference`, one `PBXBuildFile`, the Models group entry, and the
SwingArcDataset Sources build-phase entry using new unique 24-character IDs.

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/GolfDatasetIdentity.swift \
  SwingArc/Services/GolfAnnotationFrameQueueBuilder.swift \
  SwingArcDataset/Models/DatasetAnnotationQueueMode.swift \
  Tests/MacDatasetAnnotationQueueModeSmoke.swift \
  -o /private/tmp/MacDatasetAnnotationQueueModeSmoke &&
/private/tmp/MacDatasetAnnotationQueueModeSmoke
```

Expected: `All dataset annotation queue-mode tests passed.`

- [ ] **Step 5: Commit the queue-mode unit**

```bash
git add \
  SwingArcDataset/Models/DatasetAnnotationQueueMode.swift \
  SwingArcProject.xcodeproj/project.pbxproj \
  Tests/MacDatasetAnnotationQueueModeSmoke.swift
git commit -m "feat: add P-point first-pass queue mode"
```

### Task 2: Controller Mode Switching and Progress

**Files:**
- Modify: `SwingArcDataset/Services/DatasetWorkspaceController.swift`
- Modify: `Tests/MacDatasetBlindModeSmoke.swift`
- Modify: `Tests/MacDatasetWorkspaceSourceSmoke.swift`

**Interfaces:**
- Consumes: `DatasetAnnotationQueueFactory.make(mode:truth:split:totalFrames:)`.
- Produces: `@Published public private(set) var annotationQueueMode`, `selectAnnotationQueueMode(_:)`.

- [ ] **Step 1: Add failing controller assertions**

Add assertions to the controller smoke that:

```swift
precondition(controller.annotationQueueMode == .pPointFirstPass)
precondition(controller.annotationState?.annotationQueue.count == 8)

let decisionsBeforeSwitch = controller.annotationState?.decisions
controller.selectAnnotationQueueMode(.expandedTraining)
precondition(controller.annotationQueueMode == .expandedTraining)
precondition((controller.annotationState?.annotationQueue.count ?? 0) > 8)
precondition(controller.annotationState?.decisions == decisionsBeforeSwitch)

controller.selectAnnotationQueueMode(.pPointFirstPass)
precondition(controller.annotationState?.annotationQueue.count == 8)
precondition(controller.annotationState?.decisions == decisionsBeforeSwitch)
```

Extend source-contract assertions with:

```swift
"annotationQueueMode",
"selectAnnotationQueueMode",
"DatasetAnnotationQueueFactory.make"
```

- [ ] **Step 2: Run RED**

Compile the controller smoke with the same source list used by
`MacDatasetBlindModeSmoke`, adding
`SwingArcDataset/Models/DatasetAnnotationQueueMode.swift`.

Expected: compile failure because the controller does not expose the mode or
switching method.

- [ ] **Step 3: Wire the controller**

Add:

```swift
@Published public private(set) var annotationQueueMode:
    DatasetAnnotationQueueMode = .pPointFirstPass
```

Replace controller-local queue creation with:

```swift
DatasetAnnotationQueueFactory.make(
    mode: annotationQueueMode,
    truth: truth,
    split: split,
    totalFrames: totalFrames
)
```

Implement mode switching by:

1. returning early when the requested mode is already active;
2. incrementing `frameLoadGeneration`;
3. setting `annotationQueueMode`;
4. rebuilding all sidebar progress for the new mode;
5. rebuilding `DatasetAnnotationState` with the same prediction, parent run,
   decisions, annotator, and revision;
6. choosing `firstPendingFrame`, then queue first frame;
7. persisting the session frame and asynchronously loading the exact frame.

If the selected clip cannot produce a queue, set a read-only reason without
changing or deleting decisions.

- [ ] **Step 4: Run controller GREEN**

Run the updated `MacDatasetBlindModeSmoke` executable and
`MacDatasetWorkspaceSourceSmoke`.

Expected:

```text
All Mac dataset blind-mode/controller tests passed.
All Mac workspace source contracts passed.
```

- [ ] **Step 5: Commit controller behavior**

```bash
git add \
  SwingArcDataset/Services/DatasetWorkspaceController.swift \
  Tests/MacDatasetBlindModeSmoke.swift \
  Tests/MacDatasetWorkspaceSourceSmoke.swift
git commit -m "feat: default annotations to P-point first pass"
```

### Task 3: Visible Mode Selector and End-to-End Verification

**Files:**
- Modify: `SwingArcDataset/Views/DatasetTimelineView.swift`
- Modify: `SwingArcDataset/Views/DatasetWorkspaceView.swift`
- Modify: `SwingArcDataset/Views/DatasetKeypointInspector.swift`
- Modify: `Tests/MacDatasetWorkspaceSourceSmoke.swift`

**Interfaces:**
- Consumes: controller `annotationQueueMode` and
  `selectAnnotationQueueMode(_:)`.
- Produces: segmented selector with labels `P1–P8 首轮` and `扩展训练队列`.

- [ ] **Step 1: Write failing UI source assertions**

```swift
requireSourceContains("DatasetTimelineView.swift", [
    "P1–P8 首轮",
    "扩展训练队列",
    "queueMode",
    "onQueueModeChange"
])
requireSourceContains("DatasetWorkspaceView.swift", [
    "controller.annotationQueueMode",
    "controller.selectAnnotationQueueMode"
])
requireSourceContains("DatasetKeypointInspector.swift", [
    "接受本帧全部预测",
    "当前无预测，需人工标注"
])
```

- [ ] **Step 2: Run RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  Tests/MacDatasetWorkspaceSourceSmoke.swift \
  -o /private/tmp/MacDatasetWorkspaceSourceSmoke &&
/private/tmp/MacDatasetWorkspaceSourceSmoke
```

Expected: precondition failure for the missing mode-selector source markers.

- [ ] **Step 3: Add the segmented selector**

Extend `DatasetTimelineView` with:

```swift
let queueMode: DatasetAnnotationQueueMode
let onQueueModeChange: (DatasetAnnotationQueueMode) -> Void
```

Above the queue navigation row, render:

```swift
Picker(
    "标注范围",
    selection: Binding(
        get: { queueMode },
        set: onQueueModeChange
    )
) {
    ForEach(DatasetAnnotationQueueMode.allCases, id: \.self) { mode in
        Text(mode.displayName).tag(mode)
    }
}
.pickerStyle(.segmented)
```

Prefix the queue summary with `queueMode.displayName`. Pass the active mode and
controller callback through `DatasetWorkspaceView` and
`DatasetWorkspaceHostView`.

- [ ] **Step 4: Clarify the prediction bulk action**

In `DatasetKeypointInspector`, rename the button:

```swift
Button("接受本帧全部预测", action: onAcceptFrame)
```

When `allowsPredictionAcceptance` is false, show:

```swift
Text("当前无预测，需人工标注")
    .font(.caption2)
    .foregroundColor(.secondary)
```

Keep the action disabled unless `isFrameEditable && canAcceptFrame`; do not add
an explicit save action because every landmark decision already creates an
atomic revision snapshot.

- [ ] **Step 5: Run all relevant tests and builds**

Run queue-mode, annotation-state, controller, source, store, and frame-queue
smokes. Then run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -quiet -jobs 1 \
  -project SwingArcProject.xcodeproj \
  -scheme SwingArcDataset \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/SwingArcDataset-PPointFirstPass \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: every smoke exits `0`; macOS build succeeds.

- [ ] **Step 6: Verify the real eight-clip workspace**

Launch:

```bash
open -n /private/tmp/SwingArcDataset-PPointFirstPass/Build/Products/Debug/SwingArcDataset.app
```

For each of the eight clips, verify:

- default selector is `P1–P8 首轮`;
- queue total is exactly `8`;
- P1–P8 timeline markers remain visible;
- switching to `扩展训练队列` restores the prior clip-specific count;
- switching back retains all stored decisions;
- totals across the default queues equal `64`.
- the manual-bootstrap inspector says `当前无预测，需人工标注`;
- the disabled bulk button reads `接受本帧全部预测`.

Do not click or alter landmark decisions during this verification.

- [ ] **Step 7: Commit and push**

```bash
git add \
  SwingArcDataset/Views/DatasetTimelineView.swift \
  SwingArcDataset/Views/DatasetWorkspaceView.swift \
  SwingArcDataset/Views/DatasetKeypointInspector.swift \
  Tests/MacDatasetWorkspaceSourceSmoke.swift
git commit -m "feat: expose first-pass annotation scope"
git push origin codex/p-point-evaluation-pipeline
```

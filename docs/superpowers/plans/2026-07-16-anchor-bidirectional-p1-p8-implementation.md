# Anchor-Bidirectional P1–P8 Solver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed padded-window and independent-stage scoring pipeline with an adaptive, impact-anchored, bidirectional solver that locates P1–P8 within ±1 real source frame on every accepted validation clip.

**Architecture:** Keep the existing 8 FPS pose-only pass, but make it output only a high-energy swing core. Expand source-frame pose evidence around that core until the address and finish boundaries are proven, generate multiple impact corridors, search P5→P1 and P7→P8 around each corridor, then choose one strictly ordered path with explicit evidence and transition constraints. Preserve the current `SwingFrameSample`, `SwingFrameEvidence`, `SwingAnalysisResult`, manual-marker priority, and UI data contract.

**Tech Stack:** Swift 5, SwiftUI, AVFoundation, Vision, CoreGraphics, Foundation, standalone Swift smoke executables, XCTest-free command-line acceptance harnesses, Xcode iOS Simulator builds.

## Global Constraints

- Supported capture geometry is fixed front or near-front camera with one primary golfer and one complete swing.
- Support left- and right-handed golfers; the resolved lead arm must remain fixed for one analysis run.
- Source video rates are 30–120 FPS; never interpolate a missing frame.
- Every automatic marker must reference an observed `sourceFrameIndex` from the video.
- P1–P8 acceptance tolerance is ±1 source frame for each stage; one stage outside tolerance fails that clip.
- Missing required evidence must produce `lowConfidence`, `unresolved`, or an explicit failure; never fabricate a stage to complete the sequence.
- A P6 without club/ball evidence may remain a real low-confidence candidate, but may never be `confirmed`.
- Manual markers remain authoritative and are not overwritten by a new analysis result.
- Maximum adaptive span is 8.0 seconds as an abnormal-clip guard only, not as a stage boundary.
- The 25.23-second, 30 FPS baseline clip must complete in less than 45 seconds on the current development Mac/device path.
- Analysis stays entirely on-device and introduces no new package dependency, network service, score, diagnosis, or coaching recommendation.
- Progress must reflect real work: coarse scan, adaptive boundary expansion, candidate evidence, and global solving.
- A cancelled or superseded run must not write progress or results.
- Do not change the analysis workspace layout, drawing tools, persisted project format, or manual-stage adjustment interaction.

---

## File Map

The external Xcode project at `/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj` uses an explicit source list, while this repository owns only the source bundle. To keep implementation commits self-contained and avoid an uncommitted sibling-project edit, new solver types stay in the existing service file rather than adding a production Swift file.

- Modify `SwingArc/Services/SwingStageDetector.swift`
  - Owns core localization, adaptive-window policy, temporal evidence, impact candidates, bidirectional candidates, constrained path solving, and analysis failures.
- Modify `SwingArc/Services/VisionPoseDetector.swift`
  - Keeps pose, primary-golfer, shaft-contour, and stable-ball extraction, and owns a UI-independent `SwingVideoAnalysisEngine` shared by the app and real-video acceptance CLI.
- Modify `SwingArc/Views/CustomVideoPlayer.swift`
  - Orchestrates coarse scan, non-overlapping adaptive source-frame extraction, sparse object extraction, cancellation, progress, and final solve.
- Modify `SwingArc/Models/WorkspaceModels.swift`
  - Presents the four real analysis phases.
- Modify `SwingArc/Views/AnalysisWorkspaceView.swift`
  - Maps new explicit failure reasons to user-facing copy without changing layout.
- Modify `SwingArc/Views/WorkspaceComponents.swift`
  - Shows the phase/detail already supplied by `AnalysisProgressPresentation`.
- Modify `README.md`
  - Records the anchor-bidirectional pipeline, supported clips, evidence downgrade rules, and ±1-frame acceptance contract.
- Create `Tests/SwingCoreLocatorSmoke.swift`
  - Proves coarse localization returns an unpadded core and preserves ambiguity/no-motion behavior.
- Create `Tests/AdaptiveSwingWindowPlannerSmoke.swift`
  - Proves 0.5-second non-overlapping expansion, boundary stopping, video-edge behavior, and the 8-second guard.
- Create `Tests/SwingTemporalEvidenceSmoke.swift`
  - Proves time-based direction votes, address transition, top plateau end, finish plateau start, label-swap resilience, and frame-rate invariance.
- Create `Tests/ImpactCorridorResolverSmoke.swift`
  - Proves multiple P6 candidates survive until path solving and missing object evidence caps confidence.
- Create `Tests/BidirectionalStageSolverSmoke.swift`
  - Proves backward/forward candidate definitions and strict full-path selection.
- Create `Tests/Fixtures/IMG_4500-ground-truth.json`
  - Frozen two-pass manual frame annotations for the baseline clip.
- Create `Tests/P1P8AcceptanceSupport.swift`
  - Decodes frozen manifests and evaluates source-frame error without running Vision.
- Create `Tests/P1P8AcceptanceEvaluationSmoke.swift`
  - Proves the acceptance evaluator fails one wrong stage and passes only eight stages within tolerance.
- Create `Tests/RealVideoP1P8Acceptance.swift`
  - Runs the real AVFoundation/Vision pipeline and emits per-stage error/evidence/timing JSON in Task 7.
- Modify `Tests/SparseObjectSamplingPlanSmoke.swift`
  - Proves sparse object neighborhoods center on P1/P2/P6/P7 candidates rather than a preliminary final answer.
- Modify `Tests/TwoStageAnalysisPolicySmoke.swift`
  - Proves new phase copy and explicit failure coverage.
- Modify `Tests/OrderedStageSolverSmoke.swift`
  - Keeps the old fixture as a compatibility regression while routing production detection to the new solver.

## Shared Test Command

Unless a task gives additional framework flags, compile a smoke file with:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Services/SwingStageDetector.swift \
  TEST_FILE \
  -o /tmp/TEST_BINARY && /tmp/TEST_BINARY
```

Expected success output for every smoke executable is exit status `0` with no precondition failure.

---

### Task 1: Freeze the Accuracy Contract and Baseline Ground Truth

**Files:**
- Create: `Tests/Fixtures/IMG_4500-ground-truth.json`
- Create: `Tests/P1P8AcceptanceSupport.swift`
- Create: `Tests/P1P8AcceptanceEvaluationSmoke.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `/Users/liangbo/Desktop/IMG_4500.mov`, `SwingStage.rawValue`, `SwingStageDetection.sourceFrameIndex`.
- Produces: `GroundTruthManifest`, `StageGroundTruth`, `StageAcceptance`, and `RealVideoAcceptance.evaluate(manifest:result:)` for the Task 7 CLI.

- [ ] **Step 1: Freeze the reviewed baseline labels before changing the algorithm**

Replay the source clip twice at single-frame resolution. On the second pass, resolve every disagreement and write exactly this schema using the final reviewed frame integers; the currently reviewed visual anchors are `P1=375`, `P2=414`, `P3=431`, `P4=453`, `P5=466`, `P6=481`, `P7=496`, and `P8=513`:

```json
{
  "video": "IMG_4500.mov",
  "sourceFrameRate": 30.0,
  "duration": 25.23,
  "annotationPasses": 2,
  "maximumAcceptedFrameError": 1,
  "stages": [
    { "stage": "P1", "sourceFrameIndex": 375, "definition": "last stable address frame before sustained takeaway" },
    { "stage": "P2", "sourceFrameIndex": 414, "definition": "backswing shaft-horizontal frame" },
    { "stage": "P3", "sourceFrameIndex": 431, "definition": "backswing lead-arm-horizontal frame" },
    { "stage": "P4", "sourceFrameIndex": 453, "definition": "last top-plateau frame before sustained downswing" },
    { "stage": "P5", "sourceFrameIndex": 466, "definition": "downswing lead-arm-horizontal frame" },
    { "stage": "P6", "sourceFrameIndex": 481, "definition": "clubhead at stable ball position" },
    { "stage": "P7", "sourceFrameIndex": 496, "definition": "post-impact extension parallel frame" },
    { "stage": "P8", "sourceFrameIndex": 513, "definition": "first stable finish-plateau frame" }
  ]
}
```

If frame-by-frame review changes an integer, update only from visual evidence and record the same final integer in both the JSON and the review notes in the commit message; never copy the current algorithm output into this manifest.

- [ ] **Step 2: Write the strict acceptance evaluator and failing smoke fixture**

Add the following data model and strict evaluator to `Tests/P1P8AcceptanceSupport.swift`:

```swift
import Foundation

struct GroundTruthManifest: Decodable {
    let video: String
    let sourceFrameRate: Double
    let duration: Double
    let annotationPasses: Int
    let maximumAcceptedFrameError: Int
    let stages: [StageGroundTruth]
}

struct StageGroundTruth: Decodable {
    let stage: String
    let sourceFrameIndex: Int
    let definition: String
}

struct StageAcceptance: Codable {
    let stage: String
    let expectedFrame: Int
    let actualFrame: Int?
    let absoluteFrameError: Int?
    let maximumAcceptedFrameError: Int
    let status: String
    let confidence: Double
    let hasClubEvidence: Bool
    let hasBallEvidence: Bool
    let passed: Bool
}

enum RealVideoAcceptance {
    private static let stagesByCode: [String: SwingStage] = [
        "P1": .address,
        "P2": .takeaway,
        "P3": .leadArmParallelBackswing,
        "P4": .top,
        "P5": .leadArmParallelDownswing,
        "P6": .impact,
        "P7": .followThrough,
        "P8": .finish
    ]

    static func evaluate(
        manifest: GroundTruthManifest,
        result: SwingAnalysisResult
    ) -> [StageAcceptance] {
        manifest.stages.map { truth in
            let expectedStage = stagesByCode[truth.stage]
            let detection = result.detections.first { $0.stage == expectedStage }
            let error = detection?.sourceFrameIndex.map { abs($0 - truth.sourceFrameIndex) }
            return StageAcceptance(
                stage: truth.stage,
                expectedFrame: truth.sourceFrameIndex,
                actualFrame: detection?.sourceFrameIndex,
                absoluteFrameError: error,
                maximumAcceptedFrameError: manifest.maximumAcceptedFrameError,
                status: String(describing: detection?.status ?? .unresolved),
                confidence: detection?.confidence ?? 0,
                hasClubEvidence: detection?.hasClubEvidence ?? false,
                hasBallEvidence: detection?.hasBallEvidence ?? false,
                passed: error.map { $0 <= manifest.maximumAcceptedFrameError } ?? false
            )
        }
    }
}
```

Add `Tests/P1P8AcceptanceEvaluationSmoke.swift` with this `@main` behavior:

```swift
import Foundation

@main
struct P1P8AcceptanceEvaluationSmoke {
    static func main() throws {
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let manifest = try JSONDecoder().decode(
            GroundTruthManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let stages = SwingStage.allCases
        let correctDetections = zip(stages, manifest.stages).map { pair in
            let stage = pair.0
            let truth = pair.1
            SwingStageDetection(
                stage: stage,
                time: Double(truth.sourceFrameIndex) / manifest.sourceFrameRate,
                sourceFrameIndex: truth.sourceFrameIndex,
                confidence: 0.9,
                status: .confirmed,
                hasClubEvidence: true,
                hasBallEvidence: stage == .impact
            )
        }
        let correctResult = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: correctDetections
        )
        precondition(RealVideoAcceptance.evaluate(manifest: manifest, result: correctResult).allSatisfy(\.passed))

        let wrongDetections = correctDetections.map { detection in
            detection.stage == .top
                ? SwingStageDetection(
                    stage: .top,
                    time: 455.0 / manifest.sourceFrameRate,
                    sourceFrameIndex: 455,
                    confidence: 0.9,
                    status: .confirmed
                )
                : detection
        }
        let wrongResult = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: wrongDetections
        )
        let failures = RealVideoAcceptance.evaluate(manifest: manifest, result: wrongResult).filter { !$0.passed }
        precondition(failures.count == 1)
        precondition(failures[0].stage == "P4")
        precondition(failures[0].absoluteFrameError == 2)
    }
}
```

- [ ] **Step 3: Run the evaluator smoke**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Services/SwingStageDetector.swift \
  Tests/P1P8AcceptanceSupport.swift \
  Tests/P1P8AcceptanceEvaluationSmoke.swift \
  -o /tmp/p1p8-acceptance-evaluator && \
/tmp/p1p8-acceptance-evaluator Tests/Fixtures/IMG_4500-ground-truth.json
```

Expected: exit `0`; the embedded correct result passes and the deliberately wrong P4 is rejected. The real current-pipeline red baseline is captured in Task 7 after the AVFoundation harness is created.

- [ ] **Step 4: Document the frozen contract**

Add this exact README section:

```markdown
### P1–P8 accuracy contract

Automatic stages always reference observed source frames. Accepted complete fixed-camera clips must place every P1–P8 stage within ±1 source frame of a frozen two-pass manual annotation. Missing required evidence is reported as low confidence, unresolved, or a specific clip failure; the app never fills a stage from a fixed timestamp or video percentage.
```

- [ ] **Step 5: Commit the immutable acceptance baseline**

```bash
git add Tests/Fixtures/IMG_4500-ground-truth.json Tests/P1P8AcceptanceSupport.swift Tests/P1P8AcceptanceEvaluationSmoke.swift README.md
git commit -m "test: freeze P1-P8 source-frame acceptance"
```

---

### Task 2: Replace the Padded Final Window with a Swing Core and Adaptive Planner

**Files:**
- Modify: `SwingArc/Services/SwingStageDetector.swift:1125-1455`
- Create: `Tests/SwingCoreLocatorSmoke.swift`
- Create: `Tests/AdaptiveSwingWindowPlannerSmoke.swift`
- Modify: `Tests/SwingWindowLocatorSmoke.swift`

**Interfaces:**
- Consumes: `[CoarseSwingSample]`, `SwingWindow`, source duration.
- Produces: `SwingCore`, `SwingCoreLocationResult`, `SwingCoreLocator.locate(samples:)`, `AdaptiveBoundaryEvidence`, `AdaptiveSwingWindowAction`, and `AdaptiveSwingWindowPlanner.nextAction(...)`.

- [ ] **Step 1: Write failing core-localization tests**

Use the existing coarse fixtures but assert the returned value is unpadded:

```swift
let samples = coarseFixture(bursts: [8.0])
switch SwingCoreLocator.locate(samples: samples) {
case let .located(core):
    precondition(core.startTime >= 7.75)
    precondition(core.startTime <= 8.125)
    precondition(core.endTime >= 9.125)
    precondition(core.endTime <= 9.50)
    precondition((core.startTime...core.endTime).contains(core.peakTime))
case let .failed(reason):
    preconditionFailure("Expected unpadded swing core, got \(reason)")
}
```

Retain assertions that equal independent bursts return `.ambiguousCandidates`, still video returns `.noSwingMotion`, and alternating Vision left/right labels do not create a swing.

- [ ] **Step 2: Write failing adaptive-window tests**

Add exact policy assertions:

```swift
let core = SwingCore(startTime: 14.0, endTime: 16.0, peakTime: 15.5)
let initial = AdaptiveSwingWindowPlanner.initialWindow(core: core, duration: 25.23)
precondition(initial == SwingWindow(startTime: 13.5, endTime: 16.5))

let earlier = AdaptiveSwingWindowPlanner.nextAction(
    current: initial,
    duration: 25.23,
    evidence: AdaptiveBoundaryEvidence(hasAddressBoundary: false, hasFinishBoundary: true)
)
precondition(earlier == .expand(SwingWindow(startTime: 13.0, endTime: 16.5)))

let later = AdaptiveSwingWindowPlanner.nextAction(
    current: initial,
    duration: 25.23,
    evidence: AdaptiveBoundaryEvidence(hasAddressBoundary: true, hasFinishBoundary: false)
)
precondition(later == .expand(SwingWindow(startTime: 13.5, endTime: 17.0)))

precondition(
    AdaptiveSwingWindowPlanner.nextAction(
        current: initial,
        duration: 25.23,
        evidence: AdaptiveBoundaryEvidence(hasAddressBoundary: true, hasFinishBoundary: true)
    ) == .ready(initial)
)
```

Also assert a start-edge without address returns `.failed(.incompleteSwingClip)`, an end-edge without finish returns the same failure, and an 8.0-second span returns `.failed(.missingAddressBoundary)` or `.failed(.missingFinishBoundary)` according to the missing side.

- [ ] **Step 3: Run both tests to verify red**

Run the shared command once for each new test.

Expected: compile failure for missing `SwingCoreLocator` and `AdaptiveSwingWindowPlanner`.

- [ ] **Step 4: Add exact core and adaptive-window types**

Add these public-to-module types beside `SwingWindow`:

```swift
struct SwingCore: Equatable {
    let startTime: Double
    let endTime: Double
    let peakTime: Double
}

enum SwingCoreLocationResult: Equatable {
    case located(SwingCore)
    case failed(SwingWindowFailure)
}

struct AdaptiveBoundaryEvidence: Equatable {
    let hasAddressBoundary: Bool
    let hasFinishBoundary: Bool
}

enum AdaptiveSwingWindowAction: Equatable {
    case expand(SwingWindow)
    case ready(SwingWindow)
    case failed(AnalysisFailure)
}

enum AdaptiveSwingWindowPlanner {
    static let expansionStep = 0.5
    static let initialPadding = 0.5
    static let maximumSpan = 8.0

    static func initialWindow(core: SwingCore, duration: Double) -> SwingWindow {
        SwingWindow(
            startTime: max(0, core.startTime - initialPadding),
            endTime: min(duration, core.endTime + initialPadding)
        )
    }

    static func nextAction(
        current: SwingWindow,
        duration: Double,
        evidence: AdaptiveBoundaryEvidence
    ) -> AdaptiveSwingWindowAction {
        if evidence.hasAddressBoundary && evidence.hasFinishBoundary { return .ready(current) }
        if current.duration >= maximumSpan {
            return .failed(evidence.hasAddressBoundary ? .missingFinishBoundary : .missingAddressBoundary)
        }
        if !evidence.hasAddressBoundary {
            guard current.startTime > 0 else { return .failed(.incompleteSwingClip) }
            return .expand(SwingWindow(
                startTime: max(0, current.startTime - expansionStep),
                endTime: current.endTime
            ))
        }
        guard current.endTime < duration else { return .failed(.incompleteSwingClip) }
        return .expand(SwingWindow(
            startTime: current.startTime,
            endTime: min(duration, current.endTime + expansionStep)
        ))
    }
}
```

Add `.missingAddressBoundary`, `.missingTopTransition`, `.noImpactCorridor`, `.missingFinishBoundary`, `.incompleteSwingClip`, and `.analysisCancelled` to `AnalysisFailure`.

- [ ] **Step 5: Extract `SwingCoreLocator` from the current energy computation**

Rename `SwingWindowLocator` to `SwingCoreLocator`, keep its 8 FPS sample times, median smoothing, axis-label protection, energy threshold, grouping, and 0.85 ambiguity rule. Delete `leadingPadding`, `trailingPadding`, and the 6-second final-window rejection. Make the candidate builder return:

```swift
let peakIndex = group.max { energies[$0] < energies[$1] } ?? first
return (
    core: SwingCore(
        startTime: samples[max(0, first - 1)].time,
        endTime: samples[last].time,
        peakTime: samples[peakIndex].time
    ),
    score: group.reduce(0.0) { $0 + energies[$1] }
)
```

Keep `SwingWindowLocator` as a test-only compatibility adapter for one commit if needed, but production orchestration must call `SwingCoreLocator` by Task 7.

- [ ] **Step 6: Run tests and commit**

Run `SwingCoreLocatorSmoke`, `AdaptiveSwingWindowPlannerSmoke`, and the existing `SwingWindowLocatorSmoke` after updating the latter to core semantics.

Expected: all exit `0`.

```bash
git add SwingArc/Services/SwingStageDetector.swift Tests/SwingCoreLocatorSmoke.swift Tests/AdaptiveSwingWindowPlannerSmoke.swift Tests/SwingWindowLocatorSmoke.swift
git commit -m "refactor: separate swing core from adaptive boundaries"
```

---

### Task 3: Build a Time-Based Temporal Evidence Timeline

**Files:**
- Modify: `SwingArc/Services/SwingStageDetector.swift:210-500`
- Create: `Tests/SwingTemporalEvidenceSmoke.swift`
- Modify: `Tests/SwingFeatureGeometrySmoke.swift`

**Interfaces:**
- Consumes: sorted `[SwingFrameEvidence]` from `SwingFeatureExtractor.extract(frames:)`.
- Produces: `SwingMotionDirection`, `SwingTemporalFrame`, `SwingEvidenceTimeline.build(from:)`, and boundary predicates consumed by Tasks 4–7.

- [ ] **Step 1: Write the failing slow-takeaway, top-plateau, and finish tests**

Build fixtures at both 30 and 120 FPS from the same piecewise motion curve and assert source-time semantics:

```swift
let thirty = temporalFixture(fps: 30)
let oneTwenty = temporalFixture(fps: 120)
let timeline30 = SwingEvidenceTimeline.build(from: thirty)
let timeline120 = SwingEvidenceTimeline.build(from: oneTwenty)

precondition(timeline30.last(where: \.isAddressBoundary)?.frame.time == 1.00)
precondition(timeline120.last(where: \.isAddressBoundary)?.frame.time == 1.00)
precondition(timeline30.first(where: \.isTopPlateauEnd)?.frame.time == 2.50)
precondition(timeline120.first(where: \.isTopPlateauEnd)?.frame.time == 2.50)
precondition(timeline30.first(where: \.isFinishPlateauStart)?.frame.time == 4.25)
precondition(timeline120.first(where: \.isFinishPlateauStart)?.frame.time == 4.25)
```

The fixture must include one wrong-direction frame after P4 and one unstable frame inside the finish window. Assert neither changes the boundary. Add the existing alternating-left/right shoulder and hip axis fixture and assert no false direction transition.

- [ ] **Step 2: Run the test to verify red**

Run the shared command with `Tests/SwingTemporalEvidenceSmoke.swift`.

Expected: compile failure for missing temporal types.

- [ ] **Step 3: Add the exact temporal model**

```swift
enum SwingMotionDirection: Equatable {
    case backswing
    case downswing
    case stable
}

struct SwingTemporalFrame: Equatable {
    let frame: SwingFrameEvidence
    let direction: SwingMotionDirection
    let sustainedBackswing: Bool
    let sustainedDownswing: Bool
    let sustainedFollowThrough: Bool
    let isAddressBoundary: Bool
    let isTopPlateauEnd: Bool
    let isFinishPlateauStart: Bool
    let shaftAngleContinuity: Double
    let ballStability: Double
    let qualityFlags: Set<SwingEvidenceQualityFlag>
}

enum SwingEvidenceQualityFlag: Hashable {
    case missingHands
    case missingLeadArm
    case labelSwapSuspected
}

enum SwingEvidenceTimeline {
    static let directionWindow = 0.15
    static let stableWindow = 0.25
    static let directionVoteRatio = 0.75
    static let stableVoteRatio = 0.75
    static let handDirectionThreshold = 0.12
    static let bodyStabilityThreshold = 0.08

    static func build(from rawEvidence: [SwingFrameEvidence]) -> [SwingTemporalFrame] {
        let evidence = rawEvidence.sorted { $0.time < $1.time }
        return evidence.indices.map { index in
            let past = timedIndices(endingAt: index, duration: directionWindow, evidence: evidence)
            let future = timedIndices(startingAt: index, duration: directionWindow, evidence: evidence)
            let pastDirection = directionVote(indices: past, evidence: evidence)
            let futureDirection = directionVote(indices: future, evidence: evidence)
            let stablePast = stabilityVote(indices: timedIndices(endingAt: index, duration: stableWindow, evidence: evidence), evidence: evidence)
            let stableFuture = stabilityVote(indices: timedIndices(startingAt: index, duration: stableWindow, evidence: evidence), evidence: evidence)
            return SwingTemporalFrame(
                frame: evidence[index],
                direction: directionVote(indices: past + future, evidence: evidence),
                sustainedBackswing: futureDirection == .backswing,
                sustainedDownswing: futureDirection == .downswing,
                sustainedFollowThrough: futureDirection == .backswing,
                isAddressBoundary: stablePast && futureDirection == .backswing,
                isTopPlateauEnd: pastDirection != .downswing && futureDirection == .downswing,
                isFinishPlateauStart: stableFuture && pastDirection == .backswing,
                shaftAngleContinuity: shaftContinuity(at: index, evidence: evidence),
                ballStability: stableBallVote(at: index, evidence: evidence),
                qualityFlags: qualityFlags(at: index, evidence: evidence)
            )
        }
    }
}
```

Implement `timedIndices` by walking until the elapsed source time reaches the requested duration. Implement `directionVote` by counting frames whose `handVelocity.y <= -0.12` as backswing and `>= 0.12` as downswing; return a direction only when its count divided by valid frames is at least `0.75`. Implement `stabilityVote` from `headSpeed <= 0.08`, `hipSpeed <= 0.08`, and hand-speed magnitude `<= 0.18`, also at `0.75`. Require the window to span at least 80% of the requested duration so a clip edge cannot masquerade as a plateau.

Implement `shaftContinuity` from observed shaft angles in the surrounding 0.15-second window as `1 - min(1, medianAngularDelta / 25°)`. Implement `stableBallVote` as the fraction of observed ball centers within normalized distance `0.025` of their median center. Set `.missingHands` when `handCenter == nil`, `.missingLeadArm` when `leadArm == .unknown`, and `.labelSwapSuspected` when raw left/right shoulder or hip endpoints reverse while the undirected axis remains stable. `SwingFeatureExtractor` must resolve one lead arm for the full analysis array and write that same value to every evidence frame.

- [ ] **Step 4: Add the adaptive-boundary summary**

```swift
extension Array where Element == SwingTemporalFrame {
    var adaptiveBoundaryEvidence: AdaptiveBoundaryEvidence {
        AdaptiveBoundaryEvidence(
            hasAddressBoundary: contains(where: \.isAddressBoundary),
            hasFinishBoundary: contains(where: \.isFinishPlateauStart)
        )
    }
}
```

- [ ] **Step 5: Run 30/120 FPS tests and commit**

Run `SwingTemporalEvidenceSmoke` and `SwingFeatureGeometrySmoke` with the shared command.

Expected: both exit `0` and select the same event times at both frame rates.

```bash
git add SwingArc/Services/SwingStageDetector.swift Tests/SwingTemporalEvidenceSmoke.swift Tests/SwingFeatureGeometrySmoke.swift
git commit -m "feat: derive time-based swing transition evidence"
```

---

### Task 4: Resolve a Multi-Candidate P6 Impact Corridor and Sparse Object Neighborhoods

**Files:**
- Modify: `SwingArc/Services/SwingStageDetector.swift:573-850,1411-1455`
- Create: `Tests/ImpactCorridorResolverSmoke.swift`
- Modify: `Tests/SparseObjectSamplingPlanSmoke.swift`
- Modify: `Tests/SwingObjectEvidenceSmoke.swift`

**Interfaces:**
- Consumes: `[SwingTemporalFrame]` and sparse `SwingObjectEvidence`.
- Produces: `StageCandidate`, `ImpactCorridor`, `ImpactCorridorResolver.candidates(in:)`, and `SparseObjectSamplingPlan.frames(from:candidates:)`.

- [ ] **Step 1: Write failing P6 corridor tests**

Create a timeline with three hand-near-hip frames: frame 478 has body-only proximity, frame 480 has a shaft line approaching the stable ball, and frame 481 has maximum ball-local change. Assert:

```swift
let candidates = ImpactCorridorResolver.candidates(in: timeline)
precondition(candidates.map(\.sourceFrameIndex) == [478, 480, 481])
precondition(candidates.first { $0.sourceFrameIndex == 481 }?.requirementsSatisfied == true)
precondition(candidates.first { $0.sourceFrameIndex == 478 }?.maximumStatus == .lowConfidence)

let withoutObjects = ImpactCorridorResolver.candidates(in: timelineWithoutObjects)
precondition(!withoutObjects.isEmpty)
precondition(withoutObjects.allSatisfy { $0.maximumStatus != .confirmed })
```

Correct key paths in actual Swift to `\.sourceFrameIndex`.

- [ ] **Step 2: Write failing sparse-neighborhood tests**

Give `SparseObjectSamplingPlan` candidate frames for P1, P2, three P6 candidates, and P7. Assert it includes ±1 source reference around every center, de-duplicates overlapping neighborhoods, returns time order, and never exceeds 32 frames.

```swift
let selected = SparseObjectSamplingPlan.frames(from: references, candidates: candidates)
precondition(selected.count <= 32)
precondition(selected.map(\.sourceFrameIndex) == selected.map(\.sourceFrameIndex).sorted())
precondition(Set(selected.map(\.sourceFrameIndex)).isSuperset(of: [374, 375, 376, 413, 414, 415, 480, 481, 482, 495, 496, 497]))
```

- [ ] **Step 3: Run tests to verify red**

Run the shared command for `ImpactCorridorResolverSmoke.swift`. For object-policy tests include `SwingArc/Services/VisionPoseDetector.swift` and `-framework Vision -framework ImageIO`.

Expected: compile failure for missing `StageCandidate` and new sparse-plan signature.

- [ ] **Step 4: Add the exact candidate types and impact scoring**

```swift
struct StageCandidate: Equatable {
    let stage: SwingStage
    let evidenceIndex: Int
    let sourceFrameIndex: Int
    let time: Double
    let score: Double
    let requirementsSatisfied: Bool
    let maximumStatus: SwingStageDetectionStatus
    let hasClubEvidence: Bool
    let hasBallEvidence: Bool
}

struct ImpactCorridor: Equatable {
    let candidates: [StageCandidate]
}
```

`ImpactCorridorResolver.candidates(in:)` must reject frames without sustained downswing or after sustained follow-through, then compute:

```swift
let score = clamp(
    handNearHip * 0.16 +
    downwardSpeed * 0.15 +
    localAcceleration * 0.09 +
    hipOpen * 0.10 +
    shaftBallAlignment * 0.22 +
    ballLocalChange * 0.11 +
    temporalFrame.shaftAngleContinuity * 0.07 +
    frame.poseCoverage * 0.10
)
let hasRequiredObjects = shaftBallAlignment >= 0.55 || ballLocalChange >= 0.55
```

Keep candidates scoring `>= 0.38`, sort them by source frame, retain at most the best five by score, and set `maximumStatus` to `.confirmed` only when `hasRequiredObjects`; otherwise `.lowConfidence`.

- [ ] **Step 5: Route sparse object extraction from candidate neighborhoods**

Replace the preliminary-result signature with:

```swift
static func frames(
    from references: [FineFrameReference],
    candidates: [StageCandidate]
) -> [FineFrameReference]
```

Select centers only for `.address`, `.takeaway`, `.impact`, and `.followThrough`. Include the nearest reference and one neighbor on either side, de-duplicate, sort, and if more than 32 remain, keep all P6 centers first, then P1/P2/P7 centers in descending candidate score. Preserve a 12-evenly-spaced fallback only when there is no candidate at all.

- [ ] **Step 6: Run tests and commit**

Run `ImpactCorridorResolverSmoke`, `SparseObjectSamplingPlanSmoke`, and `SwingObjectEvidenceSmoke`.

Expected: all exit `0`; body-only P6 remains available but cannot be confirmed.

```bash
git add SwingArc/Services/SwingStageDetector.swift Tests/ImpactCorridorResolverSmoke.swift Tests/SparseObjectSamplingPlanSmoke.swift Tests/SwingObjectEvidenceSmoke.swift
git commit -m "feat: preserve multiple impact evidence candidates"
```

---

### Task 5: Generate Bidirectional Stage Candidates and Solve One Constrained Path

**Files:**
- Modify: `SwingArc/Services/SwingStageDetector.swift:573-910`
- Create: `Tests/BidirectionalStageSolverSmoke.swift`
- Modify: `Tests/OrderedStageSolverSmoke.swift`
- Modify: `Tests/MultiJointStageDetectorSmoke.swift`

**Interfaces:**
- Consumes: `[SwingTemporalFrame]` and `[StageCandidate]` P6 anchors.
- Produces: `StageCandidateSet`, `BidirectionalStageCandidateResolver.candidates(timeline:impact:)`, and `ConstrainedSwingPathSolver.solve(candidateSets:timeline:)`.

- [ ] **Step 1: Write the failing stage-definition fixture**

Construct a synthetic 120 FPS path containing slow takeaway, a four-frame top plateau, one false downswing frame, three P6 corridor frames, a noisy finish frame, and later walking. Assert exact observed frame indices:

```swift
let result = ConstrainedSwingPathSolver.solve(
    candidateSets: ImpactCorridorResolver.candidates(in: timeline).map {
        BidirectionalStageCandidateResolver.candidates(timeline: timeline, impact: $0)
    },
    timeline: timeline
)
let expected: [SwingStage: Int] = [
    .address: 120,
    .takeaway: 168,
    .leadArmParallelBackswing: 204,
    .top: 240,
    .leadArmParallelDownswing: 276,
    .impact: 300,
    .followThrough: 324,
    .finish: 360
]
for (stage, frame) in expected {
    precondition(result.detections.first { $0.stage == stage }?.sourceFrameIndex == frame)
}
```

Add assertions that P3 and P5 are not swapped, P4 equals the last plateau frame, P8 equals the first valid finish frame despite one noisy frame, and all frames are strictly increasing.

- [ ] **Step 2: Add failing evidence-downgrade tests**

Remove shaft/ball evidence from only P6 and assert its frame remains legal but `status == .lowConfidence`. Remove the address boundary and assert `.address` is unresolved rather than assigned to the first window frame. Remove the top transition and assert the solver returns `.missingTopTransition` through the orchestration-level validation result added in Task 7.

- [ ] **Step 3: Run tests to verify red**

Run the shared command for `BidirectionalStageSolverSmoke.swift` and `OrderedStageSolverSmoke.swift`.

Expected: missing resolver/solver compile errors or old-solver frame mismatches.

- [ ] **Step 4: Add the candidate-set interface**

```swift
struct StageCandidateSet {
    let impact: StageCandidate
    let candidatesByStage: [SwingStage: [StageCandidate]]

    func candidates(for stage: SwingStage) -> [StageCandidate] {
        candidatesByStage[stage] ?? []
    }
}
```

For each impact, generate candidates in this exact search order:

```swift
let p5 = descendingCandidates(before: impact.evidenceIndex, stage: .leadArmParallelDownswing)
let p4 = topPlateauEndCandidates(before: p5)
let p3 = ascendingParallelCandidates(before: p4)
let p2 = takeawayShaftCandidates(before: p3)
let p1 = addressBoundaryCandidates(before: p2)
let p7 = followThroughCandidates(after: impact.evidenceIndex)
let p8 = firstFinishPlateauCandidates(after: p7)
```

Candidate requirements must match the design table: P1 stable→sustained backswing, P2 backswing + horizontal shaft + hands below shoulders, P3 backswing + extended horizontal lead arm + increasing shoulder turn, P4 last plateau frame + sustained downswing, P5 downswing + extended horizontal lead arm + hip opening, P6 object evidence for confirmation, P7 sustained post-impact rise + arm/shaft parallel + continued body turn, P8 first stable plateau after P7.

Retain at most five candidates per stage, ordered by descending score with earlier source frame as the tie-breaker except P4, which prefers the later plateau-end frame.

- [ ] **Step 5: Add strict constrained path selection**

Enumerate only paths with one candidate for each P1–P8 and strict source-frame order. Prune any partial path that violates direction transitions or these tempo-scaled gap bounds:

```swift
let swingDuration = max(0.001, p8.time - p1.time)
let normalizedGaps = zip(path, path.dropFirst()).map { ($1.time - $0.time) / swingDuration }
guard normalizedGaps.allSatisfy({ (0.01...0.45).contains($0) }) else { reject() }
```

Score each complete path as:

```swift
let evidenceScore = path.reduce(0.0) { $0 + $1.score }
let missingPenalty = Double(path.filter { !$0.requirementsSatisfied }.count) * 0.35
let transitionScore = directionTransitionScore(path: path, timeline: timeline)
let total = evidenceScore + transitionScore - missingPenalty
```

Select the maximum total. Confidence for each stage is `clamp(candidate.score * 0.70 + poseCoverage * 0.20 + min(0.10, bestPathTotal - secondBestPathTotal))`, capped by `candidate.maximumStatus`. If no complete legal path exists, return unresolved detections rather than relaxing strict order.

- [ ] **Step 6: Route `SwingStageDetector.detect(frames:)` to the new solver**

Replace the production call with:

```swift
static func detect(frames: [SwingFrameSample]) -> SwingAnalysisResult {
    let evidence = SwingFeatureExtractor.extract(frames: frames)
    let timeline = SwingEvidenceTimeline.build(from: evidence)
    let candidateSets = ImpactCorridorResolver.candidates(in: timeline).map {
        BidirectionalStageCandidateResolver.candidates(timeline: timeline, impact: $0)
    }
    return ConstrainedSwingPathSolver.solve(candidateSets: candidateSets, timeline: timeline)
}
```

Keep `OrderedStageSolver` available only for its compatibility smoke test until all callers are migrated; no production caller may use it after this step.

- [ ] **Step 7: Run solver regressions and commit**

Run `BidirectionalStageSolverSmoke`, `OrderedStageSolverSmoke`, `MultiJointStageDetectorSmoke`, `SwingStageDetectorSmoke`, and `SwingPhaseTransitionSmoke`.

Expected: all exit `0`; exact synthetic frames match and objectless P6 is not confirmed.

```bash
git add SwingArc/Services/SwingStageDetector.swift Tests/BidirectionalStageSolverSmoke.swift Tests/OrderedStageSolverSmoke.swift Tests/MultiJointStageDetectorSmoke.swift
git commit -m "feat: solve P1-P8 around impact in both directions"
```

---

### Task 6: Integrate Non-Overlapping Adaptive Extraction, Real Progress, and Explicit Failures

**Files:**
- Modify: `SwingArc/Views/CustomVideoPlayer.swift:330-510`
- Modify: `SwingArc/Services/VisionPoseDetector.swift`
- Modify: `SwingArc/Models/WorkspaceModels.swift:65-98`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `SwingArc/Views/WorkspaceComponents.swift`
- Modify: `Tests/TwoStageAnalysisPolicySmoke.swift`
- Modify: `Tests/AnalysisSessionStateSmoke.swift`
- Modify: `Tests/TwoStageScanBudgetSmoke.swift`

**Interfaces:**
- Consumes: `SwingCoreLocator`, `AdaptiveSwingWindowPlanner`, `SwingEvidenceTimeline`, candidate APIs, and `AnalysisRunGate`.
- Produces: `SwingVideoAnalysisEngine.analyze(url:runID:gate:progress:)`, one cancellation-safe production pipeline shared by UI and CLI, four real work phases, and distinct UI failure messages.

- [ ] **Step 1: Write failing progress and failure-copy tests**

Update the test to assert:

```swift
precondition(AnalysisProgressPresentation(phase: .locating, progress: 0.20).detail.contains("8 FPS"))
precondition(AnalysisProgressPresentation(phase: .expanding, progress: 0.50).title == "扩展挥杆边界")
precondition(AnalysisProgressPresentation(phase: .evidence, progress: 0.80).title == "提取候选证据")
precondition(AnalysisProgressPresentation(phase: .solving, progress: 0.96).title == "全局阶段求解")

let explicitFailures: [AnalysisFailure] = [
    .missingAddressBoundary,
    .missingTopTransition,
    .noImpactCorridor,
    .missingFinishBoundary,
    .incompleteSwingClip,
    .analysisCancelled
]
precondition(explicitFailures.count == 6)
```

Add presentation assertions for exact Chinese copy:

- `.missingAddressBoundary` → `找不到准备位到起杆的边界`
- `.missingTopTransition` → `找不到上杆顶点到下杆的转换`
- `.noImpactCorridor` → `找不到可信的击球候选段`
- `.missingFinishBoundary` → `找不到稳定收杆位置`
- `.incompleteSwingClip` → `视频缺少完整挥杆前段或后段`
- `.analysisCancelled` → `分析已取消`

- [ ] **Step 2: Write failing adaptive scan-budget tests**

Test a sequence of planner windows from 13.5–16.5 through 12.0–17.5. Convert every window through `FineSwingSamplingPlan.frames`, subtract already cached frame indices, and assert no source frame is requested twice, requested frames are monotonically added, and the union equals one continuous source-frame range.

- [ ] **Step 3: Run policy tests to verify red**

Run `TwoStageAnalysisPolicySmoke`, `AnalysisSessionStateSmoke`, and `TwoStageScanBudgetSmoke`.

Expected: compile failure for `.expanding` and `.evidence` or policy mismatch.

- [ ] **Step 4: Add the four real progress phases**

Replace `AnalysisProgressPhase.extracting` with:

```swift
enum AnalysisProgressPhase: Equatable {
    case preparing
    case locating
    case expanding
    case evidence
    case solving
}
```

Use exact titles/details:

```swift
case .preparing: return "准备视频" / "正在读取视频信息"
case .locating: return "定位挥杆核心" / "正在以 8 FPS 粗扫完整视频"
case .expanding: return "扩展挥杆边界" / "正在寻找准备位和稳定收杆"
case .evidence: return "提取候选证据" / "正在检查关节、杆身和球位"
case .solving: return "全局阶段求解" / "正在联合定位 P1–P8"
```

Implement the two switch properties separately; the slash notation above pairs title with detail and is not source syntax.

- [ ] **Step 5: Add the shared video-analysis engine contract**

Import AVFoundation in `VisionPoseDetector.swift` and add:

```swift
struct SwingVideoAnalysisOutput: Equatable {
    let result: SwingAnalysisResult
    let adaptiveWindow: SwingWindow
    let sourceFrameRate: Double
    let elapsedSeconds: Double
}

enum SwingVideoAnalysisOutcome: Equatable {
    case completed(SwingVideoAnalysisOutput)
    case failed(AnalysisFailure)
    case cancelled
}

struct SwingAnalysisProgressUpdate: Equatable {
    let phase: AnalysisProgressPhase
    let progress: Double
}

final class SwingVideoAnalysisEngine {
    typealias ProgressHandler = @Sendable (SwingAnalysisProgressUpdate) -> Void
}
```

Steps 6 and 7 add `analyze(url:runID:gate:progress:)` and its extraction helpers before the engine is called by any production or test target.

- [ ] **Step 6: Replace fixed fine-window extraction with cached adaptive blocks**

Add `func analyze(url: URL, runID: UUID, gate: AnalysisRunGate, progress: @escaping ProgressHandler) -> SwingVideoAnalysisOutcome`. Start a monotonic timer, validate `AVURLAsset` duration/frame rate, run the 8 FPS coarse pose pass, resolve a `SwingCore`, then initialize:

```swift
var window = AdaptiveSwingWindowPlanner.initialWindow(core: core, duration: duration)
var samplesByFrame: [Int: SwingFrameSample] = [:]
var finalTimeline: [SwingTemporalFrame] = []
```

Create one `PrimaryGolferTracker` at the start of the analysis run and reuse it for every coarse and adaptive pose extraction in that run. Never reinitialize the tracker at a window expansion boundary; this preserves one golfer trajectory and prevents another person in the background from replacing the selected golfer.

Loop while the run gate is active:

```swift
while self.analysisRunGate.isActive(runID) {
    let references = FineSwingSamplingPlan.frames(
        window: window,
        sourceFrameRate: nominalFrameRate,
        duration: duration
    ).filter { samplesByFrame[$0.sourceFrameIndex] == nil }

    for reference in references {
        guard self.analysisRunGate.isActive(runID) else { return }
        let sample = extractPoseSample(reference: reference, generator: generator, detector: finePoseDetector)
        samplesByFrame[reference.sourceFrameIndex] = sample
    }

    let frames = samplesByFrame.values.sorted { $0.sourceFrameIndex < $1.sourceFrameIndex }
    finalTimeline = SwingEvidenceTimeline.build(from: SwingFeatureExtractor.extract(frames: frames))
    switch AdaptiveSwingWindowPlanner.nextAction(
        current: window,
        duration: duration,
        evidence: finalTimeline.adaptiveBoundaryEvidence
    ) {
    case let .expand(next): window = next
    case .ready: break
    case let .failed(reason): publishFailure(reason, runID: runID); return
    }
    if finalTimeline.adaptiveBoundaryEvidence.hasAddressBoundary &&
       finalTimeline.adaptiveBoundaryEvidence.hasFinishBoundary { break }
}
```

Extract the existing single-frame AVAssetImageGenerator/Vision code into private engine helpers `extractPoseSample(reference:generator:detector:)` and `failure(_:)`. Helpers must preserve exact source frame indices. The engine has no UI mutation; it returns an outcome and emits progress only while the gate is active.

An explicit Cancel button action must set `.failed(.analysisCancelled)` for the currently active run and then invalidate its run ID. Starting a replacement analysis must only invalidate the old run and must not flash the cancellation failure over the new run.

- [ ] **Step 7: Run sparse object evidence, validate transitions, and return the final result**

Generate body-only P1/P2/P6/P7 candidates, run sparse object detection at their neighborhoods, rebuild the timeline with merged objects, and invoke the constrained solver. Before publishing:

```swift
guard finalTimeline.contains(where: \.isTopPlateauEnd) else {
    return .failed(.missingTopTransition)
}
guard !ImpactCorridorResolver.candidates(in: finalTimeline).isEmpty else {
    return .failed(.noImpactCorridor)
}
```

Return `.completed(SwingVideoAnalysisOutput(...))` only while `gate.isActive(runID)`, otherwise `.cancelled`. Map expansion progress to `0.20...0.70` by cached source frames divided by the 8-second maximum-frame budget, candidate evidence to `0.70...0.95` by processed object references, and solve to `0.95...1.00`.

- [ ] **Step 8: Route `CustomVideoPlayer` through the engine**

Replace its coarse/fine/object loops with one background call:

```swift
let runID = analysisRunGate.begin()
let engine = SwingVideoAnalysisEngine()
analysisQueue.async {
    let outcome = engine.analyze(
        url: videoURL,
        runID: runID,
        gate: self.analysisRunGate
    ) { update in
        DispatchQueue.main.async {
            guard self.analysisRunGate.isActive(runID) else { return }
            self.analysisProgressPhase = update.phase
            self.scanProgress = update.progress
            self.analysisState = .scanning(progress: update.progress)
        }
    }
    DispatchQueue.main.async {
        guard self.analysisRunGate.isActive(runID) else { return }
        switch outcome {
        case let .completed(output): self.analysisState = .completed(output.result)
        case let .failed(reason): self.analysisState = .failed(reason)
        case .cancelled: break
        }
    }
}
```

Preserve the existing manual-marker merge after `.completed` so manual P1–P8 locks remain authoritative.

- [ ] **Step 9: Add explicit UI failure presentation**

Extend the existing failure switch with the six exact messages from Step 1. Keep actions limited to retry, import another clip, or manual stage adjustment; do not present a fake partial score.

- [ ] **Step 10: Run policy regressions, build, and commit**

Run the three policy tests plus all files matching `Tests/*SamplingPlanSmoke.swift` and `Tests/Analysis*Smoke.swift`.

Build both form factors:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj \
  -scheme SwingArcProject -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: both commands end with `** BUILD SUCCEEDED **`.

```bash
git add SwingArc/Views/CustomVideoPlayer.swift SwingArc/Services/VisionPoseDetector.swift SwingArc/Models/WorkspaceModels.swift SwingArc/Views/AnalysisWorkspaceView.swift SwingArc/Views/WorkspaceComponents.swift Tests/TwoStageAnalysisPolicySmoke.swift Tests/AnalysisSessionStateSmoke.swift Tests/TwoStageScanBudgetSmoke.swift
git commit -m "feat: run adaptive boundary analysis pipeline"
```

---

### Task 7: Complete Real-Video Acceptance, Cross-Video Fixtures, and Release Verification

**Files:**
- Create: `Tests/RealVideoP1P8Acceptance.swift`
- Modify: `Tests/Fixtures/IMG_4500-ground-truth.json`
- Create: `Tests/Fixtures/P1P8-acceptance-index.json`
- Create: `Tests/Fixtures/clip-30fps-ground-truth.json`
- Create: `Tests/Fixtures/clip-60fps-ground-truth.json`
- Create: `Tests/Fixtures/clip-120fps-ground-truth.json`
- Create: `Tests/Fixtures/clip-slow-takeaway-ground-truth.json`
- Modify: `README.md`

**Interfaces:**
- Consumes: the production `SwingCoreLocator`, adaptive extraction policy, Vision detectors, constrained solver, and frozen manifests.
- Produces: repeatable JSON acceptance reports for at least five complete clips plus explicit downgrade reports for clipped/occluded inputs.

- [ ] **Step 1: Create the real-video harness with production-equivalent extraction**

The `@main` harness must:

1. Open the `AVURLAsset` and read duration/frame rate.
2. Run 8 FPS pose-only coarse sampling with `VisionPoseDetector`.
3. Resolve one `SwingCore`.
4. Adaptively extract uncached source frames exactly as `CustomVideoPlayer` does.
5. Run candidate-neighborhood object extraction with `SwingObjectDetector`.
6. Solve P1–P8 and evaluate against the manifest.
7. Print JSON with `video`, `sourceFrameRate`, `adaptiveWindow`, `elapsedSeconds`, and eight stage entries.
8. Exit nonzero for any stage error greater than 1, any unresolved stage on a complete accepted clip, or elapsed time at least 45 seconds for `IMG_4500.mov`.

Use `CMTime(value: CMTimeValue(sourceFrameIndex), timescale: CMTimeScale(sourceFrameRate.rounded()))` for integer frame rates and `CMTime(seconds: Double(frame)/sourceFrameRate, preferredTimescale: 60_000)` otherwise. Keep `actualTime` from `copyCGImage` and reject an extracted image if it maps to a different source frame.

Use this complete CLI shell around the shared engine:

```swift
import Foundation
import Darwin

struct RealVideoReport: Encodable {
    let video: String
    let sourceFrameRate: Double
    let adaptiveWindowStart: Double
    let adaptiveWindowEnd: Double
    let elapsedSeconds: Double
    let stages: [StageAcceptance]
}

@main
struct RealVideoP1P8Acceptance {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fputs("usage: real-video-p1p8 <video-path> <manifest-path>\n", stderr)
            exit(EXIT_FAILURE)
        }
        let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let manifest = try JSONDecoder().decode(
            GroundTruthManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let gate = AnalysisRunGate()
        let runID = gate.begin()
        let outcome = SwingVideoAnalysisEngine().analyze(
            url: videoURL,
            runID: runID,
            gate: gate,
            progress: { _ in }
        )

        switch outcome {
        case let .completed(output):
            let stages = RealVideoAcceptance.evaluate(manifest: manifest, result: output.result)
            let report = RealVideoReport(
                video: videoURL.lastPathComponent,
                sourceFrameRate: output.sourceFrameRate,
                adaptiveWindowStart: output.adaptiveWindow.startTime,
                adaptiveWindowEnd: output.adaptiveWindow.endTime,
                elapsedSeconds: output.elapsedSeconds,
                stages: stages
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data("\n".utf8))
            guard stages.count == SwingStage.allCases.count,
                  stages.allSatisfy(\.passed),
                  output.elapsedSeconds < 45.0 else {
                exit(EXIT_FAILURE)
            }
        case let .failed(reason):
            fputs("analysis failed: \(reason)\n", stderr)
            exit(EXIT_FAILURE)
        case .cancelled:
            fputs("analysis cancelled\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
```

- [ ] **Step 2: Capture the old-pipeline red result, then run until all eight frame errors are ≤1**

Before routing production to the new solver, save one report from the old pipeline showing its known P1/P2/P4/P6 failures. After Tasks 2–6, run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  -framework AVFoundation -framework Vision -framework ImageIO \
  -framework SwiftUI -framework CoreVideo \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/SwingStageDetector.swift \
  Tests/P1P8AcceptanceSupport.swift \
  Tests/RealVideoP1P8Acceptance.swift \
  -o /tmp/real-video-p1p8 && \
/tmp/real-video-p1p8 \
  /Users/liangbo/Desktop/IMG_4500.mov \
  Tests/Fixtures/IMG_4500-ground-truth.json
```

Expected report shape:

```json
{
  "video": "IMG_4500.mov",
  "sourceFrameRate": 30,
  "elapsedSeconds": 44.999,
  "stages": [
    { "stage": "P1", "expectedFrame": 375, "actualFrame": 375, "absoluteFrameError": 0, "passed": true }
  ]
}
```

The actual elapsed time may be lower, but must be `<45.0`. The final report must contain eight entries and every `passed` must be true.

- [ ] **Step 3: Add the five-video acceptance index**

After importing and independently annotating four additional fixed-camera complete swings, write:

```json
{
  "maximumAcceptedFrameError": 1,
  "acceptedCompleteClips": [
    { "videoPath": "/Users/liangbo/Desktop/IMG_4500.mov", "manifestPath": "Tests/Fixtures/IMG_4500-ground-truth.json" },
    { "videoPath": "/Users/liangbo/Desktop/SwingArc-Acceptance/clip-30fps.mov", "manifestPath": "Tests/Fixtures/clip-30fps-ground-truth.json" },
    { "videoPath": "/Users/liangbo/Desktop/SwingArc-Acceptance/clip-60fps.mov", "manifestPath": "Tests/Fixtures/clip-60fps-ground-truth.json" },
    { "videoPath": "/Users/liangbo/Desktop/SwingArc-Acceptance/clip-120fps.mov", "manifestPath": "Tests/Fixtures/clip-120fps-ground-truth.json" },
    { "videoPath": "/Users/liangbo/Desktop/SwingArc-Acceptance/clip-slow-takeaway.mov", "manifestPath": "Tests/Fixtures/clip-slow-takeaway-ground-truth.json" }
  ],
  "downgradeClips": [
    { "videoPath": "/Users/liangbo/Desktop/SwingArc-Acceptance/clip-missing-address.mov", "expectedFailure": "incompleteSwingClip" },
    { "videoPath": "/Users/liangbo/Desktop/SwingArc-Acceptance/clip-occluded-ball.mov", "expectedP6Status": "lowConfidence" }
  ]
}
```

Do not mark Task 7 complete until the four paths and matching two-pass manifests exist. Missing clips are an acceptance blocker, not permission to duplicate `IMG_4500.mov` or weaken the threshold.

- [ ] **Step 4: Run the full smoke suite**

Use this loop so every standalone test receives the correct production files:

```bash
set -euo pipefail
for test in Tests/*Smoke.swift; do
  name="$(basename "$test" .swift)"
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcrun swiftc -parse-as-library \
    SwingArc/Models/DrawingModels.swift \
    SwingArc/Models/WorkspaceModels.swift \
    SwingArc/Services/SwingStageDetector.swift \
    "$test" -o "/tmp/$name"
  "/tmp/$name"
done
```

Where a test imports Vision, media export, persistence, or SwiftUI-specific types, use its existing narrower compile command instead of forcing unrelated files into the same module. Expected: every smoke executable exits `0`.

- [ ] **Step 5: Build and run iPhone and iPad simulator verification**

Repeat the two Task 6 builds. Boot each destination, install the Debug app, import `/Users/liangbo/Desktop/IMG_4500.mov` into the simulator photo library with `xcrun simctl addmedia`, run analysis, and verify:

- progress moves through locating → expanding → evidence → solving;
- P1–P8 markers remain visible and ordered;
- the UI stays responsive during the adaptive scan;
- cancelling and immediately restarting does not allow the old run to overwrite results;
- iPhone and iPad layouts remain unchanged outside status copy.

Use the currently installed simulator identifiers to avoid ambiguity while both devices are booted:

```bash
xcrun simctl addmedia 7C57E720-9644-4E59-89E5-9A554229A9EB /Users/liangbo/Desktop/IMG_4500.mov
xcrun simctl addmedia 8D2D7222-0CE1-45EB-AEF9-0440C351D457 /Users/liangbo/Desktop/IMG_4500.mov
```

- [ ] **Step 6: Update README with the production flow and limitations**

Document the exact pipeline, 30–120 FPS range, fixed/near-front camera assumption, 8-second guard, explicit failure behavior, objectless-P6 confidence cap, five-video acceptance command, and the no-interpolation rule.

- [ ] **Step 7: Final completeness, spec, and type review**

Run:

```bash
rg -n "TB[D]|TO[DO]|implement la[t]er|fill in detai[l]s|固定 1\.5|固定 1\.0|±2" \
  SwingArc Tests README.md docs/superpowers/plans/2026-07-16-anchor-bidirectional-p1-p8-implementation.md
```

Expected: no incomplete implementation marker and no stale production claim. Then verify every type name used by `CustomVideoPlayer` exactly matches its definition in `SwingStageDetector.swift`.

- [ ] **Step 8: Commit the verified acceptance result**

```bash
git add Tests/RealVideoP1P8Acceptance.swift Tests/Fixtures README.md
git commit -m "test: verify source-frame P1-P8 acceptance"
```

Do not create this commit if any required clip, stage, smoke test, simulator build, or ±1-frame check is failing.

---

## Completion Gate

Implementation is complete only when all of the following are true:

- `SwingCoreLocator` returns an unpadded high-energy core and production no longer treats it as a final swing window.
- Adaptive source-frame extraction finds both legal boundaries without decoding any source frame twice.
- P1 is the last stable frame before sustained takeaway.
- P4 is the final top-plateau frame before sustained downswing, not the plateau entrance.
- P6 is selected from multiple impact candidates using joint, hand/hip, shaft, and ball evidence; no-object P6 is never confirmed.
- P8 is the first legal stable finish plateau and is not replaced by later walking or stillness.
- The selected path is strictly `P1 < P2 < … < P8` and every returned marker references an observed source frame.
- Explicit failures distinguish address, top, impact, finish, incomplete clip, cancellation, and extraction problems.
- The baseline completes in under 45 seconds.
- Every accepted complete clip has all eight absolute frame errors `<= 1` across at least five independently annotated videos.
- iPhone and iPad simulator builds succeed, cancellation is safe, and no unrelated UI/persistence/drawing behavior changes.

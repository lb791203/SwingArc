# Precision Swing Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an evidence-backed, on-device DTL/Face-on pipeline that measures P1–P8, visible body motion, clubhead trajectory, and supported 2D swing parameters without inventing results when evidence is missing.

**Architecture:** Keep the existing Vision and constrained stage solver as the baseline, but move their outputs into a versioned frame-observation contract. Add input-quality rejection, continuous pose/club tracking, a replaceable Core ML golf-object provider, deterministic metric calculation, and a held-out evaluator. Model promotion is gated by the confirmed accuracy thresholds; the current eight videos can establish the baseline and training workflow but cannot prove final accuracy.

**Tech Stack:** Swift 5 language mode, SwiftUI, AVFoundation, Vision, Core ML, iOS 17 deployment target, standalone `swiftc` smoke tests, Python/PyTorch for the offline golf-keypoint candidate, and `coremltools` ML Program conversion.

## Global Constraints

- Support only fixed-camera DTL and Face-on clips with the full person, club, clubhead, and ball visible through the critical swing interval.
- P1–P8 uses standard `p-system-v1`: P6 is downswing shaft-parallel, P7 is impact, and P8 is post-impact shaft-parallel.
- For each view and each P stage, at least 90% of held-out results must be within ±2 source frames; unresolved and false confirmations count as failures.
- Visible body landmarks must have median 2D error no greater than 3% of person height; also report P90 and miss rate.
- At least 90% of visible clubhead frames must be tracked within 2% of frame diagonal.
- Training, validation, and held-out sets are split by golfer, never by frame or clip. The final held-out set contains at least 10 golfers not used for training or tuning.
- `/Users/liangbo/Desktop/test` is development data only after it is used for baseline or tuning.
- Detection, estimation, occlusion, out-of-frame, and missing states remain distinct in storage and UI. Estimated points never count as measured acceptance hits.
- Unsupported single-camera outputs—true 3D joint rotation, true club speed, attack angle, face angle, dynamic loft, ball launch/spin/carry—must not be presented as measured values.
- User-corrected stages and landmarks remain movable, are stored as manual truth, and are never overwritten by reanalysis.
- Raw videos and labels stay local unless the user explicitly exports an authorized training bundle.

---

## File Structure

New production files have one responsibility each:

- `SwingArc/Models/SwingObservationModels.swift`: versioned frame, landmark, trajectory, provenance, and analysis-artifact value types.
- `SwingArc/Models/SwingMetricModels.swift`: supported 2D metric identifiers, values, units, and availability reasons.
- `SwingArc/Services/SwingInputQualityEvaluator.swift`: fixed-camera, coverage, blur, and view-quality gate.
- `SwingArc/Services/SwingPoseObservationAdapter.swift`: converts Vision pose output into the common landmark contract.
- `SwingArc/Services/SwingTrajectoryTracker.swift`: time-aware smoothing and detected/estimated/missing state transitions.
- `SwingArc/Services/GolfObjectObservationProvider.swift`: replaceable golf-object provider protocol and current-contour compatibility adapter.
- `SwingArc/Services/CoreMLGolfObjectDetector.swift`: Core ML preprocessing and output decoding only.
- `SwingArc/Services/SwingMetricEngine.swift`: deterministic calculation of supported 2D parameters.
- `SwingArc/Views/SwingTrajectoryOverlay.swift`: measured, estimated, and missing trajectory presentation.
- `Tools/PrecisionDataset/`: video inventory, manifest validation, label export, and acceptance reporting.
- `Training/golf_keypoints/`: offline model, dataset loader, training, evaluation, and Core ML conversion.

The existing large files remain orchestration owners: `VisionPoseDetector.swift` decodes/analyzes frames, `SwingStageDetector.swift` resolves P stages, `CustomVideoPlayer.swift` publishes analysis, and `AnalysisWorkspaceView.swift` composes the UI. New algorithms do not get added directly to those files.

---

### Task 1: Replace the obsolete ±1-frame acceptance contract with the confirmed dataset-level gate

**Files:**
- Modify: `Tests/P1P8AcceptanceSupport.swift:1-190`
- Modify: `Tests/P1P8AcceptanceEvaluationSmoke.swift:1-240`
- Create: `Tests/SwingPrecisionAcceptanceSmoke.swift`
- Modify: `README.md:96-160`

**Interfaces:**
- Consumes: `GroundTruthManifest`, `StageAcceptance`, and `SwingAnalysisResult`.
- Produces: `SwingPrecisionAcceptance.summarize(records:) -> PrecisionAcceptanceSummary` and a single confirmed `maximumAcceptedFrameError == 2` contract.

- [ ] **Step 1: Write the failing dataset-level test**

```swift
import Foundation

@main
struct SwingPrecisionAcceptanceSmoke {
    static func main() {
        let records = (0..<10).map { index in
            PrecisionStageRecord(
                view: .downTheLine,
                stage: "P6",
                expectedFrame: 100,
                actualFrame: index == 9 ? nil : 102,
                status: index == 9 ? "unresolved" : "confirmed"
            )
        }
        let summary = SwingPrecisionAcceptance.summarize(records: records)
        precondition(summary.stageRates[.init(view: .downTheLine, stage: "P6")] == 0.9)
        precondition(summary.passed)

        var failedRecords = records
        failedRecords[8] = PrecisionStageRecord(
            view: .downTheLine,
            stage: "P6",
            expectedFrame: 100,
            actualFrame: 103,
            status: "confirmed"
        )
        precondition(!SwingPrecisionAcceptance.summarize(records: failedRecords).passed)
    }
}
```

- [ ] **Step 2: Run the test and verify that it fails**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/SwingStageDetector.swift \
  Tests/P1P8AcceptanceSupport.swift \
  Tests/SwingPrecisionAcceptanceSmoke.swift \
  -o /tmp/swing-precision-acceptance
```

Expected: compilation fails because `PrecisionStageRecord` and `SwingPrecisionAcceptance` do not exist.

- [ ] **Step 3: Implement the two-frame and 90% contracts**

Add these value types to `P1P8AcceptanceSupport.swift` and change both manifest validation and `RealVideoAcceptance.maximumAcceptedFrameError` from `1` to `2`:

```swift
enum PrecisionCameraView: String, Codable, Hashable {
    case downTheLine = "dtl"
    case faceOn = "face-on"
}

struct PrecisionStageRecord: Codable, Equatable {
    let view: PrecisionCameraView
    let stage: String
    let expectedFrame: Int
    let actualFrame: Int?
    let status: String
}

struct PrecisionStageKey: Hashable {
    let view: PrecisionCameraView
    let stage: String
}

struct PrecisionAcceptanceSummary: Equatable {
    let stageRates: [PrecisionStageKey: Double]
    let passed: Bool
}

enum SwingPrecisionAcceptance {
    static let maximumFrameError = 2
    static let minimumStageRate = 0.90

    static func summarize(records: [PrecisionStageRecord]) -> PrecisionAcceptanceSummary {
        let grouped = Dictionary(grouping: records) {
            PrecisionStageKey(view: $0.view, stage: $0.stage)
        }
        let rates = grouped.mapValues { items in
            Double(items.filter { item in
                guard item.status != "unresolved", let actual = item.actualFrame else { return false }
                return abs(actual - item.expectedFrame) <= maximumFrameError
            }.count) / Double(items.count)
        }
        return PrecisionAcceptanceSummary(
            stageRates: rates,
            passed: !rates.isEmpty && rates.values.allSatisfy { $0 >= minimumStageRate }
        )
    }
}
```

Update the canonical fixture in `P1P8AcceptanceEvaluationSmoke.swift` to `maximumAcceptedFrameError: 2`; verify a `+2` result passes and a `+3` result fails. Update README so it no longer claims ±1-frame acceptance or four-video generalization.

- [ ] **Step 4: Run acceptance regression tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/PracticeModels.swift \
  Tests/P1P8AcceptanceSupport.swift \
  Tests/SwingPrecisionAcceptanceSmoke.swift \
  -o /tmp/swing-precision-acceptance && /tmp/swing-precision-acceptance

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  -framework AVFoundation -framework Vision -framework ImageIO \
  -framework SwiftUI -framework CoreVideo \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/SwingStageDetector.swift \
  Tests/P1P8AcceptanceSupport.swift \
  Tests/P1P8AcceptanceEvaluationSmoke.swift \
  Tests/Fixtures/IMG_4500-ground-truth.json \
  -o /tmp/p1p8-contract && /tmp/p1p8-contract Tests/Fixtures/IMG_4500-ground-truth.json
```

Expected: both executables exit 0; the legacy manifest remains report-only.

- [ ] **Step 5: Commit**

```bash
git add README.md Tests/P1P8AcceptanceSupport.swift Tests/P1P8AcceptanceEvaluationSmoke.swift Tests/SwingPrecisionAcceptanceSmoke.swift
git commit -m "test: define precision swing acceptance gates"
```

### Task 2: Inventory the eight development videos and create an auditable label manifest

**Files:**
- Create: `Tools/PrecisionDataset/PrecisionDatasetModels.swift`
- Create: `Tools/PrecisionDataset/InventoryVideos.swift`
- Create: `Tools/PrecisionDataset/ValidateManifest.swift`
- Create: `Tests/PrecisionDatasetManifestSmoke.swift`
- Create: `docs/validation/precision-dataset/README.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: original MOV metadata and manual labels.
- Produces: `precision-dataset.json` entries with golfer ID, authorization, split, view, handedness, source metadata, P labels, visible landmark labels, and club labels.

- [ ] **Step 1: Write the failing manifest validation test**

```swift
import Foundation

@main
struct PrecisionDatasetManifestSmoke {
    static func main() throws {
        let clip = PrecisionClipManifest(
            clipID: "golfer-001-dtl-001",
            golferID: "golfer-001",
            fileName: "IMG_4694.MOV",
            view: .downTheLine,
            handedness: .right,
            split: .development,
            authorization: .trainingAllowed,
            sourceFrameRate: 30,
            duration: 45.5,
            annotationPasses: 0,
            stages: [],
            frameLabels: []
        )
        precondition(PrecisionManifestValidator.errors(in: [clip]) == [.missingDoublePass("golfer-001-dtl-001")])
    }
}
```

- [ ] **Step 2: Run the test and verify that it fails**

Run:

```bash
xcrun swiftc -parse-as-library \
  Tools/PrecisionDataset/PrecisionDatasetModels.swift \
  Tools/PrecisionDataset/ValidateManifest.swift \
  Tests/PrecisionDatasetManifestSmoke.swift \
  -o /tmp/precision-manifest
```

Expected: fails because the files and types do not exist.

- [ ] **Step 3: Implement the manifest contract and validator**

Use these exact enums and top-level clip fields:

```swift
enum DatasetView: String, Codable { case downTheLine = "dtl", faceOn = "face-on" }
enum DatasetHandedness: String, Codable { case left, right }
enum DatasetSplit: String, Codable { case development, training, validation, heldOut = "held-out" }
enum VideoAuthorization: String, Codable { case internalReview = "internal-review", trainingAllowed = "training-allowed" }

struct NormalizedLabelPoint: Codable, Equatable {
    let x: Double
    let y: Double
    let visibility: String
}

struct PrecisionFrameLabel: Codable, Equatable {
    let sourceFrameIndex: Int
    let landmarks: [String: NormalizedLabelPoint]
    let reviewer: String
    let reviewed: Bool
}

struct PrecisionStageLabel: Codable, Equatable {
    let stage: String
    let annotatorFrames: [String: Int]
    let adjudicatedSourceFrameIndex: Int?
}

struct PrecisionClipManifest: Codable, Equatable {
    let clipID: String
    let golferID: String
    let fileName: String
    let view: DatasetView
    let handedness: DatasetHandedness
    let split: DatasetSplit
    let authorization: VideoAuthorization
    let sourceFrameRate: Double
    let duration: Double
    let annotationPasses: Int
    let stages: [PrecisionStageLabel]
    let frameLabels: [PrecisionFrameLabel]
}

enum PrecisionManifestError: Equatable {
    case duplicateClipID(String)
    case golferSplitLeak(String)
    case missingDoublePass(String)
    case invalidStageOrder(String)
    case trainingNotAuthorized(String)
}
```

`PrecisionManifestValidator.errors(in:)` must reject duplicate clip IDs, a golfer appearing in multiple splits, training/validation clips without `trainingAllowed`, any stage with fewer than two distinct annotators, any disagreement greater than two frames without `adjudicatedSourceFrameIndex`, resolved canonical stage frames that are not strictly increasing, unreviewed frame labels used for training, and any clip with fewer than two annotation passes.

- [ ] **Step 4: Implement and run video inventory**

`InventoryVideos.swift` loads each AVAsset, emits file name, duration, nominal FPS, dimensions, and an empty development manifest entry. It must not copy or commit video bytes.

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library -framework AVFoundation \
  Tools/PrecisionDataset/PrecisionDatasetModels.swift \
  Tools/PrecisionDataset/InventoryVideos.swift \
  -o /tmp/inventory-precision-videos

/tmp/inventory-precision-videos /Users/liangbo/Desktop/test \
  > docs/validation/precision-dataset/development-inventory.json
```

Expected: eight manifest entries, all referencing MOV file names without embedding absolute paths or video data. Add `docs/validation/precision-dataset/labels/` and `Training/data/` to `.gitignore`; document that authorized manifests may be committed but raw videos remain external.

- [ ] **Step 5: Run validation and commit**

```bash
xcrun swiftc -parse-as-library \
  Tools/PrecisionDataset/PrecisionDatasetModels.swift \
  Tools/PrecisionDataset/ValidateManifest.swift \
  Tests/PrecisionDatasetManifestSmoke.swift \
  -o /tmp/precision-manifest && /tmp/precision-manifest

git add .gitignore Tools/PrecisionDataset Tests/PrecisionDatasetManifestSmoke.swift docs/validation/precision-dataset
git commit -m "feat: add precision dataset manifest tooling"
```

### Task 3: Introduce versioned frame-observation and metric contracts

**Files:**
- Create: `SwingArc/Models/SwingObservationModels.swift`
- Create: `SwingArc/Models/SwingMetricModels.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`
- Create: `Tests/SwingObservationModelsSmoke.swift`

**Interfaces:**
- Consumes: source frame/time and normalized model outputs.
- Produces: `SwingFrameObservation`, `TrackedSwingPoint`, `SwingTrajectory`, `SwingAnalysisArtifact`, and `SwingMetricValue` used by every later task.

- [ ] **Step 1: Write the failing contract test**

```swift
import Foundation

@main
struct SwingObservationModelsSmoke {
    static func main() throws {
        let point = TrackedSwingPoint(
            point: .init(x: 0.25, y: 0.5),
            confidence: 0.92,
            state: .detected,
            source: .visionPose
        )
        let data = try JSONEncoder().encode(point)
        precondition(try JSONDecoder().decode(TrackedSwingPoint.self, from: data) == point)
        precondition(!point.isEstimated)
        precondition(SwingMetricID.trueClubheadSpeed.isSupportedBySingleCamera == false)
    }
}
```

- [ ] **Step 2: Run the test and verify that it fails**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  Tests/SwingObservationModelsSmoke.swift \
  -o /tmp/swing-observation-models
```

Expected: fails because the production model files do not exist.

- [ ] **Step 3: Implement the production contracts**

Use normalized coordinates independent of CoreGraphics serialization:

```swift
struct NormalizedPoint: Codable, Hashable {
    let x: Double
    let y: Double
}

enum SwingPointState: String, Codable { case detected, estimated, occluded, outOfFrame, missing }
enum SwingPointSource: String, Codable { case visionPose, contour, coreMLGolf, temporalPrediction, manual }

struct TrackedSwingPoint: Codable, Equatable {
    let point: NormalizedPoint?
    let confidence: Double
    let state: SwingPointState
    let source: SwingPointSource
    var isEstimated: Bool { state == .estimated || source == .temporalPrediction }
}

enum SwingLandmark: String, Codable, CaseIterable {
    case head, leftShoulder, rightShoulder, leftElbow, rightElbow
    case leftWrist, rightWrist, leftHip, rightHip, leftKnee, rightKnee
    case leftAnkle, rightAnkle, handCenter, grip, shaftStart, shaftEnd, clubhead, ball
}

struct SwingFrameObservation: Codable, Equatable {
    let sourceFrameIndex: Int
    let time: Double
    let rawLandmarks: [SwingLandmark: TrackedSwingPoint]
    let landmarks: [SwingLandmark: TrackedSwingPoint]

    init(
        sourceFrameIndex: Int,
        time: Double,
        landmarks: [SwingLandmark: TrackedSwingPoint],
        rawLandmarks: [SwingLandmark: TrackedSwingPoint]? = nil
    ) {
        self.sourceFrameIndex = sourceFrameIndex
        self.time = time
        self.rawLandmarks = rawLandmarks ?? landmarks
        self.landmarks = landmarks
    }
}

struct TimedTrackedPoint: Codable, Equatable {
    let sourceFrameIndex: Int
    let time: Double
    let value: TrackedSwingPoint
}

struct SwingTrajectory: Codable, Equatable {
    let landmark: SwingLandmark
    let samples: [TimedTrackedPoint]
}

struct SwingStageArtifact: Codable, Equatable {
    let code: String
    let sourceFrameIndex: Int?
    let time: Double?
    let confidence: Double
    let status: String
    let evidenceSources: [String]
    let manuallyLocked: Bool
}

struct SwingAnalysisArtifact: Codable, Equatable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let modelVersion: String
    let view: String
    let sourceFrameRate: Double
    let qualityIssues: [String]
    let frames: [SwingFrameObservation]
    let stages: [SwingStageArtifact]
    let metrics: [SwingMetricValue]
}
```

Define the metric contract completely in `SwingMetricModels.swift`:

```swift
enum SwingMetricID: String, Codable, CaseIterable {
    case backswingTime, downswingTime, tempoRatio
    case spineTilt2D, shoulderLineAngle2D, hipLineAngle2D
    case leadElbowAngle, trailElbowAngle, leadKneeAngle, trailKneeAngle
    case headHorizontalDisplacement, headVerticalDisplacement
    case hipHorizontalDisplacement, hipVerticalDisplacement
    case handPathLength, clubheadPathLength, clubheadRelativeSpeed2D
    case shaftProjectionAngle, swingPlaneProxy2D, hipShoulderSeparationProxy2D
    case trueClubheadSpeed, attackAngle, faceAngle, dynamicLoft
    case ballSpeed, launchAngle, spinRate, carryDistance

    var isSupportedBySingleCamera: Bool {
        switch self {
        case .trueClubheadSpeed, .attackAngle, .faceAngle, .dynamicLoft,
             .ballSpeed, .launchAngle, .spinRate, .carryDistance:
            return false
        default:
            return true
        }
    }
}

enum SwingMetricUnavailableReason: String, Codable, Equatable {
    case missingEvidence, lowConfidence, estimatedInput
    case requiresCalibrated3DOrSensor
}

enum SwingMetricAvailability: Codable, Equatable {
    case measured
    case estimated
    case unavailable(reason: SwingMetricUnavailableReason)
}

struct SwingMetricValue: Codable, Equatable {
    let id: SwingMetricID
    let value: Double?
    let unit: String
    let confidence: Double
    let stage: String?
    let availability: SwingMetricAvailability
}
```

- [ ] **Step 4: Add files to the Xcode target and run tests**

Add explicit PBX file references, source build entries, and group entries for both model files. Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  Tests/SwingObservationModelsSmoke.swift \
  -o /tmp/swing-observation-models && /tmp/swing-observation-models

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project SwingArcProject.xcodeproj -scheme SwingArcProject \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: smoke test exits 0 and Xcode build ends with `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add SwingArc/Models/SwingObservationModels.swift SwingArc/Models/SwingMetricModels.swift SwingArcProject.xcodeproj/project.pbxproj Tests/SwingObservationModelsSmoke.swift
git commit -m "feat: add versioned swing observation contracts"
```

### Task 4: Reject unsupported input before stage analysis

**Files:**
- Create: `SwingArc/Services/SwingInputQualityEvaluator.swift`
- Modify: `SwingArc/Models/WorkspaceModels.swift:49-132`
- Modify: `SwingArc/Services/VisionPoseDetector.swift:650-780`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`
- Create: `Tests/SwingInputQualityEvaluatorSmoke.swift`

**Interfaces:**
- Consumes: sampled frame dimensions, pose coverage, subject bounds, camera-motion signal, blur score, and requested view.
- Produces: `SwingInputQualityReport` with stable issue codes and a blocking/nonblocking decision.

- [ ] **Step 1: Write the failing quality-gate test**

```swift
@main
struct SwingInputQualityEvaluatorSmoke {
    static func main() {
        let rejected = SwingInputQualityEvaluator.evaluate(.init(
            poseFrameCoverage: 0.95,
            fullBodyCoverage: 0.60,
            clubCoverage: 0.90,
            cameraMotion: 0.01,
            medianBlurScore: 0.80
        ))
        precondition(!rejected.isSupported)
        precondition(rejected.issues == [.fullBodyNotVisible])

        let accepted = SwingInputQualityEvaluator.evaluate(.init(
            poseFrameCoverage: 0.95,
            fullBodyCoverage: 0.95,
            clubCoverage: 0.92,
            cameraMotion: 0.01,
            medianBlurScore: 0.80
        ))
        precondition(accepted.isSupported)
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Services/SwingInputQualityEvaluator.swift \
  Tests/SwingInputQualityEvaluatorSmoke.swift \
  -o /tmp/swing-input-quality
```

Expected: compilation fails because the evaluator does not exist.

- [ ] **Step 3: Implement deterministic quality rules**

```swift
struct SwingInputQualitySignals: Equatable {
    let poseFrameCoverage: Double
    let fullBodyCoverage: Double
    let clubCoverage: Double?
    let cameraMotion: Double
    let medianBlurScore: Double
}

enum SwingInputQualityIssue: String, Codable, Equatable {
    case personNotStable, fullBodyNotVisible, clubNotVisible
    case clubVisibilityNotAssessed, cameraMoved, motionBlur
}

struct SwingInputQualityReport: Equatable {
    let blockingIssues: [SwingInputQualityIssue]
    let warnings: [SwingInputQualityIssue]
    var issues: [SwingInputQualityIssue] { blockingIssues + warnings }
    var isSupported: Bool { blockingIssues.isEmpty }
}

enum SwingInputQualityEvaluator {
    static func evaluate(_ signal: SwingInputQualitySignals) -> SwingInputQualityReport {
        var blocking: [SwingInputQualityIssue] = []
        var warnings: [SwingInputQualityIssue] = []
        if signal.poseFrameCoverage < 0.85 { blocking.append(.personNotStable) }
        if signal.fullBodyCoverage < 0.85 { blocking.append(.fullBodyNotVisible) }
        if let clubCoverage = signal.clubCoverage {
            if clubCoverage < 0.80 { blocking.append(.clubNotVisible) }
        } else {
            warnings.append(.clubVisibilityNotAssessed)
        }
        if signal.cameraMotion > 0.04 { blocking.append(.cameraMoved) }
        if signal.medianBlurScore < 0.35 { blocking.append(.motionBlur) }
        return SwingInputQualityReport(blockingIssues: blocking, warnings: warnings)
    }
}
```

Add a distinct `AnalysisFailure.unsupportedInput([SwingInputQualityIssue])` presentation. Run quality evaluation after the coarse scan has enough frames but before fine P-stage extraction; keep the video playable when rejected.

- [ ] **Step 4: Run quality, failure-copy, and build tests**

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Services/SwingInputQualityEvaluator.swift \
  Tests/SwingInputQualityEvaluatorSmoke.swift \
  -o /tmp/swing-input-quality && /tmp/swing-input-quality

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project SwingArcProject.xcodeproj -scheme SwingArcProject \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: test exits 0; build succeeds; rejected media remains a project with a specific reshoot message.

- [ ] **Step 5: Commit**

```bash
git add SwingArc/Services/SwingInputQualityEvaluator.swift SwingArc/Models/WorkspaceModels.swift SwingArc/Services/VisionPoseDetector.swift SwingArcProject.xcodeproj/project.pbxproj Tests/SwingInputQualityEvaluatorSmoke.swift
git commit -m "feat: reject unsupported swing video inputs"
```

### Task 5: Produce continuous, provenance-aware body trajectories

**Files:**
- Create: `SwingArc/Services/SwingPoseObservationAdapter.swift`
- Create: `SwingArc/Services/SwingTrajectoryTracker.swift`
- Modify: `SwingArc/Services/VisionPoseDetector.swift:7-170,1080-1235`
- Modify: `SwingArc/Services/SwingStageDetector.swift:4-78`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`
- Create: `Tests/SwingPoseObservationAdapterSmoke.swift`
- Create: `Tests/SwingTrajectoryTrackerSmoke.swift`

**Interfaces:**
- Consumes: `PoseEstimationResult`, exact source frame index, and time.
- Produces: one `SwingFrameObservation` per decoded fine frame and time-aware tracked points without changing source-frame identity.

- [ ] **Step 1: Write failing adapter and tracker tests**

```swift
var pose = PoseEstimationResult()
pose.keypoints["leftWrist"] = JointKeypoint(
    name: "leftWrist",
    position: CGPoint(x: 0.2, y: 0.4),
    confidence: 0.9
)
let frame = SwingPoseObservationAdapter.frame(
    pose: pose,
    sourceFrameIndex: 12,
    time: 0.4
)
precondition(frame.landmarks[.leftWrist]?.source == .visionPose)

var tracker = SwingTrajectoryTracker(maximumPredictionFrames: 2)
_ = tracker.update(frame)
let missing = SwingFrameObservation(sourceFrameIndex: 13, time: 0.433, landmarks: [:])
let predicted = tracker.update(missing)
precondition(predicted.landmarks[.leftWrist]?.state == .estimated)
let thirdMissing = tracker.update(.init(sourceFrameIndex: 15, time: 0.5, landmarks: [:]))
precondition(thirdMissing.landmarks[.leftWrist]?.state == .missing)
```

- [ ] **Step 2: Compile and verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library -framework Vision -framework SwiftUI -framework CoreVideo -framework AVFoundation \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/SwingPoseObservationAdapter.swift \
  SwingArc/Services/SwingTrajectoryTracker.swift \
  Tests/SwingPoseObservationAdapterSmoke.swift \
  -o /tmp/pose-observation-adapter

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library -framework Vision -framework SwiftUI -framework CoreVideo -framework AVFoundation \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/SwingPoseObservationAdapter.swift \
  SwingArc/Services/SwingTrajectoryTracker.swift \
  Tests/SwingTrajectoryTrackerSmoke.swift \
  -o /tmp/body-trajectory
```

Expected: compilation fails because adapter and tracker are absent.

- [ ] **Step 3: Implement adapter and bounded constant-velocity prediction**

The adapter maps every known Vision name to `SwingLandmark`, preserves the original per-point confidence, derives `.handCenter` only when at least one wrist is detected, and never derives a missing joint from a body ratio.

`SwingTrajectoryTracker` stores the last two detected points per landmark. For no more than `maximumPredictionFrames`, use:

```swift
let dt = currentTime - previousTime
let priorDt = previousTime - olderTime
let vx = (previous.x - older.x) / priorDt
let vy = (previous.y - older.y) / priorDt
let predicted = NormalizedPoint(
    x: min(1, max(0, previous.x + vx * dt)),
    y: min(1, max(0, previous.y + vy * dt))
)
```

Mark that point `.estimated` with `.temporalPrediction`. After the bound, emit `.missing` with a nil point. Detected points always replace predictions. Feed the tracked body frame to the stage feature extractor, but retain the raw frame in the final artifact.

- [ ] **Step 4: Run trajectory regression and build**

Run both Step 2 compile commands with `&& /tmp/pose-observation-adapter` and `&& /tmp/body-trajectory`, then run the existing `SwingTemporalEvidenceSmoke.swift` command used by the repository. Expected: new tests and existing temporal evidence pass; every fine frame retains its original frame index.

- [ ] **Step 5: Commit**

```bash
git add SwingArc/Models/SwingObservationModels.swift SwingArc/Services/SwingPoseObservationAdapter.swift SwingArc/Services/SwingTrajectoryTracker.swift SwingArc/Services/VisionPoseDetector.swift SwingArc/Services/SwingStageDetector.swift SwingArcProject.xcodeproj/project.pbxproj Tests/SwingPoseObservationAdapterSmoke.swift Tests/SwingTrajectoryTrackerSmoke.swift
git commit -m "feat: track continuous body trajectories"
```

### Task 6: Establish the golf-object label and training pipeline

**Files:**
- Create: `Training/golf_keypoints/requirements.in`
- Create: `Training/golf_keypoints/model.py`
- Create: `Training/golf_keypoints/dataset.py`
- Create: `Training/golf_keypoints/train.py`
- Create: `Training/golf_keypoints/evaluate.py`
- Create: `Training/golf_keypoints/export_coreml.py`
- Create: `Training/golf_keypoints/test_contract.py`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: authorized frame crops and five labelled points: grip, shaft start, shaft end, clubhead, and ball, each with visibility.
- Produces: `golf_keypoints.pt`, a JSON evaluation report, and `GolfKeypoints.mlpackage` only when the validation gate passes.

- [ ] **Step 1: Write the failing tensor-contract test**

```python
import torch
from model import GolfKeypointNet

def test_output_contract():
    coordinates, visibility = GolfKeypointNet()(torch.zeros(2, 3, 256, 256))
    assert coordinates.shape == (2, 5, 2)
    assert visibility.shape == (2, 5)
    assert torch.all((coordinates >= 0) & (coordinates <= 1))
```

- [ ] **Step 2: Create an isolated environment and verify failure**

Run:

```bash
python3 -m venv .venv-golf-keypoints
source .venv-golf-keypoints/bin/activate
python -m pip install --upgrade pip
python -m pip install torch torchvision coremltools pillow pytest
python -m pip freeze > Training/golf_keypoints/requirements-lock.txt
pytest Training/golf_keypoints/test_contract.py -q
```

Expected: import fails because `model.py` does not exist.

- [ ] **Step 3: Implement the model contract**

```python
import torch
from torch import nn
from torchvision.models import mobilenet_v3_small, MobileNet_V3_Small_Weights

class GolfKeypointNet(nn.Module):
    def __init__(self):
        super().__init__()
        network = mobilenet_v3_small(weights=MobileNet_V3_Small_Weights.DEFAULT)
        input_features = network.classifier[-1].in_features
        network.classifier[-1] = nn.Linear(input_features, 15)
        self.network = network

    def forward(self, image):
        output = self.network(image)
        coordinates = torch.sigmoid(output[:, :10]).reshape(-1, 5, 2)
        visibility = output[:, 10:]
        return coordinates, visibility
```

`dataset.py` reads only manifest entries whose authorization is `training-allowed`, applies the golfer-level split already present in the manifest, returns a normalized `3×256×256` tensor, `5×2` coordinates, and a five-value visibility mask. `train.py` uses masked Smooth L1 coordinate loss plus binary-cross-entropy visibility loss and records the manifest SHA-256 in the checkpoint.

`requirements.in` contains the direct dependencies; `requirements-lock.txt` records the versions actually verified on this Mac:

```text
torch
torchvision
coremltools
pillow
pytest
```

Use this exact loss boundary in `train.py` so hidden points do not contribute coordinate error:

```python
predicted_coordinates, visibility_logits = model(images)
visible = visibility_targets.unsqueeze(-1)
coordinate_error = torch.nn.functional.smooth_l1_loss(
    predicted_coordinates * visible,
    coordinate_targets * visible,
    reduction="sum",
) / visible.sum().clamp_min(1.0)
visibility_error = torch.nn.functional.binary_cross_entropy_with_logits(
    visibility_logits,
    visibility_targets,
)
loss = coordinate_error + 0.25 * visibility_error
```

- [ ] **Step 4: Implement evaluation and Core ML export**

`evaluate.py` must emit per-landmark visible-frame hit rate and diagonal-normalized error. `export_coreml.py` uses this complete conversion boundary:

```python
import argparse
import coremltools as ct
import torch
from model import GolfKeypointNet

parser = argparse.ArgumentParser()
parser.add_argument("--checkpoint", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()

network = GolfKeypointNet()
network.load_state_dict(torch.load(args.checkpoint, map_location="cpu")["model"])
network.eval()
example = torch.zeros(1, 3, 256, 256)
traced = torch.jit.trace(network, example)
converted = ct.convert(
    traced,
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS17,
    inputs=[ct.ImageType(name="image", shape=example.shape, scale=1 / 255.0)],
    outputs=[ct.TensorType(name="coordinates"), ct.TensorType(name="visibility")],
)
converted.author = "SwingArc"
converted.short_description = "Golf grip, shaft, clubhead, and ball keypoints"
converted.save(args.output)
```

Promotion requires clubhead hit rate ≥0.90 at error ≤0.02; a failing candidate remains under `Training/artifacts/` and is not added to the app.

Run:

```bash
source .venv-golf-keypoints/bin/activate
pytest Training/golf_keypoints/test_contract.py -q
python Training/golf_keypoints/train.py \
  --manifest docs/validation/precision-dataset/precision-dataset.json \
  --video-root /Users/liangbo/Desktop/test \
  --output Training/artifacts/golf_keypoints.pt
python Training/golf_keypoints/evaluate.py \
  --checkpoint Training/artifacts/golf_keypoints.pt \
  --manifest docs/validation/precision-dataset/precision-dataset.json \
  --split validation \
  --output Training/artifacts/golf_keypoints-validation.json
```

Expected now: training must stop with a clear “reviewed training labels required” error until the frame labels are complete. After labels exist, evaluation produces a report; export runs only if the report passes the gate.

- [ ] **Step 5: Commit tooling without raw videos or failed model artifacts**

```bash
git add .gitignore Training/golf_keypoints
git commit -m "feat: add golf keypoint training pipeline"
```

### Task 7: Integrate a replaceable golf-object provider and continuous clubhead tracker

**Files:**
- Create: `SwingArc/Services/GolfObjectObservationProvider.swift`
- Create: `SwingArc/Services/CoreMLGolfObjectDetector.swift`
- Modify: `SwingArc/Services/VisionPoseDetector.swift:1080-1235`
- Modify: `SwingArc/Services/SwingStageDetector.swift:80-220`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`
- Create: `Tests/GolfObjectObservationProviderSmoke.swift`
- Create: `Tests/ClubheadTrajectoryTrackerSmoke.swift`

**Interfaces:**
- Consumes: `CGImage`, pose ROI, and optional promoted Core ML model.
- Produces: frame-level grip, shaft endpoints, clubhead, and ball observations with detection state and confidence.

- [ ] **Step 1: Write failing fake-provider and tracker tests**

```swift
struct FakeGolfProvider: GolfObjectObservationProvider {
    let observation: GolfObjectObservation
    func observe(image: CGImage, pose: PoseEstimationResult?) throws -> GolfObjectObservation {
        observation
    }
}

let detected = TrackedSwingPoint(
    point: .init(x: 0.7, y: 0.6), confidence: 0.95,
    state: .detected, source: .coreMLGolf
)
let observation = GolfObjectObservation(points: [.clubhead: detected])
precondition(observation.points[.clubhead]?.state == .detected)
```

- [ ] **Step 2: Compile and verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library -framework CoreML -framework Vision -framework SwiftUI -framework AVFoundation -framework CoreVideo \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/GolfObjectObservationProvider.swift \
  SwingArc/Services/CoreMLGolfObjectDetector.swift \
  Tests/GolfObjectObservationProviderSmoke.swift \
  -o /tmp/golf-object-provider

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library -framework CoreML -framework Vision -framework SwiftUI -framework AVFoundation -framework CoreVideo \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/GolfObjectObservationProvider.swift \
  SwingArc/Services/CoreMLGolfObjectDetector.swift \
  Tests/ClubheadTrajectoryTrackerSmoke.swift \
  -o /tmp/clubhead-trajectory-tracker
```

Expected: compilation fails because the provider contract is absent.

- [ ] **Step 3: Implement provider, compatibility adapter, and tracker**

```swift
struct GolfObjectObservation: Equatable {
    let points: [SwingLandmark: TrackedSwingPoint]
}

protocol GolfObjectObservationProvider {
    func observe(image: CGImage, pose: PoseEstimationResult?) throws -> GolfObjectObservation
}

enum GolfObjectProviderError: Error, Equatable {
    case modelUnavailable
    case invalidOutput
}
```

`CoreMLGolfObjectDetector` loads an `MLModel` URL, resizes with aspect-fit metadata, decodes `coordinates` and `visibility`, maps all points back to normalized full-frame coordinates, and rejects visibility probabilities below 0.5. The contour compatibility adapter emits only shaft endpoints and ball; it never fabricates a clubhead. Use the Task 5 tracker for the same two-frame maximum prediction, but keep golf-object state separate from body state.

- [ ] **Step 4: Promote a model only after validation**

If Task 6 passes, run `export_coreml.py`, add `SwingArc/ML/GolfKeypoints.mlpackage` as an Xcode resource, and record the manifest hash and evaluation report in model metadata. If it fails, ship the provider as unavailable and keep all clubhead-dependent metrics unavailable; do not weaken the threshold.

Run tests and an unsigned build. Expected: fake-provider tests pass in all cases; a promoted model additionally passes a 20-frame golden-output comparison between Python and Core ML within `0.005` normalized coordinate error.

- [ ] **Step 5: Commit**

```bash
git add SwingArc/Services/GolfObjectObservationProvider.swift SwingArc/Services/CoreMLGolfObjectDetector.swift SwingArc/Services/VisionPoseDetector.swift SwingArc/Services/SwingStageDetector.swift SwingArcProject.xcodeproj/project.pbxproj Tests/GolfObjectObservationProviderSmoke.swift Tests/ClubheadTrajectoryTrackerSmoke.swift
git commit -m "feat: integrate tracked golf object observations"
```

### Task 8: Resolve P1–P8 from continuous body and club evidence

**Files:**
- Modify: `SwingArc/Services/SwingStageDetector.swift:202-2365`
- Modify: `SwingArc/Services/VisionPoseDetector.swift:1080-1235`
- Modify: `Tests/BidirectionalStageSolverSmoke.swift`
- Modify: `Tests/P1P8AcceptanceSupport.swift`
- Create: `Tests/ContinuousEvidenceStageSolverSmoke.swift`

**Interfaces:**
- Consumes: continuous `SwingFrameObservation` plus raw pose samples.
- Produces: canonical detections with evidence-source lists and honest unresolved stages.

- [ ] **Step 1: Write failing canonical-evidence tests**

Create a 30 FPS fixture where P2, P6, and P8 each have a detected horizontal shaft, P7 has detected clubhead/ball alignment, and all body transitions are ordered. Assert all eight frames match the fixture. Create variants removing P6 shaft, P8 shaft, and P7 clubhead/ball evidence; assert only the affected stage is unresolved and no neighboring frame is substituted.

- [ ] **Step 2: Run and verify failure**

Run the existing `BidirectionalStageSolverSmoke.swift` compile command plus `ContinuousEvidenceStageSolverSmoke.swift`. Expected: the continuous-evidence fixture fails because `SwingStageDetection` stores only boolean object evidence and the engine samples objects sparsely.

- [ ] **Step 3: Extend stage evidence without weakening canonical semantics**

Add:

```swift
enum StageEvidenceSource: String, Codable, Hashable {
    case bodyPose, grip, shaft, clubhead, ball, temporalTransition, manual
}

struct StageEvidenceSummary: Codable, Equatable {
    let sources: Set<StageEvidenceSource>
    let detectedPointCount: Int
    let estimatedPointCount: Int
}
```

Attach the summary to `SwingStageDetection`. P2/P6/P8 require `.shaft` from detected points, not estimated points. P7 requires detected `.clubhead` plus `.ball`, or an independently detected ball-change event. Preserve ordered constrained solving and exact source-frame references. Replace the 32-frame sparse object pass with continuous inference inside the already bounded fine window only after a model passes Task 6; until then, preserve sparse contour evidence and keep unsupported stages unresolved.

- [ ] **Step 4: Run synthetic, legacy, and real-development reports**

Run all stage smoke tests, the acceptance contract tests, then run `RealVideoP1P8Acceptance` for every completed manifest in `/Users/liangbo/Desktop/test`. Expected: tests pass; development reports may fail the 90% gate and must preserve their actual rates.

- [ ] **Step 5: Commit**

```bash
git add SwingArc/Services/SwingStageDetector.swift SwingArc/Services/VisionPoseDetector.swift Tests/BidirectionalStageSolverSmoke.swift Tests/ContinuousEvidenceStageSolverSmoke.swift Tests/P1P8AcceptanceSupport.swift
git commit -m "feat: solve P stages from continuous evidence"
```

### Task 9: Calculate only supported 2D swing metrics

**Files:**
- Create: `SwingArc/Services/SwingMetricEngine.swift`
- Modify: `SwingArc/Models/SwingMetricModels.swift`
- Modify: `SwingArc/Services/SwingTechniqueEvaluator.swift:132-330`
- Modify: `SwingArc/Models/WorkspaceModels.swift:413-620`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`
- Create: `Tests/SwingMetricEngineSmoke.swift`
- Modify: `Tests/SwingTechniqueEvaluatorSmoke.swift`

**Interfaces:**
- Consumes: `SwingAnalysisArtifact`, detected stage frames, view, and handedness.
- Produces: measured or unavailable values for tempo, 2D joint angles, head/hip displacement, hand/clubhead path, shaft projection, and explicitly named 2D proxies.

- [ ] **Step 1: Write failing metric tests**

```swift
let tempo = SwingMetricEngine.tempo(
    addressTime: 0.0,
    topTime: 0.9,
    impactTime: 1.2
)
precondition(tempo?.backswingSeconds == 0.9)
precondition(tempo?.downswingSeconds == 0.3)
precondition(abs((tempo?.ratio ?? 0) - 3.0) < 0.0001)

let unavailable = SwingMetricEngine.trueClubheadSpeed(frames: [])
precondition(unavailable.availability == .unavailable(reason: .requiresCalibrated3DOrSensor))
```

- [ ] **Step 2: Compile and verify failure**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Services/SwingMetricEngine.swift \
  Tests/SwingMetricEngineSmoke.swift \
  -o /tmp/swing-metrics
```

Expected: compilation fails because the metric engine is absent.

- [ ] **Step 3: Implement evidence-gated calculations**

Implement joint angle with the clamped dot product, displacement normalized by P1 person height, line projection angle with `atan2`, path length as the sum of detected-point distances, and speed only as normalized frame displacement per second. Any calculation whose input includes `.estimated`, `.missing`, or confidence below 0.65 returns unavailable unless the metric is explicitly allowed to be estimated.

Start the engine with these complete, independently testable functions:

```swift
struct SwingTempo: Equatable {
    let backswingSeconds: Double
    let downswingSeconds: Double
    let ratio: Double
}

enum SwingMetricEngine {
    static func tempo(
        addressTime: Double,
        topTime: Double,
        impactTime: Double
    ) -> SwingTempo? {
        let backswing = topTime - addressTime
        let downswing = impactTime - topTime
        guard backswing > 0, downswing > 0 else { return nil }
        return SwingTempo(
            backswingSeconds: backswing,
            downswingSeconds: downswing,
            ratio: backswing / downswing
        )
    }

    static func jointAngle(
        first: NormalizedPoint,
        vertex: NormalizedPoint,
        third: NormalizedPoint
    ) -> Double? {
        let ax = first.x - vertex.x
        let ay = first.y - vertex.y
        let bx = third.x - vertex.x
        let by = third.y - vertex.y
        let denominator = hypot(ax, ay) * hypot(bx, by)
        guard denominator > .leastNonzeroMagnitude else { return nil }
        let cosine = min(1, max(-1, (ax * bx + ay * by) / denominator))
        return acos(cosine) * 180 / .pi
    }

    static func trueClubheadSpeed(frames: [SwingFrameObservation]) -> SwingMetricValue {
        SwingMetricValue(
            id: .trueClubheadSpeed,
            value: nil,
            unit: "mph",
            confidence: 0,
            stage: nil,
            availability: .unavailable(reason: .requiresCalibrated3DOrSensor)
        )
    }
}
```

Keep these names exact in UI/export: `二维杆头相对速度`, `二维挥杆平面代理`, and `二维髋肩分离代理`. `trueClubheadSpeed`, `attackAngle`, `faceAngle`, `dynamicLoft`, and all ball-flight metrics always return `.requiresCalibrated3DOrSensor` in the single-camera engine.

- [ ] **Step 4: Run metric and technique regression tests**

Run the Step 2 command with the executable, then compile `SwingTechniqueEvaluatorSmoke.swift`. Expected: supported fixture metrics match numeric values; unsupported metrics have no numeric value; technique findings do not consume unavailable metrics.

- [ ] **Step 5: Commit**

```bash
git add SwingArc/Models/SwingMetricModels.swift SwingArc/Services/SwingMetricEngine.swift SwingArc/Services/SwingTechniqueEvaluator.swift SwingArc/Models/WorkspaceModels.swift SwingArcProject.xcodeproj/project.pbxproj Tests/SwingMetricEngineSmoke.swift Tests/SwingTechniqueEvaluatorSmoke.swift
git commit -m "feat: calculate evidence-gated swing metrics"
```

### Task 10: Persist, display, and manually correct trajectories and confidence

**Files:**
- Modify: `SwingArc/Services/LocalProjectStore.swift`
- Modify: `SwingArc/Views/CustomVideoPlayer.swift:1-450`
- Create: `SwingArc/Views/SwingTrajectoryOverlay.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift:128-840`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`
- Modify: `Tests/ProjectPersistenceSmoke.swift`
- Create: `Tests/SwingTrajectoryPresentationSmoke.swift`

**Interfaces:**
- Consumes: versioned analysis artifact, current source frame, manual point edits, and metric availability.
- Produces: measured solid trajectories, estimated dashed trajectories, explicit gaps, metric limitations, and persistent manual corrections.

- [ ] **Step 1: Write failing persistence and presentation tests**

```swift
precondition(SwingTrajectoryAppearance.resolve(state: .detected) == .solid)
precondition(SwingTrajectoryAppearance.resolve(state: .estimated) == .dashed)
precondition(SwingTrajectoryAppearance.resolve(state: .missing) == .hidden)

let manual = TrackedSwingPoint(
    point: .init(x: 0.4, y: 0.5), confidence: 1,
    state: .detected, source: .manual
)
precondition(ManualObservationMerge.merge(automatic: nil, manual: manual) == manual)
```

- [ ] **Step 2: Compile and verify failure**

Run the new presentation smoke test with `SwingObservationModels.swift`; extend `ProjectPersistenceSmoke.swift` to encode/decode an artifact and a manual clubhead edit. Expected: compilation fails because presentation and merge policies are absent.

- [ ] **Step 3: Implement UI and persistence policies**

```swift
enum SwingTrajectoryAppearance: Equatable { case solid, dashed, hidden }

extension SwingTrajectoryAppearance {
    static func resolve(state: SwingPointState) -> Self {
        switch state {
        case .detected: return .solid
        case .estimated: return .dashed
        case .occluded, .outOfFrame, .missing: return .hidden
        }
    }
}

enum ManualObservationMerge {
    static func merge(
        automatic: TrackedSwingPoint?,
        manual: TrackedSwingPoint?
    ) -> TrackedSwingPoint? {
        manual?.source == .manual ? manual : automatic
    }
}
```

Persist artifact schema/model versions and manual overrides separately. `SwingTrajectoryOverlay` draws only points belonging to the current selected path, uses solid/dashed/hidden policy, and clips to the actual video rectangle. The results sheet lists confidence and unavailable reasons. Manual point mode supports drag-to-correct and a “恢复自动值” action; reanalysis merges automatic data under manual overrides.

- [ ] **Step 4: Run persistence, UI contract, simulator, and accessibility checks**

Run smoke tests and the unsigned simulator build. Launch the existing import preview with a labelled development clip. Verify P markers remain movable, solid/dashed/gap styles are distinct, VoiceOver reads “实测/估算/无法识别”, and the workspace remains usable in portrait without adding page-level vertical scrolling.

- [ ] **Step 5: Commit**

```bash
git add SwingArc/Services/LocalProjectStore.swift SwingArc/Views/CustomVideoPlayer.swift SwingArc/Views/SwingTrajectoryOverlay.swift SwingArc/Views/AnalysisWorkspaceView.swift SwingArcProject.xcodeproj/project.pbxproj Tests/ProjectPersistenceSmoke.swift Tests/SwingTrajectoryPresentationSmoke.swift
git commit -m "feat: present and preserve swing trajectories"
```

### Task 11: Produce the development baseline, held-out report, and release gate

**Files:**
- Create: `Tools/PrecisionDataset/RunPrecisionEvaluation.swift`
- Create: `Tests/PrecisionEvaluationReportSmoke.swift`
- Create: `docs/validation/precision-swing-baseline-2026-07-23.md`
- Create: `docs/validation/precision-swing-held-out.md`
- Modify: `docs/app-store/review-notes.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: manifests, analysis artifacts, model metadata, and device timings.
- Produces: machine-readable JSON plus human-readable per-view/per-stage/per-landmark reports and a release decision.

- [ ] **Step 1: Write the failing report test**

The fixture report must include dataset hash, model version, golfer counts by split/view, each P-stage hit rate, unresolved and false-confirmation rates, landmark median/P90/miss rate, clubhead hit rate/error/gaps, input rejection results, device, elapsed time, memory, and a boolean release decision. Assert an empty view or fewer than 10 held-out golfers forces `releasePassed == false`.

- [ ] **Step 2: Run and verify failure**

Compile `RunPrecisionEvaluation.swift` with the acceptance and observation models. Expected: fails because the evaluator does not exist.

- [ ] **Step 3: Implement the report and strict release decision**

The release decision is the conjunction of:

```swift
let releasePassed = heldOutGolferCount >= 10
    && views.allSatisfy { $0.hasHeldOutCoverage }
    && stageRates.values.allSatisfy { $0 >= 0.90 }
    && bodyLandmarkMedianError <= 0.03
    && clubheadVisibleFrameHitRate >= 0.90
    && clubheadMaximumAcceptedError == 0.02
    && unsupportedMetricsHaveNoMeasuredValues
```

Generate the development baseline from the eight current videos first. Label that report `development-only` and list every failed threshold. Generate `precision-swing-held-out.md` only from the locked held-out split.

- [ ] **Step 4: Run full verification**

Run all standalone smoke tests, an unsigned simulator build, an unsigned arm64 iPhone Release build, and the evaluator. On a connected unlocked iPhone, install and analyze at least one DTL and one Face-on original MOV offline. Record elapsed time, peak memory, thermal state, artifact/model versions, and result parity with the command-line evaluator.

Expected: the current eight videos can produce a baseline but cannot set `releasePassed` to true. Final release passes only after at least 10 held-out golfers and every numerical gate succeeds. App Store/TestFlight copy must say “实验/测试中” for any capability whose gate is still false.

- [ ] **Step 5: Commit and push the evidence**

```bash
git add Tools/PrecisionDataset/RunPrecisionEvaluation.swift Tests/PrecisionEvaluationReportSmoke.swift docs/validation/precision-swing-baseline-2026-07-23.md docs/validation/precision-swing-held-out.md docs/app-store/review-notes.md README.md
git commit -m "test: add precision swing release evidence"
git push origin codex/app-store-release-prep
```

---

## Execution Gates

1. Tasks 1–5 can run immediately and establish honest baseline/body tracking infrastructure.
2. Task 6 can create the training pipeline immediately, but training must stop until reviewed, authorized frame labels exist.
3. Task 7 may integrate a model into the app only after the clubhead validation report passes; otherwise it integrates the unavailable state and preserves honest limitations.
4. Tasks 8–10 may ship incremental UI and calculations, but no “accurate” product claim is allowed before Task 11 passes on the held-out set.
5. A failed gate leads to more authorized labels, model revision, or camera guidance—not a weaker threshold.

## Official Technical References

- Apple Core ML integration: https://developer.apple.com/documentation/coreml/
- Core ML Tools PyTorch conversion workflow: https://apple.github.io/coremltools/docs-guides/source/convert-pytorch-workflow.html
- Core ML ML Program conversion: https://apple.github.io/coremltools/docs-guides/source/convert-to-ml-program.html
- Torchvision MobileNet V3: https://docs.pytorch.org/vision/master/models/mobilenetv3.html

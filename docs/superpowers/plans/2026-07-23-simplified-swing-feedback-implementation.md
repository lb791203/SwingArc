# Simplified Swing Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the competitor-style configurable feedback matrix with one evidence-backed “本次重点” and exactly five fixed swing-motion feedback cards, each linked to its relevant P stages and 2D trajectories.

**Architecture:** Keep `SwingAnalysisArtifact` as the versioned evidence boundary, finish a motion-only `SwingMetricEngine`, and add a pure `SwingFeedbackAssembler` that always returns the same five categories with independent evidence degradation. `VideoPlaybackManager` applies manual P-stage corrections before building the artifact, while SwiftUI renders only the fixed summary/cards and expands one category into its relevant trajectory overlay.

**Tech Stack:** Swift 5 language mode, SwiftUI, AVFoundation, Vision, iOS 17 deployment target, standalone `swiftc` smoke tests, and the existing `SwingArcProject.xcodeproj` simulator build.

## Global Constraints

- The result page contains one “本次重点” and exactly five fixed items: `准备姿势`, `身体稳定`, `手部路径`, `挥杆平面`, and `击球与释放`.
- The five fixed items appear in that order and do not expose item switches, a per-stage selection matrix, or a DTL / Face-On switch.
- Camera view comes from recording or import context; an unknown view withholds view-specific conclusions.
- Default cards show only `良好`, `需注意`, or `证据不足`, one conclusion sentence, and relevant P-stage labels.
- Expanded cards show only the selected category’s video position, relevant 2D trajectories, a small set of required 2D values, evidence state, and the existing manual P-stage correction entry.
- Measured, estimated, occluded, out-of-frame, and missing evidence remain distinct.
- Estimated or low-confidence evidence can be drawn as context but cannot trigger `良好` or `需注意`.
- P2, P6, and P8 require measured shaft evidence for conclusions that depend on the club.
- P7 requires measured clubhead plus ball evidence, or an independent ball-change event, before producing an impact conclusion.
- Missing evidence in one category does not downgrade unrelated categories.
- New analysis output and UI exclude true clubhead speed, attack angle, face angle, dynamic loft, ball speed, launch angle, spin rate, and carry distance.
- No cloud analysis or original-video upload is added.
- Existing manual P-stage corrections remain stored and override automatic stage positions during reanalysis.
- The compact iPhone workbench does not gain page-level empty vertical scrolling; the result sheet may use one contained scroll view for expanded evidence.
- The visual design remains SwingArc dark mode with the fluorescent theme color; only status and the currently expanded card use the accent.
- The implementation must not claim final P1–P8 or coaching-grade accuracy before the reviewed real-video manifest passes the existing acceptance gate.

---

## File Structure

New files:

- `SwingArc/Models/SimplifiedSwingFeedbackModels.swift`: the five-category domain contract, card status, summary, evidence state, and category-to-stage/landmark mapping.
- `SwingArc/Services/SwingAnalysisArtifactBuilder.swift`: converts corrected stages, tracked frames, and motion-only metrics into the versioned artifact.
- `SwingArc/Services/SwingFeedbackAssembler.swift`: pure evidence gating, fixed-card construction, and deterministic “本次重点” selection.
- `SwingArc/Views/SimplifiedSwingFeedbackView.swift`: summary, five compact cards, expansion, stage seeking, and manual-correction actions.
- `SwingArc/Views/SwingTrajectoryOverlay.swift`: measured solid paths, estimated dashed paths, and accessibility descriptions for only the expanded category.
- `Tests/SimplifiedSwingFeedbackSmoke.swift`: exact five-card contract, order, summaries, and independent degradation.
- `Tests/SwingAnalysisArtifactBuilderSmoke.swift`: artifact filtering and manual-stage provenance.
- `Tests/SwingTrajectoryPresentationSmoke.swift`: category-to-landmark mapping and measured/estimated display policy.
- `Tests/SimplifiedFeedbackPersistenceSmoke.swift`: legacy configuration decode plus retained manual P-stage corrections.

Focused modifications:

- `SwingArc/Models/SwingMetricModels.swift`: motion-only output allow-list and user-facing titles only for supported 2D values.
- `SwingArc/Services/SwingMetricEngine.swift`: deterministic 2D motion calculations; remove unsupported-parameter constructors.
- `SwingArc/Services/SwingTechniqueEvaluator.swift`: accept only measured motion values above the confidence threshold.
- `SwingArc/Services/VisionPoseDetector.swift`: expose the already merged body/golf observation frames as the output evidence set.
- `SwingArc/Views/CustomVideoPlayer.swift`: apply manual stage truth, build the artifact, and publish simplified feedback.
- `SwingArc/Views/AnalysisWorkspaceView.swift`: replace the priority card/configuration entry with the fixed result surface and selected-category trajectory.
- `SwingArc/Views/WorkspaceComponents.swift`: remove `SwingFeedbackConfigurationView`; retain unrelated workspace components.
- `SwingArc/Views/ContentView.swift`: stop holding and persisting an active feedback configuration.
- `SwingArc/Services/LocalProjectStore.swift`: retain legacy decode compatibility but mark the configuration field as inactive.
- `SwingArc/Models/WorkspaceModels.swift`: remove the unfinished generic metric presentation; retain legacy Codable feedback types only for old project decoding.
- `Tests/SwingMetricEngineSmoke.swift`: cover motion calculations and unsupported-output exclusion.
- `Tests/SwingTechniqueEvaluatorSmoke.swift`: verify estimated, low-confidence, and unsupported metrics cannot become coaching evidence.
- `Tests/ProjectPersistenceSmoke.swift`: retain old-project decoding while proving new saves do not require the old matrix.
- `SwingArcProject.xcodeproj/project.pbxproj`: add the focused model, service, and view files to the app target.

The existing `FeedbackMetric`, `FeedbackConfiguration`, and `SwingFeedbackProfiles` Codable types remain temporarily for decoding old projects. They are not referenced by the new analysis or UI path and are not written for new/updated projects.

---

### Task 1: Finish the motion-only metric boundary

**Files:**
- Modify: `SwingArc/Models/SwingMetricModels.swift`
- Modify: `SwingArc/Services/SwingMetricEngine.swift`
- Modify: `SwingArc/Services/SwingTechniqueEvaluator.swift`
- Modify: `SwingArc/Models/WorkspaceModels.swift`
- Modify: `Tests/SwingMetricEngineSmoke.swift`
- Modify: `Tests/SwingTechniqueEvaluatorSmoke.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SwingFrameObservation`, `TrackedSwingPoint`, `SwingStageDetection`, `SwingMetricID`, and `SwingMetricValue`.
- Produces: `SwingMetricID.motionAnalysisOutputs`, `SwingMetricID.userFacingTitle`, `SwingMetricEngine.motionMeasurements(frames:stages:personHeight:) -> [SwingMetricValue]`, and `SwingTechniqueEvaluator.measuredMetricEvidence(_:metrics:) -> Double?`.

- [ ] **Step 1: Replace unsupported-value assertions with a failing motion-only output test**

Use this contract in `Tests/SwingMetricEngineSmoke.swift` after the existing geometry assertions:

```swift
let stageDetections = [
    detection(.address, frame: 10, time: 1.0),
    detection(.top, frame: 12, time: 1.2),
    detection(.impact, frame: 14, time: 1.4)
]
let measurements = SwingMetricEngine.motionMeasurements(
    frames: [
        bodyFrame(index: 10, time: 1.0, handX: 0.30, headX: 0.50),
        bodyFrame(index: 12, time: 1.2, handX: 0.45, headX: 0.52),
        bodyFrame(index: 14, time: 1.4, handX: 0.60, headX: 0.53)
    ],
    stages: stageDetections,
    personHeight: 0.5
)
precondition(!measurements.isEmpty)
precondition(measurements.allSatisfy { $0.id.isMotionAnalysisOutput })
precondition(measurements.allSatisfy { $0.id.userFacingTitle != nil })
precondition(!measurements.contains { [
    SwingMetricID.trueClubheadSpeed,
    .attackAngle,
    .faceAngle,
    .dynamicLoft,
    .ballSpeed,
    .launchAngle,
    .spinRate,
    .carryDistance
].contains($0.id) })
precondition(SwingMetricID.trueClubheadSpeed.userFacingTitle == nil)
```

Add these local helpers to the smoke executable:

```swift
private static func detection(
    _ stage: SwingStage,
    frame: Int,
    time: Double
) -> SwingStageDetection {
    SwingStageDetection(
        stage: stage,
        time: time,
        sourceFrameIndex: frame,
        confidence: 0.9,
        status: .confirmed
    )
}

private static func bodyFrame(
    index: Int,
    time: Double,
    handX: Double,
    headX: Double
) -> SwingFrameObservation {
    let measured: (Double, Double, SwingPointSource) -> TrackedSwingPoint = { x, y, source in
        TrackedSwingPoint(
            point: NormalizedPoint(x: x, y: y),
            confidence: 0.9,
            state: .detected,
            source: source
        )
    }
    return SwingFrameObservation(
        sourceFrameIndex: index,
        time: time,
        landmarks: [
            .head: measured(headX, 0.80, .visionPose),
            .leftShoulder: measured(0.42, 0.70, .visionPose),
            .rightShoulder: measured(0.58, 0.70, .visionPose),
            .leftHip: measured(0.44, 0.48, .visionPose),
            .rightHip: measured(0.56, 0.48, .visionPose),
            .leftKnee: measured(0.45, 0.27, .visionPose),
            .rightKnee: measured(0.55, 0.27, .visionPose),
            .leftAnkle: measured(0.45, 0.05, .visionPose),
            .rightAnkle: measured(0.55, 0.05, .visionPose),
            .handCenter: measured(handX, 0.50, .visionPose)
        ]
    )
}
```

- [ ] **Step 2: Compile the smoke test and verify the new API is missing**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  -framework AVFoundation -framework Vision -framework ImageIO \
  -framework SwiftUI -framework CoreVideo \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingMetricEngine.swift \
  Tests/SwingMetricEngineSmoke.swift \
  -o /tmp/swing-metric-engine
```

Expected: compilation fails because `isMotionAnalysisOutput`, `userFacingTitle`, and `motionMeasurements` do not exist.

- [ ] **Step 3: Add the exact motion-only allow-list and remove unsupported display names**

Replace the unfinished `displayName` property in `SwingMetricModels.swift` with:

```swift
extension SwingMetricID {
    static let motionAnalysisOutputs: Set<SwingMetricID> = [
        .backswingTime,
        .downswingTime,
        .tempoRatio,
        .spineTilt2D,
        .shoulderLineAngle2D,
        .hipLineAngle2D,
        .leadElbowAngle,
        .trailElbowAngle,
        .leadKneeAngle,
        .trailKneeAngle,
        .headHorizontalDisplacement,
        .headVerticalDisplacement,
        .hipHorizontalDisplacement,
        .hipVerticalDisplacement,
        .handPathLength,
        .clubheadPathLength,
        .clubheadRelativeSpeed2D,
        .shaftProjectionAngle,
        .swingPlaneProxy2D,
        .hipShoulderSeparationProxy2D
    ]

    var isMotionAnalysisOutput: Bool {
        Self.motionAnalysisOutputs.contains(self)
    }

    var userFacingTitle: String? {
        switch self {
        case .backswingTime: return "上杆时间"
        case .downswingTime: return "下杆时间"
        case .tempoRatio: return "挥杆节奏"
        case .spineTilt2D: return "脊柱二维倾角"
        case .shoulderLineAngle2D: return "肩线二维角度"
        case .hipLineAngle2D: return "髋线二维角度"
        case .leadElbowAngle: return "前侧手肘角度"
        case .trailElbowAngle: return "后侧手肘角度"
        case .leadKneeAngle: return "前侧膝部角度"
        case .trailKneeAngle: return "后侧膝部角度"
        case .headHorizontalDisplacement: return "头部水平位移"
        case .headVerticalDisplacement: return "头部垂直位移"
        case .hipHorizontalDisplacement: return "髋部水平位移"
        case .hipVerticalDisplacement: return "髋部垂直位移"
        case .handPathLength: return "手部二维路径"
        case .clubheadPathLength: return "杆头二维路径"
        case .clubheadRelativeSpeed2D: return "二维杆头相对速度"
        case .shaftProjectionAngle: return "杆身二维投影角"
        case .swingPlaneProxy2D: return "二维挥杆平面代理"
        case .hipShoulderSeparationProxy2D: return "二维髋肩分离代理"
        case .trueClubheadSpeed, .attackAngle, .faceAngle, .dynamicLoft,
             .ballSpeed, .launchAngle, .spinRate, .carryDistance:
            return nil
        }
    }
}
```

Delete `SwingMetricPresentation` from `WorkspaceModels.swift`. A generic metric list is not part of the simplified result UI.

- [ ] **Step 4: Make the engine produce only measured 2D motion outputs**

Delete `unsupported(_:)`, `trueClubheadSpeed(frames:)`, and `unsupportedUnit(for:)` from `SwingMetricEngine.swift`.

Add:

```swift
static func motionMeasurements(
    frames: [SwingFrameObservation],
    stages: [SwingStageDetection],
    personHeight: Double
) -> [SwingMetricValue] {
    var confirmed: [SwingStage: Int] = [:]
    for detection in stages {
        guard detection.status == .confirmed,
              let frameIndex = detection.sourceFrameIndex else { continue }
        confirmed[detection.stage] = frameIndex
    }
    let framesByIndex = Dictionary(uniqueKeysWithValues: frames.map {
        ($0.sourceFrameIndex, $0)
    })
    var result: [SwingMetricValue] = []

    if let p1 = confirmedTime(.address, in: stages),
       let p4 = confirmedTime(.top, in: stages),
       let p7 = confirmedTime(.impact, in: stages),
       let swingTempo = tempo(addressTime: p1, topTime: p4, impactTime: p7) {
        result.append(contentsOf: [
            SwingMetricValue(
                id: .backswingTime,
                value: swingTempo.backswingSeconds,
                unit: "s",
                confidence: minimumStageConfidence([.address, .top], in: stages),
                stage: "P1-P4",
                availability: .measured
            ),
            SwingMetricValue(
                id: .downswingTime,
                value: swingTempo.downswingSeconds,
                unit: "s",
                confidence: minimumStageConfidence([.top, .impact], in: stages),
                stage: "P4-P7",
                availability: .measured
            ),
            SwingMetricValue(
                id: .tempoRatio,
                value: swingTempo.ratio,
                unit: "ratio",
                confidence: minimumStageConfidence([.address, .top, .impact], in: stages),
                stage: "P1-P7",
                availability: .measured
            )
        ])
    }

    let p2ToP7 = SwingStage.pStages.filter {
        [.takeaway, .leadArmParallelBackswing, .top,
         .leadArmParallelDownswing, .shaftParallelDownswing, .impact].contains($0)
    }.compactMap { confirmed[$0] }.compactMap { framesByIndex[$0] }

    if p2ToP7.count == 6 {
        result.append(pathLength(
            landmark: .handCenter,
            frames: p2ToP7,
            personHeight: personHeight,
            id: .handPathLength
        ))
        result.append(pathLength(
            landmark: .clubhead,
            frames: p2ToP7,
            personHeight: personHeight,
            id: .clubheadPathLength
        ))
        result.append(normalizedRelativeSpeed2D(
            landmark: .clubhead,
            frames: p2ToP7,
            personHeight: personHeight
        ))
    }

    if let p1Index = confirmed[.address],
       let p7Index = confirmed[.impact],
       let p1Frame = framesByIndex[p1Index],
       let p7Frame = framesByIndex[p7Index],
       let p1Head = p1Frame.landmarks[.head],
       let p7Head = p7Frame.landmarks[.head] {
        result.append(normalizedDisplacement(
            id: .headHorizontalDisplacement,
            from: p1Head,
            to: p7Head,
            personHeight: personHeight,
            axis: \.x,
            stage: "P1-P7"
        ))
        result.append(normalizedDisplacement(
            id: .headVerticalDisplacement,
            from: p1Head,
            to: p7Head,
            personHeight: personHeight,
            axis: \.y,
            stage: "P1-P7"
        ))
    }

    return result.filter { $0.id.isMotionAnalysisOutput }
}

private static func minimumStageConfidence(
    _ required: [SwingStage],
    in stages: [SwingStageDetection]
) -> Double {
    required.compactMap { stage in
        stages.first(where: { $0.stage == stage })?.confidence
    }.min() ?? 0
}

private static func confirmedTime(
    _ stage: SwingStage,
    in stages: [SwingStageDetection]
) -> Double? {
    guard let detection = stages.first(where: { $0.stage == stage }),
          detection.status == .confirmed,
          detection.confidence >= minimumMeasuredConfidence else {
        return nil
    }
    return detection.time
}
```

Keep `pathLength`, `normalizedRelativeSpeed2D`, `jointAngle`, `projectionAngle`, and `normalizedDisplacement` pure. An estimated point, a missing point, or confidence below `0.65` continues to return an unavailable motion value.

- [ ] **Step 5: Restrict technique metric evidence to the allow-list**

Change `SwingTechniqueEvaluator.measuredMetricEvidence` to:

```swift
static func measuredMetricEvidence(
    _ id: SwingMetricID,
    metrics: [SwingMetricValue]
) -> Double? {
    guard id.isMotionAnalysisOutput,
          let metric = metrics.first(where: { $0.id == id }),
          metric.availability == .measured,
          metric.confidence >= Double(minimumAggregateConfidence),
          let value = metric.value,
          value.isFinite else { return nil }
    return value
}
```

Replace the unfinished unsupported-speed assertion in `SwingTechniqueEvaluatorSmoke.swift` with:

```swift
let forbiddenValue = SwingMetricValue(
    id: .trueClubheadSpeed,
    value: 105,
    unit: "mph",
    confidence: 0.99,
    stage: "P7",
    availability: .measured
)
precondition(SwingTechniqueEvaluator.measuredMetricEvidence(
    .trueClubheadSpeed,
    metrics: [forbiddenValue]
) == nil)
```

- [ ] **Step 6: Run the focused motion tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  -framework AVFoundation -framework Vision -framework ImageIO \
  -framework SwiftUI -framework CoreVideo \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingMetricEngine.swift \
  Tests/SwingMetricEngineSmoke.swift \
  -o /tmp/swing-metric-engine && /tmp/swing-metric-engine
```

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingMetricEngine.swift \
  SwingArc/Models/PracticeModels.swift \
  SwingArc/Services/SwingTechniqueEvaluator.swift \
  Tests/SwingTechniqueEvaluatorSmoke.swift \
  -o /tmp/technique-evaluator && /tmp/technique-evaluator
```

Expected: both executables exit 0; no test creates an unsupported measurement through `SwingMetricEngine`.

- [ ] **Step 7: Commit the motion-only boundary**

```bash
git add \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Services/SwingMetricEngine.swift \
  SwingArc/Services/SwingTechniqueEvaluator.swift \
  Tests/SwingMetricEngineSmoke.swift \
  Tests/SwingTechniqueEvaluatorSmoke.swift \
  SwingArcProject.xcodeproj/project.pbxproj
git commit -m "feat: calculate motion-only swing metrics"
```

### Task 2: Build the exact five-card feedback contract

**Files:**
- Create: `SwingArc/Models/SimplifiedSwingFeedbackModels.swift`
- Create: `SwingArc/Services/SwingFeedbackAssembler.swift`
- Create: `Tests/SimplifiedSwingFeedbackSmoke.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SwingAnalysisArtifact`, corrected `SwingStageDetection` values, and existing `TechniqueFinding` values.
- Produces: `SimplifiedSwingFeedback`, `SwingFeedbackSummary`, `SwingFeedbackCard`, `SwingFeedbackCategory`, and `SwingFeedbackAssembler.make(artifact:detections:findings:) -> SimplifiedSwingFeedback`.

- [ ] **Step 1: Write the failing exact-five-cards smoke test**

Create `Tests/SimplifiedSwingFeedbackSmoke.swift`:

```swift
import Foundation

@main
struct SimplifiedSwingFeedbackSmoke {
    static func main() {
        let complete = SwingFeedbackAssembler.make(
            artifact: fixtureArtifact(
                estimatedHandAtP3: false,
                includeImpactObjects: true
            ),
            detections: fixtureDetections(missingP7ImpactEvidence: false),
            findings: []
        )
        precondition(complete.cards.count == 5)
        precondition(complete.cards.map(\.category) == [
            .setup,
            .bodyStability,
            .handPath,
            .swingPlane,
            .impactAndRelease
        ])
        precondition(complete.cards.allSatisfy { $0.status != .insufficientEvidence })
        precondition(complete.summary.title == "本次动作整体稳定")

        let estimated = SwingFeedbackAssembler.make(
            artifact: fixtureArtifact(
                estimatedHandAtP3: true,
                includeImpactObjects: true
            ),
            detections: fixtureDetections(missingP7ImpactEvidence: false),
            findings: []
        )
        precondition(estimated.card(for: .handPath)?.status == .insufficientEvidence)
        precondition(estimated.card(for: .bodyStability)?.status != .insufficientEvidence)

        let missingImpact = SwingFeedbackAssembler.make(
            artifact: fixtureArtifact(
                estimatedHandAtP3: false,
                includeImpactObjects: false
            ),
            detections: fixtureDetections(missingP7ImpactEvidence: true),
            findings: []
        )
        precondition(missingImpact.card(for: .impactAndRelease)?.status == .insufficientEvidence)
        precondition(missingImpact.card(for: .swingPlane)?.status != .insufficientEvidence)
        precondition(missingImpact.cards.flatMap(\.metrics).allSatisfy {
            $0.id.isMotionAnalysisOutput
        })
    }

    private static func fixtureArtifact(
        estimatedHandAtP3: Bool,
        includeImpactObjects: Bool
    ) -> SwingAnalysisArtifact {
        let frames = SwingStage.pStages.enumerated().map { offset, stage in
            fixtureFrame(
                stage: stage,
                frameIndex: 100 + offset,
                estimatedHand: estimatedHandAtP3
                    && stage == .leadArmParallelBackswing,
                includeImpactObjects: includeImpactObjects
                    && stage == .impact
            )
        }
        return SwingAnalysisArtifact(
            schemaVersion: SwingAnalysisArtifact.currentSchemaVersion,
            modelVersion: "fixture",
            view: PracticeCameraView.downTheLine.rawValue,
            sourceFrameRate: 60,
            qualityIssues: [],
            frames: frames,
            stages: [],
            metrics: [
                SwingMetricValue(
                    id: .handPathLength,
                    value: 1.1,
                    unit: "person-height",
                    confidence: 0.9,
                    stage: "P2-P7",
                    availability: .measured
                )
            ]
        )
    }

    private static func fixtureDetections(
        missingP7ImpactEvidence: Bool
    ) -> [SwingStageDetection] {
        SwingStage.pStages.enumerated().map { offset, stage in
            SwingStageDetection(
                stage: stage,
                time: Double(offset) / 60,
                sourceFrameIndex: 100 + offset,
                confidence: 0.9,
                status: .confirmed,
                hasClubEvidence: [
                    SwingStage.takeaway,
                    .shaftParallelDownswing,
                    .followThrough
                ].contains(stage),
                hasBallEvidence: stage == .impact
                    && !missingP7ImpactEvidence,
                hasBallChangeEvidence: stage == .impact
                    && !missingP7ImpactEvidence
            )
        }
    }

    private static func fixtureFrame(
        stage: SwingStage,
        frameIndex: Int,
        estimatedHand: Bool,
        includeImpactObjects: Bool
    ) -> SwingFrameObservation {
        func point(
            _ x: Double,
            _ y: Double,
            state: SwingPointState = .detected,
            source: SwingPointSource = .visionPose
        ) -> TrackedSwingPoint {
            TrackedSwingPoint(
                point: NormalizedPoint(x: x, y: y),
                confidence: 0.9,
                state: state,
                source: source
            )
        }
        var landmarks: [SwingLandmark: TrackedSwingPoint] = [
            .head: point(0.50, 0.86),
            .leftShoulder: point(0.43, 0.72),
            .rightShoulder: point(0.57, 0.72),
            .leftHip: point(0.45, 0.50),
            .rightHip: point(0.55, 0.50),
            .leftKnee: point(0.45, 0.28),
            .rightKnee: point(0.55, 0.28),
            .leftAnkle: point(0.44, 0.06),
            .rightAnkle: point(0.56, 0.06),
            .handCenter: estimatedHand
                ? point(
                    0.38,
                    0.58,
                    state: .estimated,
                    source: .temporalPrediction
                )
                : point(0.38, 0.58)
        ]
        if [
            SwingStage.takeaway,
            .shaftParallelDownswing,
            .followThrough
        ].contains(stage) {
            landmarks[.shaftStart] = point(
                0.38,
                0.58,
                source: .coreMLGolf
            )
            landmarks[.shaftEnd] = point(
                0.62,
                0.42,
                source: .coreMLGolf
            )
        }
        if includeImpactObjects {
            landmarks[.clubhead] = point(
                0.68,
                0.10,
                source: .coreMLGolf
            )
            landmarks[.ball] = point(
                0.70,
                0.08,
                source: .coreMLGolf
            )
        }
        return SwingFrameObservation(
            sourceFrameIndex: frameIndex,
            time: Double(frameIndex - 100) / 60,
            landmarks: landmarks
        )
    }
}
```

- [ ] **Step 2: Compile and verify the feedback types do not exist**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  -framework AVFoundation -framework Vision -framework ImageIO \
  -framework SwiftUI -framework CoreVideo \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Models/SimplifiedSwingFeedbackModels.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingTechniqueEvaluator.swift \
  SwingArc/Services/SwingFeedbackAssembler.swift \
  Tests/SimplifiedSwingFeedbackSmoke.swift \
  -o /tmp/simplified-swing-feedback
```

Expected: compilation fails because both new production files and their types are absent.

- [ ] **Step 3: Define the fixed model and immutable category mapping**

Create `SimplifiedSwingFeedbackModels.swift` with:

```swift
import Foundation

enum SwingFeedbackCategory: String, Codable, CaseIterable, Identifiable {
    case setup
    case bodyStability
    case handPath
    case swingPlane
    case impactAndRelease

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: return "准备姿势"
        case .bodyStability: return "身体稳定"
        case .handPath: return "手部路径"
        case .swingPlane: return "挥杆平面"
        case .impactAndRelease: return "击球与释放"
        }
    }

    var stages: [SwingStage] {
        switch self {
        case .setup:
            return [.address]
        case .bodyStability, .handPath:
            return [.takeaway, .leadArmParallelBackswing, .top,
                    .leadArmParallelDownswing, .shaftParallelDownswing, .impact]
        case .swingPlane:
            return [.takeaway, .leadArmParallelBackswing,
                    .leadArmParallelDownswing, .shaftParallelDownswing, .followThrough]
        case .impactAndRelease:
            return [.shaftParallelDownswing, .impact, .followThrough]
        }
    }

    var trajectoryLandmarks: [SwingLandmark] {
        switch self {
        case .setup:
            return [.head, .leftShoulder, .rightShoulder,
                    .leftHip, .rightHip, .leftKnee, .rightKnee,
                    .leftAnkle, .rightAnkle, .handCenter]
        case .bodyStability:
            return [.head, .leftShoulder, .rightShoulder, .leftHip, .rightHip]
        case .handPath:
            return [.handCenter]
        case .swingPlane:
            return [.handCenter, .shaftStart, .shaftEnd, .clubhead]
        case .impactAndRelease:
            return [.handCenter, .shaftStart, .shaftEnd, .clubhead, .ball]
        }
    }
}

enum SwingFeedbackStatus: String, Codable, Equatable {
    case good
    case attention
    case insufficientEvidence

    var title: String {
        switch self {
        case .good: return "良好"
        case .attention: return "需注意"
        case .insufficientEvidence: return "证据不足"
        }
    }
}

enum SwingFeedbackEvidenceState: String, Codable, Equatable {
    case measured
    case estimated
    case unavailable

    var title: String {
        switch self {
        case .measured: return "实测"
        case .estimated: return "估算"
        case .unavailable: return "无法识别"
        }
    }
}

struct SwingFeedbackCard: Codable, Equatable, Identifiable {
    var id: String { category.rawValue }
    let category: SwingFeedbackCategory
    let status: SwingFeedbackStatus
    let conclusion: String
    let stages: [SwingStage]
    let metrics: [SwingMetricValue]
    let evidenceState: SwingFeedbackEvidenceState
    let evidenceConfidence: Double
    let attentionSeverity: Int?
}

struct SwingFeedbackSummary: Codable, Equatable {
    let title: String
    let observation: String
    let recommendation: String
    let stages: [SwingStage]
}

struct SimplifiedSwingFeedback: Codable, Equatable {
    let summary: SwingFeedbackSummary
    let cards: [SwingFeedbackCard]

    func card(for category: SwingFeedbackCategory) -> SwingFeedbackCard? {
        cards.first(where: { $0.category == category })
    }
}

extension SwingStage {
    var evidenceCode: String {
        switch self {
        case .address: return "P1"
        case .takeaway: return "P2"
        case .leadArmParallelBackswing: return "P3"
        case .top: return "P4"
        case .leadArmParallelDownswing: return "P5"
        case .shaftParallelDownswing: return "P6"
        case .impact: return "P7"
        case .followThrough: return "P8"
        case .finish: return "收杆"
        }
    }
}
```

- [ ] **Step 4: Implement category-local evidence gating**

Create `SwingFeedbackAssembler.swift` with these public rules:

```swift
import Foundation

enum SwingFeedbackAssembler {
    static let minimumMeasuredConfidence = 0.65

    static func make(
        artifact: SwingAnalysisArtifact,
        detections: [SwingStageDetection],
        findings: [TechniqueFinding]
    ) -> SimplifiedSwingFeedback {
        let cards = SwingFeedbackCategory.allCases.map {
            makeCard(
                category: $0,
                artifact: artifact,
                detections: detections,
                findings: findings
            )
        }
        return SimplifiedSwingFeedback(
            summary: makeSummary(cards: cards),
            cards: cards
        )
    }
}
```

For each category, first require every listed stage to have `status == .confirmed`, `confidence >= 0.65`, and a source frame. Then apply these exact landmark requirements:

```swift
private static func requiredLandmarks(
    for category: SwingFeedbackCategory,
    stage: SwingStage
) -> [SwingLandmark] {
    switch category {
    case .setup:
        return [.head, .leftShoulder, .rightShoulder,
                .leftHip, .rightHip, .leftKnee, .rightKnee,
                .leftAnkle, .rightAnkle, .handCenter]
    case .bodyStability:
        return [.head, .leftShoulder, .rightShoulder, .leftHip, .rightHip]
    case .handPath:
        return [.handCenter]
    case .swingPlane:
        if [.takeaway, .shaftParallelDownswing, .followThrough].contains(stage) {
            return [.handCenter, .shaftStart, .shaftEnd]
        }
        return [.handCenter]
    case .impactAndRelease:
        if stage == .impact {
            return [.handCenter]
        }
        return [.handCenter, .shaftStart, .shaftEnd]
    }
}
```

A required point is conclusion-grade only when:

```swift
private static func isConclusionGrade(_ point: TrackedSwingPoint?) -> Bool {
    guard let point else { return false }
    return point.isMeasured
        && point.confidence.isFinite
        && point.confidence >= minimumMeasuredConfidence
}
```

Use this complete card constructor:

```swift
private static func makeCard(
    category: SwingFeedbackCategory,
    artifact: SwingAnalysisArtifact,
    detections: [SwingStageDetection],
    findings: [TechniqueFinding]
) -> SwingFeedbackCard {
    let framesByIndex = Dictionary(uniqueKeysWithValues: artifact.frames.map {
        ($0.sourceFrameIndex, $0)
    })
    var confidences: [Double] = []
    var sawEstimated = false

    for stage in category.stages {
        guard let detection = detections.first(where: { $0.stage == stage }),
              detection.status == .confirmed,
              detection.confidence >= minimumMeasuredConfidence,
              let frameIndex = detection.sourceFrameIndex,
              let frame = framesByIndex[frameIndex] else {
            return insufficientCard(
                category: category,
                state: .unavailable
            )
        }
        confidences.append(detection.confidence)
        for landmark in requiredLandmarks(for: category, stage: stage) {
            let point = frame.landmarks[landmark]
            if point?.isEstimated == true {
                sawEstimated = true
                continue
            }
            guard isConclusionGrade(point) else {
                return insufficientCard(
                    category: category,
                    state: .unavailable
                )
            }
            confidences.append(point?.confidence ?? 0)
        }
        if category == .impactAndRelease,
           stage == .impact,
           !hasImpactEvidence(detection, frame: frame) {
            return insufficientCard(
                category: category,
                state: .unavailable
            )
        }
    }

    if sawEstimated {
        return insufficientCard(
            category: category,
            state: .estimated
        )
    }

    let metrics = artifact.metrics.filter {
        metricIDs(for: category).contains($0.id)
            && $0.id.isMotionAnalysisOutput
    }
    let matchedFinding = findings
        .filter { findingMatches($0, category: category) }
        .max { severityRank(for: $0) < severityRank(for: $1) }
    if let matchedFinding {
        return SwingFeedbackCard(
            category: category,
            status: .attention,
            conclusion: attentionConclusion(for: matchedFinding),
            stages: matchedFinding.evidence.stages,
            metrics: metrics,
            evidenceState: .measured,
            evidenceConfidence: confidences.min() ?? 0,
            attentionSeverity: severityRank(for: matchedFinding)
        )
    }
    return SwingFeedbackCard(
        category: category,
        status: .good,
        conclusion: goodConclusion(for: category),
        stages: category.stages,
        metrics: metrics,
        evidenceState: .measured,
        evidenceConfidence: confidences.min() ?? 0,
        attentionSeverity: nil
    )
}

private static func insufficientCard(
    category: SwingFeedbackCategory,
    state: SwingFeedbackEvidenceState
) -> SwingFeedbackCard {
    SwingFeedbackCard(
        category: category,
        status: .insufficientEvidence,
        conclusion: "\(category.title)所需画面证据不足，暂不判断动作好坏。",
        stages: category.stages,
        metrics: [],
        evidenceState: state,
        evidenceConfidence: 0,
        attentionSeverity: nil
    )
}

private static func metricIDs(
    for category: SwingFeedbackCategory
) -> Set<SwingMetricID> {
    switch category {
    case .setup:
        return [
            .spineTilt2D, .shoulderLineAngle2D, .hipLineAngle2D,
            .leadKneeAngle, .trailKneeAngle
        ]
    case .bodyStability:
        return [
            .headHorizontalDisplacement, .headVerticalDisplacement,
            .hipHorizontalDisplacement, .hipVerticalDisplacement,
            .spineTilt2D
        ]
    case .handPath:
        return [.handPathLength]
    case .swingPlane:
        return [
            .handPathLength, .clubheadPathLength,
            .shaftProjectionAngle, .swingPlaneProxy2D
        ]
    case .impactAndRelease:
        return [
            .downswingTime, .tempoRatio, .leadElbowAngle,
            .trailElbowAngle, .clubheadPathLength,
            .clubheadRelativeSpeed2D
        ]
    }
}
```

For `.impactAndRelease`, P7 additionally requires:

```swift
private static func hasImpactEvidence(
    _ detection: SwingStageDetection,
    frame: SwingFrameObservation
) -> Bool {
    let measuredClubheadAndBall =
        isConclusionGrade(frame.landmarks[.clubhead])
        && isConclusionGrade(frame.landmarks[.ball])
    return detection.hasBallChangeEvidence || measuredClubheadAndBall
}
```

If any required evidence is estimated, return `证据不足` with evidence state `.estimated`; if it is absent, occluded, out of frame, low confidence, or the stage is unresolved, return `证据不足` with evidence state `.unavailable`. Do not inspect other categories when determining this result.

Map existing findings only after the evidence gate passes:

```swift
private static func findingMatches(
    _ finding: TechniqueFinding,
    category: SwingFeedbackCategory
) -> Bool {
    switch (finding.kind, category) {
    case (.postureLoss, .bodyStability),
         (.overTheTop, .swingPlane),
         (.chickenWing, .impactAndRelease):
        return true
    default:
        return false
    }
}
```

Use these exact default conclusions:

```swift
private static func goodConclusion(
    for category: SwingFeedbackCategory
) -> String {
    switch category {
    case .setup: return "准备姿势关键点已完整识别，未发现明显异常。"
    case .bodyStability: return "P2–P7 身体关键点连续，未发现明显失稳。"
    case .handPath: return "P2–P7 手部路径连续可识别。"
    case .swingPlane: return "关键阶段的手部与杆身证据连续。"
    case .impactAndRelease: return "P6–P8 的击球与释放证据连续。"
    }
}
```

Map matched findings to card conclusions with:

```swift
private static func attentionConclusion(
    for finding: TechniqueFinding
) -> String {
    switch finding.kind {
    case .postureLoss: return "上杆时身体有起身趋势。"
    case .overTheTop: return "下杆路径略偏外。"
    case .chickenWing: return "送杆阶段前侧手臂略收紧。"
    }
}

private static func severityRank(
    for finding: TechniqueFinding
) -> Int {
    switch finding.severity {
    case .attention: return 1
    case .significant: return 2
    }
}
```

For insufficient evidence, use `"\(category.title)所需画面证据不足，暂不判断动作好坏。"` and set `attentionSeverity` to `nil`. A good card also has `attentionSeverity == nil`.

- [ ] **Step 5: Implement deterministic “本次重点” selection**

Add:

```swift
private static func makeSummary(
    cards: [SwingFeedbackCard]
) -> SwingFeedbackSummary {
    let attention = cards
        .filter { $0.status == .attention }
        .max { lhs, rhs in
            let leftSeverity = lhs.attentionSeverity ?? 0
            let rightSeverity = rhs.attentionSeverity ?? 0
            if leftSeverity != rightSeverity {
                return leftSeverity < rightSeverity
            }
            if lhs.evidenceConfidence != rhs.evidenceConfidence {
                return lhs.evidenceConfidence < rhs.evidenceConfidence
            }
            let leftStage = lhs.stages.compactMap {
                SwingStage.pStages.firstIndex(of: $0)
            }.max() ?? 0
            let rightStage = rhs.stages.compactMap {
                SwingStage.pStages.firstIndex(of: $0)
            }.max() ?? 0
            return leftStage < rightStage
        }
    if let attention {
        return SwingFeedbackSummary(
            title: attention.conclusion,
            observation: "该问题由\(attention.stages.map(\.evidenceCode).joined(separator: "、"))画面证据支持。",
            recommendation: recommendation(for: attention.category),
            stages: attention.stages
        )
    }
    if cards.allSatisfy({ $0.status == .good }) {
        return SwingFeedbackSummary(
            title: "本次动作整体稳定",
            observation: "五项动作反馈均有合格画面证据，未发现明显异常。",
            recommendation: "保持当前节奏，再录制同机位挥杆用于连续对比。",
            stages: []
        )
    }
    return SwingFeedbackSummary(
        title: "部分动作证据不足",
        observation: "只显示画面能够支持的结论，证据不足项目不会判断动作好坏。",
        recommendation: "固定手机并确保全身、球杆、杆头和球位持续入镜。",
        stages: []
    )
}

private static func recommendation(
    for category: SwingFeedbackCategory
) -> String {
    switch category {
    case .setup: return "重新对齐站位后录制一次，保持全身和球杆完整入镜。"
    case .bodyStability: return "用较慢速度练习，优先保持头部与髋部运动稳定。"
    case .handPath: return "用半挥杆练习，让双手沿稳定路径通过下杆区。"
    case .swingPlane: return "先做半挥杆，检查 P5–P6 的手部和杆身位置。"
    case .impactAndRelease: return "用小幅度击球练习，保持 P6 到 P8 的连续释放。"
    }
}
```

Card order is always `SwingFeedbackCategory.allCases`. Never sort cards by status.

- [ ] **Step 6: Run exact-five and degradation tests**

Run the command from Step 2 again.

Expected: executable exits 0; changing P3 hand evidence affects only `手部路径`, and removing P7 impact evidence affects only `击球与释放`.

- [ ] **Step 7: Commit the fixed feedback domain**

```bash
git add \
  SwingArc/Models/SimplifiedSwingFeedbackModels.swift \
  SwingArc/Services/SwingFeedbackAssembler.swift \
  Tests/SimplifiedSwingFeedbackSmoke.swift \
  SwingArcProject.xcodeproj/project.pbxproj
git commit -m "feat: assemble five fixed swing feedback cards"
```

### Task 3: Build corrected artifacts at the playback boundary

**Files:**
- Create: `SwingArc/Services/SwingAnalysisArtifactBuilder.swift`
- Create: `Tests/SwingAnalysisArtifactBuilderSmoke.swift`
- Modify: `SwingArc/Services/VisionPoseDetector.swift`
- Modify: `SwingArc/Views/CustomVideoPlayer.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SwingVideoAnalysisOutput.observationFrames`, `ManualStageDetectionPolicy.applying`, `SwingMetricEngine.motionMeasurements`, and `PracticeCameraView`.
- Produces: `SwingAnalysisArtifactBuilder.make(view:sourceFrameRate:frames:detections:metrics:) -> SwingAnalysisArtifact`, `VideoPlaybackManager.analysisArtifact(view:manualMarkers:) -> SwingAnalysisArtifact?`, and `VideoPlaybackManager.simplifiedFeedback(view:manualMarkers:) -> SimplifiedSwingFeedback?`.

- [ ] **Step 1: Write the failing artifact filtering test**

Create `Tests/SwingAnalysisArtifactBuilderSmoke.swift`:

```swift
import Foundation

@main
struct SwingAnalysisArtifactBuilderSmoke {
    static func main() {
        let manual = SwingStageDetection(
            stage: .impact,
            time: 1.4,
            sourceFrameIndex: 84,
            confidence: 1,
            status: .confirmed,
            evidence: StageEvidenceSummary(
                sources: [.manual],
                detectedPointCount: 0,
                estimatedPointCount: 0
            )
        )
        let artifact = SwingAnalysisArtifactBuilder.make(
            view: .downTheLine,
            sourceFrameRate: 60,
            frames: [],
            detections: [manual],
            metrics: [
                SwingMetricValue(
                    id: .handPathLength,
                    value: 1.2,
                    unit: "person-height",
                    confidence: 0.9,
                    stage: "P2-P7",
                    availability: .measured
                ),
                SwingMetricValue(
                    id: .attackAngle,
                    value: -4,
                    unit: "deg",
                    confidence: 0.9,
                    stage: "P7",
                    availability: .measured
                )
            ]
        )
        precondition(artifact.schemaVersion == SwingAnalysisArtifact.currentSchemaVersion)
        precondition(artifact.metrics.map(\.id) == [.handPathLength])
        precondition(artifact.stages.first?.manuallyLocked == true)
        precondition(artifact.stages.first?.sourceFrameIndex == 84)
        precondition(artifact.view == PracticeCameraView.downTheLine.rawValue)
    }
}
```

- [ ] **Step 2: Compile and verify the builder is missing**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  -framework AVFoundation -framework Vision -framework ImageIO \
  -framework SwiftUI -framework CoreVideo \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Models/SimplifiedSwingFeedbackModels.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingAnalysisArtifactBuilder.swift \
  Tests/SwingAnalysisArtifactBuilderSmoke.swift \
  -o /tmp/swing-artifact-builder
```

Expected: compilation fails because `SwingAnalysisArtifactBuilder` does not exist.

- [ ] **Step 3: Implement the versioned artifact builder**

Create `SwingAnalysisArtifactBuilder.swift`:

```swift
import Foundation

enum SwingAnalysisArtifactBuilder {
    static let modelVersion = "vision-p-system-v1"

    static func make(
        view: PracticeCameraView,
        sourceFrameRate: Double,
        qualityIssues: [String] = [],
        frames: [SwingFrameObservation],
        detections: [SwingStageDetection],
        metrics: [SwingMetricValue]
    ) -> SwingAnalysisArtifact {
        SwingAnalysisArtifact(
            schemaVersion: SwingAnalysisArtifact.currentSchemaVersion,
            modelVersion: modelVersion,
            view: view.rawValue,
            sourceFrameRate: sourceFrameRate,
            qualityIssues: qualityIssues,
            frames: frames,
            stages: detections.map { detection in
                SwingStageArtifact(
                    code: detection.stage.evidenceCode,
                    sourceFrameIndex: detection.sourceFrameIndex,
                    time: detection.time,
                    confidence: detection.confidence,
                    status: detection.status.rawValue,
                    evidenceSources: detection.evidence.sources.map(\.rawValue).sorted(),
                    manuallyLocked: detection.evidence.sources.contains(.manual)
                )
            },
            metrics: metrics.filter { $0.id.isMotionAnalysisOutput }
        )
    }
}
```

- [ ] **Step 4: Rename output evidence to match its actual contents**

In `SwingVideoAnalysisOutput`, replace `bodyFrames` with:

```swift
/// Fine-frame observations after body and available golf-object points have
/// been merged and temporally tracked. Point state and source remain intact.
let observationFrames: [SwingFrameObservation]
```

Change the initializer parameter and assignment to `observationFrames`. At the completion site, pass `trackedBodyFrames`, which already contains merged golf landmarks after the evidence pass.

Use a temporary read-only compatibility property only while updating call sites:

```swift
var bodyFrames: [SwingFrameObservation] { observationFrames }
```

Delete that compatibility property before committing once `rg -n "bodyFrames" SwingArc Tests` returns no call sites.

- [ ] **Step 5: Apply manual P-stage truth before building metrics and feedback**

Add to `VideoPlaybackManager`:

```swift
func analysisArtifact(
    view: PracticeCameraView?,
    manualMarkers: [KeyframeMarker]
) -> SwingAnalysisArtifact? {
    guard let output = analysisOutput, let view else { return nil }
    let correctedDetections = correctedDetections(
        manualMarkers: manualMarkers
    )
    let personHeight = SwingMetricEvidence.personHeight(
        frames: output.observationFrames,
        detections: correctedDetections
    )
    let metrics = SwingMetricEngine.motionMeasurements(
        frames: output.observationFrames,
        stages: correctedDetections,
        personHeight: personHeight
    )
    return SwingAnalysisArtifactBuilder.make(
        view: view,
        sourceFrameRate: output.sourceFrameRate,
        frames: output.observationFrames,
        detections: correctedDetections,
        metrics: metrics
    )
}

func simplifiedFeedback(
    view: PracticeCameraView?,
    manualMarkers: [KeyframeMarker]
) -> SimplifiedSwingFeedback? {
    guard let output = analysisOutput,
          let view,
          let artifact = analysisArtifact(
            view: view,
            manualMarkers: manualMarkers
          ) else { return nil }
    let correctedDetections = correctedDetections(
        manualMarkers: manualMarkers
    )
    let findings = SwingTechniqueEvaluator.evaluate(
        samples: output.poseSamples,
        stages: correctedDetections,
        view: view,
        leadArm: output.leadArm
    )
    return SwingFeedbackAssembler.make(
        artifact: artifact,
        detections: correctedDetections,
        findings: findings
    )
}

func correctedDetections(
    manualMarkers: [KeyframeMarker]
) -> [SwingStageDetection] {
    guard let output = analysisOutput else { return [] }
    return ManualStageDetectionPolicy.applying(
        manualMarkers: manualMarkers,
        sourceFrameRate: output.sourceFrameRate,
        automatic: output.result.detections,
        availablePoseSamples: output.poseSamples
    )
}
```

Add this evidence helper to `SwingMetricEngine.swift`:

```swift
enum SwingMetricEvidence {
    static func personHeight(
        frames: [SwingFrameObservation],
        detections: [SwingStageDetection]
    ) -> Double {
        let preferredFrames = Set(detections.compactMap(\.sourceFrameIndex))
        let heights = frames
            .filter { preferredFrames.contains($0.sourceFrameIndex) }
            .compactMap { frame -> Double? in
                guard let head = frame.landmarks[.head],
                      let leftAnkle = frame.landmarks[.leftAnkle],
                      let rightAnkle = frame.landmarks[.rightAnkle],
                      head.isMeasured,
                      leftAnkle.isMeasured,
                      rightAnkle.isMeasured,
                      let headPoint = head.point,
                      let leftPoint = leftAnkle.point,
                      let rightPoint = rightAnkle.point else { return nil }
                let ankleY = (leftPoint.y + rightPoint.y) / 2
                let value = abs(headPoint.y - ankleY)
                return value.isFinite && value > 0 ? value : nil
            }
        return heights.sorted().dropFirst(heights.count / 2).first ?? 0
    }
}
```

An unknown imported-video view returns no simplified feedback instead of inferring a view.

- [ ] **Step 6: Preserve manual evidence provenance**

Update `ManualStageDetectionPolicy.applying` so a manual replacement creates:

```swift
evidence: StageEvidenceSummary(
    sources: [.manual],
    detectedPointCount: 0,
    estimatedPointCount: 0
)
```

Keep the existing rule that a manual frame without an exact pose sample becomes low confidence. Manual truth changes the stage position; it does not invent missing pose, shaft, clubhead, or ball evidence.

- [ ] **Step 7: Run artifact and existing manual-correction tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  -framework AVFoundation -framework Vision -framework ImageIO \
  -framework SwiftUI -framework CoreVideo \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Models/SimplifiedSwingFeedbackModels.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingAnalysisArtifactBuilder.swift \
  Tests/SwingAnalysisArtifactBuilderSmoke.swift \
  -o /tmp/swing-artifact-builder && /tmp/swing-artifact-builder
```

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/PracticeModels.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/SwingTechniqueEvaluator.swift \
  Tests/TechniqueFeedbackPresentationSmoke.swift \
  -o /tmp/manual-stage-policy && /tmp/manual-stage-policy
```

Expected: both executables exit 0; the artifact contains no unsupported metric IDs and the manual P-stage is locked at its exact corrected source frame.

- [ ] **Step 8: Commit the playback evidence boundary**

```bash
git add \
  SwingArc/Services/SwingAnalysisArtifactBuilder.swift \
  SwingArc/Services/SwingMetricEngine.swift \
  SwingArc/Services/SwingTechniqueEvaluator.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Views/CustomVideoPlayer.swift \
  Tests/SwingAnalysisArtifactBuilderSmoke.swift \
  SwingArcProject.xcodeproj/project.pbxproj
git commit -m "feat: build corrected swing feedback artifacts"
```

### Task 4: Replace the configurable result UI with the fixed five-card surface

**Files:**
- Create: `SwingArc/Views/SimplifiedSwingFeedbackView.swift`
- Create: `SwingArc/Views/SwingTrajectoryOverlay.swift`
- Create: `Tests/SwingTrajectoryPresentationSmoke.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `SwingArc/Views/WorkspaceComponents.swift`
- Modify: `SwingArc/Views/ContentView.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `VideoPlaybackManager.simplifiedFeedback(view:manualMarkers:)`, `VideoPlaybackManager.analysisOutput?.observationFrames`, and `SwingFeedbackCategory.trajectoryLandmarks`.
- Produces: `SimplifiedSwingFeedbackView`, `SwingTrajectoryOverlay`, and the selected expanded category state in `AnalysisWorkspaceView`.

- [ ] **Step 1: Write the failing trajectory presentation policy test**

Create `Tests/SwingTrajectoryPresentationSmoke.swift`:

```swift
import Foundation

@main
struct SwingTrajectoryPresentationSmoke {
    static func main() {
        precondition(SwingTrajectoryPresentationPolicy.landmarks(for: .setup) == [
            .head, .leftShoulder, .rightShoulder,
            .leftHip, .rightHip, .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle, .handCenter
        ])
        precondition(SwingTrajectoryPresentationPolicy.landmarks(for: .handPath) == [
            .handCenter
        ])
        precondition(SwingTrajectoryPresentationPolicy.style(
            for: TrackedSwingPoint(
                point: NormalizedPoint(x: 0.5, y: 0.5),
                confidence: 0.9,
                state: .detected,
                source: .visionPose
            )
        ) == .measured)
        precondition(SwingTrajectoryPresentationPolicy.style(
            for: TrackedSwingPoint(
                point: NormalizedPoint(x: 0.5, y: 0.5),
                confidence: 0.8,
                state: .estimated,
                source: .temporalPrediction
            )
        ) == .estimated)
        precondition(SwingTrajectoryPresentationPolicy.style(
            for: TrackedSwingPoint(
                point: nil,
                confidence: 0,
                state: .missing,
                source: .visionPose
            )
        ) == .hidden)
    }
}
```

- [ ] **Step 2: Compile and verify the trajectory policy is missing**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/SimplifiedSwingFeedbackModels.swift \
  SwingArc/Views/SwingTrajectoryOverlay.swift \
  Tests/SwingTrajectoryPresentationSmoke.swift \
  -o /tmp/swing-trajectory-presentation
```

Expected: compilation fails because `SwingTrajectoryPresentationPolicy` is absent.

- [ ] **Step 3: Implement the pure trajectory presentation policy**

At the top of `SwingTrajectoryOverlay.swift`, define:

```swift
import SwiftUI

enum SwingTrajectorySegmentStyle: Equatable {
    case measured
    case estimated
    case hidden
}

enum SwingTrajectoryPresentationPolicy {
    static func landmarks(
        for category: SwingFeedbackCategory
    ) -> [SwingLandmark] {
        category.trajectoryLandmarks
    }

    static func style(
        for point: TrackedSwingPoint
    ) -> SwingTrajectorySegmentStyle {
        guard point.point != nil else { return .hidden }
        if point.isEstimated { return .estimated }
        if point.isMeasured, point.confidence >= 0.65 { return .measured }
        return .hidden
    }
}
```

Implement `SwingTrajectoryOverlay` so it:

- filters frames to the selected card’s `stages` using their corrected source frames;
- builds one path per `trajectoryLandmark`;
- draws consecutive `.measured` points with a solid fluorescent 2-point stroke;
- draws any segment containing `.estimated` with a 1.5-point dashed stroke at 55% opacity;
- draws no segment for missing, occluded, out-of-frame, or low-confidence points;
- maps normalized coordinates into the supplied `videoRect`;
- sets `allowsHitTesting(false)`;
- combines accessibility into `"\(category.title)轨迹，实测\(measuredCount)段，估算\(estimatedCount)段"`.

The normalized point mapping is:

```swift
private func canvasPoint(
    _ point: NormalizedPoint,
    in videoRect: CGRect
) -> CGPoint {
    CGPoint(
        x: videoRect.minX + CGFloat(point.x) * videoRect.width,
        y: videoRect.minY + (1 - CGFloat(point.y)) * videoRect.height
    )
}
```

Use this concrete view implementation:

```swift
struct SwingTrajectoryOverlay: View {
    let category: SwingFeedbackCategory
    let frames: [SwingFrameObservation]
    let detections: [SwingStageDetection]
    let videoRect: CGRect

    private struct Segment {
        let start: NormalizedPoint
        let end: NormalizedPoint
        let style: SwingTrajectorySegmentStyle
    }

    private var segments: [Segment] {
        let stageFrames = Set(detections.compactMap { detection -> Int? in
            guard category.stages.contains(detection.stage),
                  let index = detection.sourceFrameIndex else { return nil }
            return index
        })
        let relevantFrames = frames
            .filter { stageFrames.contains($0.sourceFrameIndex) }
            .sorted { $0.sourceFrameIndex < $1.sourceFrameIndex }
        return SwingTrajectoryPresentationPolicy.landmarks(for: category)
            .flatMap { landmark in
                let points = relevantFrames.compactMap {
                    $0.landmarks[landmark]
                }
                return zip(points, points.dropFirst()).compactMap { pair in
                    let first = pair.0
                    let second = pair.1
                    guard let start = first.point, let end = second.point else {
                        return nil
                    }
                    let firstStyle = SwingTrajectoryPresentationPolicy.style(for: first)
                    let secondStyle = SwingTrajectoryPresentationPolicy.style(for: second)
                    guard firstStyle != .hidden, secondStyle != .hidden else {
                        return nil
                    }
                    return Segment(
                        start: start,
                        end: end,
                        style: firstStyle == .estimated || secondStyle == .estimated
                            ? .estimated
                            : .measured
                    )
                }
            }
    }

    var body: some View {
        Canvas { context, _ in
            for segment in segments {
                var path = Path()
                path.move(to: canvasPoint(segment.start, in: videoRect))
                path.addLine(to: canvasPoint(segment.end, in: videoRect))
                switch segment.style {
                case .measured:
                    context.stroke(
                        path,
                        with: .color(AnalysisTheme.proTourSignal),
                        style: StrokeStyle(
                            lineWidth: 2,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                case .estimated:
                    context.stroke(
                        path,
                        with: .color(
                            AnalysisTheme.proTourSignal.opacity(0.55)
                        ),
                        style: StrokeStyle(
                            lineWidth: 1.5,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [6, 5]
                        )
                    )
                case .hidden:
                    break
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let measured = segments.filter { $0.style == .measured }.count
        let estimated = segments.filter { $0.style == .estimated }.count
        return "\(category.title)轨迹，实测\(measured)段，估算\(estimated)段"
    }

    private func canvasPoint(
        _ point: NormalizedPoint,
        in videoRect: CGRect
    ) -> CGPoint {
        CGPoint(
            x: videoRect.minX + CGFloat(point.x) * videoRect.width,
            y: videoRect.minY + (1 - CGFloat(point.y)) * videoRect.height
        )
    }
}
```

- [ ] **Step 4: Implement the fixed summary and five cards**

Create `SimplifiedSwingFeedbackView.swift` with:

```swift
import SwiftUI

struct SimplifiedSwingFeedbackView: View {
    let feedback: SimplifiedSwingFeedback
    @Binding var expandedCategory: SwingFeedbackCategory?
    let onSelectStage: (SwingStage) -> Void
    let onAdjustStage: (SwingStage) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                summaryCard
                ForEach(feedback.cards) { card in
                    feedbackCard(card)
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AnalysisTheme.proTourBackground)
    }
}
```

The summary card shows:

```swift
Text("本次重点")
Text(feedback.summary.title)
Text(feedback.summary.observation)
Text(feedback.summary.recommendation)
```

Each default card shows only:

```swift
Text(card.category.title)
Text(card.status.title)
Text(card.conclusion)
ForEach(card.stages) { stage in
    Text(stage.evidenceCode)
}
```

Use one button per card to toggle `expandedCategory`. In the expanded section show:

- `card.evidenceState.title`;
- at most three measured motion metrics whose `id.userFacingTitle` is non-nil;
- each metric formatted as `title + value + unit`;
- P-stage buttons that seek to evidence;
- one `修正阶段` button per P-stage that calls `onAdjustStage`.

Do not show unavailable unsupported values. Do not show a category switch, checkpoint matrix, view selector, or generic “Customize” action.

Use these accessibility labels:

```swift
".\(card.category.title)，\(card.status.title)，\(card.conclusion)"
"证据状态，\(card.evidenceState.title)"
"定位到\(stage.evidenceCode)"
"修正\(stage.evidenceCode)"
```

Remove the leading period from the first string when applying it.

Complete the view with these helpers:

```swift
private var summaryCard: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("本次重点")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(AnalysisTheme.proTourSignal)
        Text(feedback.summary.title)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
        Text(feedback.summary.observation)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AnalysisTheme.proTourSecondaryText)
        Text(feedback.summary.recommendation)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
    }
    .padding(16)
    .background(
        AnalysisTheme.proTourSurface,
        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
    )
}

private func feedbackCard(
    _ card: SwingFeedbackCard
) -> some View {
    let isExpanded = expandedCategory == card.category
    return VStack(alignment: .leading, spacing: 12) {
        Button {
            expandedCategory = isExpanded ? nil : card.category
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(card.category.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                    Spacer()
                    Text(card.status.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(statusColor(card.status))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                }
                Text(card.conclusion)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    ForEach(card.stages) { stage in
                        Text(stage.evidenceCode)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 28)
                            .background(
                                AnalysisTheme.proTourRaisedSurface,
                                in: Capsule()
                            )
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(card.category.title)，\(card.status.title)，\(card.conclusion)"
        )

        if isExpanded {
            Divider().overlay(AnalysisTheme.proTourRaisedSurface)
            HStack {
                Text("证据状态")
                Spacer()
                Text(card.evidenceState.title)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("证据状态，\(card.evidenceState.title)")

            ForEach(
                Array(
                    card.metrics
                        .filter {
                            $0.availability == .measured
                                && $0.id.userFacingTitle != nil
                                && $0.value != nil
                        }
                        .prefix(3)
                        .enumerated()
                ),
                id: \.offset
            ) { entry in
                let metric = entry.element
                HStack {
                    Text(metric.id.userFacingTitle ?? "")
                    Spacer()
                    Text(
                        String(
                            format: "%.2f %@",
                            metric.value ?? 0,
                            metric.unit
                        )
                    )
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AnalysisTheme.proTourPrimaryText)
            }

            ForEach(card.stages) { stage in
                HStack {
                    Button("定位到\(stage.evidenceCode)") {
                        onSelectStage(stage)
                    }
                    .accessibilityLabel("定位到\(stage.evidenceCode)")
                    Spacer()
                    Button("修正阶段") {
                        onAdjustStage(stage)
                    }
                    .accessibilityLabel("修正\(stage.evidenceCode)")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AnalysisTheme.proTourSignal)
            }
        }
    }
    .padding(16)
    .background(
        isExpanded
            ? AnalysisTheme.proTourRaisedSurface
            : AnalysisTheme.proTourSurface,
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
    )
    .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(
                isExpanded
                    ? AnalysisTheme.proTourSignal
                    : AnalysisTheme.proTourRaisedSurface,
                lineWidth: 1
            )
    }
}

private func statusColor(
    _ status: SwingFeedbackStatus
) -> Color {
    switch status {
    case .good: return AnalysisTheme.proTourSignal
    case .attention: return AnalysisTheme.proTourPaused
    case .insufficientEvidence: return AnalysisTheme.proTourSecondaryText
    }
}
```

- [ ] **Step 5: Integrate category selection and trajectory overlay into the workspace**

In `AnalysisWorkspaceView`:

```swift
@State private var expandedFeedbackCategory: SwingFeedbackCategory?

private var simplifiedFeedback: SimplifiedSwingFeedback? {
    playbackManager.simplifiedFeedback(
        view: practiceCameraView,
        manualMarkers: keyframes
    )
}
```

Remove the `feedbackConfiguration` binding and the `techniquePresentation` computed property. Keep the existing `feedback: PriorityFeedback?` argument only until all construction sites compile, then remove it because the five-card feedback is now derived from `analysisOutput`.

Pass these optional values into `VideoCanvasView`:

```swift
trajectoryCategory: expandedFeedbackCategory,
trajectoryFrames: playbackManager.analysisOutput?.observationFrames ?? [],
trajectoryDetections: playbackManager.correctedDetections(
    manualMarkers: keyframes
)
```

Inside `VideoCanvasView`, place `SwingTrajectoryOverlay` above `DrawingOverlay` only when a category is expanded.

Replace `TechniqueFeedbackCard` and the `StageInspectorView`-only results sheet with:

```swift
if let simplifiedFeedback {
    SimplifiedSwingFeedbackView(
        feedback: simplifiedFeedback,
        expandedCategory: $expandedFeedbackCategory,
        onSelectStage: seekToStage,
        onAdjustStage: openAdjustment
    )
} else {
    ContentUnavailableView(
        "等待动作分析",
        systemImage: "figure.golf",
        description: Text("完成分析后显示本次重点和五项动作反馈。")
    )
}
```

Keep the existing `StageAdjustmentBar` and `onSetManualStage`; this is the manual correction entry required by the design.

On compact iPhone layouts, keep the workbench itself non-scrolling. Only the results sheet owns the contained `ScrollView`, with `.presentationDetents([.large])`.

- [ ] **Step 6: Remove the active configuration UI and state**

Delete `SwingFeedbackConfigurationView` from `WorkspaceComponents.swift`.

In `FullscreenVideoPlaybackView`, replace `showsFeedbackConfiguration` and the “选择回放分析参数” action with a single “动作反馈” action that opens the same `SimplifiedSwingFeedbackView`. Remove `activeMetricTitle`.

In `ContentView`:

- delete `@State private var feedbackConfiguration`;
- remove the binding passed to `AnalysisWorkspaceView`;
- remove `.onChange(of: feedbackConfiguration)`;
- stop assigning `saved.feedbackConfiguration` when loading;
- pass `feedbackConfiguration: nil` when constructing `LocalAnalysisProject` until Task 5 removes that initializer argument from active call sites.

Run:

```bash
rg -n "SwingFeedbackConfigurationView|showsFeedbackConfiguration|activeMetricTitle|选择回放分析参数" SwingArc
```

Expected: no matches.

- [ ] **Step 7: Run trajectory and presentation regression tests**

Run the Step 2 trajectory command again.

Then compile and run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  -framework SwiftUI \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Models/SimplifiedSwingFeedbackModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Design/AnalysisTheme.swift \
  Tests/TechniqueFeedbackPresentationSmoke.swift \
  -o /tmp/feedback-presentation && /tmp/feedback-presentation
```

Expected: both executables exit 0. Update the existing presentation smoke only where its old assertion explicitly requires the removed configuration button.

- [ ] **Step 8: Commit the simplified result UI**

```bash
git add \
  SwingArc/Views/SimplifiedSwingFeedbackView.swift \
  SwingArc/Views/SwingTrajectoryOverlay.swift \
  SwingArc/Views/AnalysisWorkspaceView.swift \
  SwingArc/Views/WorkspaceComponents.swift \
  SwingArc/Views/ContentView.swift \
  Tests/SwingTrajectoryPresentationSmoke.swift \
  Tests/TechniqueFeedbackPresentationSmoke.swift \
  SwingArcProject.xcodeproj/project.pbxproj
git commit -m "feat: show simplified swing feedback results"
```

### Task 5: Preserve legacy projects and verify the complete app

**Files:**
- Create: `Tests/SimplifiedFeedbackPersistenceSmoke.swift`
- Modify: `SwingArc/Services/LocalProjectStore.swift`
- Modify: `Tests/ProjectPersistenceSmoke.swift`
- Modify: `Tests/AnalysisWorkspacePresentationSmoke.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: legacy JSON containing `feedbackConfiguration`, current JSON containing `stageCorrections`, and the complete app target.
- Produces: backward-compatible project decoding, inactive legacy configuration storage, release-facing documentation of the five fixed outputs, and simulator build evidence.

- [ ] **Step 1: Write the failing legacy/new persistence contract**

Create `Tests/SimplifiedFeedbackPersistenceSmoke.swift`:

```swift
import Foundation

@main
struct SimplifiedFeedbackPersistenceSmoke {
    static func main() throws {
        let legacyJSON = """
        {
          "drawings": [],
          "keyframes": [],
          "isKeyframeMode": false,
          "showPoseSkeleton": true,
          "showHeadStability": true,
          "showSpineAngle": true,
          "showGrid": false,
          "practiceCameraView": "downTheLine",
          "stageCorrections": [],
          "feedbackConfiguration": {
            "activeMetric": "headPosition",
            "enabledCheckpoints": []
          }
        }
        """.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(
            LocalAnalysisProject.self,
            from: legacyJSON
        )
        precondition(legacy.practiceCameraView == .downTheLine)
        precondition(
            legacy.legacyFeedbackConfiguration?.activeMetric == .headPosition
        )

        let correction = StageCorrection(
            stage: .impact,
            view: .downTheLine,
            automaticFrameIndex: 80,
            manualFrameIndex: 84
        )
        let current = LocalAnalysisProject(
            drawings: [],
            keyframes: [],
            isKeyframeMode: false,
            showPoseSkeleton: true,
            showHeadStability: true,
            showSpineAngle: true,
            showGrid: false,
            practiceCameraView: .downTheLine,
            stageCorrections: [correction]
        )
        let data = try JSONEncoder().encode(current)
        let roundTrip = try JSONDecoder().decode(
            LocalAnalysisProject.self,
            from: data
        )
        precondition(roundTrip.stageCorrections == [correction])
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(object["feedbackConfiguration"] == nil)
    }
}
```

- [ ] **Step 2: Run the persistence test and capture the actual legacy decode result**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/LocalProjectStore.swift \
  Tests/SimplifiedFeedbackPersistenceSmoke.swift \
  -o /tmp/simplified-feedback-persistence && \
  /tmp/simplified-feedback-persistence
```

Expected: compilation fails because `legacyFeedbackConfiguration` does not exist yet.

- [ ] **Step 3: Keep decode compatibility but disable new writes**

In `LocalProjectStore.swift`, retain `feedbackConfiguration` in `CodingKeys` and `init(from:)`, but make it read-only compatibility data:

```swift
/// Decoded only so projects saved by the removed configuration UI remain
/// readable. New saves omit this field and the value never affects analysis.
private(set) var legacyFeedbackConfiguration: FeedbackConfiguration?
```

Decode `feedbackConfiguration` into `legacyFeedbackConfiguration`. Remove the active initializer parameter. Do not encode it:

```swift
// Intentionally omit the legacy feedbackConfiguration key.
```

Update `ProjectPersistenceSmoke.swift` so it checks:

- old JSON with no configuration still decodes;
- old JSON with configuration still decodes;
- stage corrections round-trip;
- new encoded JSON omits `feedbackConfiguration`.

Run:

```bash
rg -n "feedbackConfiguration" SwingArc Tests
```

Expected matches are limited to `LocalProjectStore.swift` legacy decoding and the two persistence tests. There are no view, state, or analysis references.

- [ ] **Step 4: Document exactly what the result page does and does not analyze**

Add this section to `README.md`:

```markdown
## 简化挥杆反馈

每次分析固定显示“本次重点”和五项动作反馈：准备姿势、身体稳定、手部路径、挥杆平面、击球与释放。卡片只在对应 P 阶段及二维画面证据充分时显示“良好”或“需注意”；估算、遮挡、出画、低置信度和缺失证据统一降级为“证据不足”，且不会影响其他卡片。

SwingArc 当前分析单机位视频中的二维挥杆动作，不检测或展示真实杆头速度、攻角、杆面角、动态杆面倾角、球速、起飞角、旋转或飞行距离。当前开发视频和合成测试不能证明最终 P1–P8 或教练级准确率，准确率结论以完成双人标注的独立测试集报告为准。
```

- [ ] **Step 5: Run forbidden-output and UI-scope audits**

Run:

```bash
rg -n \
  "真实杆头速度|攻角|杆面角|动态杆面倾角|球速|起飞角|倒旋率|飞行距离|Customize|选择回放分析参数" \
  SwingArc/Views SwingArc/Services
```

Expected: no matches.

Run:

```bash
rg -n \
  "SwingFeedbackConfigurationView|FeedbackConfiguration\\?|feedbackConfiguration:" \
  SwingArc/Views SwingArc/Services
```

Expected: only the private legacy decoder representation in `LocalProjectStore.swift`; no active UI or analysis reference.

- [ ] **Step 6: Run focused smoke regressions**

Run all new executables:

```bash
/tmp/swing-metric-engine
/tmp/simplified-swing-feedback
/tmp/swing-artifact-builder
/tmp/swing-trajectory-presentation
```

Recompile any executable whose production source changed after its previous run, then require exit status 0.

Run existing regressions for:

- `ContinuousEvidenceStageSolverSmoke`;
- `SwingObjectEvidenceSmoke`;
- `SwingTemporalEvidenceSmoke`;
- `ProjectPersistenceSmoke`;
- `AnalysisWorkspacePresentationSmoke`;
- `TechniqueFeedbackPresentationSmoke`.

Expected: every executable exits 0. P2/P6/P8 shaft and P7 impact evidence behavior remains unchanged.

- [ ] **Step 7: Build the complete simulator app**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild \
  -project SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `** BUILD SUCCEEDED **`.

If Xcode reports that an input file changed during the build while the source is unchanged, re-run once after File Provider finishes hydrating the file. Do not alter production code to hide that filesystem condition.

- [ ] **Step 8: Perform the compact portrait visual check**

Launch the simulator preview path that imports a bundled or local development clip and automatically analyzes it. Verify:

- one “本次重点” appears;
- exactly five cards appear in the confirmed order;
- default cards contain no raw metric list;
- tapping one card expands only that category;
- the video seeks to its P-stage button;
- measured trajectory is solid and estimated trajectory is dashed;
- VoiceOver reads category, status, conclusion, and evidence state;
- the compact workbench has no page-level empty vertical scrolling;
- the result sheet owns the only scrolling needed for expanded evidence.

Record the device model, iOS simulator version, and screenshot paths in the implementation handoff. A visual check does not count as algorithm-accuracy proof.

- [ ] **Step 9: Commit compatibility, documentation, and verification updates**

```bash
git add \
  SwingArc/Services/LocalProjectStore.swift \
  Tests/SimplifiedFeedbackPersistenceSmoke.swift \
  Tests/ProjectPersistenceSmoke.swift \
  Tests/AnalysisWorkspacePresentationSmoke.swift \
  README.md
git commit -m "refactor: retire configurable swing feedback"
```

---

## Completion Gate

Implementation is complete only when all of the following are true:

- `SwingFeedbackCategory.allCases` produces exactly five cards in the confirmed order.
- A single estimated P3 hand point downgrades only `手部路径`.
- Missing P7 impact evidence downgrades only `击球与释放`.
- Unsupported equipment/ball-flight parameters are absent from new artifacts, services, and views.
- Old projects containing `feedbackConfiguration` still decode.
- New saves omit `feedbackConfiguration` and preserve manual P-stage corrections.
- Expanded cards show only category-local stages, trajectories, and at most three supported 2D values.
- The simulator app builds successfully and the compact portrait visual check passes.
- The handoff explicitly states that reviewed real-video accuracy remains unproven until the dataset acceptance report exists.

After this plan is complete, return to the separate precision-analysis plan for reviewed dataset labeling, held-out evaluation, model promotion, and TestFlight evidence. Those accuracy/release gates are intentionally not duplicated here.

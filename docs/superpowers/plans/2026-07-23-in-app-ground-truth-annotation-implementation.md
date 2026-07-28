# App 内正式真值标注 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 SwingArc iPhone/iPad App 内完成可变帧率原片的精确逐帧、P1–P8 双人独立标注、人体/球杆关键点修正、分歧裁定、人工锁定和标准 JSON 导出闭环。

**Architecture:** 新增独立的标注领域模型与存储目录，使用共享的真实 presentation timestamp 时间线读取源帧，并以全屏 `AnnotationWorkspaceView` 与普通分析工作台隔离。Apple Vision 与现有分析结果只作为未复核预标注；双人提交、裁定、授权和导出由纯逻辑验证器控制。

**Tech Stack:** Swift 5、SwiftUI、AVFoundation、CoreMedia、CryptoKit、Foundation、现有 standalone Swift smoke tests、Xcode 27 beta、iOS 17+。

## Global Constraints

- 原片只读；不得剪辑、转码、覆盖或静默上传。
- iPhone 可变帧率原片必须按真实 presentation timestamp 读取，禁止使用 `sourceFrameIndex / averageFrameRate`。
- 使用标准 `p-system-v1`：P6 为下杆杆身平行，P7 为击球，P8 为击球后杆身平行。
- 人工锁定结果优先级最高，重新分析不得覆盖。
- 标注者 B 提交前不得看到标注者 A 的帧号和点位。
- 未经人工复核的 AI 预测不得进入训练集。
- 只有 `training-allowed`、双人阶段标注完整且关键点已复核的数据可导出为训练或验证数据。
- 标注数据与 `LocalAnalysisProject` 隔离，普通项目、绘图和媒体状态不得改变。
- 默认导出不包含原始视频字节。
- 所有生产行为修改必须遵循 RED → GREEN → REFACTOR。

---

## File Structure

- `SwingArc/Models/AnnotationModels.swift`
  - 标注包、媒体身份、标注者会话、阶段、关键点、可见性和修订模型。
- `SwingArc/Models/AnnotationWorkspaceState.swift`
  - 标注步骤、选中工具、会话隔离、裁定队列和纯状态转换。
- `SwingArc/Services/ExactVideoFrameProvider.swift`
  - 加载真实源帧时间线、精确解码、方向修正和帧身份校验。
- `SwingArc/Services/AnnotationPackageValidator.swift`
  - 阶段顺序、双人独立性、裁定、关键点复核和授权门。
- `SwingArc/Services/AnnotationStore.swift`
  - 原片 SHA-256 身份、独立目录、原子保存、恢复和修订。
- `SwingArc/Services/AnnotationExportService.swift`
  - 冻结、标准 JSON 导出、校验值和训练导出限制。
- `SwingArc/Services/AnnotationPredictionAdapter.swift`
  - 将现有 Vision/球杆证据转换为只读预标注，不产生人工真值。
- `SwingArc/Views/AnnotationFrameCanvas.swift`
  - 高分辨率帧、缩放、放大镜和关键点拖动。
- `SwingArc/Views/AnnotationWorkspaceView.swift`
  - 五步全屏标注工作流和手机/平板布局。
- `Tests/AnnotationModelsSmoke.swift`
- `Tests/AnnotationFixture.swift`
- `Tests/AnnotationSourceFrameTimelineSmoke.swift`
- `Tests/AnnotationWorkspaceStateSmoke.swift`
- `Tests/AnnotationStoreSmoke.swift`
- `Tests/AnnotationExportSmoke.swift`
- `Tests/AnnotationPresentationSmoke.swift`
- `Tools/PrecisionDataset/ValidateAnnotationExport.swift`
- Modify `SwingArc/Models/FrameExtractionTolerancePolicy.swift`
- Modify `SwingArc/Services/VisionPoseDetector.swift`
- Modify `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify `SwingArc/Views/WorkspaceComponents.swift`
- Modify `SwingArc/Views/ContentView.swift`
- Modify `SwingArcProject.xcodeproj/project.pbxproj`

---

### Task 1: Freeze the annotation data contract and validation rules

**Files:**
- Create: `SwingArc/Models/AnnotationModels.swift`
- Create: `SwingArc/Services/AnnotationPackageValidator.swift`
- Create: `Tests/AnnotationModelsSmoke.swift`

**Interfaces:**
- Produces: `AnnotationPackage`, `AnnotationMediaIdentity`, `AnnotationClipMetadata`, `AnnotationPass`, `AnnotationStageSelection`, `AnnotationFrameLabel`, `AnnotationPoint`, `AnnotationVisibility`, `AnnotationPackageValidator.validate(_:)`.
- Consumes: Standard P codes `P1...P8`; no UI or AVFoundation dependency.

- [ ] **Step 1: Write the failing model and validator test**

Create `Tests/AnnotationModelsSmoke.swift`:

```swift
import Foundation

@main
struct AnnotationModelsSmoke {
    static func main() throws {
        let media = AnnotationMediaIdentity(
            fileName: "IMG_4692.MOV",
            sha256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            frameCount: 1526,
            width: 1080,
            height: 1920
        )
        let metadata = AnnotationClipMetadata(
            clipID: "clip-4692",
            golferID: "golfer-001",
            view: .faceOn,
            handedness: .right,
            authorization: .trainingAllowed,
            split: .development
        )
        let stages = (1...8).map {
            AnnotationStageSelection(
                stage: "P\($0)",
                sourceFrameIndex: 100 + $0 * 10,
                status: .manual,
                note: nil
            )
        }
        let passA = AnnotationPass(
            id: UUID(),
            annotatorID: "annotator-a",
            revision: 1,
            submittedAt: Date(timeIntervalSince1970: 1),
            stages: stages,
            frameLabels: []
        )
        let passB = AnnotationPass(
            id: UUID(),
            annotatorID: "annotator-b",
            revision: 1,
            submittedAt: Date(timeIntervalSince1970: 2),
            stages: stages,
            frameLabels: []
        )
        let package = AnnotationPackage(
            schemaVersion: 1,
            stageSystem: "p-system-v1",
            media: media,
            metadata: metadata,
            passes: [passA, passB],
            adjudications: [],
            frozenAt: nil
        )

        precondition(AnnotationPackageValidator.validate(package).isEmpty)
        let roundTrip = try JSONDecoder().decode(
            AnnotationPackage.self,
            from: JSONEncoder().encode(package)
        )
        precondition(roundTrip == package)

        let duplicate = package.replacingPasses([passA, passA])
        precondition(
            AnnotationPackageValidator.validate(duplicate)
                .contains(.duplicateAnnotator("annotator-a"))
        )

        var wrongStages = stages
        wrongStages[0] = .init(
            stage: "P1",
            sourceFrameIndex: 120,
            status: .manual,
            note: nil
        )
        wrongStages[1] = .init(
            stage: "P2",
            sourceFrameIndex: 110,
            status: .manual,
            note: nil
        )
        let wrongOrder = passB.replacingStages(wrongStages)
        precondition(
            AnnotationPackageValidator.validate(
                package.replacingPasses([passA, wrongOrder])
            ).contains(.invalidStageOrder(annotatorID: "annotator-b"))
        )

        let point = AnnotationPoint(
            x: 0.5,
            y: 0.6,
            visibility: .visible,
            source: .manual,
            confidence: nil
        )
        precondition(point.isEligibleForCoordinateTraining)
        precondition(
            AnnotationPoint(
                x: 0.5,
                y: 0.6,
                visibility: .occluded,
                source: .manual,
                confidence: nil
            ).isEligibleForCoordinateTraining == false
        )

        var closeStages = stages
        closeStages[0].sourceFrameIndex = stages[0].sourceFrameIndex.map { $0 + 1 }
        let closePass = passB.replacingStages(closeStages)
        let consensus = AnnotationConsensusResolver.resolve(
            package.replacingPasses([passA, closePass])
        )
        precondition(consensus.first { $0.stage == "P1" }?.sourceFrameIndex == 111)
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Services/AnnotationPackageValidator.swift \
  Tests/AnnotationModelsSmoke.swift \
  -o /tmp/annotation-models-smoke
```

Expected: FAIL because `AnnotationModels.swift` and the declared contracts do not exist.

- [ ] **Step 3: Implement the minimal annotation models**

Create `SwingArc/Models/AnnotationModels.swift` with:

```swift
import Foundation

enum AnnotationView: String, Codable, CaseIterable {
    case downTheLine = "dtl"
    case faceOn = "face-on"
}

enum AnnotationHandedness: String, Codable, CaseIterable {
    case left
    case right
}

enum AnnotationAuthorization: String, Codable, CaseIterable {
    case internalReview = "internal-review"
    case trainingAllowed = "training-allowed"
}

enum AnnotationSplit: String, Codable, CaseIterable {
    case development
    case training
    case validation
    case heldOut = "held-out"
}

enum AnnotationVisibility: String, Codable, CaseIterable {
    case visible
    case occluded
    case outOfFrame = "out-of-frame"
    case unresolved
}

enum AnnotationPointSource: String, Codable {
    case predicted
    case manual
}

enum AnnotationStageStatus: String, Codable {
    case predicted
    case manual
    case unresolved
}

struct AnnotationMediaIdentity: Codable, Equatable {
    let fileName: String
    let sha256: String
    let timelineSHA256: String
    let frameCount: Int
    let width: Int
    let height: Int
}

struct AnnotationClipMetadata: Codable, Equatable {
    let clipID: String
    let golferID: String
    let view: AnnotationView
    let handedness: AnnotationHandedness
    let authorization: AnnotationAuthorization
    let split: AnnotationSplit
}

struct AnnotationPoint: Codable, Equatable {
    var x: Double?
    var y: Double?
    var visibility: AnnotationVisibility
    var source: AnnotationPointSource
    var confidence: Double?

    var isEligibleForCoordinateTraining: Bool {
        guard visibility == .visible,
              source == .manual,
              let x,
              let y else { return false }
        return (0...1).contains(x) && (0...1).contains(y)
    }
}

struct AnnotationFrameLabel: Codable, Equatable {
    let sourceFrameIndex: Int
    var landmarks: [String: AnnotationPoint]
    var reviewerID: String?
    var reviewed: Bool
}

struct AnnotationStageSelection: Codable, Equatable {
    let stage: String
    var sourceFrameIndex: Int?
    var suggestedSourceFrameIndex: Int?
    var suggestedRangeStart: Int?
    var suggestedRangeEnd: Int?
    var status: AnnotationStageStatus
    var note: String?

    init(
        stage: String,
        sourceFrameIndex: Int?,
        suggestedSourceFrameIndex: Int? = nil,
        suggestedRangeStart: Int? = nil,
        suggestedRangeEnd: Int? = nil,
        status: AnnotationStageStatus,
        note: String?
    ) {
        self.stage = stage
        self.sourceFrameIndex = sourceFrameIndex
        self.suggestedSourceFrameIndex = suggestedSourceFrameIndex
        self.suggestedRangeStart = suggestedRangeStart
        self.suggestedRangeEnd = suggestedRangeEnd
        self.status = status
        self.note = note
    }
}

struct AnnotationPass: Codable, Equatable, Identifiable {
    let id: UUID
    let annotatorID: String
    let revision: Int
    let submittedAt: Date?
    var stages: [AnnotationStageSelection]
    var frameLabels: [AnnotationFrameLabel]

    func replacingStages(_ stages: [AnnotationStageSelection]) -> Self {
        .init(
            id: id,
            annotatorID: annotatorID,
            revision: revision,
            submittedAt: submittedAt,
            stages: stages,
            frameLabels: frameLabels
        )
    }
}

struct AnnotationAdjudication: Codable, Equatable {
    let stage: String
    let sourceFrameIndex: Int?
    let adjudicatorID: String
    let decidedAt: Date
    let originalSelections: [AnnotationStageSelection]
    let note: String

    init(
        stage: String,
        sourceFrameIndex: Int?,
        adjudicatorID: String,
        decidedAt: Date,
        originalSelections: [AnnotationStageSelection] = [],
        note: String
    ) {
        self.stage = stage
        self.sourceFrameIndex = sourceFrameIndex
        self.adjudicatorID = adjudicatorID
        self.decidedAt = decidedAt
        self.originalSelections = originalSelections
        self.note = note
    }
}

struct AnnotationFrameQueuePolicy: Codable, Equatable {
    let version: String
    let p1ThroughP5Stride: Int
    let p5ThroughP8Stride: Int

    static let v1 = AnnotationFrameQueuePolicy(
        version: "swingarc-annotation-queue-v1",
        p1ThroughP5Stride: 4,
        p5ThroughP8Stride: 2
    )
}

struct AnnotationPackage: Codable, Equatable {
    let schemaVersion: Int
    let stageSystem: String
    let media: AnnotationMediaIdentity
    let metadata: AnnotationClipMetadata
    let frameQueuePolicy: AnnotationFrameQueuePolicy
    var frameQueue: [Int]
    var activeDraft: AnnotationPass?
    var currentSourceFrameIndex: Int
    var passes: [AnnotationPass]
    var archivedPassRevisions: [AnnotationPass]
    var adjudications: [AnnotationAdjudication]
    var frozenAt: Date?

    init(
        schemaVersion: Int,
        stageSystem: String,
        media: AnnotationMediaIdentity,
        metadata: AnnotationClipMetadata,
        frameQueuePolicy: AnnotationFrameQueuePolicy = .v1,
        frameQueue: [Int] = [],
        activeDraft: AnnotationPass? = nil,
        currentSourceFrameIndex: Int = 0,
        passes: [AnnotationPass],
        archivedPassRevisions: [AnnotationPass] = [],
        adjudications: [AnnotationAdjudication],
        frozenAt: Date?
    ) {
        self.schemaVersion = schemaVersion
        self.stageSystem = stageSystem
        self.media = media
        self.metadata = metadata
        self.frameQueuePolicy = frameQueuePolicy
        self.frameQueue = frameQueue
        self.activeDraft = activeDraft
        self.currentSourceFrameIndex = currentSourceFrameIndex
        self.passes = passes
        self.archivedPassRevisions = archivedPassRevisions
        self.adjudications = adjudications
        self.frozenAt = frozenAt
    }

    func replacingPasses(_ passes: [AnnotationPass]) -> Self {
        var copy = self
        copy.passes = passes
        return copy
    }
}

enum AnnotationCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 4: Implement the validator**

Create `SwingArc/Services/AnnotationPackageValidator.swift`:

```swift
import Foundation

enum AnnotationValidationError: Equatable {
    case unsupportedSchema(Int)
    case invalidStageSystem(String)
    case invalidMediaIdentity
    case invalidSubmittedPassCount
    case duplicateAnnotator(String)
    case invalidStageSet(annotatorID: String)
    case invalidStageOrder(annotatorID: String)
    case trainingWithoutAuthorization
    case missingReviewedFrames(annotatorID: String)
    case unreviewedTrainingFrame(sourceFrameIndex: Int)
    case unresolvedTrainingStage(stage: String)
    case activeDraftPresent
    case invalidFrameQueue
    case missingAdjudication(stage: String)
    case incompleteAdjudication(stage: String)
}

enum AnnotationPackageValidator {
    static let stageCodes = (1...8).map { "P\($0)" }

    static func validate(_ package: AnnotationPackage) -> [AnnotationValidationError] {
        var errors: [AnnotationValidationError] = []
        if package.schemaVersion != 1 {
            errors.append(.unsupportedSchema(package.schemaVersion))
        }
        if package.stageSystem != "p-system-v1" {
            errors.append(.invalidStageSystem(package.stageSystem))
        }
        if package.media.sha256.count != 64
            || package.media.timelineSHA256.count != 64
            || package.media.frameCount <= 0
            || package.media.width <= 0
            || package.media.height <= 0 {
            errors.append(.invalidMediaIdentity)
        }

        let groups = Dictionary(grouping: package.passes, by: \.annotatorID)
        if package.passes.count != 2
            || package.passes.contains(where: { $0.submittedAt == nil }) {
            errors.append(.invalidSubmittedPassCount)
        }
        for (annotator, passes) in groups where passes.count > 1 {
            errors.append(.duplicateAnnotator(annotator))
        }
        for pass in package.passes {
            let groupedStages = Dictionary(grouping: pass.stages, by: \.stage)
            if Set(groupedStages.keys) != Set(stageCodes)
                || groupedStages.values.contains(where: { $0.count != 1 }) {
                errors.append(.invalidStageSet(annotatorID: pass.annotatorID))
                continue
            }
            let stageMap = groupedStages.compactMapValues { $0.first }
            let frames = stageCodes.compactMap { stageMap[$0]?.sourceFrameIndex }
            if !zip(frames, frames.dropFirst()).allSatisfy(<) {
                errors.append(.invalidStageOrder(annotatorID: pass.annotatorID))
            }
        }

        if package.metadata.split != .development
            && package.metadata.authorization != .trainingAllowed {
            errors.append(.trainingWithoutAuthorization)
        }
        if package.metadata.split != .development {
            for pass in package.passes {
                if pass.frameLabels.isEmpty {
                    errors.append(.missingReviewedFrames(
                        annotatorID: pass.annotatorID
                    ))
                }
                for frame in pass.frameLabels
                    where !frame.reviewed || frame.reviewerID?.isEmpty != false {
                    errors.append(.unreviewedTrainingFrame(
                        sourceFrameIndex: frame.sourceFrameIndex
                    ))
                }
            }
            for resolved in AnnotationConsensusResolver.resolve(package)
                where resolved.sourceFrameIndex == nil {
                errors.append(.unresolvedTrainingStage(stage: resolved.stage))
            }
        }
        if package.frozenAt != nil, package.activeDraft != nil {
            errors.append(.activeDraftPresent)
        }
        if package.frameQueue.contains(where: {
            !(0..<package.media.frameCount).contains($0)
        }) || package.frameQueue != Array(Set(package.frameQueue)).sorted() {
            errors.append(.invalidFrameQueue)
        }
        if package.frozenAt != nil,
           package.metadata.split != .development,
           package.frameQueue.isEmpty {
            errors.append(.invalidFrameQueue)
        }

        if package.passes.count == 2 {
            for stage in stageCodes {
                let selections = package.passes.compactMap {
                    $0.stages.first(where: { $0.stage == stage })
                }
                let frames = selections.compactMap(\.sourceFrameIndex)
                let needsDecision = frames.count != 2
                    || abs(frames[0] - frames[1]) > 2
                if needsDecision
                    && !package.adjudications.contains(where: { $0.stage == stage }) {
                    errors.append(.missingAdjudication(stage: stage))
                }
                if let decision = package.adjudications.first(where: {
                    $0.stage == stage
                }), decision.originalSelections.count != 2 {
                    errors.append(.incompleteAdjudication(stage: stage))
                }
            }
        }
        return errors
    }
}

enum AnnotationConsensusResolver {
    static func resolve(
        _ package: AnnotationPackage
    ) -> [AnnotationStageSelection] {
        AnnotationPackageValidator.stageCodes.map { stage in
            if let decision = package.adjudications.first(where: {
                $0.stage == stage
            }) {
                return .init(
                    stage: stage,
                    sourceFrameIndex: decision.sourceFrameIndex,
                    status: decision.sourceFrameIndex == nil
                        ? .unresolved
                        : .manual,
                    note: "adjudicated"
                )
            }
            let originals = package.passes.prefix(2).compactMap {
                $0.stages.first(where: { $0.stage == stage })
            }
            let frames = originals.compactMap(\.sourceFrameIndex)
            guard frames.count == 2, abs(frames[0] - frames[1]) <= 2 else {
                return .init(
                    stage: stage,
                    sourceFrameIndex: nil,
                    status: .unresolved,
                    note: "requires-adjudication"
                )
            }
            return .init(
                stage: stage,
                sourceFrameIndex: Int(
                    (Double(frames[0] + frames[1]) / 2).rounded()
                ),
                status: .manual,
                note: "two-pass-midpoint"
            )
        }
    }
}
```

- [ ] **Step 5: Run GREEN and commit**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Services/AnnotationPackageValidator.swift \
  Tests/AnnotationModelsSmoke.swift \
  -o /tmp/annotation-models-smoke &&
/tmp/annotation-models-smoke
```

Expected: PASS with no output.

Commit:

```bash
git add SwingArc/Models/AnnotationModels.swift \
  SwingArc/Services/AnnotationPackageValidator.swift \
  Tests/AnnotationModelsSmoke.swift
git commit -m "feat: define annotation data contract"
```

---

### Task 2: Share an exact variable-frame-rate source timeline

**Files:**
- Create: `SwingArc/Services/ExactVideoFrameProvider.swift`
- Create: `Tests/AnnotationSourceFrameTimelineSmoke.swift`
- Modify: `SwingArc/Models/FrameExtractionTolerancePolicy.swift`
- Modify: `SwingArc/Services/VisionPoseDetector.swift`

**Interfaces:**
- Consumes: `SourceFrameTimeline`.
- Produces: `ExactVideoFrameProvider.load(url:)`, `ExactVideoFrameProvider.frame(at:)`, `ExactVideoFrame`, and `SourceFrameTimeline.timelineSHA256`.
- Later tasks depend on exact frame index, oriented `CGImage`, PTS, frame count, and timeline digest.

- [ ] **Step 1: Write the failing synthetic and real-video test**

Create `Tests/AnnotationSourceFrameTimelineSmoke.swift`:

```swift
import AVFoundation
import Foundation

@main
struct AnnotationSourceFrameTimelineSmoke {
    static func main() throws {
        let synthetic = SourceFrameTimeline(presentationTimes: [
            CMTime(value: 0, timescale: 240),
            CMTime(value: 1, timescale: 240),
            CMTime(value: 3, timescale: 240)
        ])!
        precondition(synthetic.count == 3)
        precondition(synthetic.timelineSHA256.count == 64)
        precondition(synthetic.presentationTime(sourceFrameIndex: 2)
            == CMTime(value: 3, timescale: 240))

        guard CommandLine.arguments.count == 2 else { return }
        let provider = try ExactVideoFrameProvider.load(
            url: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        precondition(provider.frameCount > 0)
        if provider.url.lastPathComponent == "IMG_4692.MOV" {
            precondition(provider.frameCount == 1526)
        }
        let first = try provider.frame(at: 0)
        let last = try provider.frame(at: provider.frameCount - 1)
        precondition(first.sourceFrameIndex == 0)
        precondition(last.sourceFrameIndex == provider.frameCount - 1)
        precondition(first.presentationTime < last.presentationTime)
        precondition(first.image.width == last.image.width)
        precondition(first.image.height == last.image.height)
        print("TIMELINE \(provider.timelineSHA256) \(provider.frameCount)")
    }
}
```

- [ ] **Step 2: Verify RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  SwingArc/Services/ExactVideoFrameProvider.swift \
  Tests/AnnotationSourceFrameTimelineSmoke.swift \
  -o /tmp/annotation-frame-timeline
```

Expected: FAIL because `ExactVideoFrameProvider` and `timelineSHA256` do not exist.

- [ ] **Step 3: Expose a deterministic timeline digest**

Modify `SourceFrameTimeline` in
`SwingArc/Models/FrameExtractionTolerancePolicy.swift`:

```swift
import CryptoKit

var timelineSHA256: String {
    var data = Data()
    for time in presentationTimes {
        var value = time.value.bigEndian
        var timescale = time.timescale.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &timescale) { data.append(contentsOf: $0) }
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
```

Keep `presentationTimes` private; callers continue through
`presentationTime(sourceFrameIndex:)`.

- [ ] **Step 4: Implement the exact frame provider**

Create `SwingArc/Services/ExactVideoFrameProvider.swift`:

```swift
import AVFoundation
import CoreGraphics
import Foundation

struct ExactVideoFrame: @unchecked Sendable {
    let sourceFrameIndex: Int
    let presentationTime: CMTime
    let image: CGImage
}

enum ExactVideoFrameProviderError: Error, Equatable {
    case missingVideoTrack
    case timelineUnavailable
    case frameOutOfRange(Int)
    case decodeFailed(Int)
    case decodedNeighborFrame(requested: Int)
}

final class ExactVideoFrameProvider {
    let url: URL
    let timeline: SourceFrameTimeline
    let orientedSize: CGSize

    private let asset: AVURLAsset
    private let generator: AVAssetImageGenerator

    var frameCount: Int { timeline.count }
    var timelineSHA256: String { timeline.timelineSHA256 }

    private init(
        url: URL,
        asset: AVURLAsset,
        timeline: SourceFrameTimeline,
        orientedSize: CGSize
    ) {
        self.url = url
        self.asset = asset
        self.timeline = timeline
        self.orientedSize = orientedSize
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let tolerance = timeline.averageFrameRate.flatMap {
            FrameExtractionTolerancePolicy.halfFrameTime(sourceFrameRate: $0)
        } ?? .zero
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
    }

    static func load(url: URL) throws -> ExactVideoFrameProvider {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw ExactVideoFrameProviderError.missingVideoTrack
        }
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw ExactVideoFrameProviderError.timelineUnavailable
        }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
        guard reader.canAdd(output) else {
            throw ExactVideoFrameProviderError.timelineUnavailable
        }
        reader.add(output)
        guard reader.startReading() else {
            throw ExactVideoFrameProviderError.timelineUnavailable
        }
        var times: [CMTime] = []
        while let sample = output.copyNextSampleBuffer() {
            times.append(CMSampleBufferGetPresentationTimeStamp(sample))
        }
        guard reader.status == .completed,
              let timeline = SourceFrameTimeline(presentationTimes: times) else {
            throw ExactVideoFrameProviderError.timelineUnavailable
        }
        let transformed = track.naturalSize.applying(track.preferredTransform)
        let size = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        return .init(url: url, asset: asset, timeline: timeline, orientedSize: size)
    }

    func frame(at sourceFrameIndex: Int) throws -> ExactVideoFrame {
        guard let time = timeline.presentationTime(
            sourceFrameIndex: sourceFrameIndex
        ) else {
            throw ExactVideoFrameProviderError.frameOutOfRange(sourceFrameIndex)
        }
        var actual = CMTime.invalid
        guard let image = try? generator.copyCGImage(at: time, actualTime: &actual) else {
            throw ExactVideoFrameProviderError.decodeFailed(sourceFrameIndex)
        }
        guard timeline.matches(
            requestedSourceFrameIndex: sourceFrameIndex,
            actualTime: actual
        ) else {
            throw ExactVideoFrameProviderError.decodedNeighborFrame(
                requested: sourceFrameIndex
            )
        }
        return .init(
            sourceFrameIndex: sourceFrameIndex,
            presentationTime: actual,
            image: image
        )
    }
}
```

`frame(at:)` must remain serialized. In Task 6, all calls to `load(url:)` and
`frame(at:)` run through one background actor; the SwiftUI main actor receives
only the resulting metadata or `ExactVideoFrame`. Do not scan a 240 FPS file or
decode a frame on the main actor.

- [ ] **Step 5: Reuse the provider timeline in the analysis engine**

Replace the private `SwingVideoAnalysisEngine.sourceFrameTimeline(...)`
implementation with:

```swift
let sourceFrameTimeline: SourceFrameTimeline?
if metadataFrameRate == metadataFrameRate.rounded(),
   metadataFrameRate <= FineSwingSamplingPlan.maximumSamplesPerSecond {
    sourceFrameTimeline = SourceFrameTimeline(
        duration: duration,
        constantFrameRate: metadataFrameRate
    )
} else {
    sourceFrameTimeline = try? ExactVideoFrameProvider.load(url: url).timeline
}
```

Delete the duplicated private AVAssetReader timeline loader. Keep the existing
integer-CFR fast path unchanged.

- [ ] **Step 6: Run synthetic, real original, and existing regression tests**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  SwingArc/Services/ExactVideoFrameProvider.swift \
  Tests/AnnotationSourceFrameTimelineSmoke.swift \
  -o /tmp/annotation-frame-timeline &&
/tmp/annotation-frame-timeline \
  /Users/liangbo/Desktop/test/original-240fps/IMG_4692.MOV
```

Expected: PASS; the original file exposes 1526 decodable frames and both
endpoints decode as their requested source-frame identity.

Also run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  Tests/FrameExtractionTolerancePolicySmoke.swift \
  -o /tmp/frame-tolerance-smoke &&
/tmp/frame-tolerance-smoke \
  SwingArc/Services/VisionPoseDetector.swift \
  /Users/liangbo/Desktop/test/original-240fps/IMG_4692.MOV
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  SwingArc/Services/ExactVideoFrameProvider.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  Tests/AnnotationSourceFrameTimelineSmoke.swift
git commit -m "feat: add exact annotation frame provider"
```

---

### Task 3: Persist annotation packages independently and atomically

**Files:**
- Create: `SwingArc/Services/AnnotationStore.swift`
- Create: `Tests/AnnotationFixture.swift`
- Create: `Tests/AnnotationStoreSmoke.swift`

**Interfaces:**
- Consumes: `AnnotationPackage`, local video URL.
- Produces: `AnnotationStore.mediaSHA256(url:)`, `load(mediaSHA256:)`,
  `save(_:mediaSHA256:)`, `packageURL(mediaSHA256:)`, and revision-safe atomic writes.

- [ ] **Step 1: Write the failing store test**

Create `Tests/AnnotationStoreSmoke.swift`:

```swift
import Foundation

@main
struct AnnotationStoreSmoke {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let video = root.appendingPathComponent("sample.mov")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data("video-bytes".utf8).write(to: video)

        let hash = try AnnotationStore.mediaSHA256(url: video)
        precondition(hash.count == 64)

        let package = AnnotationFixture.package(
            mediaSHA256: hash,
            timelineSHA256: String(repeating: "b", count: 64)
        )
        let store = AnnotationStore(rootDirectory: root.appendingPathComponent("labels"))
        try store.save(package)
        precondition(try store.load(mediaSHA256: hash) == package)

        let mismatched = AnnotationFixture.package(
            mediaSHA256: String(repeating: "c", count: 64),
            timelineSHA256: String(repeating: "b", count: 64)
        )
        do {
            try store.save(mismatched, expectedMediaSHA256: hash)
            preconditionFailure("mismatched media identity must be rejected")
        } catch AnnotationStoreError.mediaIdentityMismatch {
        }
    }
}
```

Create `Tests/AnnotationFixture.swift`:

```swift
import Foundation

enum AnnotationFixture {
    static func package(
        mediaSHA256: String = String(repeating: "a", count: 64),
        timelineSHA256: String = String(repeating: "b", count: 64),
        reviewed: Bool = true
    ) -> AnnotationPackage {
        let media = AnnotationMediaIdentity(
            fileName: "fixture.mov",
            sha256: mediaSHA256,
            timelineSHA256: timelineSHA256,
            frameCount: 400,
            width: 1080,
            height: 1920
        )
        let metadata = AnnotationClipMetadata(
            clipID: "fixture-clip",
            golferID: "fixture-golfer",
            view: .faceOn,
            handedness: .right,
            authorization: .trainingAllowed,
            split: .training
        )
        let points = Dictionary(uniqueKeysWithValues:
            ["grip", "shaftStart", "shaftEnd", "clubhead", "ball"].map {
                ($0, AnnotationPoint(
                    x: 0.5,
                    y: 0.5,
                    visibility: .visible,
                    source: .manual,
                    confidence: nil
                ))
            }
        )
        func pass(_ annotator: String, submittedAt: TimeInterval) -> AnnotationPass {
            AnnotationPass(
                id: UUID(),
                annotatorID: annotator,
                revision: 1,
                submittedAt: Date(timeIntervalSince1970: submittedAt),
                stages: (1...8).map {
                    AnnotationStageSelection(
                        stage: "P\($0)",
                        sourceFrameIndex: $0 * 40,
                        status: .manual,
                        note: nil
                    )
                },
                frameLabels: [
                    AnnotationFrameLabel(
                        sourceFrameIndex: 280,
                        landmarks: points,
                        reviewerID: reviewed ? "reviewer" : nil,
                        reviewed: reviewed
                    )
                ]
            )
        }
        return AnnotationPackage(
            schemaVersion: 1,
            stageSystem: "p-system-v1",
            media: media,
            metadata: metadata,
            frameQueue: (1...8).map { $0 * 40 },
            passes: [
                pass("annotator-a", submittedAt: 1),
                pass("annotator-b", submittedAt: 2)
            ],
            adjudications: [],
            frozenAt: nil
        )
    }

    static func completeReviewedPackage() -> AnnotationPackage {
        package(reviewed: true)
    }
}
```

- [ ] **Step 2: Verify RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Services/AnnotationStore.swift \
  Tests/AnnotationFixture.swift \
  Tests/AnnotationStoreSmoke.swift \
  -o /tmp/annotation-store-smoke
```

Expected: FAIL because `AnnotationStore` does not exist.

- [ ] **Step 3: Implement file hashing and atomic storage**

Create `SwingArc/Services/AnnotationStore.swift`:

```swift
import CryptoKit
import Foundation

enum AnnotationStoreError: Error, Equatable {
    case unreadableMedia
    case mediaIdentityMismatch
    case invalidPackage
    case writeFailed
}

struct AnnotationStore {
    let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory
            ?? fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("SwingArcAnnotations", isDirectory: true)
    }

    static func mediaSHA256(url: URL) throws -> String {
        guard let stream = InputStream(url: url) else {
            throw AnnotationStoreError.unreadableMedia
        }
        stream.open()
        defer { stream.close() }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw AnnotationStoreError.unreadableMedia }
            if count == 0 { break }
            hasher.update(data: Data(buffer[0..<count]))
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }

    func packageURL(mediaSHA256: String) -> URL {
        rootDirectory.appendingPathComponent(
            "\(mediaSHA256).annotation.json"
        )
    }

    func load(mediaSHA256: String) throws -> AnnotationPackage? {
        let url = packageURL(mediaSHA256: mediaSHA256)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let package = try AnnotationCoding.makeDecoder().decode(
            AnnotationPackage.self,
            from: Data(contentsOf: url)
        )
        guard package.media.sha256 == mediaSHA256 else {
            throw AnnotationStoreError.mediaIdentityMismatch
        }
        return package
    }

    func save(
        _ package: AnnotationPackage,
        expectedMediaSHA256: String? = nil
    ) throws {
        if let expectedMediaSHA256,
           expectedMediaSHA256 != package.media.sha256 {
            throw AnnotationStoreError.mediaIdentityMismatch
        }
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        do {
            let data = try AnnotationCoding.makeEncoder().encode(package)
            try data.write(
                to: packageURL(mediaSHA256: package.media.sha256),
                options: .atomic
            )
        } catch {
            throw AnnotationStoreError.writeFailed
        }
    }
}
```

- [ ] **Step 4: Run GREEN and commit**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Services/AnnotationStore.swift \
  Tests/AnnotationFixture.swift \
  Tests/AnnotationStoreSmoke.swift \
  -o /tmp/annotation-store-smoke &&
/tmp/annotation-store-smoke
```

Expected: PASS.

Commit:

```bash
git add SwingArc/Services/AnnotationStore.swift \
  Tests/AnnotationFixture.swift \
  Tests/AnnotationStoreSmoke.swift
git commit -m "feat: persist annotation packages separately"
```

---

### Task 4: Implement isolated passes, manual locks, and adjudication

**Files:**
- Create: `SwingArc/Models/AnnotationWorkspaceState.swift`
- Create: `Tests/AnnotationWorkspaceStateSmoke.swift`

**Interfaces:**
- Consumes: Task 1 models and `SwingAnalysisResult`-independent prediction snapshots.
- Produces: `AnnotationWorkspaceState`, `AnnotationWorkflowAction`,
  `AnnotationWorkflowReducer.reduce(state:action:)`,
  `visibleComparison(for:)`, `adjudicationQueue`.

- [ ] **Step 1: Write the failing workflow test**

Create `Tests/AnnotationWorkspaceStateSmoke.swift`:

```swift
import Foundation

@main
struct AnnotationWorkspaceStateSmoke {
    static func main() {
        var state = AnnotationWorkspaceState.empty
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .beginPass(annotatorID: "annotator-a")
        )
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .setStage(
                stage: "P1",
                sourceFrameIndex: 100
            )
        )
        precondition(state.activePass?.stages.first {
            $0.stage == "P1"
        }?.sourceFrameIndex == 100)
        precondition(state.activePass?.stages.first {
            $0.stage == "P1"
        }?.status == .manual)
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .updatePrediction(.init(
                stages: [
                    .init(
                        stage: "P1",
                        sourceFrameIndex: 200,
                        status: .predicted,
                        note: nil
                    )
                ],
                frameLabels: []
            ))
        )
        precondition(state.activePass?.stages.first {
            $0.stage == "P1"
        }?.sourceFrameIndex == 100)

        AnnotationWorkflowReducer.reduce(state: &state, action: .submitActivePass)
        precondition(state.submittedPasses.count == 1)

        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .beginRevision(annotatorID: "annotator-a")
        )
        precondition(state.activePass?.revision == 2)
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .setStage(stage: "P1", sourceFrameIndex: 101)
        )
        AnnotationWorkflowReducer.reduce(state: &state, action: .submitActivePass)
        precondition(state.submittedPasses.count == 1)
        precondition(state.archivedPassRevisions.count == 1)

        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .beginPass(annotatorID: "annotator-b")
        )
        precondition(state.visibleComparison(for: "P1") == nil)
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .setStage(stage: "P1", sourceFrameIndex: 104)
        )
        AnnotationWorkflowReducer.reduce(state: &state, action: .submitActivePass)
        precondition(state.adjudicationQueue.contains("P1"))

        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .adjudicate(
                stage: "P1",
                sourceFrameIndex: 102,
                adjudicatorID: "reviewer",
                note: "逐帧确认"
            )
        )
        precondition(!state.adjudicationQueue.contains("P1"))
        precondition(state.adjudications.first?.sourceFrameIndex == 102)
        precondition(state.adjudications.first?.originalSelections.count == 2)

        let queue = AnnotationFrameQueueBuilder.build(
            stageFrames: ["P1": 0, "P5": 16, "P8": 24],
            flaggedFrames: [7],
            userAddedFrames: [9],
            protectedFrames: [11],
            frameCount: 25,
            policy: .v1
        )
        precondition(
            Set([0, 4, 7, 8, 9, 11, 12, 16, 18, 20, 22, 24])
                .isSubset(of: Set(queue))
        )
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .replaceFrameQueue(queue, protectedFrames: [11])
        )
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .removeFrameFromQueue(11)
        )
        precondition(state.frameQueue.contains(11))
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .removeFrameFromQueue(9)
        )
        precondition(!state.frameQueue.contains(9))
    }
}
```

- [ ] **Step 2: Verify RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Models/AnnotationWorkspaceState.swift \
  Tests/AnnotationWorkspaceStateSmoke.swift \
  -o /tmp/annotation-workflow-smoke
```

Expected: FAIL because the workspace state and reducer do not exist.

- [ ] **Step 3: Implement the pure workflow state**

Create `SwingArc/Models/AnnotationWorkspaceState.swift` with:

```swift
import Foundation

enum AnnotationStep: String, CaseIterable {
    case setup
    case stages
    case landmarks
    case adjudication
    case export
}

struct AnnotationPredictionSnapshot: Equatable {
    var stages: [AnnotationStageSelection]
    var frameLabels: [AnnotationFrameLabel]
}

struct AnnotationWorkspaceState: Equatable {
    var step: AnnotationStep
    var currentSourceFrameIndex: Int
    var activePass: AnnotationPass?
    var submittedPasses: [AnnotationPass]
    var archivedPassRevisions: [AnnotationPass]
    var adjudications: [AnnotationAdjudication]
    var frameQueue: [Int]
    var protectedFrameIndices: Set<Int>
    var prediction: AnnotationPredictionSnapshot

    static let empty = AnnotationWorkspaceState(
        step: .setup,
        currentSourceFrameIndex: 0,
        activePass: nil,
        submittedPasses: [],
        archivedPassRevisions: [],
        adjudications: [],
        frameQueue: [],
        protectedFrameIndices: [],
        prediction: .init(stages: [], frameLabels: [])
    )

    func visibleComparison(for stage: String) -> [AnnotationStageSelection]? {
        guard activePass == nil, submittedPasses.count >= 2 else { return nil }
        return submittedPasses.compactMap {
            $0.stages.first(where: { $0.stage == stage })
        }
    }

    var adjudicationQueue: [String] {
        AnnotationPackageValidator.stageCodes.filter { stage in
            guard !adjudications.contains(where: { $0.stage == stage }),
                  submittedPasses.count >= 2 else { return false }
            let frames = submittedPasses.prefix(2).compactMap {
                $0.stages.first(where: { $0.stage == stage })?.sourceFrameIndex
            }
            return frames.count != 2 || abs(frames[0] - frames[1]) > 2
        }
    }
}

enum AnnotationWorkflowAction {
    case beginPass(annotatorID: String)
    case beginRevision(annotatorID: String)
    case updatePrediction(AnnotationPredictionSnapshot)
    case replaceFrameQueue([Int], protectedFrames: Set<Int>)
    case addFrameToQueue(Int)
    case removeFrameFromQueue(Int)
    case setStage(stage: String, sourceFrameIndex: Int?)
    case setPoint(
        landmark: String,
        sourceFrameIndex: Int,
        point: AnnotationPoint
    )
    case reviewFrame(sourceFrameIndex: Int, reviewerID: String)
    case submitActivePass
    case adjudicate(
        stage: String,
        sourceFrameIndex: Int?,
        adjudicatorID: String,
        note: String
    )
}

enum AnnotationWorkflowReducer {
    static func reduce(
        state: inout AnnotationWorkspaceState,
        action: AnnotationWorkflowAction
    ) {
        switch action {
        case let .beginPass(annotatorID):
            guard state.activePass == nil,
                  !state.submittedPasses.contains(where: {
                      $0.annotatorID == annotatorID
                  }) else { return }
            state.activePass = AnnotationPass(
                id: UUID(),
                annotatorID: annotatorID,
                revision: 1,
                submittedAt: nil,
                stages: AnnotationPackageValidator.stageCodes.map {
                    .init(
                        stage: $0,
                        sourceFrameIndex: nil,
                        status: .unresolved,
                        note: nil
                    )
                },
                frameLabels: []
            )
            state.step = .stages

        case let .updatePrediction(prediction):
            state.prediction = prediction

        case let .replaceFrameQueue(frames, protectedFrames):
            state.frameQueue = Array(Set(frames)).sorted()
            state.protectedFrameIndices = protectedFrames

        case let .addFrameToQueue(frame):
            state.frameQueue = Array(Set(state.frameQueue + [frame])).sorted()

        case let .removeFrameFromQueue(frame):
            guard !state.protectedFrameIndices.contains(frame) else { return }
            state.frameQueue.removeAll { $0 == frame }

        case let .beginRevision(annotatorID):
            guard state.activePass == nil,
                  let previous = state.submittedPasses.first(where: {
                      $0.annotatorID == annotatorID
                  }) else { return }
            state.activePass = AnnotationPass(
                id: UUID(),
                annotatorID: annotatorID,
                revision: previous.revision + 1,
                submittedAt: nil,
                stages: previous.stages,
                frameLabels: previous.frameLabels
            )
            state.step = .stages

        case let .setStage(stage, sourceFrameIndex):
            guard var pass = state.activePass,
                  let index = pass.stages.firstIndex(where: {
                      $0.stage == stage
                  }) else { return }
            pass.stages[index].sourceFrameIndex = sourceFrameIndex
            pass.stages[index].status = sourceFrameIndex == nil
                ? .unresolved
                : .manual
            state.activePass = pass

        case let .setPoint(landmark, sourceFrameIndex, point):
            guard var pass = state.activePass else { return }
            let frameIndex = pass.frameLabels.firstIndex {
                $0.sourceFrameIndex == sourceFrameIndex
            }
            if let frameIndex {
                pass.frameLabels[frameIndex].landmarks[landmark] = point
                pass.frameLabels[frameIndex].reviewed = false
                pass.frameLabels[frameIndex].reviewerID = nil
            } else {
                pass.frameLabels.append(.init(
                    sourceFrameIndex: sourceFrameIndex,
                    landmarks: [landmark: point],
                    reviewerID: nil,
                    reviewed: false
                ))
            }
            state.activePass = pass

        case let .reviewFrame(sourceFrameIndex, reviewerID):
            guard var pass = state.activePass,
                  let index = pass.frameLabels.firstIndex(where: {
                      $0.sourceFrameIndex == sourceFrameIndex
                  }) else { return }
            pass.frameLabels[index].reviewed = true
            pass.frameLabels[index].reviewerID = reviewerID
            state.activePass = pass

        case .submitActivePass:
            guard let active = state.activePass else { return }
            let submitted = AnnotationPass(
                id: active.id,
                annotatorID: active.annotatorID,
                revision: active.revision,
                submittedAt: Date(),
                stages: active.stages,
                frameLabels: active.frameLabels
            )
            if let currentIndex = state.submittedPasses.firstIndex(where: {
                $0.annotatorID == submitted.annotatorID
            }) {
                state.archivedPassRevisions.append(
                    state.submittedPasses[currentIndex]
                )
                state.submittedPasses[currentIndex] = submitted
            } else {
                state.submittedPasses.append(submitted)
            }
            state.activePass = nil
            state.step = state.submittedPasses.count >= 2
                ? .adjudication
                : .setup

        case let .adjudicate(
            stage,
            sourceFrameIndex,
            adjudicatorID,
            note
        ):
            let originals = state.submittedPasses.prefix(2).compactMap {
                $0.stages.first(where: { $0.stage == stage })
            }
            state.adjudications.removeAll { $0.stage == stage }
            state.adjudications.append(.init(
                stage: stage,
                sourceFrameIndex: sourceFrameIndex,
                adjudicatorID: adjudicatorID,
                decidedAt: Date(),
                originalSelections: originals,
                note: note
            ))
        }
    }
}

enum AnnotationFrameQueueBuilder {
    static func build(
        stageFrames: [String: Int],
        flaggedFrames: Set<Int>,
        userAddedFrames: Set<Int>,
        protectedFrames: Set<Int>,
        frameCount: Int,
        policy: AnnotationFrameQueuePolicy
    ) -> [Int] {
        guard frameCount > 0 else { return [] }
        var frames = Set(stageFrames.values)
        func appendStride(from start: Int?, through end: Int?, stride: Int) {
            guard let start, let end, start <= end else { return }
            for frame in Swift.stride(
                from: start,
                through: end,
                by: max(1, stride)
            ) {
                frames.insert(frame)
            }
        }
        appendStride(
            from: stageFrames["P1"],
            through: stageFrames["P5"],
            stride: policy.p1ThroughP5Stride
        )
        appendStride(
            from: stageFrames["P5"],
            through: stageFrames["P8"],
            stride: policy.p5ThroughP8Stride
        )
        frames.formUnion(flaggedFrames)
        frames.formUnion(userAddedFrames)
        frames.formUnion(protectedFrames)
        return frames.filter { (0..<frameCount).contains($0) }.sorted()
    }
}
```

- [ ] **Step 4: Run GREEN and commit**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Services/AnnotationPackageValidator.swift \
  SwingArc/Models/AnnotationWorkspaceState.swift \
  Tests/AnnotationWorkspaceStateSmoke.swift \
  -o /tmp/annotation-workflow-smoke &&
/tmp/annotation-workflow-smoke
```

Expected: PASS.

Commit:

```bash
git add SwingArc/Models/AnnotationWorkspaceState.swift \
  Tests/AnnotationWorkspaceStateSmoke.swift
git commit -m "feat: add isolated annotation workflow"
```

---

### Task 5: Freeze and export verified annotation packages

**Files:**
- Create: `SwingArc/Services/AnnotationExportService.swift`
- Create: `Tests/AnnotationExportSmoke.swift`
- Create: `Tools/PrecisionDataset/ValidateAnnotationExport.swift`

**Interfaces:**
- Consumes: `AnnotationPackage`, validation errors, destination directory.
- Produces: `AnnotationExportService.freezeAndExport`, deterministic JSON,
  `AnnotationExportReceipt`, and a Mac command-line validator.

- [ ] **Step 1: Write the failing export test**

Create `Tests/AnnotationExportSmoke.swift`:

```swift
import Foundation

@main
struct AnnotationExportSmoke {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var package = AnnotationFixture.completeReviewedPackage()
        let receipt = try AnnotationExportService.freezeAndExport(
            package: &package,
            destinationDirectory: directory,
            now: Date(timeIntervalSince1970: 100)
        )
        precondition(package.frozenAt == Date(timeIntervalSince1970: 100))
        precondition(receipt.sha256.count == 64)
        precondition(receipt.url.pathExtension == "json")
        precondition(receipt.includesRawVideo == false)
        precondition(
            try AnnotationCoding.makeDecoder().decode(
                AnnotationPackage.self,
                from: Data(contentsOf: receipt.url)
            ) == package
        )

        var unreviewed = AnnotationFixture.completeReviewedPackage()
        unreviewed.passes[0].frameLabels[0].reviewed = false
        do {
            _ = try AnnotationExportService.freezeAndExport(
                package: &unreviewed,
                destinationDirectory: directory,
                now: Date()
            )
            preconditionFailure("unreviewed training data must not export")
        } catch AnnotationExportError.validationFailed {
        }
    }
}
```

The fixture must contain two different annotator IDs, ordered P1–P8,
five golf landmarks at one reviewed frame, training authorization, and no
unresolved adjudication.

- [ ] **Step 2: Verify RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Services/AnnotationPackageValidator.swift \
  SwingArc/Services/AnnotationExportService.swift \
  Tests/AnnotationFixture.swift \
  Tests/AnnotationExportSmoke.swift \
  -o /tmp/annotation-export-smoke
```

Expected: FAIL because `AnnotationExportService` does not exist.

- [ ] **Step 3: Implement freeze and deterministic export**

Create `SwingArc/Services/AnnotationExportService.swift`:

```swift
import CryptoKit
import Foundation

enum AnnotationExportError: Error, Equatable {
    case validationFailed([AnnotationValidationError])
    case writeFailed
}

struct AnnotationExportReceipt: Equatable {
    let url: URL
    let sha256: String
    let includesRawVideo: Bool
}

enum AnnotationExportService {
    static func freezeAndExport(
        package: inout AnnotationPackage,
        destinationDirectory: URL,
        now: Date
    ) throws -> AnnotationExportReceipt {
        var candidate = package
        candidate.frozenAt = now
        let errors = AnnotationPackageValidator.validate(candidate)
        guard errors.isEmpty else {
            throw AnnotationExportError.validationFailed(errors)
        }

        guard let data = try? AnnotationCoding.makeEncoder().encode(candidate) else {
            throw AnnotationExportError.writeFailed
        }
        do {
            try FileManager.default.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
            let url = destinationDirectory.appendingPathComponent(
                "\(candidate.metadata.clipID)-annotation-v\(candidate.schemaVersion).json"
            )
            try data.write(to: url, options: .atomic)
            let digest = SHA256.hash(data: data).map {
                String(format: "%02x", $0)
            }.joined()
            package = candidate
            return .init(
                url: url,
                sha256: digest,
                includesRawVideo: false
            )
        } catch {
            throw AnnotationExportError.writeFailed
        }
    }
}
```

- [ ] **Step 4: Implement the Mac export validator**

Create `Tools/PrecisionDataset/ValidateAnnotationExport.swift`:

```swift
import Foundation

@main
struct ValidateAnnotationExport {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: validate-annotation-export <json-path>\n", stderr)
            exit(EXIT_FAILURE)
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(
            AnnotationPackage.self,
            from: Data(contentsOf: url)
        )
        let errors = AnnotationPackageValidator.validate(package)
        guard package.frozenAt != nil, errors.isEmpty else {
            for error in errors {
                fputs("\(error)\n", stderr)
            }
            exit(EXIT_FAILURE)
        }
        print(
            "VALID \(package.metadata.clipID) " +
            "\(package.media.frameCount) frames " +
            "\(package.passes.count) passes"
        )
    }
}
```

- [ ] **Step 5: Run GREEN, validate the exported fixture, and commit**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Services/AnnotationPackageValidator.swift \
  SwingArc/Services/AnnotationExportService.swift \
  Tests/AnnotationFixture.swift \
  Tests/AnnotationExportSmoke.swift \
  -o /tmp/annotation-export-smoke &&
/tmp/annotation-export-smoke
```

Expected: PASS.

Compile the validator:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Services/AnnotationPackageValidator.swift \
  Tools/PrecisionDataset/ValidateAnnotationExport.swift \
  -o /tmp/validate-annotation-export
```

Expected: compilation succeeds.

Commit:

```bash
git add SwingArc/Services/AnnotationExportService.swift \
  Tests/AnnotationExportSmoke.swift \
  Tools/PrecisionDataset/ValidateAnnotationExport.swift
git commit -m "feat: export frozen annotation packages"
```

---

### Task 6: Build the frame canvas and phone-first annotation workspace

**Files:**
- Create: `SwingArc/Views/AnnotationFrameCanvas.swift`
- Create: `SwingArc/Views/AnnotationWorkspaceView.swift`
- Create: `Tests/AnnotationPresentationSmoke.swift`

**Interfaces:**
- Consumes: `AnnotationWorkspaceState`, `ExactVideoFrame`,
  `AnnotationWorkflowAction`, stage codes, landmark names.
- Produces: a full-screen phone/iPad annotation UI with exact stepping,
  zoom, magnifier, stage selection, point editing, visibility controls,
  submission, adjudication, and export callback.

- [ ] **Step 1: Write the failing presentation policy test**

Create `Tests/AnnotationPresentationSmoke.swift`:

```swift
import Foundation

@main
struct AnnotationPresentationSmoke {
    static func main() {
        precondition(
            AnnotationStepPresentation.title(for: .setup) == "任务资料"
        )
        precondition(
            AnnotationStepPresentation.title(for: .stages) == "P1–P8"
        )
        precondition(
            AnnotationStepPresentation.title(for: .landmarks) == "关键点"
        )
        precondition(
            AnnotationStepPresentation.title(for: .adjudication) == "分歧裁定"
        )
        precondition(
            AnnotationStepPresentation.title(for: .export) == "冻结与导出"
        )
        precondition(
            AnnotationLandmarkCatalog.golf
                == ["grip", "shaftStart", "shaftEnd", "clubhead", "ball"]
        )
        precondition(
            AnnotationFrameStepPolicy.target(
                current: 100,
                delta: -5,
                frameCount: 1526
            ) == 95
        )
        precondition(
            AnnotationFrameStepPolicy.target(
                current: 1525,
                delta: 5,
                frameCount: 1526
            ) == 1525
        )
    }
}
```

- [ ] **Step 2: Verify RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Models/AnnotationWorkspaceState.swift \
  SwingArc/Services/AnnotationPackageValidator.swift \
  Tests/AnnotationPresentationSmoke.swift \
  -o /tmp/annotation-presentation-smoke
```

Expected: FAIL specifically because the three pure presentation policies do
not exist in `AnnotationWorkspaceState.swift`.

- [ ] **Step 3: Add pure presentation and stepping policies**

Add to `AnnotationWorkspaceState.swift`:

```swift
enum AnnotationStepPresentation {
    static func title(for step: AnnotationStep) -> String {
        switch step {
        case .setup: return "任务资料"
        case .stages: return "P1–P8"
        case .landmarks: return "关键点"
        case .adjudication: return "分歧裁定"
        case .export: return "冻结与导出"
        }
    }
}

enum AnnotationLandmarkCatalog {
    static let body = [
        "head", "leftShoulder", "rightShoulder",
        "leftElbow", "rightElbow",
        "leftWrist", "rightWrist", "handCenter",
        "leftHip", "rightHip",
        "leftKnee", "rightKnee",
        "leftAnkle", "rightAnkle"
    ]
    static let golf = [
        "grip", "shaftStart", "shaftEnd", "clubhead", "ball"
    ]
}

enum AnnotationFrameStepPolicy {
    static func target(
        current: Int,
        delta: Int,
        frameCount: Int
    ) -> Int {
        max(0, min(max(0, frameCount - 1), current + delta))
    }
}
```

- [ ] **Step 4: Add the background frame session**

Append to `ExactVideoFrameProvider.swift`:

```swift
struct ExactVideoFrameSessionMetadata: Sendable {
    let frameCount: Int
    let timelineSHA256: String
    let orientedWidth: Int
    let orientedHeight: Int
}

actor ExactVideoFrameSession {
    private var provider: ExactVideoFrameProvider?

    func open(url: URL) throws -> ExactVideoFrameSessionMetadata {
        let provider = try ExactVideoFrameProvider.load(url: url)
        self.provider = provider
        return .init(
            frameCount: provider.frameCount,
            timelineSHA256: provider.timelineSHA256,
            orientedWidth: Int(provider.orientedSize.width.rounded()),
            orientedHeight: Int(provider.orientedSize.height.rounded())
        )
    }

    func frame(at sourceFrameIndex: Int) throws -> ExactVideoFrame {
        guard let provider else {
            throw ExactVideoFrameProviderError.timelineUnavailable
        }
        return try provider.frame(at: sourceFrameIndex)
    }
}
```

This actor is the only owner that calls the provider after opening. Add to
`AnnotationWorkspaceView.swift`:

```swift
@MainActor
final class AnnotationFrameController: ObservableObject {
    @Published private(set) var frameCount = 0
    @Published private(set) var timelineSHA256 = ""
    @Published private(set) var orientedWidth = 0
    @Published private(set) var orientedHeight = 0
    @Published private(set) var currentFrame: ExactVideoFrame?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let session = ExactVideoFrameSession()
    private var requestToken = 0

    func open(url: URL) async {
        requestToken += 1
        let token = requestToken
        isLoading = true
        defer { if token == requestToken { isLoading = false } }
        do {
            let metadata = try await session.open(url: url)
            let first = try await session.frame(at: 0)
            guard token == requestToken else { return }
            frameCount = metadata.frameCount
            timelineSHA256 = metadata.timelineSHA256
            orientedWidth = metadata.orientedWidth
            orientedHeight = metadata.orientedHeight
            currentFrame = first
        } catch {
            guard token == requestToken else { return }
            errorMessage = "无法建立原片逐帧时间线：\(error.localizedDescription)"
        }
    }

    func show(index: Int) async -> Bool {
        requestToken += 1
        let token = requestToken
        isLoading = true
        defer { if token == requestToken { isLoading = false } }
        do {
            let frame = try await session.frame(at: index)
            guard token == requestToken else { return false }
            currentFrame = frame
            return true
        } catch {
            guard token == requestToken else { return false }
            errorMessage = "无法读取源帧 \(index)"
            return false
        }
    }
}
```

- [ ] **Step 5: Implement the zoomable frame canvas**

Create `SwingArc/Views/AnnotationFrameCanvas.swift` with:

```swift
import SwiftUI

struct AnnotationFrameCanvas: View {
    let image: CGImage?
    let points: [String: AnnotationPoint]
    let selectedLandmark: String?
    let onMovePoint: (String, AnnotationPoint) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                }
                ForEach(points.keys.sorted(), id: \.self) { landmark in
                    if let point = points[landmark],
                       point.visibility == .visible,
                       let pointX = point.x,
                       let pointY = point.y {
                        Circle()
                            .fill(landmark == selectedLandmark
                                ? AnalysisTheme.proTourSignal
                                : Color.white)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.black, lineWidth: 2))
                            .position(
                                x: CGFloat(pointX) * geometry.size.width,
                                y: CGFloat(pointY) * geometry.size.height
                            )
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        var moved = point
                                        moved.x = min(1, max(0,
                                            value.location.x / geometry.size.width
                                        ))
                                        moved.y = min(1, max(0,
                                            value.location.y / geometry.size.height
                                        ))
                                        moved.source = .manual
                                        onMovePoint(landmark, moved)
                                    }
                            )
                    }
                }
            }
            .clipped()
            .gesture(
                MagnificationGesture()
                    .onChanged { scale = min(8, max(1, lastScale * $0)) }
                    .onEnded { _ in lastScale = scale }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged {
                        offset = CGSize(
                            width: lastOffset.width + $0.translation.width,
                            height: lastOffset.height + $0.translation.height
                        )
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .accessibilityLabel("标注画面")
        }
    }
}
```

Add a 2× magnifier overlay while a point drag is active, reusing the geometry
and visual treatment in `DrawingOverlay`. Map normalized points through the
displayed image’s aspect-fit rectangle before applying zoom/pan, so portrait
and landscape media do not shift labels. Make canvas panning a two-finger
gesture so it cannot steal a one-finger landmark drag.

- [ ] **Step 6: Implement the full-screen workspace**

Create `SwingArc/Views/AnnotationWorkspaceView.swift`:

```swift
import SwiftUI

struct AnnotationWorkspaceView: View {
    let videoURL: URL
    let prediction: AnnotationPredictionSnapshot
    let onClose: () -> Void
    let onExport: (URL) -> Void

    @State private var state = AnnotationWorkspaceState.empty
    @StateObject private var frameController = AnnotationFrameController()
    @State private var selectedStage = "P1"
    @State private var selectedLandmark = "clubhead"
    @State private var visibility: AnnotationVisibility = .visible

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AnnotationFrameCanvas(
                    image: frameController.currentFrame?.image,
                    points: activePoints,
                    selectedLandmark: selectedLandmark,
                    onMovePoint: setPoint
                )
                .frame(maxHeight: .infinity)

                frameControls
                stepControls
                editorControls
            }
            .background(Color.black.ignoresSafeArea())
            .foregroundStyle(.white)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", action: onClose)
                }
                ToolbarItem(placement: .principal) {
                    Text(AnnotationStepPresentation.title(for: state.step))
                        .font(.headline)
                }
            }
            .task {
                state.prediction = prediction
                await frameController.open(url: videoURL)
            }
            .alert(
                "标注无法继续",
                isPresented: Binding(
                    get: { frameController.errorMessage != nil },
                    set: { if !$0 { frameController.errorMessage = nil } }
                )
            ) {
                Button("好") { frameController.errorMessage = nil }
            } message: {
                Text(frameController.errorMessage ?? "")
            }
        }
    }

    private var activePoints: [String: AnnotationPoint] {
        state.activePass?.frameLabels.first {
            $0.sourceFrameIndex == state.currentSourceFrameIndex
        }?.landmarks ?? prediction.frameLabels.first {
            $0.sourceFrameIndex == state.currentSourceFrameIndex
        }?.landmarks ?? [:]
    }

    private var frameControls: some View {
        HStack {
            Text("帧 \(state.currentSourceFrameIndex + 1) / \(frameController.frameCount)")
                .monospacedDigit()
            Spacer()
            Text(frameController.currentFrame?.presentationTime.seconds
                .formatted(.number.precision(.fractionLength(3))) ?? "0.000")
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .frame(height: 34)
    }

    private var stepControls: some View {
        HStack(spacing: 14) {
            stepButton(-5, label: "−5")
            stepButton(-1, label: "−1")
            stepButton(1, label: "+1")
            stepButton(5, label: "+5")
        }
        .frame(height: 52)
    }

    @ViewBuilder
    private var editorControls: some View {
        switch state.step {
        case .stages:
            StageAnnotationControls(
                selectedStage: $selectedStage,
                onSet: setCurrentStage,
                onUnresolved: { setStage(nil) }
            )
        case .landmarks:
            LandmarkAnnotationControls(
                selectedLandmark: $selectedLandmark,
                visibility: $visibility,
                bodyLandmarks: AnnotationLandmarkCatalog.body,
                golfLandmarks: AnnotationLandmarkCatalog.golf
            )
        case .setup, .adjudication, .export:
            AnnotationStepControls(
                state: $state,
                videoURL: videoURL,
                onExport: onExport
            )
        }
    }

    private func stepButton(_ delta: Int, label: String) -> some View {
        Button(label) {
            Task { await loadFrame(delta: delta) }
        }
            .buttonStyle(.bordered)
            .frame(minWidth: 58, minHeight: 44)
    }

    @MainActor
    private func loadFrame(delta: Int) async {
        let target = AnnotationFrameStepPolicy.target(
            current: state.currentSourceFrameIndex,
            delta: delta,
            frameCount: frameController.frameCount
        )
        if await frameController.show(index: target) {
            state.currentSourceFrameIndex = target
        }
    }

    private func setCurrentStage() {
        setStage(state.currentSourceFrameIndex)
    }

    private func setStage(_ sourceFrameIndex: Int?) {
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .setStage(
                stage: selectedStage,
                sourceFrameIndex: sourceFrameIndex
            )
        )
    }

    private func setPoint(_ landmark: String, _ point: AnnotationPoint) {
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .setPoint(
                landmark: landmark,
                sourceFrameIndex: state.currentSourceFrameIndex,
                point: point
            )
        )
    }
}
```

Implement the three control views in the same file with this exact contract:

| Control | Visible choices | Reducer/service action |
|---|---|---|
| `StageAnnotationControls` | P1…P8, “设为当前帧”, “无法确定” | `.setStage(stage:index)` or `.setStage(stage:nil)` |
| `LandmarkAnnotationControls` | “人体/球杆”, every catalog landmark, visible/occluded/out-of-frame/unresolved, “复核本帧” | `.setPoint` and `.reviewFrame` |
| `FrameQueueControls` | queue position, “添加当前帧”, “移除当前帧” | `.addFrameToQueue`; `.removeFrameFromQueue` is disabled for any frame referenced by the other pass or an adjudication |
| `AnnotationStepControls.setup` | annotator-a, annotator-b, “开始”, submitted pass “创建修订” | `.beginPass` or `.beginRevision` |
| `AnnotationStepControls.adjudication` | both immutable original frames, ±1/±5, “采用当前帧”, “仍无法确定” | `.adjudicate` with both originals |
| `AnnotationStepControls.export` | authorization/split summary, validation errors, “冻结并导出” | `AnnotationExportService.freezeAndExport` |

Every primary control has at least a 44×44 point hit target and an accessibility
label equal to its visible title. On compact width, controls occupy a bottom
sheet no taller than 42% of the screen; on regular width, use a 360-point
trailing inspector and give the video the remaining width. The saved data is
identical on iPhone and iPad.

Create the package after `frameController.open` returns, using the video
SHA-256, timeline SHA-256, oriented dimensions, and source frame count. Before
creating it, call `AnnotationStore.load(mediaSHA256:)`; restore the existing
package only when both media and timeline identities match. Debounce every
reducer mutation to an atomic save within 250 ms, and force a save when
`scenePhase` becomes inactive or background. Reopening after a forced quit must
restore the active draft, current revision, frame queue, reviewed flags, and
manual locks. Before each save, mirror `state.activePass`,
`state.currentSourceFrameIndex`, `state.frameQueue`, `state.submittedPasses`,
`state.archivedPassRevisions`, and `state.adjudications` into the corresponding
package fields; on restore, rebuild state from those fields.

- [ ] **Step 7: Run policy test and build the app**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Services/AnnotationPackageValidator.swift \
  SwingArc/Models/AnnotationWorkspaceState.swift \
  Tests/AnnotationPresentationSmoke.swift \
  -o /tmp/annotation-presentation-smoke &&
/tmp/annotation-presentation-smoke
```

Expected: PASS.

Do not run the Xcode build until Task 7 registers the new production files.

- [ ] **Step 8: Commit**

```bash
git add SwingArc/Views/AnnotationFrameCanvas.swift \
  SwingArc/Views/AnnotationWorkspaceView.swift \
  SwingArc/Models/AnnotationWorkspaceState.swift \
  SwingArc/Services/ExactVideoFrameProvider.swift \
  Tests/AnnotationPresentationSmoke.swift
git commit -m "feat: build annotation workspace"
```

---

### Task 7: Integrate pre-annotations and the full-screen entry

**Files:**
- Modify: `SwingArc/Views/ContentView.swift`
- Modify: `SwingArc/Views/AnalysisWorkspaceView.swift`
- Modify: `SwingArc/Views/WorkspaceComponents.swift`
- Modify: `SwingArcProject.xcodeproj/project.pbxproj`
- Create: `SwingArc/Services/AnnotationPredictionAdapter.swift`
- Create: `Tests/AnnotationIntegrationSmoke.swift`
- Create: `Tests/AnnotationProjectIsolationSmoke.swift`

**Interfaces:**
- Consumes: current project video URL, `playbackManager.analysisOutput`,
  manual stage markers, new annotation workspace.
- Produces: a visible “标注” entry and an `AnnotationPredictionSnapshot`
  that never marks AI output as manual or reviewed.

- [ ] **Step 1: Write the failing prediction adapter test**

Create `Tests/AnnotationIntegrationSmoke.swift`:

```swift
import Foundation

@main
struct AnnotationIntegrationSmoke {
    static func main() {
        let prediction = AnnotationPredictionAdapter.snapshot(
            detections: [
                .init(
                    stage: .address,
                    time: 1,
                    confidence: 0.9,
                    status: .confirmed,
                    hasClubEvidence: false,
                    hasBallEvidence: false,
                    hasBallChangeEvidence: false,
                    sourceFrameIndex: 100
                ),
                .init(
                    stage: .takeaway,
                    time: 2,
                    confidence: 0.8,
                    status: .confirmed,
                    hasClubEvidence: false,
                    hasBallEvidence: false,
                    hasBallChangeEvidence: false,
                    sourceFrameIndex: 200
                )
            ],
            frames: []
        )
        precondition(
            prediction.stages.first { $0.stage == "P1" }?.status == .predicted
        )
        precondition(
            prediction.stages.first { $0.stage == "P2" }?.status == .unresolved,
            "P2 cannot be confirmed without shaft evidence"
        )
        precondition(
            prediction.stages.first { $0.stage == "P2" }?
                .suggestedSourceFrameIndex == 200
        )
    }
}
```

- [ ] **Step 2: Verify RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Models/AnnotationWorkspaceState.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/AnnotationPredictionAdapter.swift \
  Tests/AnnotationIntegrationSmoke.swift \
  -o /tmp/annotation-integration-smoke
```

Expected: FAIL specifically because `AnnotationPredictionAdapter` does not
exist.

- [ ] **Step 3: Implement the prediction adapter**

Create `SwingArc/Services/AnnotationPredictionAdapter.swift`:

```swift
import Foundation

enum AnnotationPredictionAdapter {
    static func snapshot(
        detections: [SwingStageDetection],
        frames: [SwingFrameObservation]
    ) -> AnnotationPredictionSnapshot {
        let stageMap: [(String, SwingStage)] = [
            ("P1", .address),
            ("P2", .takeaway),
            ("P3", .leadArmParallelBackswing),
            ("P4", .top),
            ("P5", .leadArmParallelDownswing),
            ("P6", .shaftParallelDownswing),
            ("P7", .impact),
            ("P8", .followThrough)
        ]
        let stageSelections = stageMap.map { code, stage in
            guard let detection = detections.first(where: {
                $0.stage == stage
            }) else {
                return AnnotationStageSelection(
                    stage: code,
                    sourceFrameIndex: nil,
                    status: .unresolved,
                    note: nil
                )
            }
            let needsClub = ["P2", "P6", "P8"].contains(code)
            let needsImpact = code == "P7"
            let isResolvedDetection = detection.status != .unresolved
                && detection.sourceFrameIndex != nil
            let evidenceSatisfied = isResolvedDetection
                && (!needsClub || detection.evidence.sources.contains(.shaft))
                && (!needsImpact
                    || detection.hasBallEvidence
                    || detection.hasBallChangeEvidence)
            return .init(
                stage: code,
                sourceFrameIndex: evidenceSatisfied
                    ? detection.sourceFrameIndex
                    : nil,
                suggestedSourceFrameIndex: detection.sourceFrameIndex,
                suggestedRangeStart: detection.sourceFrameIndex.map {
                    max(0, $0 - 2)
                },
                suggestedRangeEnd: detection.sourceFrameIndex.map { $0 + 2 },
                status: evidenceSatisfied
                    ? .predicted
                    : .unresolved,
                note: evidenceSatisfied ? nil : "缺少球杆或球位证据"
            )
        }
        let frameLabels = frames.map { frame in
            AnnotationFrameLabel(
                sourceFrameIndex: frame.sourceFrameIndex,
                landmarks: Dictionary(uniqueKeysWithValues:
                    frame.landmarks.compactMap { landmark, tracked in
                        let visibility: AnnotationVisibility
                        switch tracked.state {
                        case .detected: visibility = .visible
                        case .occluded: visibility = .occluded
                        case .outOfFrame: visibility = .outOfFrame
                        case .estimated, .missing: visibility = .unresolved
                        }
                        guard tracked.point != nil || visibility != .unresolved
                        else { return nil }
                        return (
                            landmark.rawValue,
                            AnnotationPoint(
                                x: tracked.point.map { Double($0.x) },
                                y: tracked.point.map { Double($0.y) },
                                visibility: visibility,
                                source: .predicted,
                                confidence: tracked.confidence
                            )
                        )
                    }
                ),
                reviewerID: nil,
                reviewed: false
            )
        }
        return .init(stages: stageSelections, frameLabels: frameLabels)
    }
}
```

- [ ] **Step 4: Add the entry callback**

Add `onAnnotate: () -> Void` to `AnalysisWorkspaceView` and
`WorkspaceHeaderView`. Place a “标注” button beside export on regular layout
and in the mobile replay action row. The button pauses playback before invoking
the callback.

In `ContentView` add:

```swift
@State private var showAnnotationWorkspace = false
```

Pass:

```swift
onAnnotate: {
    playbackManager.pause()
    showAnnotationWorkspace = true
}
```

Present:

```swift
.fullScreenCover(isPresented: $showAnnotationWorkspace) {
    if let videoURL = currentProjectURL {
        AnnotationWorkspaceView(
            videoURL: videoURL,
            prediction: AnnotationPredictionAdapter.snapshot(
                detections: playbackManager.analysisOutput?.result.detections ?? [],
                frames: playbackManager.analysisOutput?.observationFrames ?? []
            ),
            onClose: { showAnnotationWorkspace = false },
            onExport: { url in
                sharePayload = SharePayload(url: url)
            }
        )
    }
}
```

- [ ] **Step 5: Register every new production source in the Xcode project**

Add file references under the existing `Models`, `Services`, and `Views`
groups and add source build-phase entries for:

```text
AnnotationModels.swift
AnnotationWorkspaceState.swift
ExactVideoFrameProvider.swift
AnnotationPackageValidator.swift
AnnotationStore.swift
AnnotationExportService.swift
AnnotationPredictionAdapter.swift
AnnotationFrameCanvas.swift
AnnotationWorkspaceView.swift
```

Use these exact 24-character ID pairs (`build ID / file reference ID`):

```text
A90000000000000000000001 / A90000000000000000000002 AnnotationModels.swift
A90000000000000000000003 / A90000000000000000000004 AnnotationWorkspaceState.swift
A90000000000000000000005 / A90000000000000000000006 ExactVideoFrameProvider.swift
A90000000000000000000007 / A90000000000000000000008 AnnotationPackageValidator.swift
A90000000000000000000009 / A9000000000000000000000A AnnotationStore.swift
A9000000000000000000000B / A9000000000000000000000C AnnotationExportService.swift
A9000000000000000000000D / A9000000000000000000000E AnnotationFrameCanvas.swift
A9000000000000000000000F / A90000000000000000000010 AnnotationWorkspaceView.swift
A90000000000000000000011 / A90000000000000000000012 AnnotationPredictionAdapter.swift
```

Before editing, run `rg 'A900000000000000000000' SwingArcProject.xcodeproj/project.pbxproj`;
expected: no matches. After editing, verify each file appears exactly once in
`PBXFileReference`, its owning group, `PBXBuildFile`, and
`PBXSourcesBuildPhase`.

- [ ] **Step 6: Run adapter test and simulator build**

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/SwingMetricModels.swift \
  SwingArc/Models/SwingObservationModels.swift \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Models/AnnotationWorkspaceState.swift \
  SwingArc/Services/SwingStageDetector.swift \
  SwingArc/Services/AnnotationPredictionAdapter.swift \
  Tests/AnnotationIntegrationSmoke.swift \
  -o /tmp/annotation-integration-smoke &&
/tmp/annotation-integration-smoke
```

Expected: PASS.

Then run:

```bash
set -o pipefail
xcodebuild \
  -project SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/SwingArcAnnotationSimulator \
  build 2>&1 | tee /tmp/swingarc-annotation-simulator.log
```

Expected: `** BUILD SUCCEEDED **` for arm64 and x86_64.

- [ ] **Step 7: Verify project isolation**

Create `Tests/AnnotationProjectIsolationSmoke.swift`:

```swift
import Foundation
import SwiftUI

@main
struct AnnotationProjectIsolationSmoke {
    static func main() throws {
        let suiteName = "annotation-isolation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let videoURL = root.appendingPathComponent("same-video.mov")

        let project = LocalAnalysisProject(
            drawings: [
                DrawingElement(
                    tool: .line,
                    points: [.init(x: 0.1, y: 0.2), .init(x: 0.8, y: 0.9)],
                    color: .green,
                    lineWidth: 3,
                    isKeyframeSpecific: true,
                    videoTime: 1
                )
            ],
            keyframes: [
                KeyframeMarker(
                    time: 1,
                    stage: .impact,
                    source: .manual
                )
            ],
            isKeyframeMode: true,
            showPoseSkeleton: false,
            showHeadStability: false,
            showSpineAngle: false,
            showGrid: false
        )
        precondition(LocalProjectStore.save(
            project,
            for: videoURL,
            defaults: defaults
        ))
        let before = defaults.persistentDomain(forName: suiteName)! as NSDictionary

        let package = AnnotationFixture.package()
        let annotationStore = AnnotationStore(
            rootDirectory: root.appendingPathComponent(
                "SwingArcAnnotations",
                isDirectory: true
            )
        )
        try annotationStore.save(package)

        let after = defaults.persistentDomain(forName: suiteName)! as NSDictionary
        precondition(before.isEqual(to: after as! [AnyHashable: Any]))
        precondition(LocalProjectStore.load(
            for: videoURL,
            defaults: defaults
        ) == project)
        precondition(try annotationStore.load(
            mediaSHA256: package.media.sha256
        ) == package)
        precondition(
            annotationStore.packageURL(mediaSHA256: package.media.sha256)
                .path.contains("SwingArcAnnotations")
        )
    }
}
```

Run:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Models/AnnotationModels.swift \
  SwingArc/Services/LocalProjectStore.swift \
  SwingArc/Services/AnnotationStore.swift \
  Tests/AnnotationFixture.swift \
  Tests/AnnotationProjectIsolationSmoke.swift \
  -o /tmp/annotation-project-isolation &&
/tmp/annotation-project-isolation
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add SwingArc/Views/ContentView.swift \
  SwingArc/Views/AnalysisWorkspaceView.swift \
  SwingArc/Views/WorkspaceComponents.swift \
  SwingArc/Models/AnnotationWorkspaceState.swift \
  SwingArc/Services/AnnotationPredictionAdapter.swift \
  SwingArcProject.xcodeproj/project.pbxproj \
  Tests/AnnotationIntegrationSmoke.swift \
  Tests/AnnotationProjectIsolationSmoke.swift
git commit -m "feat: integrate in-app annotation mode"
```

---

### Task 8: Real-original end-to-end verification, device install, and handoff

**Files:**
- Modify: `docs/validation/precision-swing-baseline-2026-07-23.md`
- Create: `docs/validation/in-app-annotation-verification-2026-07-23.md`

**Interfaces:**
- Consumes: completed annotation feature and
  `/Users/liangbo/Desktop/test/original-240fps/IMG_4692.MOV`.
- Produces: signed device build, installed app, launch proof, exported fixture,
  Mac validation output, and documented remaining limitations.

- [ ] **Step 1: Run all focused smoke tests**

Run every new smoke executable plus:

```bash
xcrun swiftc -parse-as-library \
  SwingArc/Services/SwingInputQualityEvaluator.swift \
  Tests/SwingInputQualityEvaluatorSmoke.swift \
  -o /tmp/swing-input-quality &&
/tmp/swing-input-quality
```

Run:

```bash
git diff --check
```

Expected: all tests pass and no whitespace errors.

- [ ] **Step 2: Run the original-video frame identity check**

Run:

```bash
/tmp/annotation-frame-timeline \
  /Users/liangbo/Desktop/test/original-240fps/IMG_4692.MOV
```

Expected:

- 1526 decoded frames;
- exact first and last source-frame identities;
- no `decodedNeighborFrame`;
- stable timeline SHA-256 across two runs.

- [ ] **Step 3: Exercise the full annotation loop in the simulator**

Import `IMG_4692.MOV`, open “标注”, and verify:

1. Frame 1/1526 opens.
2. `+1`, `−1`, `+5`, `−5` move by exact source-frame ordinals.
3. Annotator A submits P1–P8.
4. Annotator B cannot see A before submission.
5. A deliberate four-frame disagreement creates one adjudication item.
6. Each annotator reviews at least one queue frame containing grip,
   shaftStart, shaftEnd, clubhead, and ball; a clubhead point can be zoomed,
   moved, marked visible, and reviewed.
7. Force quit with an active revision, relaunch, and verify the draft, current
   source frame, queue, reviewed flags, and manual locks restore.
8. Test compact iPhone and regular-width iPad layouts; neither allows point
   dragging to start video playback.
9. Export creates JSON only.
10. `/tmp/validate-annotation-export` prints `VALID`.
11. Closing the full-screen page returns to the unchanged analysis project.

Capture screenshots of the stage screen, landmark screen, adjudication screen,
and successful export receipt for the verification document.

- [ ] **Step 4: Build a signed Release app**

Run:

```bash
set -o pipefail
xcodebuild \
  -project SwingArcProject.xcodeproj \
  -scheme SwingArcProject \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -derivedDataPath /tmp/SwingArcAnnotationDevice \
  build 2>&1 | tee /tmp/swingarc-annotation-device.log
```

Expected: `** BUILD SUCCEEDED **`.

Verify:

```bash
codesign --verify --deep --strict --verbose=2 \
  /tmp/SwingArcAnnotationDevice/Build/Products/Release-iphoneos/SwingArcProject.app
```

Expected: valid on disk and satisfies its Designated Requirement.

- [ ] **Step 5: Install and launch on the wireless iPhone 16 Pro**

Require the phone to be unlocked, on the same Wi-Fi, and listed as available:

```bash
xcrun devicectl list devices
```

Install:

```bash
xcrun devicectl device install app \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 \
  /tmp/SwingArcAnnotationDevice/Build/Products/Release-iphoneos/SwingArcProject.app
```

Launch:

```bash
xcrun devicectl device process launch \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 \
  --terminate-existing \
  com.liangbo.swingarc
```

Verify the process:

```bash
xcrun devicectl device info processes \
  --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 |
rg 'SwingArcProject'
```

Expected: one running `SwingArcProject` process.

- [ ] **Step 6: Document verified behavior and explicit limitations**

Create `docs/validation/in-app-annotation-verification-2026-07-23.md` with:

- commit hash;
- device and iOS version;
- exact original file name, frame count, timeline digest;
- two-pass and adjudication result;
- keypoint review result;
- export file hash and validator output;
- simulator and device build results;
- screenshots;
- explicit statement that the feature creates ground truth but does not yet
  contain a trained `GolfKeypoints` model;
- explicit next project: high-resolution golf-object model and continuous
  trajectory tracking.

Update the baseline document so “App 内正式标注模式” changes from required work
to verified infrastructure only after the real-device loop succeeds.

- [ ] **Step 7: Commit and push**

```bash
git add docs/validation/in-app-annotation-verification-2026-07-23.md \
  docs/validation/precision-swing-baseline-2026-07-23.md
git commit -m "docs: verify in-app annotation workflow"
git push origin codex/precision-swing-analysis
```

Expected: push succeeds and the branch is clean.

---

## Plan Self-Review

- **Spec coverage:** Tasks 1–8 cover data contract, exact VFR frames, isolated
  storage, double-pass isolation, immutable submitted revisions,
  two-frame consensus/adjudication, auditable 4-frame/2-frame queues,
  visibility, manual locks, background recovery, export gates, phone/iPad UI,
  normal-project isolation, simulator/device verification, and handoff to the
  club model project.
- **Scope:** Model training and P1–P8 fusion changes are intentionally excluded;
  they begin only after this annotation loop is verified.
- **Type consistency:** `AnnotationPackage`, `AnnotationPass`,
  `AnnotationPredictionSnapshot`, `ExactVideoFrameProvider`, and the reducer
  signatures are defined before their consumers.
- **No raw media export:** The only export receipt sets
  `includesRawVideo: false`.
- **No AI-as-truth:** Prediction adapter always emits `.predicted` or
  `.unresolved`; P2/P6/P8 require shaft evidence, P7 requires ball/impact
  evidence, and only explicit human actions emit `.manual`.

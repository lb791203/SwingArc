# SwingArc Golf Dataset Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立按 golferID 隔离、自动预测不可变、人工决策可审计且能确定性导出训练真值的数据合同。

**Architecture:** 新增 Foundation-only 的数据集身份、预测和人工 revision 模型；`GolfDatasetStore` 负责原子保存与不可变 prediction run，`GolfResolvedLabelExporter` 负责把冻结 revision 解析为训练标签和清单哈希。现有 iPhone `AnnotationPackage` 不直接升级为新训练格式，只作为后续 Mac 导入可读取的旧来源。

**Tech Stack:** Swift 5、Foundation、CryptoKit、现有 standalone `swiftc` smoke tests、Xcode 27 beta；数据保存在本地 JSON，原始视频与训练产物不进入 Git。

## Global Constraints

- 权威坐标是方向修正后原片的标准化坐标：左上原点、x 向右、y 向下、范围 `[0, 1]`。
- `sourceFrameIndex` 从 0 开始，并绑定媒体 SHA-256 与源时间线 SHA-256。
- 同一 golferID 的全部 clip 只能属于一个 split。
- prediction run 不可原地修改；人工 revision 必须引用一个 prediction run。
- `visible` 必须有坐标；`occluded`、`out-of-frame` 不保存人工坐标；`unresolved` 不进入任何监督。
- training/validation/held-out 只能读取 `training-allowed` 素材。
- 所有生产行为修改遵循 RED → GREEN → REFACTOR。

---

### Task 1: Define golfer, clip, and split identity

**Files:**
- Create: `SwingArc/Models/GolfDatasetIdentity.swift`
- Create: `Tests/GolfDatasetIdentitySmoke.swift`

**Interfaces:**
- Produces: `GolfDatasetSplit`, `GolfDatasetAuthorization`, `GolfDatasetView`, `GolfDatasetHandedness`
- Produces: `GolfMediaIdentity`, `GolfClipIdentity`, `GolferRecord`, `GolferRegistry`
- Produces: `GolferRegistry.assign(golferID:split:at:) throws -> GolferRegistry`
- Consumes: no application UI or Apple framework

- [ ] **Step 1: Write the failing identity and split-lock test**

Create `Tests/GolfDatasetIdentitySmoke.swift`:

```swift
import Foundation

@main
struct GolfDatasetIdentitySmoke {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_721_808_000)
        let empty = GolferRegistry(
            schemaVersion: 1,
            datasetID: "swingarc-local-1",
            golfers: []
        )
        let training = try empty.assign(
            golferID: "golfer-001",
            split: .training,
            at: now
        )
        precondition(training.split(for: "golfer-001") == .training)
        precondition(
            try training.assign(
                golferID: "golfer-001",
                split: .training,
                at: now
            ) == training
        )
        do {
            _ = try training.assign(
                golferID: "golfer-001",
                split: .validation,
                at: now
            )
            preconditionFailure("a locked golfer cannot cross splits")
        } catch GolfDatasetIdentityError.splitConflict(
            golferID: "golfer-001",
            existing: .training,
            requested: .validation
        ) {}

        let media = GolfMediaIdentity(
            fileName: "clip.mov",
            sha256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            frameCount: 900,
            orientedWidth: 1080,
            orientedHeight: 1920,
            sourceTimescale: 600
        )
        let clip = GolfClipIdentity(
            schemaVersion: 1,
            clipID: "clip-001",
            golferID: "golfer-001",
            media: media,
            view: .downTheLine,
            handedness: .right,
            authorization: .trainingAllowed,
            pPointTruthSHA256: String(repeating: "c", count: 64)
        )
        precondition(clip.media.frameCount == 900)
        precondition(
            try JSONDecoder().decode(
                GolfClipIdentity.self,
                from: JSONEncoder().encode(clip)
            ) == clip
        )
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/GolfDatasetIdentity.swift \
  Tests/GolfDatasetIdentitySmoke.swift \
  -o /tmp/golf-dataset-identity-smoke
```

Expected: FAIL because `GolfDatasetIdentity.swift` does not exist.

- [ ] **Step 3: Implement the minimal identity model**

Create the enums and Codable/Equatable structs named in the Interfaces block. Implement `assign` as:

```swift
func assign(
    golferID rawID: String,
    split: GolfDatasetSplit,
    at date: Date
) throws -> GolferRegistry {
    let golferID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !golferID.isEmpty, golferID == rawID else {
        throw GolfDatasetIdentityError.invalidGolferID(rawID)
    }
    if let existing = golfers.first(where: { $0.golferID == golferID }) {
        guard existing.split == split else {
            throw GolfDatasetIdentityError.splitConflict(
                golferID: golferID,
                existing: existing.split,
                requested: split
            )
        }
        return self
    }
    var copy = self
    copy.golfers.append(.init(
        golferID: golferID,
        split: split,
        splitLockedAt: date
    ))
    copy.golfers.sort { $0.golferID < $1.golferID }
    return copy
}
```

- [ ] **Step 4: Run GREEN and commit**

Run the compiled binary. Expected: exit 0 with no output.

```bash
git add SwingArc/Models/GolfDatasetIdentity.swift \
  Tests/GolfDatasetIdentitySmoke.swift
git commit -m "feat: add golfer-locked dataset identity"
```

---

### Task 2: Define prediction and manual-decision contracts

**Files:**
- Create: `SwingArc/Models/GolfKeypointAnnotations.swift`
- Create: `SwingArc/Models/GolfPredictionRun.swift`
- Create: `Tests/GolfKeypointAnnotationContractSmoke.swift`

**Interfaces:**
- Produces: `GolfLandmark` in fixed order `grip`, `shaftStart`, `shaftEnd`, `clubhead`, `ball`
- Produces: `GolfVisibilityClass`, `GolfAnnotationDecisionKind`, `GolfAnnotationDecision`
- Produces: `GolfFrameRevision`, `GolfAnnotationRevision`
- Produces: `GolfROIAffineTransform`, `GolfPredictionPoint`, `GolfPredictionFrame`, `GolfPredictionRun`
- Produces: `GolfAnnotationDecision.resolvedLandmark(prediction:) throws -> GolfResolvedLandmark?`

- [ ] **Step 1: Write the failing hidden-point and provenance test**

Create a smoke test with these exact assertions:

```swift
let predicted = GolfPredictionPoint(
    roiX: 0.25,
    roiY: 0.75,
    heatmapConfidence: 0.91,
    heatmapDispersion: 0.04,
    visibilityProbabilities: [0.9, 0.08, 0.02]
)
let accepted = GolfAnnotationDecision(
    landmark: .clubhead,
    kind: .acceptedPrediction,
    fullFramePoint: .init(x: 0.4, y: 0.6),
    annotatorID: "reviewer-1",
    decidedAt: Date(timeIntervalSince1970: 10)
)
precondition(
    try accepted.resolvedLandmark(prediction: predicted)?.source
        == .acceptedPrediction
)

let occluded = GolfAnnotationDecision(
    landmark: .shaftEnd,
    kind: .occluded,
    fullFramePoint: nil,
    annotatorID: "reviewer-1",
    decidedAt: Date(timeIntervalSince1970: 11)
)
let resolvedOccluded = try occluded.resolvedLandmark(prediction: predicted)
precondition(resolvedOccluded?.visibility == .occluded)
precondition(resolvedOccluded?.point == nil)

do {
    _ = try GolfAnnotationDecision(
        landmark: .grip,
        kind: .correctedPoint,
        fullFramePoint: nil,
        annotatorID: "reviewer-1",
        decidedAt: Date()
    ).validated()
    preconditionFailure("visible decisions require coordinates")
} catch GolfAnnotationContractError.visiblePointMissingCoordinate {}

do {
    _ = try GolfAnnotationDecision(
        landmark: .ball,
        kind: .outOfFrame,
        fullFramePoint: .init(x: 0.5, y: 0.5),
        annotatorID: "reviewer-1",
        decidedAt: Date()
    ).validated()
    preconditionFailure("out-of-frame decisions cannot carry coordinates")
} catch GolfAnnotationContractError.hiddenPointHasCoordinate {}
```

Also assert a `GolfPredictionRun` round-trips with model, ROI, decoder, tracker, media, and creation hashes unchanged.

- [ ] **Step 2: Run RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/GolfDatasetIdentity.swift \
  SwingArc/Models/GolfKeypointAnnotations.swift \
  SwingArc/Models/GolfPredictionRun.swift \
  Tests/GolfKeypointAnnotationContractSmoke.swift \
  -o /tmp/golf-keypoint-annotation-contract-smoke
```

Expected: FAIL because the two new model files are absent.

- [ ] **Step 3: Implement strict state validation**

Implement `validated()` with these exhaustive rules:

```swift
switch kind {
case .acceptedPrediction, .correctedPoint:
    guard let point = fullFramePoint else {
        throw GolfAnnotationContractError.visiblePointMissingCoordinate
    }
    guard point.x.isFinite, point.y.isFinite,
          (0...1).contains(point.x), (0...1).contains(point.y) else {
        throw GolfAnnotationContractError.coordinateOutOfRange
    }
case .occluded, .outOfFrame, .unresolved:
    guard fullFramePoint == nil else {
        throw GolfAnnotationContractError.hiddenPointHasCoordinate
    }
}
guard !annotatorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    throw GolfAnnotationContractError.missingAnnotator
}
return self
```

`GolfROIAffineTransform` stores six forward and six inverse coefficients; it does not depend on CoreGraphics so the contract remains portable.
`resolvedLandmark` returns nil only for `.unresolved`; hidden decisions return a
resolved visibility row with `point == nil`.

- [ ] **Step 4: Run GREEN and commit**

```bash
git add SwingArc/Models/GolfKeypointAnnotations.swift \
  SwingArc/Models/GolfPredictionRun.swift \
  Tests/GolfKeypointAnnotationContractSmoke.swift
git commit -m "feat: define golf prediction and revision contracts"
```

---

### Task 3: Add an atomic, immutable dataset store

**Files:**
- Create: `SwingArc/Services/GolfDatasetStore.swift`
- Create: `Tests/GolfDatasetStoreSmoke.swift`

**Interfaces:**
- Consumes: `GolferRegistry`, `GolfClipIdentity`, `GolfPredictionRun`, `GolfAnnotationRevision`
- Produces: `GolfDatasetStore.saveRegistry(_:)`
- Produces: `GolfDatasetStore.saveClip(_:)`
- Produces: `GolfDatasetStore.appendPrediction(_:)`
- Produces: `GolfDatasetStore.saveRevision(_:)`
- Produces: typed load methods for all four records
- Produces: `GolfDatasetStore.loadSnapshot() throws -> GolfDatasetSnapshot`

- [ ] **Step 1: Write the failing atomicity and immutability test**

Use a UUID temporary root. Save a registry and clip, append `prediction-run-1`,
then call `appendPrediction` again with the same ID and different bytes:

```swift
do {
    try store.appendPrediction(changedPrediction)
    preconditionFailure("prediction runs are immutable")
} catch GolfDatasetStoreError.predictionAlreadyExists("prediction-run-1") {}
precondition(try store.loadPrediction(
    clipID: "clip-001",
    predictionRunID: "prediction-run-1"
) == originalPrediction)
```

Save `revision-1` twice with identical bytes and require idempotence. Save the same
revision ID with changed bytes and require `.revisionConflict("revision-1")`.
Verify no `.tmp` file remains after successful writes.

- [ ] **Step 2: Run RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/GolfDatasetIdentity.swift \
  SwingArc/Models/GolfKeypointAnnotations.swift \
  SwingArc/Models/GolfPredictionRun.swift \
  SwingArc/Services/GolfDatasetStore.swift \
  Tests/GolfDatasetStoreSmoke.swift \
  -o /tmp/golf-dataset-store-smoke
```

Expected: FAIL because `GolfDatasetStore` is undefined.

- [ ] **Step 3: Implement deterministic JSON and atomic writes**

Use one encoder:

```swift
private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
}
```

Write to a sibling temporary URL, compare existing bytes for idempotence/conflict,
then use `FileManager.replaceItemAt` when the destination exists or
`moveItem(at:to:)` when it does not. Prediction files must reject every existing
destination, even if the bytes match.

- [ ] **Step 4: Run GREEN and commit**

```bash
git add SwingArc/Services/GolfDatasetStore.swift \
  Tests/GolfDatasetStoreSmoke.swift
git commit -m "feat: add immutable golf dataset store"
```

---

### Task 4: Validate complete clips and golfer-level splits

**Files:**
- Create: `SwingArc/Services/GolfDatasetValidator.swift`
- Create: `Tests/GolfDatasetValidatorSmoke.swift`

**Interfaces:**
- Consumes: registry, clips, prediction runs, revisions
- Produces: `[GolfDatasetValidationError]`
- Enforces: unique clip IDs, media hashes, authorization, frame bounds, five decisions per reviewed frame, golfer split isolation, revision/prediction linkage

- [ ] **Step 1: Write the failing validator matrix**

Create fixtures for one passing training clip and assert exact failures for:

```swift
precondition(errors(for: duplicateClips) == [.duplicateClipID("clip-001")])
precondition(errors(for: leakedGolfer) == [
    .golferSplitConflict(
        golferID: "golfer-001",
        registry: .training,
        clip: .validation
    )
])
precondition(errors(for: internalOnlyTraining) == [
    .trainingNotAuthorized("clip-001")
])
precondition(errors(for: missingBallDecision) == [
    .incompleteFrameDecisions(clipID: "clip-001", sourceFrameIndex: 542)
])
precondition(errors(for: wrongPredictionReference) == [
    .missingPredictionRun("prediction-missing")
])
precondition(errors(for: outOfRangeFrame) == [
    .frameOutOfRange(clipID: "clip-001", sourceFrameIndex: 900)
])
```

- [ ] **Step 2: Run RED**

Compile the three model files, `GolfDatasetValidator.swift`, and the new test.
Expected: FAIL because the validator is absent.

- [ ] **Step 3: Implement deterministic validation ordering**

Return errors sorted first by clipID, then source frame, then stable enum order.
Development clips may use `internal-review`; every non-development split requires
`training-allowed`. A frame counts as reviewed only when all five `GolfLandmark`
values have exactly one validated decision.

- [ ] **Step 4: Run GREEN and commit**

```bash
git add SwingArc/Services/GolfDatasetValidator.swift \
  Tests/GolfDatasetValidatorSmoke.swift
git commit -m "feat: validate golfer-isolated keypoint datasets"
```

---

### Task 5: Export deterministic resolved labels and a manifest hash

**Files:**
- Create: `SwingArc/Services/GolfResolvedLabelExporter.swift`
- Create: `Tests/GolfResolvedLabelExportSmoke.swift`
- Create: `Tools/PrecisionDataset/ValidateGolfDataset.swift`

**Interfaces:**
- Consumes: validated dataset snapshot, selected ROI version, selected prediction/revision IDs
- Produces: `GolfResolvedDataset`, `GolfResolvedFrameLabel`, `GolfDatasetExportReceipt`
- Produces: `manifestSHA256`
- CLI: `validate-golf-dataset <dataset-root>`

- [ ] **Step 1: Write the failing resolved-label test**

Build one frame where grip is accepted, shaftStart/shaftEnd are corrected, clubhead
is occluded, and ball is unresolved. Assert:

```swift
let frame = try export.clips[0].frames[0]
precondition(frame.landmarks[.grip]?.visibility == .visible)
precondition(frame.landmarks[.grip]?.source == .acceptedPrediction)
precondition(frame.landmarks[.shaftEnd]?.source == .correctedPoint)
precondition(frame.landmarks[.clubhead]?.visibility == .occluded)
precondition(frame.landmarks[.clubhead]?.point == nil)
precondition(frame.landmarks[.ball] == nil)
precondition(receipt.manifestSHA256.count == 64)
```

Export twice to two empty directories and require byte-identical
`resolved-labels.json` and `manifest.json`. Modify one decision and require a
different hash.

- [ ] **Step 2: Run RED**

Compile with `-framework CryptoKit` unnecessary because CryptoKit is imported as
a Swift module:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  SwingArc/Models/GolfDatasetIdentity.swift \
  SwingArc/Models/GolfKeypointAnnotations.swift \
  SwingArc/Models/GolfPredictionRun.swift \
  SwingArc/Services/GolfDatasetValidator.swift \
  SwingArc/Services/GolfResolvedLabelExporter.swift \
  Tests/GolfResolvedLabelExportSmoke.swift \
  -o /tmp/golf-resolved-label-export-smoke
```

Expected: FAIL because the exporter is absent.

- [ ] **Step 3: Implement canonical export**

Sort golfers, clips, frames, and landmarks by their canonical identifiers.
Exclude unresolved points. Preserve occluded/out-of-frame rows with `point: null`.
Each resolved clip also carries its ordered P1–P8 source-frame truth, and every
frame carries sorted queue reasons such as `p6-dense`, `p8-dense`,
`low-confidence`, or `negative`. These fields let model evaluation identify
P6/P8 shaft-angle frames without reading an active annotation package.
Hash the final UTF-8 bytes of `manifest.json` with SHA-256. Never read an active,
unfinished revision.

Implement the CLI as:

```swift
@main
enum ValidateGolfDataset {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(
                Data("usage: validate-golf-dataset <dataset-root>\n".utf8)
            )
            Foundation.exit(64)
        }
        let snapshot = try GolfDatasetStore(
            rootDirectory: URL(fileURLWithPath: CommandLine.arguments[1])
        ).loadSnapshot()
        let errors = GolfDatasetValidator.errors(in: snapshot)
        guard errors.isEmpty else {
            for error in errors {
                print(error.description)
            }
            Foundation.exit(1)
        }
        print("dataset contract passed")
    }
}
```

- [ ] **Step 4: Run the complete contract suite**

Run all five new smoke binaries. Expected: each exits 0. Also run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add SwingArc/Models/GolfDatasetIdentity.swift \
  SwingArc/Models/GolfKeypointAnnotations.swift \
  SwingArc/Models/GolfPredictionRun.swift \
  SwingArc/Services/GolfDatasetStore.swift \
  SwingArc/Services/GolfDatasetValidator.swift \
  SwingArc/Services/GolfResolvedLabelExporter.swift \
  Tests/GolfDatasetIdentitySmoke.swift \
  Tests/GolfKeypointAnnotationContractSmoke.swift \
  Tests/GolfDatasetStoreSmoke.swift \
  Tests/GolfDatasetValidatorSmoke.swift \
  Tests/GolfResolvedLabelExportSmoke.swift \
  Tools/PrecisionDataset/ValidateGolfDataset.swift
git commit -m "feat: export reproducible golf keypoint labels"
```

## Plan 1 Completion Gate

- All five new smoke tests pass.
- An immutable prediction cannot be overwritten.
- A hidden point without coordinates exports successfully and never becomes a coordinate target.
- A visible point without coordinates fails validation.
- Golfer split leakage fails before export.
- Two identical exports are byte-for-byte identical and share one SHA-256.
- No production UI or model code has changed.

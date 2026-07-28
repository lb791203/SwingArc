import CryptoKit
import Foundation

private enum GolfResolvedLabelExportSmokeError: Error {
    case missingFixture
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func auditTransform() -> GolfROIAffineTransform {
    GolfROIAffineTransform(
        a: 2, b: 0, c: 0, d: 2, tx: -0.5, ty: -0.5,
        invA: 0.5, invB: 0, invC: 0, invD: 0.5, invTx: 0.25, invTy: 0.25
    )
}

private func predictionPoint(_ point: GolfNormalizedPoint) -> GolfPredictionPoint {
    GolfPredictionPoint(
        roiX: point.x,
        roiY: point.y,
        heatmapConfidence: 0.91,
        heatmapDispersion: 0.02,
        visibilityProbabilities: [0.96, 0.03, 0.01],
        preTrackingFullFramePoint: point,
        trackingStatus: "decoded"
    )
}

private func fixture(
    shaftEndX: Double = 0.72,
    orientedWidth: Int = 1920,
    orientedHeight: Int = 1080
) -> (
    snapshot: GolfDatasetSnapshot,
    selection: GolfDatasetExportSelection
) {
    let mediaHash = String(repeating: "a", count: 64)
    let timelineHash = String(repeating: "b", count: 64)
    let truthHash = String(repeating: "c", count: 64)
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let gripPoint = GolfNormalizedPoint(x: 0.42, y: 0.58)

    let registry = GolferRegistry(
        datasetID: "swingarc-eight-clips-v1",
        golfers: [
            GolferRecord(
                golferID: "golfer-002",
                split: .validation,
                splitLockedAt: fixedDate
            )
        ]
    )
    let clip = GolfClipIdentity(
        clipID: "clip-b",
        golferID: "golfer-002",
        media: GolfMediaIdentity(
            fileName: "clip-b.mov",
            sha256: mediaHash,
            timelineSHA256: timelineHash,
            frameCount: 120,
            orientedWidth: orientedWidth,
            orientedHeight: orientedHeight,
            sourceTimescale: 600
        ),
        view: .downTheLine,
        handedness: .right,
        authorization: .trainingAllowed,
        pPointTruthSHA256: truthHash
    )
    let prediction = GolfPredictionRun(
        predictionRunID: "prediction-b-v3",
        clipID: clip.clipID,
        mediaSHA256: mediaHash,
        timelineSHA256: timelineHash,
        visionFrameworkVersion: "3.0",
        visionRequestVersion: "VNDetectHumanBodyPoseRequest-1",
        roiAlgorithmVersion: "stable-roi-v2",
        roiConfigSHA256: String(repeating: "d", count: 64),
        modelSHA256: String(repeating: "e", count: 64),
        decoderVersion: "heatmap-v1",
        trackerVersion: "temporal-v1",
        createdAt: fixedDate,
        frames: [
            GolfPredictionFrame(
                sourceFrameIndex: 60,
                sourceTime: 2.0,
                roiTransform: auditTransform(),
                points: [.grip: predictionPoint(gripPoint)]
            )
        ],
        provenanceHash: String(repeating: "f", count: 64)
    )
    let decisions = [
        GolfAnnotationDecision(
            landmark: .ball,
            kind: .unresolved,
            fullFramePoint: nil,
            annotatorID: "annotator-a",
            decidedAt: fixedDate
        ),
        GolfAnnotationDecision(
            landmark: .clubhead,
            kind: .occluded,
            fullFramePoint: nil,
            annotatorID: "annotator-a",
            decidedAt: fixedDate
        ),
        GolfAnnotationDecision(
            landmark: .shaftEnd,
            kind: .correctedPoint,
            fullFramePoint: GolfNormalizedPoint(x: shaftEndX, y: 0.31),
            annotatorID: "annotator-a",
            decidedAt: fixedDate
        ),
        GolfAnnotationDecision(
            landmark: .grip,
            kind: .acceptedPrediction,
            fullFramePoint: gripPoint,
            annotatorID: "annotator-a",
            decidedAt: fixedDate
        ),
        GolfAnnotationDecision(
            landmark: .shaftStart,
            kind: .correctedPoint,
            fullFramePoint: GolfNormalizedPoint(x: 0.49, y: 0.53),
            annotatorID: "annotator-a",
            decidedAt: fixedDate
        )
    ]
    let revision = GolfAnnotationRevision(
        revisionID: "revision-b-final",
        clipID: clip.clipID,
        parentPredictionRunID: prediction.predictionRunID,
        annotatorID: "annotator-a",
        createdAt: fixedDate,
        completedAt: fixedDate.addingTimeInterval(90),
        frameRevisions: [
            GolfFrameRevision(sourceFrameIndex: 60, decisions: decisions)
        ]
    )
    let selection = GolfDatasetExportSelection(
        roiAlgorithmVersion: "stable-roi-v2",
        clips: [
            GolfDatasetClipExportSelection(
                clipID: clip.clipID,
                predictionRunID: prediction.predictionRunID,
                revisionID: revision.revisionID,
                pPointTruth: [
                    .init(stage: .p8, sourceFrameIndex: 60),
                    .init(stage: .p2, sourceFrameIndex: 60),
                    .init(stage: .p1, sourceFrameIndex: 60),
                    .init(stage: .p4, sourceFrameIndex: 60),
                    .init(stage: .p3, sourceFrameIndex: 60),
                    .init(stage: .p6, sourceFrameIndex: 60),
                    .init(stage: .p5, sourceFrameIndex: 60),
                    .init(stage: .p7, sourceFrameIndex: 60)
                ],
                frameMetadata: [
                    .init(
                        sourceFrameIndex: 60,
                        queueReasons: ["p8-dense", "p6-dense", "p6-dense"]
                    )
                ]
            )
        ]
    )
    return (
        GolfDatasetSnapshot(
            registry: registry,
            clips: [clip],
            predictions: [prediction],
            revisions: [revision]
        ),
        selection
    )
}

private func temporaryDirectory(_ suffix: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("golf-resolved-export-\(UUID().uuidString)-\(suffix)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func testResolvedSemanticsAndDeterminism() throws {
    let input = fixture()
    let firstDirectory = try temporaryDirectory("first")
    let secondDirectory = try temporaryDirectory("second")
    defer {
        try? FileManager.default.removeItem(at: firstDirectory)
        try? FileManager.default.removeItem(at: secondDirectory)
    }

    let first = try GolfResolvedLabelExporter.export(
        snapshot: input.snapshot,
        selection: input.selection,
        to: firstDirectory
    )
    let second = try GolfResolvedLabelExporter.export(
        snapshot: input.snapshot,
        selection: input.selection,
        to: secondDirectory
    )

    guard let clip = first.dataset.clips.first,
          let frame = clip.frames.first else {
        throw GolfResolvedLabelExportSmokeError.missingFixture
    }
    precondition(frame.landmarks[.grip]?.visibility == .visible)
    precondition(frame.landmarks[.grip]?.source == .acceptedPrediction)
    precondition(frame.landmarks[.shaftEnd]?.source == .correctedPoint)
    precondition(frame.landmarks[.clubhead]?.visibility == .occluded)
    precondition(frame.landmarks[.clubhead]?.point == nil)
    precondition(frame.landmarks[.ball] == nil)
    precondition(frame.annotationROITransform == auditTransform())
    precondition(frame.queueReasons == ["p6-dense", "p8-dense"])
    precondition(clip.pPointTruth.map(\.stage) == GolfPPointStage.allCases)
    precondition(clip.authorization == .trainingAllowed)
    precondition(clip.fileName == "clip-b.mov")
    precondition(clip.frameCount == 120)
    precondition(clip.orientedWidth == 1920)
    precondition(clip.orientedHeight == 1080)
    precondition(clip.sourceTimescale == 600)
    let landscapeTransform = try GolfTrainingInputTransform(
        sourceOrientedWidth: 1920,
        sourceOrientedHeight: 1080
    )
    precondition(clip.trainingInputTransform == landscapeTransform)
    precondition(clip.trainingInputTransform.contentWidth == 512)
    precondition(clip.trainingInputTransform.contentHeight == 288)
    precondition(clip.trainingInputTransform.offsetX == 0)
    precondition(clip.trainingInputTransform.offsetY == 112)
    let portraitTransform = try GolfTrainingInputTransform(
        sourceOrientedWidth: 1080,
        sourceOrientedHeight: 1920
    )
    precondition(portraitTransform.contentWidth == 288)
    precondition(portraitTransform.contentHeight == 512)
    precondition(portraitTransform.offsetX == 112)
    precondition(portraitTransform.offsetY == 0)
    precondition(
        clip.revisionCompletedAt
            == Date(timeIntervalSince1970: 1_700_000_090)
    )
    precondition(first.dataset.schemaVersion == 2)
    precondition(first.manifest.schemaVersion == 2)
    precondition(
        first.dataset.inputTransformVersion
            == GolfTrainingInputTransform.version
    )
    precondition(first.dataset.inputWidth == 512)
    precondition(first.dataset.inputHeight == 512)
    precondition(
        first.manifest.inputTransformVersion
            == GolfTrainingInputTransform.version
    )
    precondition(first.manifest.inputWidth == 512)
    precondition(first.manifest.inputHeight == 512)
    guard let manifestClip = first.manifest.clips.first else {
        throw GolfResolvedLabelExportSmokeError.missingFixture
    }
    precondition(manifestClip.split == .validation)
    precondition(manifestClip.view == .downTheLine)
    precondition(manifestClip.handedness == .right)
    precondition(manifestClip.trainingInputTransformSHA256.count == 64)
    precondition(first.receipt.manifestSHA256.count == 64)
    precondition(first.receipt.manifestSHA256 == second.receipt.manifestSHA256)

    let firstLabels = try Data(contentsOf: first.receipt.resolvedLabelsURL)
    let secondLabels = try Data(contentsOf: second.receipt.resolvedLabelsURL)
    let firstManifest = try Data(contentsOf: first.receipt.manifestURL)
    let secondManifest = try Data(contentsOf: second.receipt.manifestURL)
    precondition(firstLabels == secondLabels)
    precondition(firstManifest == secondManifest)
    precondition(first.manifest.resolvedLabelsSHA256 == sha256(firstLabels))
    precondition(first.receipt.manifestSHA256 == sha256(firstManifest))
    let labelsJSON = String(decoding: firstLabels, as: UTF8.self)
    precondition(labelsJSON.contains("\"point\" : null"))
    precondition(!labelsJSON.contains("\"source\" : \"unresolved\""))
}

private func testDecisionChangesManifestHash() throws {
    let original = fixture(shaftEndX: 0.72)
    let modified = fixture(shaftEndX: 0.73)
    let originalDirectory = try temporaryDirectory("original")
    let modifiedDirectory = try temporaryDirectory("modified")
    defer {
        try? FileManager.default.removeItem(at: originalDirectory)
        try? FileManager.default.removeItem(at: modifiedDirectory)
    }

    let first = try GolfResolvedLabelExporter.export(
        snapshot: original.snapshot,
        selection: original.selection,
        to: originalDirectory
    )
    let second = try GolfResolvedLabelExporter.export(
        snapshot: modified.snapshot,
        selection: modified.selection,
        to: modifiedDirectory
    )
    precondition(first.receipt.manifestSHA256 != second.receipt.manifestSHA256)
}

private func testRejectsUnfinishedRevision() throws {
    let input = fixture()
    let finished = input.snapshot.revisions[0]
    let unfinished = GolfAnnotationRevision(
        revisionID: finished.revisionID,
        clipID: finished.clipID,
        parentPredictionRunID: finished.parentPredictionRunID,
        annotatorID: finished.annotatorID,
        createdAt: finished.createdAt,
        completedAt: nil,
        frameRevisions: finished.frameRevisions
    )
    let snapshot = GolfDatasetSnapshot(
        registry: input.snapshot.registry,
        clips: input.snapshot.clips,
        predictions: input.snapshot.predictions,
        revisions: [unfinished]
    )
    let directory = try temporaryDirectory("unfinished")
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
        _ = try GolfResolvedLabelExporter.export(
            snapshot: snapshot,
            selection: input.selection,
            to: directory
        )
        preconditionFailure("unfinished revisions must not export")
    } catch GolfResolvedLabelExportError.validationFailed(let errors) {
        precondition(errors.contains(.revisionNotCompleted(unfinished.revisionID)))
    }
}

private func testRejectsInvalidOrOverflowingOrientedDimensions() throws {
    for (width, height, expectedOverflow) in [
        (0, 1080, false),
        (Int.max, Int.max - 1, true)
    ] {
        let input = fixture(
            orientedWidth: width,
            orientedHeight: height
        )
        let directory = try temporaryDirectory("invalid-dimensions")
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try GolfResolvedLabelExporter.export(
                snapshot: input.snapshot,
                selection: input.selection,
                to: directory
            )
            preconditionFailure("invalid dimensions must not export")
        } catch GolfResolvedLabelExportError.invalidOrientedDimensions(
            let clipID,
            let actualWidth,
            let actualHeight
        ) {
            precondition(!expectedOverflow)
            precondition(clipID == "clip-b")
            precondition(actualWidth == width)
            precondition(actualHeight == height)
        } catch GolfResolvedLabelExportError.trainingInputTransformOverflow(
            let clipID,
            let actualWidth,
            let actualHeight
        ) {
            precondition(expectedOverflow)
            precondition(clipID == "clip-b")
            precondition(actualWidth == width)
            precondition(actualHeight == height)
        }
    }
}

private func testRequiresExactPPointResolvedFrameSet() throws {
    let input = fixture()
    let source = input.snapshot.revisions[0]
    let missingFrame = GolfAnnotationRevision(
        revisionID: source.revisionID,
        clipID: source.clipID,
        parentPredictionRunID: source.parentPredictionRunID,
        annotatorID: source.annotatorID,
        createdAt: source.createdAt,
        completedAt: source.completedAt,
        frameRevisions: []
    )
    let snapshot = GolfDatasetSnapshot(
        registry: input.snapshot.registry,
        clips: input.snapshot.clips,
        predictions: input.snapshot.predictions,
        revisions: [missingFrame]
    )
    let directory = try temporaryDirectory("missing-p-point-frame")
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        _ = try GolfResolvedLabelExporter.export(
            snapshot: snapshot,
            selection: input.selection,
            to: directory
        )
        preconditionFailure("missing P-point frames must not export")
    } catch GolfResolvedLabelExportError.resolvedFrameSetMismatch(
        let clipID,
        let expected,
        let actual
    ) {
        precondition(clipID == "clip-b")
        precondition(expected == [60])
        precondition(actual.isEmpty)
    }
}

private func testSkinnyInputTransformsRemainFinite() throws {
    let fixtures = [
        (width: 2048, height: 1, contentWidth: 512, contentHeight: 1,
         offsetX: 0, offsetY: 255),
        (width: 1, height: 2048, contentWidth: 1, contentHeight: 512,
         offsetX: 255, offsetY: 0),
        (width: 1025, height: 1, contentWidth: 512, contentHeight: 1,
         offsetX: 0, offsetY: 255)
    ]
    for fixture in fixtures {
        let transform = try GolfTrainingInputTransform(
            sourceOrientedWidth: fixture.width,
            sourceOrientedHeight: fixture.height
        )
        precondition(transform.contentWidth == fixture.contentWidth)
        precondition(transform.contentHeight == fixture.contentHeight)
        precondition(transform.offsetX == fixture.offsetX)
        precondition(transform.offsetY == fixture.offsetY)
        let auditValues = [
            transform.forward.scaleX,
            transform.forward.scaleY,
            transform.forward.translateX,
            transform.forward.translateY,
            transform.inverse.scaleX,
            transform.inverse.scaleY,
            transform.inverse.translateX,
            transform.inverse.translateY
        ]
        precondition(auditValues.allSatisfy(\.isFinite))

        for point in [(x: 0.0, y: 0.0), (x: 0.37, y: 0.61), (x: 1.0, y: 1.0)] {
            let canvasX = (
                Double(transform.offsetX)
                    + point.x * Double(transform.contentWidth)
            ) / 512
            let canvasY = (
                Double(transform.offsetY)
                    + point.y * Double(transform.contentHeight)
            ) / 512
            let sourceX = (
                canvasX * 512 - Double(transform.offsetX)
            ) / Double(transform.contentWidth)
            let sourceY = (
                canvasY * 512 - Double(transform.offsetY)
            ) / Double(transform.contentHeight)
            precondition(abs(sourceX - point.x) <= 1e-9)
            precondition(abs(sourceY - point.y) <= 1e-9)
        }
    }
}

@main
struct GolfResolvedLabelExportSmokeRunner {
    static func main() throws {
        try testResolvedSemanticsAndDeterminism()
        try testDecisionChangesManifestHash()
        try testRejectsUnfinishedRevision()
        try testRejectsInvalidOrOverflowingOrientedDimensions()
        try testRequiresExactPPointResolvedFrameSet()
        try testSkinnyInputTransformsRemainFinite()
        print("All GolfResolvedLabelExporter tests passed.")
    }
}

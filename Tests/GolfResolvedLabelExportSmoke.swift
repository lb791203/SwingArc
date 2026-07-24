import CryptoKit
import Foundation

private enum GolfResolvedLabelExportSmokeError: Error {
    case missingFixture
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func identityTransform() -> GolfROIAffineTransform {
    GolfROIAffineTransform(
        a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0,
        invA: 1, invB: 0, invC: 0, invD: 1, invTx: 0, invTy: 0
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

private func fixture(shaftEndX: Double = 0.72) -> (
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
            orientedWidth: 1920,
            orientedHeight: 1080,
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
                roiTransform: identityTransform(),
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
                    .init(stage: .p8, sourceFrameIndex: 105),
                    .init(stage: .p2, sourceFrameIndex: 20),
                    .init(stage: .p1, sourceFrameIndex: 10),
                    .init(stage: .p4, sourceFrameIndex: 45),
                    .init(stage: .p3, sourceFrameIndex: 32),
                    .init(stage: .p6, sourceFrameIndex: 70),
                    .init(stage: .p5, sourceFrameIndex: 60),
                    .init(stage: .p7, sourceFrameIndex: 86)
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
    precondition(frame.queueReasons == ["p6-dense", "p8-dense"])
    precondition(clip.pPointTruth.map(\.stage) == GolfPPointStage.allCases)
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

@main
struct GolfResolvedLabelExportSmokeRunner {
    static func main() throws {
        try testResolvedSemanticsAndDeterminism()
        try testDecisionChangesManifestHash()
        try testRejectsUnfinishedRevision()
        print("All GolfResolvedLabelExporter tests passed.")
    }
}

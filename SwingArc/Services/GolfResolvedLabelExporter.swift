import CryptoKit
import Foundation

public enum GolfPPointStage: String, Codable, CaseIterable, Equatable, Sendable {
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"
    case p4 = "P4"
    case p5 = "P5"
    case p6 = "P6"
    case p7 = "P7"
    case p8 = "P8"
}

public struct GolfPPointFrameTruth: Codable, Equatable, Sendable {
    public let stage: GolfPPointStage
    public let sourceFrameIndex: Int

    public init(stage: GolfPPointStage, sourceFrameIndex: Int) {
        self.stage = stage
        self.sourceFrameIndex = sourceFrameIndex
    }
}

public struct GolfExportFrameMetadata: Equatable, Sendable {
    public let sourceFrameIndex: Int
    public let queueReasons: [String]

    public init(sourceFrameIndex: Int, queueReasons: [String]) {
        self.sourceFrameIndex = sourceFrameIndex
        self.queueReasons = queueReasons
    }
}

public struct GolfDatasetClipExportSelection: Equatable, Sendable {
    public let clipID: String
    public let predictionRunID: String
    public let revisionID: String
    public let pPointTruth: [GolfPPointFrameTruth]
    public let frameMetadata: [GolfExportFrameMetadata]

    public init(
        clipID: String,
        predictionRunID: String,
        revisionID: String,
        pPointTruth: [GolfPPointFrameTruth],
        frameMetadata: [GolfExportFrameMetadata]
    ) {
        self.clipID = clipID
        self.predictionRunID = predictionRunID
        self.revisionID = revisionID
        self.pPointTruth = pPointTruth
        self.frameMetadata = frameMetadata
    }
}

public struct GolfDatasetExportSelection: Equatable, Sendable {
    public let roiAlgorithmVersion: String
    public let clips: [GolfDatasetClipExportSelection]

    public init(
        roiAlgorithmVersion: String,
        clips: [GolfDatasetClipExportSelection]
    ) {
        self.roiAlgorithmVersion = roiAlgorithmVersion
        self.clips = clips
    }
}

public struct GolfTrainingInputAffineAudit: Codable, Equatable, Sendable {
    public let scaleX: Double
    public let scaleY: Double
    public let translateX: Double
    public let translateY: Double
}

public enum GolfTrainingInputTransformError: Error, Equatable, Sendable {
    case invalidDimensions(width: Int, height: Int)
    case arithmeticOverflow(width: Int, height: Int)
}

public struct GolfTrainingInputTransform: Codable, Equatable, Sendable {
    public static let version = "full-frame-aspect-fit-v1"
    public static let canvasSize = 512

    public let version: String
    public let sourceOrientedWidth: Int
    public let sourceOrientedHeight: Int
    public let canvasWidth: Int
    public let canvasHeight: Int
    public let contentWidth: Int
    public let contentHeight: Int
    public let offsetX: Int
    public let offsetY: Int
    public let forward: GolfTrainingInputAffineAudit
    public let inverse: GolfTrainingInputAffineAudit

    public init(
        sourceOrientedWidth width: Int,
        sourceOrientedHeight height: Int
    ) throws {
        guard width > 0, height > 0 else {
            throw GolfTrainingInputTransformError.invalidDimensions(
                width: width,
                height: height
            )
        }
        let canvas = Self.canvasSize
        let contentWidth: Int
        let contentHeight: Int
        if width >= height {
            contentWidth = canvas
            contentHeight = try Self.halfUpContentDimension(
                scaledDimension: height,
                referenceDimension: width
            )
        } else {
            contentWidth = try Self.halfUpContentDimension(
                scaledDimension: width,
                referenceDimension: height
            )
            contentHeight = canvas
        }
        let offsetX = (canvas - contentWidth) / 2
        let offsetY = (canvas - contentHeight) / 2

        version = Self.version
        sourceOrientedWidth = width
        sourceOrientedHeight = height
        canvasWidth = canvas
        canvasHeight = canvas
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
        self.offsetX = offsetX
        self.offsetY = offsetY
        forward = GolfTrainingInputAffineAudit(
            scaleX: Double(contentWidth) / Double(canvas),
            scaleY: Double(contentHeight) / Double(canvas),
            translateX: Double(offsetX) / Double(canvas),
            translateY: Double(offsetY) / Double(canvas)
        )
        inverse = GolfTrainingInputAffineAudit(
            scaleX: Double(canvas) / Double(contentWidth),
            scaleY: Double(canvas) / Double(contentHeight),
            translateX: -Double(offsetX) / Double(contentWidth),
            translateY: -Double(offsetY) / Double(contentHeight)
        )
    }

    private static func halfUpContentDimension(
        scaledDimension: Int,
        referenceDimension: Int
    ) throws -> Int {
        let (twiceCanvas, canvasOverflow) = canvasSize
            .multipliedReportingOverflow(by: 2)
        let (scaledNumerator, scaleOverflow) = scaledDimension
            .multipliedReportingOverflow(by: twiceCanvas)
        let (numerator, additionOverflow) = scaledNumerator
            .addingReportingOverflow(referenceDimension)
        let (denominator, denominatorOverflow) = referenceDimension
            .multipliedReportingOverflow(by: 2)
        guard !canvasOverflow,
              !scaleOverflow,
              !additionOverflow,
              !denominatorOverflow,
              denominator > 0 else {
            throw GolfTrainingInputTransformError.arithmeticOverflow(
                width: scaledDimension,
                height: referenceDimension
            )
        }
        return max(1, numerator / denominator)
    }

    fileprivate var canonicalIdentity: String {
        [
            version,
            String(sourceOrientedWidth),
            String(sourceOrientedHeight),
            String(canvasWidth),
            String(canvasHeight),
            String(contentWidth),
            String(contentHeight),
            String(offsetX),
            String(offsetY)
        ].joined(separator: "|")
    }
}

public struct GolfResolvedGolfer: Codable, Equatable, Sendable {
    public let golferID: String
    public let split: GolfDatasetSplit
}

public struct GolfResolvedLandmarkCollection: Codable, Equatable, Sendable {
    private let orderedValues: [GolfResolvedLandmark]

    private enum CodingKeys: String, CodingKey {
        case landmark
        case visibility
        case point
        case source
    }

    public init(_ values: [GolfResolvedLandmark]) {
        let order = Dictionary(
            uniqueKeysWithValues: GolfLandmark.allCases.enumerated().map { ($1, $0) }
        )
        orderedValues = values.sorted {
            order[$0.landmark, default: Int.max] < order[$1.landmark, default: Int.max]
        }
    }

    public subscript(landmark: GolfLandmark) -> GolfResolvedLandmark? {
        orderedValues.first(where: { $0.landmark == landmark })
    }

    public var values: [GolfResolvedLandmark] {
        orderedValues
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [GolfResolvedLandmark] = []
        while !container.isAtEnd {
            let item = try container.nestedContainer(keyedBy: CodingKeys.self)
            values.append(GolfResolvedLandmark(
                landmark: try item.decode(GolfLandmark.self, forKey: .landmark),
                visibility: try item.decode(GolfVisibilityClass.self, forKey: .visibility),
                point: try item.decodeIfPresent(GolfNormalizedPoint.self, forKey: .point),
                source: try item.decode(GolfAnnotationDecisionKind.self, forKey: .source)
            ))
        }
        self.init(values)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for value in orderedValues {
            var item = container.nestedContainer(keyedBy: CodingKeys.self)
            try item.encode(value.landmark, forKey: .landmark)
            try item.encode(value.visibility, forKey: .visibility)
            if let point = value.point {
                try item.encode(point, forKey: .point)
            } else {
                try item.encodeNil(forKey: .point)
            }
            try item.encode(value.source, forKey: .source)
        }
    }
}

public struct GolfResolvedFrameLabel: Codable, Equatable, Sendable {
    public let sourceFrameIndex: Int
    public let sourceTime: Double
    public let queueReasons: [String]
    public let annotationROITransform: GolfROIAffineTransform
    public let landmarks: GolfResolvedLandmarkCollection
}

public struct GolfResolvedClip: Codable, Equatable, Sendable {
    public let clipID: String
    public let golferID: String
    public let split: GolfDatasetSplit
    public let view: GolfDatasetView
    public let handedness: GolfDatasetHandedness
    public let authorization: GolfDatasetAuthorization
    public let fileName: String
    public let frameCount: Int
    public let orientedWidth: Int
    public let orientedHeight: Int
    public let sourceTimescale: Int
    public let mediaSHA256: String
    public let timelineSHA256: String
    public let pPointTruthSHA256: String
    public let predictionRunID: String
    public let revisionID: String
    public let revisionCompletedAt: Date
    public let trainingInputTransform: GolfTrainingInputTransform
    public let pPointTruth: [GolfPPointFrameTruth]
    public let frames: [GolfResolvedFrameLabel]
}

public struct GolfResolvedDataset: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let datasetID: String
    public let roiAlgorithmVersion: String
    public let inputTransformVersion: String
    public let inputWidth: Int
    public let inputHeight: Int
    public let golfers: [GolfResolvedGolfer]
    public let clips: [GolfResolvedClip]
}

public struct GolfDatasetManifestClip: Codable, Equatable, Sendable {
    public let clipID: String
    public let golferID: String
    public let split: GolfDatasetSplit
    public let view: GolfDatasetView
    public let handedness: GolfDatasetHandedness
    public let predictionRunID: String
    public let revisionID: String
    public let revisionCompletedAt: Date
    public let authorization: GolfDatasetAuthorization
    public let fileName: String
    public let frameCount: Int
    public let orientedWidth: Int
    public let orientedHeight: Int
    public let sourceTimescale: Int
    public let mediaSHA256: String
    public let timelineSHA256: String
    public let pPointTruthSHA256: String
    public let predictionProvenanceHash: String
    public let resolvedFrameCount: Int
    public let trainingInputTransformSHA256: String
}

public struct GolfDatasetExportManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let datasetID: String
    public let roiAlgorithmVersion: String
    public let inputTransformVersion: String
    public let inputWidth: Int
    public let inputHeight: Int
    public let resolvedLabelsFile: String
    public let resolvedLabelsSHA256: String
    public let clips: [GolfDatasetManifestClip]
}

public struct GolfDatasetExportReceipt: Equatable, Sendable {
    public let manifestSHA256: String
    public let resolvedLabelsURL: URL
    public let manifestURL: URL
}

public struct GolfDatasetExportResult: Equatable, Sendable {
    public let dataset: GolfResolvedDataset
    public let manifest: GolfDatasetExportManifest
    public let receipt: GolfDatasetExportReceipt
}

public enum GolfResolvedLabelExportError: Error, Equatable, CustomStringConvertible {
    case validationFailed([GolfDatasetValidationError])
    case missingRegistry
    case emptyROIVersion
    case duplicateClipSelection(String)
    case missingClip(String)
    case missingPredictionRun(String)
    case missingRevision(String)
    case duplicateRevision(String)
    case predictionClipMismatch(String)
    case revisionClipMismatch(String)
    case revisionPredictionMismatch(String)
    case revisionNotCompleted(String)
    case roiVersionMismatch(expected: String, actual: String)
    case incompletePPointTruth(String)
    case duplicatePPointStage(clipID: String, stage: GolfPPointStage)
    case pPointFrameOutOfRange(clipID: String, sourceFrameIndex: Int)
    case duplicateFrameMetadata(clipID: String, sourceFrameIndex: Int)
    case missingPredictionFrame(clipID: String, sourceFrameIndex: Int)
    case resolvedFrameSetMismatch(
        clipID: String,
        expected: [Int],
        actual: [Int]
    )
    case invalidOrientedDimensions(clipID: String, width: Int, height: Int)
    case trainingInputTransformOverflow(
        clipID: String,
        width: Int,
        height: Int
    )

    public var description: String {
        switch self {
        case .validationFailed(let errors):
            return "Dataset validation failed: \(errors.map(\.description).joined(separator: "; "))"
        case .missingRegistry:
            return "Dataset registry is required for export"
        case .emptyROIVersion:
            return "Selected ROI algorithm version cannot be empty"
        case .duplicateClipSelection(let clipID):
            return "Duplicate export selection for clip \(clipID)"
        case .missingClip(let clipID):
            return "Missing selected clip \(clipID)"
        case .missingPredictionRun(let predictionRunID):
            return "Missing selected prediction run \(predictionRunID)"
        case .missingRevision(let revisionID):
            return "Missing selected revision \(revisionID)"
        case .duplicateRevision(let revisionID):
            return "Selected revision \(revisionID) is not unique within its clip"
        case .predictionClipMismatch(let predictionRunID):
            return "Prediction run \(predictionRunID) does not belong to its selected clip"
        case .revisionClipMismatch(let revisionID):
            return "Revision \(revisionID) does not belong to its selected clip"
        case .revisionPredictionMismatch(let revisionID):
            return "Revision \(revisionID) does not reference its selected prediction run"
        case .revisionNotCompleted(let revisionID):
            return "Revision \(revisionID) is not completed"
        case .roiVersionMismatch(let expected, let actual):
            return "ROI algorithm version mismatch: expected \(expected), got \(actual)"
        case .incompletePPointTruth(let clipID):
            return "Clip \(clipID) must carry exactly one source frame for every P1-P8 stage"
        case .duplicatePPointStage(let clipID, let stage):
            return "Clip \(clipID) has duplicate \(stage.rawValue) truth"
        case .pPointFrameOutOfRange(let clipID, let sourceFrameIndex):
            return "Clip \(clipID) P-point frame \(sourceFrameIndex) is out of range"
        case .duplicateFrameMetadata(let clipID, let sourceFrameIndex):
            return "Clip \(clipID) has duplicate metadata for frame \(sourceFrameIndex)"
        case .missingPredictionFrame(let clipID, let sourceFrameIndex):
            return "Clip \(clipID) has no unique prediction frame at \(sourceFrameIndex)"
        case .resolvedFrameSetMismatch(let clipID, let expected, let actual):
            return "Clip \(clipID) resolved frame set \(actual) does not match " +
                "P1-P8 truth frame set \(expected)"
        case .invalidOrientedDimensions(let clipID, let width, let height):
            return "Clip \(clipID) has invalid oriented dimensions \(width)x\(height)"
        case .trainingInputTransformOverflow(let clipID, let width, let height):
            return "Clip \(clipID) oriented dimensions \(width)x\(height) " +
                "overflow full-frame input transform arithmetic"
        }
    }
}

public enum GolfResolvedLabelExporter {
    public static func export(
        snapshot: GolfDatasetSnapshot,
        selection: GolfDatasetExportSelection,
        to outputDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> GolfDatasetExportResult {
        let validationErrors = GolfDatasetValidator.validate(snapshot: snapshot)
        guard validationErrors.isEmpty else {
            throw GolfResolvedLabelExportError.validationFailed(validationErrors)
        }
        guard let registry = snapshot.registry else {
            throw GolfResolvedLabelExportError.missingRegistry
        }
        guard !selection.roiAlgorithmVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GolfResolvedLabelExportError.emptyROIVersion
        }

        let selectionGroups = Dictionary(grouping: selection.clips, by: \.clipID)
        if let duplicate = selectionGroups.keys.sorted().first(where: {
            (selectionGroups[$0]?.count ?? 0) > 1
        }) {
            throw GolfResolvedLabelExportError.duplicateClipSelection(duplicate)
        }

        var resolvedClips: [GolfResolvedClip] = []
        var manifestClips: [GolfDatasetManifestClip] = []

        for selected in selection.clips.sorted(by: { $0.clipID < $1.clipID }) {
            guard let clip = snapshot.clips.first(where: { $0.clipID == selected.clipID }) else {
                throw GolfResolvedLabelExportError.missingClip(selected.clipID)
            }
            guard let prediction = snapshot.predictions.first(where: {
                $0.predictionRunID == selected.predictionRunID
            }) else {
                throw GolfResolvedLabelExportError.missingPredictionRun(selected.predictionRunID)
            }
            let matchingRevisions = snapshot.revisions.filter {
                $0.revisionID == selected.revisionID && $0.clipID == selected.clipID
            }
            guard !matchingRevisions.isEmpty else {
                throw GolfResolvedLabelExportError.missingRevision(selected.revisionID)
            }
            guard matchingRevisions.count == 1, let revision = matchingRevisions.first else {
                throw GolfResolvedLabelExportError.duplicateRevision(selected.revisionID)
            }
            guard prediction.clipID == clip.clipID else {
                throw GolfResolvedLabelExportError.predictionClipMismatch(prediction.predictionRunID)
            }
            guard revision.clipID == clip.clipID else {
                throw GolfResolvedLabelExportError.revisionClipMismatch(revision.revisionID)
            }
            guard revision.parentPredictionRunID == prediction.predictionRunID else {
                throw GolfResolvedLabelExportError.revisionPredictionMismatch(revision.revisionID)
            }
            guard let revisionCompletedAt = revision.completedAt else {
                throw GolfResolvedLabelExportError.revisionNotCompleted(revision.revisionID)
            }
            guard prediction.roiAlgorithmVersion == selection.roiAlgorithmVersion else {
                throw GolfResolvedLabelExportError.roiVersionMismatch(
                    expected: selection.roiAlgorithmVersion,
                    actual: prediction.roiAlgorithmVersion
                )
            }
            guard let golfer = registry.golfers.first(where: { $0.golferID == clip.golferID }) else {
                throw GolfResolvedLabelExportError.missingRegistry
            }

            let orderedTruth = try canonicalPPointTruth(selected.pPointTruth, for: clip)
            let expectedFrameIndexes = Set(
                orderedTruth.map(\.sourceFrameIndex)
            )
            let actualFrameIndexes = Set(
                revision.frameRevisions.map(\.sourceFrameIndex)
            )
            guard actualFrameIndexes == expectedFrameIndexes else {
                throw GolfResolvedLabelExportError.resolvedFrameSetMismatch(
                    clipID: clip.clipID,
                    expected: expectedFrameIndexes.sorted(),
                    actual: actualFrameIndexes.sorted()
                )
            }
            let metadata = try canonicalFrameMetadata(selected.frameMetadata, clipID: clip.clipID)
            let predictionFrameGroups = Dictionary(
                grouping: prediction.frames,
                by: \.sourceFrameIndex
            )
            var frames: [GolfResolvedFrameLabel] = []

            for frameRevision in revision.frameRevisions.sorted(by: {
                $0.sourceFrameIndex < $1.sourceFrameIndex
            }) {
                let predictionFrames = predictionFrameGroups[frameRevision.sourceFrameIndex] ?? []
                guard predictionFrames.count == 1, let predictionFrame = predictionFrames.first else {
                    throw GolfResolvedLabelExportError.missingPredictionFrame(
                        clipID: clip.clipID,
                        sourceFrameIndex: frameRevision.sourceFrameIndex
                    )
                }
                let decisions = Dictionary(
                    uniqueKeysWithValues: frameRevision.decisions.map { ($0.landmark, $0) }
                )
                var landmarks: [GolfResolvedLandmark] = []
                for landmark in GolfLandmark.allCases {
                    guard let decision = decisions[landmark] else { continue }
                    if let resolved = try decision.resolvedLandmark(
                        prediction: predictionFrame.points[landmark]
                    ) {
                        landmarks.append(resolved)
                    }
                }
                frames.append(GolfResolvedFrameLabel(
                    sourceFrameIndex: frameRevision.sourceFrameIndex,
                    sourceTime: predictionFrame.sourceTime,
                    queueReasons: metadata[frameRevision.sourceFrameIndex] ?? [],
                    annotationROITransform: predictionFrame.roiTransform,
                    landmarks: GolfResolvedLandmarkCollection(landmarks)
                ))
            }

            let trainingInputTransform: GolfTrainingInputTransform
            do {
                trainingInputTransform = try GolfTrainingInputTransform(
                    sourceOrientedWidth: clip.media.orientedWidth,
                    sourceOrientedHeight: clip.media.orientedHeight
                )
            } catch GolfTrainingInputTransformError.invalidDimensions {
                throw GolfResolvedLabelExportError.invalidOrientedDimensions(
                    clipID: clip.clipID,
                    width: clip.media.orientedWidth,
                    height: clip.media.orientedHeight
                )
            } catch GolfTrainingInputTransformError.arithmeticOverflow {
                throw GolfResolvedLabelExportError
                    .trainingInputTransformOverflow(
                        clipID: clip.clipID,
                        width: clip.media.orientedWidth,
                        height: clip.media.orientedHeight
                    )
            }
            let resolvedClip = GolfResolvedClip(
                clipID: clip.clipID,
                golferID: clip.golferID,
                split: golfer.split,
                view: clip.view,
                handedness: clip.handedness,
                authorization: clip.authorization,
                fileName: clip.media.fileName,
                frameCount: clip.media.frameCount,
                orientedWidth: clip.media.orientedWidth,
                orientedHeight: clip.media.orientedHeight,
                sourceTimescale: clip.media.sourceTimescale,
                mediaSHA256: clip.media.sha256,
                timelineSHA256: clip.media.timelineSHA256,
                pPointTruthSHA256: clip.pPointTruthSHA256,
                predictionRunID: prediction.predictionRunID,
                revisionID: revision.revisionID,
                revisionCompletedAt: revisionCompletedAt,
                trainingInputTransform: trainingInputTransform,
                pPointTruth: orderedTruth,
                frames: frames
            )
            resolvedClips.append(resolvedClip)
            manifestClips.append(GolfDatasetManifestClip(
                clipID: clip.clipID,
                golferID: clip.golferID,
                split: golfer.split,
                view: clip.view,
                handedness: clip.handedness,
                predictionRunID: prediction.predictionRunID,
                revisionID: revision.revisionID,
                revisionCompletedAt: revisionCompletedAt,
                authorization: clip.authorization,
                fileName: clip.media.fileName,
                frameCount: clip.media.frameCount,
                orientedWidth: clip.media.orientedWidth,
                orientedHeight: clip.media.orientedHeight,
                sourceTimescale: clip.media.sourceTimescale,
                mediaSHA256: clip.media.sha256,
                timelineSHA256: clip.media.timelineSHA256,
                pPointTruthSHA256: clip.pPointTruthSHA256,
                predictionProvenanceHash: prediction.provenanceHash,
                resolvedFrameCount: frames.count,
                trainingInputTransformSHA256: sha256(
                    Data(trainingInputTransform.canonicalIdentity.utf8)
                )
            ))
        }

        let selectedGolferIDs = Set(resolvedClips.map(\.golferID))
        let golferGroups = Dictionary(grouping: registry.golfers, by: \.golferID)
        let golfers = selectedGolferIDs.sorted().compactMap { golferID in
            golferGroups[golferID]?.first.map {
                GolfResolvedGolfer(golferID: $0.golferID, split: $0.split)
            }
        }
        let dataset = GolfResolvedDataset(
            schemaVersion: 2,
            datasetID: registry.datasetID,
            roiAlgorithmVersion: selection.roiAlgorithmVersion,
            inputTransformVersion: GolfTrainingInputTransform.version,
            inputWidth: GolfTrainingInputTransform.canvasSize,
            inputHeight: GolfTrainingInputTransform.canvasSize,
            golfers: golfers,
            clips: resolvedClips
        )
        let encoder = canonicalEncoder()
        let resolvedLabelsData = try encoder.encode(dataset)
        let manifest = GolfDatasetExportManifest(
            schemaVersion: 2,
            datasetID: registry.datasetID,
            roiAlgorithmVersion: selection.roiAlgorithmVersion,
            inputTransformVersion: GolfTrainingInputTransform.version,
            inputWidth: GolfTrainingInputTransform.canvasSize,
            inputHeight: GolfTrainingInputTransform.canvasSize,
            resolvedLabelsFile: "resolved-labels.json",
            resolvedLabelsSHA256: sha256(resolvedLabelsData),
            clips: manifestClips
        )
        let manifestData = try encoder.encode(manifest)

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let resolvedLabelsURL = outputDirectory.appendingPathComponent("resolved-labels.json")
        let manifestURL = outputDirectory.appendingPathComponent("manifest.json")
        try resolvedLabelsData.write(to: resolvedLabelsURL, options: .atomic)
        try manifestData.write(to: manifestURL, options: .atomic)

        return GolfDatasetExportResult(
            dataset: dataset,
            manifest: manifest,
            receipt: GolfDatasetExportReceipt(
                manifestSHA256: sha256(manifestData),
                resolvedLabelsURL: resolvedLabelsURL,
                manifestURL: manifestURL
            )
        )
    }

    private static func canonicalPPointTruth(
        _ truth: [GolfPPointFrameTruth],
        for clip: GolfClipIdentity
    ) throws -> [GolfPPointFrameTruth] {
        let groups = Dictionary(grouping: truth, by: \.stage)
        for stage in GolfPPointStage.allCases where (groups[stage]?.count ?? 0) > 1 {
            throw GolfResolvedLabelExportError.duplicatePPointStage(
                clipID: clip.clipID,
                stage: stage
            )
        }
        guard GolfPPointStage.allCases.allSatisfy({ groups[$0]?.count == 1 }),
              truth.count == GolfPPointStage.allCases.count else {
            throw GolfResolvedLabelExportError.incompletePPointTruth(clip.clipID)
        }
        let ordered = GolfPPointStage.allCases.compactMap { groups[$0]?.first }
        for item in ordered
        where item.sourceFrameIndex < 0 || item.sourceFrameIndex >= clip.media.frameCount {
            throw GolfResolvedLabelExportError.pPointFrameOutOfRange(
                clipID: clip.clipID,
                sourceFrameIndex: item.sourceFrameIndex
            )
        }
        return ordered
    }

    private static func canonicalFrameMetadata(
        _ metadata: [GolfExportFrameMetadata],
        clipID: String
    ) throws -> [Int: [String]] {
        let groups = Dictionary(grouping: metadata, by: \.sourceFrameIndex)
        if let duplicate = groups.keys.sorted().first(where: {
            (groups[$0]?.count ?? 0) > 1
        }) {
            throw GolfResolvedLabelExportError.duplicateFrameMetadata(
                clipID: clipID,
                sourceFrameIndex: duplicate
            )
        }
        return Dictionary(uniqueKeysWithValues: metadata.map {
            ($0.sourceFrameIndex, Array(Set($0.queueReasons)).sorted())
        })
    }

    private static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

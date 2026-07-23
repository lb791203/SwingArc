import Foundation

enum DatasetView: String, Codable {
    case downTheLine = "dtl"
    case faceOn = "face-on"
}

enum DatasetHandedness: String, Codable {
    case left
    case right
}

enum DatasetSplit: String, Codable {
    case development
    case training
    case validation
    case heldOut = "held-out"
}

enum VideoAuthorization: String, Codable {
    case internalReview = "internal-review"
    case trainingAllowed = "training-allowed"
}

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
    let golferID: String?
    let fileName: String
    let view: DatasetView?
    let handedness: DatasetHandedness?
    let split: DatasetSplit
    let authorization: VideoAuthorization
    let sourceFrameRate: Double
    let duration: Double
    let sourceWidth: Int?
    let sourceHeight: Int?
    let annotationPasses: Int
    let stages: [PrecisionStageLabel]
    let frameLabels: [PrecisionFrameLabel]

    init(
        clipID: String,
        golferID: String?,
        fileName: String,
        view: DatasetView?,
        handedness: DatasetHandedness?,
        split: DatasetSplit,
        authorization: VideoAuthorization,
        sourceFrameRate: Double,
        duration: Double,
        annotationPasses: Int,
        stages: [PrecisionStageLabel],
        frameLabels: [PrecisionFrameLabel],
        sourceWidth: Int? = nil,
        sourceHeight: Int? = nil
    ) {
        self.clipID = clipID
        self.golferID = golferID
        self.fileName = fileName
        self.view = view
        self.handedness = handedness
        self.split = split
        self.authorization = authorization
        self.sourceFrameRate = sourceFrameRate
        self.duration = duration
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.annotationPasses = annotationPasses
        self.stages = stages
        self.frameLabels = frameLabels
    }
}

enum PrecisionManifestError: Equatable {
    case duplicateClipID(String)
    case golferSplitLeak(String)
    case missingRequiredMetadata(clipID: String, field: String)
    case missingDoublePass(String)
    case stageMissingDoublePass(clipID: String, stage: String)
    case stageNeedsAdjudication(clipID: String, stage: String)
    case invalidStageOrder(String)
    case trainingNotAuthorized(String)
    case unreviewedTrainingLabel(clipID: String, sourceFrameIndex: Int)
}

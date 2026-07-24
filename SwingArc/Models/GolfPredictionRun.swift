import Foundation

public struct GolfROIAffineTransform: Codable, Equatable, Sendable, Hashable {
    public let a: Double
    public let b: Double
    public let c: Double
    public let d: Double
    public let tx: Double
    public let ty: Double

    public let invA: Double
    public let invB: Double
    public let invC: Double
    public let invD: Double
    public let invTx: Double
    public let invTy: Double

    public init(
        a: Double,
        b: Double,
        c: Double,
        d: Double,
        tx: Double,
        ty: Double,
        invA: Double,
        invB: Double,
        invC: Double,
        invD: Double,
        invTx: Double,
        invTy: Double
    ) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty

        self.invA = invA
        self.invB = invB
        self.invC = invC
        self.invD = invD
        self.invTx = invTx
        self.invTy = invTy
    }

    public func fullFramePointToROI(_ point: NormalizedPoint) -> NormalizedPoint {
        let x = a * point.x + c * point.y + tx
        let y = b * point.x + d * point.y + ty
        return NormalizedPoint(x: x, y: y)
    }

    public func roiPointToFullFrame(_ point: NormalizedPoint) -> NormalizedPoint {
        let x = invA * point.x + invC * point.y + invTx
        let y = invB * point.x + invD * point.y + invTy
        return NormalizedPoint(x: x, y: y)
    }
}

public struct GolfPredictionPoint: Codable, Equatable, Sendable, Hashable {
    public let roiX: Double
    public let roiY: Double
    public let heatmapConfidence: Double
    public let heatmapDispersion: Double
    public let visibilityProbabilities: [Double]
    public let preTrackingFullFramePoint: NormalizedPoint?
    public let postTrackingFullFramePoint: NormalizedPoint?
    public let trackingStatus: String?
    public let anomalyReason: String?

    public var resolvedFullFramePoint: NormalizedPoint? {
        postTrackingFullFramePoint ?? preTrackingFullFramePoint
    }

    public var fullFramePoint: NormalizedPoint? {
        resolvedFullFramePoint
    }

    public init(
        roiX: Double,
        roiY: Double,
        heatmapConfidence: Double,
        heatmapDispersion: Double,
        visibilityProbabilities: [Double],
        preTrackingFullFramePoint: NormalizedPoint? = nil,
        postTrackingFullFramePoint: NormalizedPoint? = nil,
        trackingStatus: String? = nil,
        anomalyReason: String? = nil
    ) {
        self.roiX = roiX
        self.roiY = roiY
        self.heatmapConfidence = heatmapConfidence
        self.heatmapDispersion = heatmapDispersion
        self.visibilityProbabilities = visibilityProbabilities
        self.preTrackingFullFramePoint = preTrackingFullFramePoint
        self.postTrackingFullFramePoint = postTrackingFullFramePoint
        self.trackingStatus = trackingStatus
        self.anomalyReason = anomalyReason
    }
}

public struct GolfPredictionFrame: Codable, Equatable, Sendable, Hashable {
    public let sourceFrameIndex: Int
    public let sourceTime: Double
    public let roiTransform: GolfROIAffineTransform
    public let points: [GolfLandmark: GolfPredictionPoint]
    public let anomalyReason: String?

    public init(
        sourceFrameIndex: Int,
        sourceTime: Double,
        roiTransform: GolfROIAffineTransform,
        points: [GolfLandmark: GolfPredictionPoint],
        anomalyReason: String? = nil
    ) {
        self.sourceFrameIndex = sourceFrameIndex
        self.sourceTime = sourceTime
        self.roiTransform = roiTransform
        self.points = points
        self.anomalyReason = anomalyReason
    }
}

public struct GolfPredictionRun: Codable, Equatable, Sendable, Hashable {
    public let schemaVersion: Int
    public let predictionRunID: String
    public let clipID: String
    public let mediaSHA256: String
    public let timelineSHA256: String
    public let visionFrameworkVersion: String
    public let visionRequestVersion: String
    public let roiAlgorithmVersion: String
    public let roiConfigSHA256: String
    public let modelSHA256: String
    public let decoderVersion: String
    public let trackerVersion: String
    public let createdAt: Date
    public let frames: [GolfPredictionFrame]
    public let provenanceHash: String

    public init(
        schemaVersion: Int = 1,
        predictionRunID: String,
        clipID: String,
        mediaSHA256: String,
        timelineSHA256: String,
        visionFrameworkVersion: String,
        visionRequestVersion: String,
        roiAlgorithmVersion: String,
        roiConfigSHA256: String,
        modelSHA256: String,
        decoderVersion: String,
        trackerVersion: String,
        createdAt: Date,
        frames: [GolfPredictionFrame],
        provenanceHash: String
    ) {
        self.schemaVersion = schemaVersion
        self.predictionRunID = predictionRunID
        self.clipID = clipID
        self.mediaSHA256 = mediaSHA256
        self.timelineSHA256 = timelineSHA256
        self.visionFrameworkVersion = visionFrameworkVersion
        self.visionRequestVersion = visionRequestVersion
        self.roiAlgorithmVersion = roiAlgorithmVersion
        self.roiConfigSHA256 = roiConfigSHA256
        self.modelSHA256 = modelSHA256
        self.decoderVersion = decoderVersion
        self.trackerVersion = trackerVersion
        self.createdAt = createdAt
        self.frames = frames
        self.provenanceHash = provenanceHash
    }
}

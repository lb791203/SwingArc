import Foundation

public enum GolfPredictionRunKind: String, Codable, Equatable, Sendable, Hashable {
    case modelInference
    case manualBootstrap
}

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

    public func fullFramePointToROI(_ point: GolfNormalizedPoint) -> GolfNormalizedPoint {
        let x = a * point.x + c * point.y + tx
        let y = b * point.x + d * point.y + ty
        return GolfNormalizedPoint(x: x, y: y)
    }

    public func roiPointToFullFrame(_ point: GolfNormalizedPoint) -> GolfNormalizedPoint {
        let x = invA * point.x + invC * point.y + invTx
        let y = invB * point.x + invD * point.y + invTy
        return GolfNormalizedPoint(x: x, y: y)
    }
}

public struct GolfPredictionPoint: Codable, Equatable, Sendable, Hashable {
    public let roiX: Double
    public let roiY: Double
    public let heatmapConfidence: Double
    public let heatmapDispersion: Double
    public let visibilityProbabilities: [Double]
    public let preTrackingFullFramePoint: GolfNormalizedPoint?
    public let postTrackingFullFramePoint: GolfNormalizedPoint?
    public let trackingStatus: String?
    public let anomalyReason: String?

    public var resolvedFullFramePoint: GolfNormalizedPoint? {
        postTrackingFullFramePoint ?? preTrackingFullFramePoint
    }

    public var fullFramePoint: GolfNormalizedPoint? {
        resolvedFullFramePoint
    }

    public init(
        roiX: Double,
        roiY: Double,
        heatmapConfidence: Double,
        heatmapDispersion: Double,
        visibilityProbabilities: [Double],
        preTrackingFullFramePoint: GolfNormalizedPoint? = nil,
        postTrackingFullFramePoint: GolfNormalizedPoint? = nil,
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

public struct GolfManualBootstrapAnchorReference:
    Codable, Equatable, Sendable, Hashable
{
    public let anchorID: String
    public let sourceFrameIndex: Int
    public let candidateIndex: Int
    public let normalizedClickX: Double
    public let normalizedClickY: Double

    public init(
        anchorID: String,
        sourceFrameIndex: Int,
        candidateIndex: Int,
        normalizedClickX: Double,
        normalizedClickY: Double
    ) {
        self.anchorID = anchorID
        self.sourceFrameIndex = sourceFrameIndex
        self.candidateIndex = candidateIndex
        self.normalizedClickX = normalizedClickX
        self.normalizedClickY = normalizedClickY
    }
}

public enum GolfManualBootstrapProvenance {
    public static func canonicalString(
        clipID: String,
        mediaSHA256: String,
        timelineSHA256: String,
        anchors: [GolfManualBootstrapAnchorReference],
        visionFrameworkVersion: String,
        visionRequestVersion: String,
        roiAlgorithmVersion: String,
        roiConfigSHA256: String,
        decoderVersion: String,
        trackerVersion: String,
        frames: [GolfPredictionFrame]
    ) -> String {
        var components: [String] = [
            "clipID:\(clipID)",
            "mediaSHA256:\(mediaSHA256)",
            "timelineSHA256:\(timelineSHA256)"
        ]
        for anchor in anchors.sorted(by: {
            if $0.sourceFrameIndex != $1.sourceFrameIndex {
                return $0.sourceFrameIndex < $1.sourceFrameIndex
            }
            return $0.anchorID < $1.anchorID
        }) {
            components.append(
                "anchor:\(anchor.anchorID):\(anchor.sourceFrameIndex):" +
                    "\(anchor.candidateIndex):\(anchor.normalizedClickX):" +
                    "\(anchor.normalizedClickY)"
            )
        }
        components.append("visionFramework:\(visionFrameworkVersion)")
        components.append("visionRequest:\(visionRequestVersion)")
        components.append("roiAlgorithm:\(roiAlgorithmVersion)")
        components.append("roiConfigSHA256:\(roiConfigSHA256)")
        components.append("decoder:\(decoderVersion)")
        components.append("tracker:\(trackerVersion)")
        for frame in frames {
            let t = frame.roiTransform
            components.append(
                "frame:\(frame.sourceFrameIndex):\(frame.sourceTime):" +
                    "\(t.a):\(t.b):\(t.c):\(t.d):\(t.tx):\(t.ty):" +
                    "\(t.invA):\(t.invB):\(t.invC):\(t.invD):" +
                    "\(t.invTx):\(t.invTy)"
            )
        }
        return components.joined(separator: "\n")
    }
}

public struct GolfPredictionRun: Codable, Equatable, Sendable, Hashable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let runKind: GolfPredictionRunKind
    public let predictionRunID: String
    public let clipID: String
    public let mediaSHA256: String
    public let timelineSHA256: String
    public let visionFrameworkVersion: String
    public let visionRequestVersion: String
    public let roiAlgorithmVersion: String
    public let roiConfigSHA256: String
    public let modelSHA256: String?
    public let decoderVersion: String
    public let trackerVersion: String
    public let createdAt: Date
    public let frames: [GolfPredictionFrame]
    public let manualBootstrapAnchors: [GolfManualBootstrapAnchorReference]
    public let provenanceHash: String

    public init(
        schemaVersion: Int = 2,
        runKind: GolfPredictionRunKind = .modelInference,
        predictionRunID: String,
        clipID: String,
        mediaSHA256: String,
        timelineSHA256: String,
        visionFrameworkVersion: String,
        visionRequestVersion: String,
        roiAlgorithmVersion: String,
        roiConfigSHA256: String,
        modelSHA256: String?,
        decoderVersion: String,
        trackerVersion: String,
        createdAt: Date,
        frames: [GolfPredictionFrame],
        manualBootstrapAnchors: [GolfManualBootstrapAnchorReference] = [],
        provenanceHash: String
    ) {
        self.schemaVersion = schemaVersion
        self.runKind = runKind
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
        self.manualBootstrapAnchors = manualBootstrapAnchors
        self.provenanceHash = provenanceHash
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runKind
        case predictionRunID
        case clipID
        case mediaSHA256
        case timelineSHA256
        case visionFrameworkVersion
        case visionRequestVersion
        case roiAlgorithmVersion
        case roiConfigSHA256
        case modelSHA256
        case decoderVersion
        case trackerVersion
        case createdAt
        case frames
        case manualBootstrapAnchors
        case provenanceHash
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.runKind = try container.decodeIfPresent(GolfPredictionRunKind.self, forKey: .runKind) ?? .modelInference
        self.predictionRunID = try container.decode(String.self, forKey: .predictionRunID)
        self.clipID = try container.decode(String.self, forKey: .clipID)
        self.mediaSHA256 = try container.decode(String.self, forKey: .mediaSHA256)
        self.timelineSHA256 = try container.decode(String.self, forKey: .timelineSHA256)
        self.visionFrameworkVersion = try container.decode(String.self, forKey: .visionFrameworkVersion)
        self.visionRequestVersion = try container.decode(String.self, forKey: .visionRequestVersion)
        self.roiAlgorithmVersion = try container.decode(String.self, forKey: .roiAlgorithmVersion)
        self.roiConfigSHA256 = try container.decode(String.self, forKey: .roiConfigSHA256)
        self.modelSHA256 = try container.decodeIfPresent(String.self, forKey: .modelSHA256)
        self.decoderVersion = try container.decode(String.self, forKey: .decoderVersion)
        self.trackerVersion = try container.decode(String.self, forKey: .trackerVersion)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.frames = try container.decode([GolfPredictionFrame].self, forKey: .frames)
        self.manualBootstrapAnchors = try container.decodeIfPresent(
            [GolfManualBootstrapAnchorReference].self,
            forKey: .manualBootstrapAnchors
        ) ?? []
        self.provenanceHash = try container.decode(String.self, forKey: .provenanceHash)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(runKind, forKey: .runKind)
        try container.encode(predictionRunID, forKey: .predictionRunID)
        try container.encode(clipID, forKey: .clipID)
        try container.encode(mediaSHA256, forKey: .mediaSHA256)
        try container.encode(timelineSHA256, forKey: .timelineSHA256)
        try container.encode(visionFrameworkVersion, forKey: .visionFrameworkVersion)
        try container.encode(visionRequestVersion, forKey: .visionRequestVersion)
        try container.encode(roiAlgorithmVersion, forKey: .roiAlgorithmVersion)
        try container.encode(roiConfigSHA256, forKey: .roiConfigSHA256)
        try container.encode(modelSHA256, forKey: .modelSHA256)
        try container.encode(decoderVersion, forKey: .decoderVersion)
        try container.encode(trackerVersion, forKey: .trackerVersion)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(frames, forKey: .frames)
        try container.encode(
            manualBootstrapAnchors,
            forKey: .manualBootstrapAnchors
        )
        try container.encode(provenanceHash, forKey: .provenanceHash)
    }

    public static func == (lhs: GolfPredictionRun, rhs: GolfPredictionRun) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion &&
        lhs.runKind == rhs.runKind &&
        lhs.predictionRunID == rhs.predictionRunID &&
        lhs.clipID == rhs.clipID &&
        lhs.mediaSHA256 == rhs.mediaSHA256 &&
        lhs.timelineSHA256 == rhs.timelineSHA256 &&
        lhs.visionFrameworkVersion == rhs.visionFrameworkVersion &&
        lhs.visionRequestVersion == rhs.visionRequestVersion &&
        lhs.roiAlgorithmVersion == rhs.roiAlgorithmVersion &&
        lhs.roiConfigSHA256 == rhs.roiConfigSHA256 &&
        lhs.modelSHA256 == rhs.modelSHA256 &&
        lhs.decoderVersion == rhs.decoderVersion &&
        lhs.trackerVersion == rhs.trackerVersion &&
        (
            lhs.runKind == .manualBootstrap ||
                Int(lhs.createdAt.timeIntervalSince1970) ==
                Int(rhs.createdAt.timeIntervalSince1970)
        ) &&
        lhs.frames == rhs.frames &&
        lhs.manualBootstrapAnchors == rhs.manualBootstrapAnchors &&
        lhs.provenanceHash == rhs.provenanceHash
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(schemaVersion)
        hasher.combine(runKind)
        hasher.combine(predictionRunID)
        hasher.combine(clipID)
        hasher.combine(mediaSHA256)
        hasher.combine(timelineSHA256)
        hasher.combine(visionFrameworkVersion)
        hasher.combine(visionRequestVersion)
        hasher.combine(roiAlgorithmVersion)
        hasher.combine(roiConfigSHA256)
        hasher.combine(modelSHA256)
        hasher.combine(decoderVersion)
        hasher.combine(trackerVersion)
        if runKind != .manualBootstrap {
            hasher.combine(Int(createdAt.timeIntervalSince1970))
        }
        hasher.combine(frames)
        hasher.combine(manualBootstrapAnchors)
        hasher.combine(provenanceHash)
    }
}

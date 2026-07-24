import Foundation

public struct GolfAxisAlignedRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var isEmpty: Bool { width <= 0 || height <= 0 }
}

public struct GolfPoseTrackFrame: Equatable, Sendable {
    public let sourceFrameIndex: Int
    public let sourceTime: Double
    public let bodyCenter: GolfNormalizedPoint
    public let bodyBounds: GolfAxisAlignedRect
    public let handCenter: GolfNormalizedPoint?
    public let identityConfidence: Double

    public init(
        sourceFrameIndex: Int,
        sourceTime: Double,
        bodyCenter: GolfNormalizedPoint,
        bodyBounds: GolfAxisAlignedRect,
        handCenter: GolfNormalizedPoint?,
        identityConfidence: Double
    ) {
        self.sourceFrameIndex = sourceFrameIndex
        self.sourceTime = sourceTime
        self.bodyCenter = bodyCenter
        self.bodyBounds = bodyBounds
        self.handCenter = handCenter
        self.identityConfidence = identityConfidence
    }
}

public struct StableSwingROIConfiguration: Equatable, Sendable {
    public let clubBallSafetyMarginFraction: Double
    public let framePaddingFraction: Double
    public let maxBidirectionalCorrectionFraction: Double
    public let version: String

    public static let v1 = StableSwingROIConfiguration(
        clubBallSafetyMarginFraction: 0.08,
        framePaddingFraction: 0.05,
        maxBidirectionalCorrectionFraction: 0.02,
        version: "roi-v1"
    )
}

public struct StableSwingROIFrame: Equatable, Sendable {
    public let sourceFrameIndex: Int
    public let sourceTime: Double
    public let transform: GolfROIAffineTransform
    public let cropRect: GolfAxisAlignedRect
    public let paddingLeft: Double
    public let paddingTop: Double
    public let paddingRight: Double
    public let paddingBottom: Double
    public let configurationVersion: String
    public let interpolated: Bool
    public let coverageOK: Bool
    public let qualityScore: Double

    public init(
        sourceFrameIndex: Int,
        sourceTime: Double,
        transform: GolfROIAffineTransform,
        cropRect: GolfAxisAlignedRect,
        paddingLeft: Double,
        paddingTop: Double,
        paddingRight: Double,
        paddingBottom: Double,
        configurationVersion: String,
        interpolated: Bool,
        coverageOK: Bool,
        qualityScore: Double
    ) {
        self.sourceFrameIndex = sourceFrameIndex
        self.sourceTime = sourceTime
        self.transform = transform
        self.cropRect = cropRect
        self.paddingLeft = paddingLeft
        self.paddingTop = paddingTop
        self.paddingRight = paddingRight
        self.paddingBottom = paddingBottom
        self.configurationVersion = configurationVersion
        self.interpolated = interpolated
        self.coverageOK = coverageOK
        self.qualityScore = qualityScore
    }
}

public struct StableSwingROITrack: Equatable, Sendable {
    public let frames: [StableSwingROIFrame]
    public let centerMovementP95InTargetPixels: Double
    public let configuration: StableSwingROIConfiguration

    public init(
        frames: [StableSwingROIFrame],
        centerMovementP95InTargetPixels: Double,
        configuration: StableSwingROIConfiguration
    ) {
        self.frames = frames
        self.centerMovementP95InTargetPixels = centerMovementP95InTargetPixels
        self.configuration = configuration
    }
}

public enum StableSwingROIError: Error, Equatable, CustomStringConvertible {
    case poseGapTooLong
    case identityUnstable
    case coverageFailed
    case nonMonotonicTime
    case invalidDimensions
    case duplicateFrameConflict(Int)

    public var description: String {
        switch self {
        case .poseGapTooLong:
            return "Pose gap exceeds 150ms interpolation limit"
        case .identityUnstable:
            return "Identity confidence below stability threshold"
        case .coverageFailed:
            return "Cannot cover body envelope with safety margins"
        case .nonMonotonicTime:
            return "Source timestamps are not monotonically increasing"
        case .invalidDimensions:
            return "Frame or target dimensions are invalid"
        case .duplicateFrameConflict(let index):
            return "Conflicting data for sourceFrameIndex \(index)"
        }
    }
}

import Foundation

public struct NormalizedPoint: Codable, Equatable, Sendable, Hashable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum GolfLandmark: String, Codable, Equatable, CaseIterable, Sendable, Hashable {
    case grip = "grip"
    case shaftStart = "shaftStart"
    case shaftEnd = "shaftEnd"
    case clubhead = "clubhead"
    case ball = "ball"
}

public enum GolfVisibilityClass: String, Codable, Equatable, CaseIterable, Sendable, Hashable {
    case visible = "visible"
    case occluded = "occluded"
    case outOfFrame = "out-of-frame"
}

public enum GolfAnnotationDecisionKind: String, Codable, Equatable, CaseIterable, Sendable, Hashable {
    case acceptedPrediction = "accepted-prediction"
    case correctedPoint = "corrected-point"
    case occluded = "occluded"
    case outOfFrame = "out-of-frame"
    case unresolved = "unresolved"
}

public enum GolfAnnotationContractError: Error, Equatable, CustomStringConvertible {
    case visiblePointMissingCoordinate
    case hiddenPointHasCoordinate
    case coordinateOutOfRange
    case missingAnnotator
    case unresolvedPointCannotBeResolved
    case missingParentPredictionRun

    public var description: String {
        switch self {
        case .visiblePointMissingCoordinate:
            return "Visible decisions require a valid normalized coordinate"
        case .hiddenPointHasCoordinate:
            return "Hidden decisions (occluded/out-of-frame/unresolved) cannot carry coordinates"
        case .coordinateOutOfRange:
            return "Coordinates must be finite numbers in range [0, 1]"
        case .missingAnnotator:
            return "Annotator ID cannot be empty or whitespace"
        case .unresolvedPointCannotBeResolved:
            return "Unresolved points cannot be converted to resolved landmarks"
        case .missingParentPredictionRun:
            return "Revision must specify a parent prediction run ID"
        }
    }
}

public struct GolfResolvedLandmark: Codable, Equatable, Sendable, Hashable {
    public let landmark: GolfLandmark
    public let visibility: GolfVisibilityClass
    public let point: NormalizedPoint?
    public let source: GolfAnnotationDecisionKind

    public init(
        landmark: GolfLandmark,
        visibility: GolfVisibilityClass,
        point: NormalizedPoint?,
        source: GolfAnnotationDecisionKind
    ) {
        self.landmark = landmark
        self.visibility = visibility
        self.point = point
        self.source = source
    }
}

public struct GolfAnnotationDecision: Codable, Equatable, Sendable, Hashable {
    public let landmark: GolfLandmark
    public let kind: GolfAnnotationDecisionKind
    public let fullFramePoint: NormalizedPoint?
    public let annotatorID: String
    public let decidedAt: Date

    public init(
        landmark: GolfLandmark,
        kind: GolfAnnotationDecisionKind,
        fullFramePoint: NormalizedPoint?,
        annotatorID: String,
        decidedAt: Date
    ) {
        self.landmark = landmark
        self.kind = kind
        self.fullFramePoint = fullFramePoint
        self.annotatorID = annotatorID
        self.decidedAt = decidedAt
    }

    public func validated() throws -> GolfAnnotationDecision {
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
    }

    public func resolvedLandmark(prediction: GolfPredictionPoint? = nil) throws -> GolfResolvedLandmark? {
        let validatedDecision = try self.validated()
        switch validatedDecision.kind {
        case .acceptedPrediction, .correctedPoint:
            return GolfResolvedLandmark(
                landmark: landmark,
                visibility: .visible,
                point: fullFramePoint,
                source: validatedDecision.kind
            )
        case .occluded:
            return GolfResolvedLandmark(
                landmark: landmark,
                visibility: .occluded,
                point: nil,
                source: .occluded
            )
        case .outOfFrame:
            return GolfResolvedLandmark(
                landmark: landmark,
                visibility: .outOfFrame,
                point: nil,
                source: .outOfFrame
            )
        case .unresolved:
            return nil
        }
    }
}

public struct GolfFrameRevision: Codable, Equatable, Sendable, Hashable {
    public let sourceFrameIndex: Int
    public let decisions: [GolfAnnotationDecision]

    public init(sourceFrameIndex: Int, decisions: [GolfAnnotationDecision]) {
        self.sourceFrameIndex = sourceFrameIndex
        self.decisions = decisions
    }
}

public struct GolfAnnotationRevision: Codable, Equatable, Sendable, Hashable {
    public let schemaVersion: Int
    public let revisionID: String
    public let clipID: String
    public let parentPredictionRunID: String
    public let annotatorID: String
    public let createdAt: Date
    public let completedAt: Date?
    public let frameRevisions: [GolfFrameRevision]
    public let notes: String?

    public init(
        schemaVersion: Int = 1,
        revisionID: String,
        clipID: String,
        parentPredictionRunID: String,
        annotatorID: String,
        createdAt: Date,
        completedAt: Date? = nil,
        frameRevisions: [GolfFrameRevision] = [],
        notes: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.revisionID = revisionID
        self.clipID = clipID
        self.parentPredictionRunID = parentPredictionRunID
        self.annotatorID = annotatorID
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.frameRevisions = frameRevisions
        self.notes = notes
    }
}

import Foundation

public struct GolfSubjectAnchorDecision: Codable, Equatable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let anchorID: String
    public let clipID: String
    public let mediaSHA256: String
    public let timelineSHA256: String
    public let sourceFrameIndex: Int
    public let candidateIndex: Int
    public let normalizedClickPoint: GolfNormalizedPoint
    public let visionFrameworkVersion: String
    public let visionRequestRevision: String
    public let annotatorID: String
    public let decidedAt: Date

    public init(
        schemaVersion: Int = 1,
        anchorID: String,
        clipID: String,
        mediaSHA256: String,
        timelineSHA256: String,
        sourceFrameIndex: Int,
        candidateIndex: Int,
        normalizedClickPoint: GolfNormalizedPoint,
        visionFrameworkVersion: String,
        visionRequestRevision: String,
        annotatorID: String,
        decidedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.anchorID = anchorID
        self.clipID = clipID
        self.mediaSHA256 = mediaSHA256
        self.timelineSHA256 = timelineSHA256
        self.sourceFrameIndex = sourceFrameIndex
        self.candidateIndex = candidateIndex
        self.normalizedClickPoint = normalizedClickPoint
        self.visionFrameworkVersion = visionFrameworkVersion
        self.visionRequestRevision = visionRequestRevision
        self.annotatorID = annotatorID
        self.decidedAt = decidedAt
    }
}

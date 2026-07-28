import Foundation

enum AnnotationView: String, Codable, CaseIterable {
    case downTheLine = "dtl"
    case faceOn = "face-on"
}

enum AnnotationHandedness: String, Codable, CaseIterable {
    case left
    case right
}

enum AnnotationAuthorization: String, Codable, CaseIterable {
    case internalReview = "internal-review"
    case trainingAllowed = "training-allowed"
}

enum AnnotationSplit: String, Codable, CaseIterable {
    case development
    case training
    case validation
    case heldOut = "held-out"
}

enum AnnotationVisibility: String, Codable, CaseIterable {
    case visible
    case occluded
    case outOfFrame = "out-of-frame"
    case unresolved
}

enum AnnotationPointSource: String, Codable {
    case predicted
    case manual
}

enum AnnotationStageStatus: String, Codable {
    case predicted
    case manual
    case unresolved
}

struct AnnotationMediaIdentity: Codable, Equatable {
    let fileName: String
    let sha256: String
    let timelineSHA256: String
    let frameCount: Int
    let width: Int
    let height: Int
}

struct AnnotationClipMetadata: Codable, Equatable {
    let clipID: String
    let golferID: String
    let view: AnnotationView
    let handedness: AnnotationHandedness
    let authorization: AnnotationAuthorization
    let split: AnnotationSplit
}

struct AnnotationPoint: Codable, Equatable {
    var x: Double?
    var y: Double?
    var visibility: AnnotationVisibility
    var source: AnnotationPointSource
    var confidence: Double?

    var isEligibleForCoordinateTraining: Bool {
        guard visibility == .visible,
              source == .manual,
              let x,
              let y else { return false }
        return (0...1).contains(x) && (0...1).contains(y)
    }
}

struct AnnotationFrameLabel: Codable, Equatable {
    let sourceFrameIndex: Int
    var landmarks: [String: AnnotationPoint]
    var reviewerID: String?
    var reviewed: Bool
}

struct AnnotationStageSelection: Codable, Equatable {
    let stage: String
    var sourceFrameIndex: Int?
    var suggestedSourceFrameIndex: Int?
    var suggestedRangeStart: Int?
    var suggestedRangeEnd: Int?
    var status: AnnotationStageStatus
    var note: String?

    init(
        stage: String,
        sourceFrameIndex: Int?,
        suggestedSourceFrameIndex: Int? = nil,
        suggestedRangeStart: Int? = nil,
        suggestedRangeEnd: Int? = nil,
        status: AnnotationStageStatus,
        note: String?
    ) {
        self.stage = stage
        self.sourceFrameIndex = sourceFrameIndex
        self.suggestedSourceFrameIndex = suggestedSourceFrameIndex
        self.suggestedRangeStart = suggestedRangeStart
        self.suggestedRangeEnd = suggestedRangeEnd
        self.status = status
        self.note = note
    }
}

struct AnnotationPass: Codable, Equatable, Identifiable {
    let id: UUID
    let annotatorID: String
    let revision: Int
    let submittedAt: Date?
    var stages: [AnnotationStageSelection]
    var frameLabels: [AnnotationFrameLabel]

    func replacingStages(_ stages: [AnnotationStageSelection]) -> Self {
        .init(
            id: id,
            annotatorID: annotatorID,
            revision: revision,
            submittedAt: submittedAt,
            stages: stages,
            frameLabels: frameLabels
        )
    }
}

struct AnnotationAdjudication: Codable, Equatable {
    let stage: String
    let sourceFrameIndex: Int?
    let adjudicatorID: String
    let decidedAt: Date
    let originalSelections: [AnnotationStageSelection]
    let note: String

    init(
        stage: String,
        sourceFrameIndex: Int?,
        adjudicatorID: String,
        decidedAt: Date,
        originalSelections: [AnnotationStageSelection] = [],
        note: String
    ) {
        self.stage = stage
        self.sourceFrameIndex = sourceFrameIndex
        self.adjudicatorID = adjudicatorID
        self.decidedAt = decidedAt
        self.originalSelections = originalSelections
        self.note = note
    }
}

struct AnnotationFrameQueuePolicy: Codable, Equatable {
    let version: String
    let p1ThroughP5Stride: Int
    let p5ThroughP8Stride: Int

    static let v1 = AnnotationFrameQueuePolicy(
        version: "swingarc-annotation-queue-v1",
        p1ThroughP5Stride: 4,
        p5ThroughP8Stride: 2
    )
}

struct AnnotationPackage: Codable, Equatable {
    let schemaVersion: Int
    let stageSystem: String
    let media: AnnotationMediaIdentity
    let metadata: AnnotationClipMetadata
    let frameQueuePolicy: AnnotationFrameQueuePolicy
    var frameQueue: [Int]
    var activeDraft: AnnotationPass?
    var currentSourceFrameIndex: Int
    var passes: [AnnotationPass]
    var archivedPassRevisions: [AnnotationPass]
    var adjudications: [AnnotationAdjudication]
    var frozenAt: Date?

    init(
        schemaVersion: Int,
        stageSystem: String,
        media: AnnotationMediaIdentity,
        metadata: AnnotationClipMetadata,
        frameQueuePolicy: AnnotationFrameQueuePolicy = .v1,
        frameQueue: [Int] = [],
        activeDraft: AnnotationPass? = nil,
        currentSourceFrameIndex: Int = 0,
        passes: [AnnotationPass],
        archivedPassRevisions: [AnnotationPass] = [],
        adjudications: [AnnotationAdjudication],
        frozenAt: Date?
    ) {
        self.schemaVersion = schemaVersion
        self.stageSystem = stageSystem
        self.media = media
        self.metadata = metadata
        self.frameQueuePolicy = frameQueuePolicy
        self.frameQueue = frameQueue
        self.activeDraft = activeDraft
        self.currentSourceFrameIndex = currentSourceFrameIndex
        self.passes = passes
        self.archivedPassRevisions = archivedPassRevisions
        self.adjudications = adjudications
        self.frozenAt = frozenAt
    }

    func replacingPasses(_ passes: [AnnotationPass]) -> Self {
        var copy = self
        copy.passes = passes
        return copy
    }
}

enum AnnotationCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

import Foundation

public enum GolfDatasetSplit: String, Codable, Equatable, CaseIterable, Sendable {
    case training = "training"
    case validation = "validation"
    case heldOut = "held-out"
}

public enum GolfDatasetAuthorization: String, Codable, Equatable, CaseIterable, Sendable {
    case trainingAllowed = "training-allowed"
    case internalReview = "internal-review"
}

public enum GolfDatasetView: String, Codable, Equatable, CaseIterable, Sendable {
    case downTheLine = "dtl"
    case faceOn = "face-on"
}

public enum GolfDatasetHandedness: String, Codable, Equatable, CaseIterable, Sendable {
    case right = "right"
    case left = "left"
}

public enum GolfDatasetIdentityError: Error, Equatable, CustomStringConvertible {
    case invalidGolferID(String)
    case splitConflict(golferID: String, existing: GolfDatasetSplit, requested: GolfDatasetSplit)

    public var description: String {
        switch self {
        case .invalidGolferID(let id):
            return "Invalid golfer ID: '\(id)'"
        case .splitConflict(let golferID, let existing, let requested):
            return "Golfer '\(golferID)' is locked to split '\(existing.rawValue)' but requested split is '\(requested.rawValue)'"
        }
    }
}

public struct GolferRecord: Codable, Equatable, Sendable {
    public let golferID: String
    public let split: GolfDatasetSplit
    public let splitLockedAt: Date

    public init(golferID: String, split: GolfDatasetSplit, splitLockedAt: Date) {
        self.golferID = golferID
        self.split = split
        self.splitLockedAt = splitLockedAt
    }
}

public struct GolferRegistry: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var datasetID: String
    public var golfers: [GolferRecord]

    public init(schemaVersion: Int = 1, datasetID: String, golfers: [GolferRecord] = []) {
        self.schemaVersion = schemaVersion
        self.datasetID = datasetID
        self.golfers = golfers
    }

    public func split(for golferID: String) -> GolfDatasetSplit? {
        golfers.first(where: { $0.golferID == golferID })?.split
    }

    public func assign(
        golferID rawID: String,
        split: GolfDatasetSplit,
        at date: Date
    ) throws -> GolferRegistry {
        let golferID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !golferID.isEmpty, golferID == rawID else {
            throw GolfDatasetIdentityError.invalidGolferID(rawID)
        }
        if let existing = golfers.first(where: { $0.golferID == golferID }) {
            guard existing.split == split else {
                throw GolfDatasetIdentityError.splitConflict(
                    golferID: golferID,
                    existing: existing.split,
                    requested: split
                )
            }
            return self
        }
        var copy = self
        copy.golfers.append(.init(
            golferID: golferID,
            split: split,
            splitLockedAt: date
        ))
        copy.golfers.sort { $0.golferID < $1.golferID }
        return copy
    }
}

public struct GolfMediaIdentity: Codable, Equatable, Sendable {
    public let fileName: String
    public let sha256: String
    public let timelineSHA256: String
    public let frameCount: Int
    public let orientedWidth: Int
    public let orientedHeight: Int
    public let sourceTimescale: Int

    public init(
        fileName: String,
        sha256: String,
        timelineSHA256: String,
        frameCount: Int,
        orientedWidth: Int,
        orientedHeight: Int,
        sourceTimescale: Int
    ) {
        self.fileName = fileName
        self.sha256 = sha256
        self.timelineSHA256 = timelineSHA256
        self.frameCount = frameCount
        self.orientedWidth = orientedWidth
        self.orientedHeight = orientedHeight
        self.sourceTimescale = sourceTimescale
    }
}

public struct GolfClipIdentity: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let clipID: String
    public let golferID: String
    public let media: GolfMediaIdentity
    public let view: GolfDatasetView
    public let handedness: GolfDatasetHandedness
    public let authorization: GolfDatasetAuthorization
    public let pPointTruthSHA256: String

    public init(
        schemaVersion: Int = 1,
        clipID: String,
        golferID: String,
        media: GolfMediaIdentity,
        view: GolfDatasetView,
        handedness: GolfDatasetHandedness,
        authorization: GolfDatasetAuthorization,
        pPointTruthSHA256: String
    ) {
        self.schemaVersion = schemaVersion
        self.clipID = clipID
        self.golferID = golferID
        self.media = media
        self.view = view
        self.handedness = handedness
        self.authorization = authorization
        self.pPointTruthSHA256 = pPointTruthSHA256
    }
}

public enum GolfPPointStageCode: String, Codable, Equatable, CaseIterable, Sendable {
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"
    case p4 = "P4"
    case p5 = "P5"
    case p6 = "P6"
    case p7 = "P7"
    case p8 = "P8"
}

public struct GolfPPointTruthMedia: Codable, Equatable, Sendable {
    public let sha256: String
    public let timelineSHA256: String
    public let frameCount: Int

    public init(sha256: String, timelineSHA256: String, frameCount: Int) {
        self.sha256 = sha256
        self.timelineSHA256 = timelineSHA256
        self.frameCount = frameCount
    }
}

public struct GolfPPointTruthStage: Codable, Equatable, Sendable {
    public let code: GolfPPointStageCode
    public let sourceFrameIndex: Int

    public init(code: GolfPPointStageCode, sourceFrameIndex: Int) {
        self.code = code
        self.sourceFrameIndex = sourceFrameIndex
    }
}

/// The narrow P1–P8 payload required to build an annotation queue. Additional
/// export metadata remains in the immutable source JSON and is ignored here.
public struct GolfPPointTruthDocument: Codable, Equatable, Sendable {
    public let media: GolfPPointTruthMedia
    public let view: GolfDatasetView
    public let stages: [GolfPPointTruthStage]

    public init(
        media: GolfPPointTruthMedia,
        view: GolfDatasetView,
        stages: [GolfPPointTruthStage]
    ) {
        self.media = media
        self.view = view
        self.stages = stages
    }

    public func frame(for code: GolfPPointStageCode) -> Int? {
        stages.first { $0.code == code }?.sourceFrameIndex
    }
}

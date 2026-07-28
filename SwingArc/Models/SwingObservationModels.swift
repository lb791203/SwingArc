import Foundation

struct NormalizedPoint: Codable, Hashable {
    let x: Double
    let y: Double
}

enum SwingPointState: String, Codable, Equatable {
    case detected
    case estimated
    case occluded
    case outOfFrame
    case missing
}

enum SwingPointSource: String, Codable, Equatable {
    case visionPose
    case contour
    case coreMLGolf
    case temporalPrediction
    case manual
}

struct TrackedSwingPoint: Codable, Equatable {
    let point: NormalizedPoint?
    let confidence: Double
    let state: SwingPointState
    let source: SwingPointSource

    var isEstimated: Bool {
        state == .estimated || source == .temporalPrediction
    }

    var isMeasured: Bool {
        point != nil
            && state == .detected
            && source != .temporalPrediction
    }
}

enum SwingLandmark: String, Codable, CaseIterable, Hashable {
    case head
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
    case handCenter
    case grip
    case shaftStart
    case shaftEnd
    case clubhead
    case ball
}

struct SwingFrameObservation: Codable, Equatable {
    let sourceFrameIndex: Int
    let time: Double
    let rawLandmarks: [SwingLandmark: TrackedSwingPoint]
    let landmarks: [SwingLandmark: TrackedSwingPoint]

    init(
        sourceFrameIndex: Int,
        time: Double,
        landmarks: [SwingLandmark: TrackedSwingPoint],
        rawLandmarks: [SwingLandmark: TrackedSwingPoint]? = nil
    ) {
        self.sourceFrameIndex = sourceFrameIndex
        self.time = time
        self.rawLandmarks = rawLandmarks ?? landmarks
        self.landmarks = landmarks
    }
}

struct TimedTrackedPoint: Codable, Equatable {
    let sourceFrameIndex: Int
    let time: Double
    let value: TrackedSwingPoint
}

struct SwingTrajectory: Codable, Equatable {
    let landmark: SwingLandmark
    let samples: [TimedTrackedPoint]

    static func make(
        landmark: SwingLandmark,
        frames: [SwingFrameObservation]
    ) -> SwingTrajectory {
        SwingTrajectory(
            landmark: landmark,
            samples: frames.compactMap { frame in
                frame.landmarks[landmark].map {
                    TimedTrackedPoint(
                        sourceFrameIndex: frame.sourceFrameIndex,
                        time: frame.time,
                        value: $0
                    )
                }
            }
        )
    }
}

struct SwingStageArtifact: Codable, Equatable {
    let code: String
    let sourceFrameIndex: Int?
    let time: Double?
    let confidence: Double
    let status: String
    let evidenceSources: [String]
    let manuallyLocked: Bool
}

struct SwingAnalysisArtifact: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let modelVersion: String
    let view: String
    let sourceFrameRate: Double
    let qualityIssues: [String]
    let frames: [SwingFrameObservation]
    let stages: [SwingStageArtifact]
    let metrics: [SwingMetricValue]
}

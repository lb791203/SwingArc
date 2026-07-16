import Foundation

struct GroundTruthManifest: Decodable {
    let video: String
    let sourceFrameRate: Double
    let duration: Double
    let annotationPasses: Int
    let maximumAcceptedFrameError: Int
    let stages: [StageGroundTruth]
}

struct StageGroundTruth: Decodable {
    let stage: String
    let sourceFrameIndex: Int
    let definition: String
}

struct StageAcceptance: Codable {
    let stage: String
    let expectedFrame: Int
    let actualFrame: Int?
    let absoluteFrameError: Int?
    let maximumAcceptedFrameError: Int
    let status: String
    let confidence: Double
    let hasClubEvidence: Bool
    let hasBallEvidence: Bool
    let passed: Bool
}

enum RealVideoAcceptance {
    private static let stagesByCode: [String: SwingStage] = [
        "P1": .address,
        "P2": .takeaway,
        "P3": .leadArmParallelBackswing,
        "P4": .top,
        "P5": .leadArmParallelDownswing,
        "P6": .impact,
        "P7": .followThrough,
        "P8": .finish
    ]

    static func evaluate(
        manifest: GroundTruthManifest,
        result: SwingAnalysisResult
    ) -> [StageAcceptance] {
        manifest.stages.map { truth in
            let expectedStage = stagesByCode[truth.stage]
            let detection = result.detections.first { $0.stage == expectedStage }
            let error = detection?.sourceFrameIndex.map { abs($0 - truth.sourceFrameIndex) }
            return StageAcceptance(
                stage: truth.stage,
                expectedFrame: truth.sourceFrameIndex,
                actualFrame: detection?.sourceFrameIndex,
                absoluteFrameError: error,
                maximumAcceptedFrameError: manifest.maximumAcceptedFrameError,
                status: String(describing: detection?.status ?? .unresolved),
                confidence: detection?.confidence ?? 0,
                hasClubEvidence: detection?.hasClubEvidence ?? false,
                hasBallEvidence: detection?.hasBallEvidence ?? false,
                passed: error.map { $0 <= manifest.maximumAcceptedFrameError } ?? false
            )
        }
    }
}

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

enum GroundTruthManifestValidationError: Error, CustomStringConvertible {
    case videoName(expected: String, actual: String)
    case sourceFrameRate(expected: Double, actual: Double)
    case duration(expected: Double, actual: Double)
    case annotationPasses(Int)
    case maximumAcceptedFrameError(Int)
    case stageCodes([String])

    var description: String {
        switch self {
        case let .videoName(expected, actual):
            return "manifest video \(expected) does not match \(actual)"
        case let .sourceFrameRate(expected, actual):
            return "manifest FPS \(expected) does not match \(actual)"
        case let .duration(expected, actual):
            return "manifest duration \(expected) does not match \(actual)"
        case let .annotationPasses(passes):
            return "manifest requires at least 2 annotation passes; found \(passes)"
        case let .maximumAcceptedFrameError(error):
            return "manifest threshold must be exactly 1 frame; found \(error)"
        case let .stageCodes(codes):
            return "manifest must contain exactly one of P1...P8; found \(codes)"
        }
    }
}

enum GroundTruthManifestValidator {
    /// Nominal frame rate metadata may be rounded by AVFoundation. A 0.01 FPS
    /// tolerance accepts that metadata rounding without accepting another rate.
    static let sourceFrameRateTolerance = 0.01
    /// Container duration can differ by a final partial frame. Fifty
    /// milliseconds covers one frame at 24/25/30 FPS while remaining strict.
    static let durationTolerance = 0.05
    private static let requiredStageCodes = Set((1...8).map { "P\($0)" })

    static func validate(
        _ manifest: GroundTruthManifest,
        videoName: String,
        sourceFrameRate: Double,
        duration: Double
    ) throws {
        guard manifest.video == videoName else {
            throw GroundTruthManifestValidationError.videoName(
                expected: manifest.video,
                actual: videoName
            )
        }
        guard manifest.sourceFrameRate.isFinite,
              sourceFrameRate.isFinite,
              abs(manifest.sourceFrameRate - sourceFrameRate) <= sourceFrameRateTolerance else {
            throw GroundTruthManifestValidationError.sourceFrameRate(
                expected: manifest.sourceFrameRate,
                actual: sourceFrameRate
            )
        }
        guard manifest.duration.isFinite,
              duration.isFinite,
              abs(manifest.duration - duration) <= durationTolerance else {
            throw GroundTruthManifestValidationError.duration(
                expected: manifest.duration,
                actual: duration
            )
        }
        guard manifest.annotationPasses >= 2 else {
            throw GroundTruthManifestValidationError.annotationPasses(manifest.annotationPasses)
        }
        guard manifest.maximumAcceptedFrameError == 1 else {
            throw GroundTruthManifestValidationError.maximumAcceptedFrameError(
                manifest.maximumAcceptedFrameError
            )
        }
        let codes = manifest.stages.map(\.stage)
        guard codes.count == requiredStageCodes.count,
              Set(codes) == requiredStageCodes else {
            throw GroundTruthManifestValidationError.stageCodes(codes)
        }
    }
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
    static let maximumAcceptedFrameError = 1
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
                maximumAcceptedFrameError: maximumAcceptedFrameError,
                status: String(describing: detection?.status ?? .unresolved),
                confidence: detection?.confidence ?? 0,
                hasClubEvidence: detection?.hasClubEvidence ?? false,
                hasBallEvidence: detection?.hasBallEvidence ?? false,
                passed: error.map { $0 <= maximumAcceptedFrameError } ?? false
            )
        }
    }
}

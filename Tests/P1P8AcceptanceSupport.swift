import Foundation

enum GroundTruthStageSystem: String, Codable {
    /// A manually annotated standard P1–P8 sequence. P6 is delivery
    /// shaft-parallel, P7 is impact, and P8 is release shaft-parallel.
    case canonicalP1P8 = "p-system-v1"
    /// Historical eight-keyframe labels retained for comparison only. This
    /// format intentionally has no canonical P6 delivery annotation.
    case legacyNamedKeyframes = "legacy-named-keyframes-v1"

    var requiredStageCodes: [String] {
        switch self {
        case .canonicalP1P8:
            return (1...8).map { "P\($0)" }
        case .legacyNamedKeyframes:
            return ["P1", "P2", "P3", "P4", "P5", "impact", "followThrough", "finish"]
        }
    }

    var requiredDefinitions: [String] {
        switch self {
        case .canonicalP1P8:
            return [
                "last stable address frame before sustained takeaway",
                "backswing shaft-horizontal frame",
                "backswing lead-arm-horizontal frame",
                "last top-plateau frame before sustained downswing",
                "downswing lead-arm-horizontal frame",
                "downswing shaft-horizontal delivery frame",
                "clubhead at stable ball position",
                "post-impact shaft-horizontal release frame"
            ]
        case .legacyNamedKeyframes:
            return [
                "last stable address frame before sustained takeaway",
                "backswing shaft-horizontal frame",
                "backswing lead-arm-horizontal frame",
                "last top-plateau frame before sustained downswing",
                "downswing lead-arm-horizontal frame",
                "legacy impact anchor",
                "legacy post-impact extension parallel frame",
                "legacy stable finish-plateau frame"
            ]
        }
    }

    func swingStage(for code: String) -> SwingStage? {
        switch self {
        case .canonicalP1P8:
            return [
                "P1": .address,
                "P2": .takeaway,
                "P3": .leadArmParallelBackswing,
                "P4": .top,
                "P5": .leadArmParallelDownswing,
                "P6": .shaftParallelDownswing,
                "P7": .impact,
                "P8": .followThrough
            ][code]
        case .legacyNamedKeyframes:
            return [
                "P1": .address,
                "P2": .takeaway,
                "P3": .leadArmParallelBackswing,
                "P4": .top,
                "P5": .leadArmParallelDownswing,
                "impact": .impact,
                "followThrough": .followThrough,
                "finish": .finish
            ][code]
        }
    }
}

struct GroundTruthManifest: Decodable {
    let stageSystem: GroundTruthStageSystem
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
    case stageCodes(system: GroundTruthStageSystem, codes: [String])
    case stageDefinitions(system: GroundTruthStageSystem)
    case stageFrameIndices([Int])

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
            return "manifest threshold must be exactly 2 frames; found \(error)"
        case let .stageCodes(system, codes):
            return "manifest \(system.rawValue) has invalid stage codes \(codes)"
        case let .stageDefinitions(system):
            return "manifest definitions do not match \(system.rawValue)"
        case let .stageFrameIndices(indices):
            return "manifest source frames must be unique, strictly increasing, and in range; found \(indices)"
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
        guard manifest.maximumAcceptedFrameError == 2 else {
            throw GroundTruthManifestValidationError.maximumAcceptedFrameError(
                manifest.maximumAcceptedFrameError
            )
        }
        let codes = manifest.stages.map(\.stage)
        guard codes == manifest.stageSystem.requiredStageCodes else {
            throw GroundTruthManifestValidationError.stageCodes(
                system: manifest.stageSystem,
                codes: codes
            )
        }
        guard manifest.stages.map(\.definition) == manifest.stageSystem.requiredDefinitions else {
            throw GroundTruthManifestValidationError.stageDefinitions(
                system: manifest.stageSystem
            )
        }
        let indices = manifest.stages.map(\.sourceFrameIndex)
        let maximumSourceFrameIndex = max(
            0,
            Int(ceil(manifest.duration * manifest.sourceFrameRate)) - 1
        )
        guard indices.allSatisfy({ (0...maximumSourceFrameIndex).contains($0) }),
              Set(indices).count == indices.count,
              zip(indices, indices.dropFirst()).allSatisfy(<) else {
            throw GroundTruthManifestValidationError.stageFrameIndices(indices)
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
    let hasBallChangeEvidence: Bool
    let passed: Bool
}

enum RealVideoAcceptance {
    static let maximumAcceptedFrameError = 2

    static func evaluate(
        manifest: GroundTruthManifest,
        result: SwingAnalysisResult
    ) -> [StageAcceptance] {
        manifest.stages.map { truth in
            let expectedStage = manifest.stageSystem.swingStage(for: truth.stage)
            let matchingDetections = result.detections.filter { $0.stage == expectedStage }
            let detection = matchingDetections.count == 1 ? matchingDetections[0] : nil
            let error = detection?.sourceFrameIndex.map { abs($0 - truth.sourceFrameIndex) }
            let isResolved = detection?.status != .unresolved
            let requiresShaft = manifest.stageSystem == .canonicalP1P8
                && (expectedStage == .shaftParallelDownswing || expectedStage == .followThrough)
            let hasRequiredShaftEvidence = !requiresShaft || detection?.hasClubEvidence == true
            let hasRequiredImpactEvidence = expectedStage != .impact
                || detection?.status != .confirmed
                || ((detection?.hasClubEvidence == true) && (detection?.hasBallEvidence == true))
                || detection?.hasBallChangeEvidence == true
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
                hasBallChangeEvidence: detection?.hasBallChangeEvidence ?? false,
                passed: matchingDetections.count == 1
                    && isResolved
                    && hasRequiredShaftEvidence
                    && hasRequiredImpactEvidence
                    && (error.map { $0 <= maximumAcceptedFrameError } ?? false)
            )
        }
    }
}

enum PrecisionCameraView: String, Codable, Hashable {
    case downTheLine = "dtl"
    case faceOn = "face-on"
}

struct PrecisionStageRecord: Codable, Equatable {
    let view: PrecisionCameraView
    let stage: String
    let expectedFrame: Int
    let actualFrame: Int?
    let status: String
}

struct PrecisionStageKey: Hashable {
    let view: PrecisionCameraView
    let stage: String
}

struct PrecisionAcceptanceSummary: Equatable {
    let stageRates: [PrecisionStageKey: Double]
    let passed: Bool
}

enum SwingPrecisionAcceptance {
    static let maximumFrameError = 2
    static let minimumStageRate = 0.90

    static func summarize(records: [PrecisionStageRecord]) -> PrecisionAcceptanceSummary {
        let grouped = Dictionary(grouping: records) {
            PrecisionStageKey(view: $0.view, stage: $0.stage)
        }
        let rates = grouped.mapValues { items in
            Double(items.filter { item in
                guard item.status != "unresolved", let actual = item.actualFrame else {
                    return false
                }
                return abs(actual - item.expectedFrame) <= maximumFrameError
            }.count) / Double(items.count)
        }
        return PrecisionAcceptanceSummary(
            stageRates: rates,
            passed: !rates.isEmpty && rates.values.allSatisfy { $0 >= minimumStageRate }
        )
    }
}

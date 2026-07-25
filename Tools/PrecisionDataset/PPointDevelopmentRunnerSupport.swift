import Foundation

struct PPointDevelopmentVideoCandidate: Equatable {
    let url: URL
    let sha256: String
    let timelineSHA256: String
    let frameCount: Int
}

enum PPointDevelopmentRunnerError: Error, Equatable {
    case videoNotFound(String)
    case noGroundTruthPackages
    case analysisFailed(String)
}

enum PPointDevelopmentVideoMatcher {
    static func match(
        truth: PPointGroundTruthMedia,
        candidates: [PPointDevelopmentVideoCandidate]
    ) throws -> PPointDevelopmentVideoCandidate {
        if let exact = candidates.first(where: {
            $0.sha256 == truth.sha256
        }) {
            return exact
        }
        if let sameTimeline = candidates.first(where: {
            $0.timelineSHA256 == truth.timelineSHA256
                && $0.frameCount == truth.frameCount
        }) {
            return sameTimeline
        }
        throw PPointDevelopmentRunnerError.videoNotFound(truth.sha256)
    }
}

extension PPointDevelopmentRunnerError: CustomStringConvertible {
    var description: String {
        switch self {
        case let .videoNotFound(identity):
            return "no video matches ground truth \(identity)"
        case .noGroundTruthPackages:
            return "no P-point ground-truth JSON packages found"
        case let .analysisFailed(file):
            return "analysis failed for \(file)"
        }
    }
}

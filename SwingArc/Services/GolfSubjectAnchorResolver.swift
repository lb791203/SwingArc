import Foundation

public enum GolfSubjectAnchorValidationResult: Equatable, Sendable {
    case valid
    case candidateNotFound
    case clickPointOutsideBounds
    case clipOrMediaMismatch
    case conflictingFrameAnchors(frameIndex: Int)
}

public struct GolfSubjectAnchorResolver: Sendable {
    public init() {}

    public func validateAnchor(
        _ anchor: GolfSubjectAnchorDecision,
        against candidates: [GolfPoseCandidateFrame],
        clipID: String,
        mediaSHA256: String,
        timelineSHA256: String
    ) -> GolfSubjectAnchorValidationResult {
        guard anchor.clipID == clipID,
              anchor.mediaSHA256 == mediaSHA256,
              anchor.timelineSHA256 == timelineSHA256 else {
            return .clipOrMediaMismatch
        }

        let frameCandidates = candidates.filter { $0.sourceFrameIndex == anchor.sourceFrameIndex }
        guard let matchingCandidate = frameCandidates.first(where: { $0.candidateIndex == anchor.candidateIndex }) else {
            return .candidateNotFound
        }

        let pt = anchor.normalizedClickPoint
        let bounds = matchingCandidate.bodyBounds
        guard pt.x >= bounds.x,
              pt.x <= bounds.x + bounds.width,
              pt.y >= bounds.y,
              pt.y <= bounds.y + bounds.height else {
            return .clickPointOutsideBounds
        }

        return .valid
    }

    public func validateAnchors(_ anchors: [GolfSubjectAnchorDecision]) -> GolfSubjectAnchorValidationResult {
        var candidatesByFrame: [Int: GolfSubjectAnchorDecision] = [:]
        for anchor in anchors {
            if let existing = candidatesByFrame[anchor.sourceFrameIndex] {
                if existing.candidateIndex != anchor.candidateIndex ||
                    existing.normalizedClickPoint != anchor.normalizedClickPoint {
                    return .conflictingFrameAnchors(frameIndex: anchor.sourceFrameIndex)
                }
            } else {
                candidatesByFrame[anchor.sourceFrameIndex] = anchor
            }
        }
        return .valid
    }
}

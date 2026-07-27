import Foundation

@main
struct GolfSubjectAnchorContractSmoke {
    static func main() throws {
        testAnchorDecisionInitialization()
        testAnchorValidationSuccess()
        testAnchorValidationStaleCandidate()
        testAnchorValidationClickOutsideBounds()
        testAnchorValidationMismatchClipOrMedia()
        testSameFrameConflictingAnchors()
        print("All GolfSubjectAnchorContract tests passed.")
    }

    static func testAnchorDecisionInitialization() {
        let anchor = GolfSubjectAnchorDecision(
            anchorID: "anchor-001",
            clipID: "golfer-001-face-on-001",
            mediaSHA256: "1111111111111111111111111111111111111111111111111111111111111111",
            timelineSHA256: "2222222222222222222222222222222222222222222222222222222222222222",
            sourceFrameIndex: 10,
            candidateIndex: 1,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.5, y: 0.5),
            visionFrameworkVersion: "Vision 14.0",
            visionRequestRevision: "VNRecognizeAnimalsRequestRevision1",
            annotatorID: "annotator-01",
            decidedAt: Date(timeIntervalSince1970: 1700000000)
        )

        precondition(anchor.schemaVersion == 1)
        precondition(anchor.anchorID == "anchor-001")
        precondition(anchor.candidateIndex == 1)
        precondition(anchor.normalizedClickPoint.x == 0.5)
    }

    static func testAnchorValidationSuccess() {
        let anchor = GolfSubjectAnchorDecision(
            anchorID: "anchor-001",
            clipID: "clip-A",
            mediaSHA256: "mSHA",
            timelineSHA256: "tSHA",
            sourceFrameIndex: 5,
            candidateIndex: 0,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.45, y: 0.45),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "user1",
            decidedAt: Date()
        )

        let candidate = GolfPoseCandidateFrame(
            sourceFrameIndex: 5,
            sourceTime: 0.166,
            candidateIndex: 0,
            bodyCenter: GolfNormalizedPoint(x: 0.45, y: 0.45),
            bodyBounds: GolfNormalizedRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3),
            bodyScale: 0.3,
            jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.1, hipWidth: 0.1, torsoLength: 0.2),
            handCenter: nil,
            identityConfidence: 0.9
        )

        let resolver = GolfSubjectAnchorResolver()
        let result = resolver.validateAnchor(
            anchor,
            against: [candidate],
            clipID: "clip-A",
            mediaSHA256: "mSHA",
            timelineSHA256: "tSHA"
        )
        precondition(result == .valid)
    }

    static func testAnchorValidationStaleCandidate() {
        let anchor = GolfSubjectAnchorDecision(
            anchorID: "anchor-001",
            clipID: "clip-A",
            mediaSHA256: "mSHA",
            timelineSHA256: "tSHA",
            sourceFrameIndex: 5,
            candidateIndex: 2, // candidateIndex 2 doesn't exist
            normalizedClickPoint: GolfNormalizedPoint(x: 0.45, y: 0.45),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "user1",
            decidedAt: Date()
        )

        let candidate = GolfPoseCandidateFrame(
            sourceFrameIndex: 5,
            sourceTime: 0.166,
            candidateIndex: 0,
            bodyCenter: GolfNormalizedPoint(x: 0.45, y: 0.45),
            bodyBounds: GolfNormalizedRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3),
            bodyScale: 0.3,
            jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.1, hipWidth: 0.1, torsoLength: 0.2),
            handCenter: nil,
            identityConfidence: 0.9
        )

        let resolver = GolfSubjectAnchorResolver()
        let result = resolver.validateAnchor(
            anchor,
            against: [candidate],
            clipID: "clip-A",
            mediaSHA256: "mSHA",
            timelineSHA256: "tSHA"
        )
        precondition(result == .candidateNotFound)
    }

    static func testAnchorValidationClickOutsideBounds() {
        let anchor = GolfSubjectAnchorDecision(
            anchorID: "anchor-001",
            clipID: "clip-A",
            mediaSHA256: "mSHA",
            timelineSHA256: "tSHA",
            sourceFrameIndex: 5,
            candidateIndex: 0,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.95, y: 0.95), // outside [0.3, 0.3, 0.3, 0.3]
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "user1",
            decidedAt: Date()
        )

        let candidate = GolfPoseCandidateFrame(
            sourceFrameIndex: 5,
            sourceTime: 0.166,
            candidateIndex: 0,
            bodyCenter: GolfNormalizedPoint(x: 0.45, y: 0.45),
            bodyBounds: GolfNormalizedRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3),
            bodyScale: 0.3,
            jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.1, hipWidth: 0.1, torsoLength: 0.2),
            handCenter: nil,
            identityConfidence: 0.9
        )

        let resolver = GolfSubjectAnchorResolver()
        let result = resolver.validateAnchor(
            anchor,
            against: [candidate],
            clipID: "clip-A",
            mediaSHA256: "mSHA",
            timelineSHA256: "tSHA"
        )
        precondition(result == .clickPointOutsideBounds)
    }

    static func testAnchorValidationMismatchClipOrMedia() {
        let anchor = GolfSubjectAnchorDecision(
            anchorID: "anchor-001",
            clipID: "clip-A",
            mediaSHA256: "mSHA-WRONG",
            timelineSHA256: "tSHA",
            sourceFrameIndex: 5,
            candidateIndex: 0,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.45, y: 0.45),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "user1",
            decidedAt: Date()
        )

        let candidate = GolfPoseCandidateFrame(
            sourceFrameIndex: 5,
            sourceTime: 0.166,
            candidateIndex: 0,
            bodyCenter: GolfNormalizedPoint(x: 0.45, y: 0.45),
            bodyBounds: GolfNormalizedRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3),
            bodyScale: 0.3,
            jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.1, hipWidth: 0.1, torsoLength: 0.2),
            handCenter: nil,
            identityConfidence: 0.9
        )

        let resolver = GolfSubjectAnchorResolver()
        let result = resolver.validateAnchor(
            anchor,
            against: [candidate],
            clipID: "clip-A",
            mediaSHA256: "mSHA",
            timelineSHA256: "tSHA"
        )
        precondition(result == .clipOrMediaMismatch)
    }

    static func testSameFrameConflictingAnchors() {
        let anchor1 = GolfSubjectAnchorDecision(
            anchorID: "anchor-001",
            clipID: "clip-A",
            mediaSHA256: "mSHA",
            timelineSHA256: "tSHA",
            sourceFrameIndex: 5,
            candidateIndex: 0,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.4, y: 0.4),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "user1",
            decidedAt: Date()
        )
        let anchor2 = GolfSubjectAnchorDecision(
            anchorID: "anchor-002",
            clipID: "clip-A",
            mediaSHA256: "mSHA",
            timelineSHA256: "tSHA",
            sourceFrameIndex: 5,
            candidateIndex: 1, // conflict on same frame index!
            normalizedClickPoint: GolfNormalizedPoint(x: 0.7, y: 0.7),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "user2",
            decidedAt: Date()
        )

        let resolver = GolfSubjectAnchorResolver()
        let check = resolver.validateAnchors([anchor1, anchor2])
        precondition(check == .conflictingFrameAnchors(frameIndex: 5))
    }
}

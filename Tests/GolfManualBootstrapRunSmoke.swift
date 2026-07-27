import Foundation

@main
struct GolfManualBootstrapRunSmoke {
    static func main() throws {
        testManualBootstrapRunBuilderSuccess()
        testManualBootstrapRunSchema1Compatibility()
        testManualBootstrapRunCanonicalProvenanceHash()
        testManualBootstrapRunRejectsInvalidAnchor()
        testManualBootstrapRunRejectsAmbiguityExceeding150ms()
        print("All GolfManualBootstrapRun tests passed.")
    }

    static func testManualBootstrapRunBuilderSuccess() {
        let clipID = "golfer-001-dtl-001"
        let mediaSHA = "1111111111111111111111111111111111111111111111111111111111111111"
        let timelineSHA = "2222222222222222222222222222222222222222222222222222222222222222"

        var candidates: [GolfPoseCandidateFrame] = []
        for i in 0..<30 {
            candidates.append(
                GolfPoseCandidateFrame(
                    sourceFrameIndex: i,
                    sourceTime: Double(i) / 30.0,
                    candidateIndex: 0,
                    bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
                    bodyBounds: GolfNormalizedRect(x: 0.4, y: 0.3, width: 0.2, height: 0.5),
                    bodyScale: 0.5,
                    jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.1, hipWidth: 0.1, torsoLength: 0.2),
                    handCenter: GolfNormalizedPoint(x: 0.5, y: 0.4),
                    identityConfidence: 0.95
                )
            )
        }

        let anchor = GolfSubjectAnchorDecision(
            anchorID: "anchor-001",
            clipID: clipID,
            mediaSHA256: mediaSHA,
            timelineSHA256: timelineSHA,
            sourceFrameIndex: 0,
            candidateIndex: 0,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.5, y: 0.5),
            visionFrameworkVersion: "Vision 14.0",
            visionRequestRevision: "VNRecognizeAnimalsRequestRevision1",
            annotatorID: "annotator-01",
            decidedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let result = GolfManualBootstrapRunBuilder.build(
            clipID: clipID,
            mediaSHA256: mediaSHA,
            timelineSHA256: timelineSHA,
            anchors: [anchor],
            candidates: candidates,
            visionFrameworkVersion: "Vision 14.0",
            visionRequestVersion: "VNRecognizeAnimalsRequestRevision1",
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512.0
        )

        switch result {
        case .success(let run):
            precondition(run.schemaVersion == 2)
            precondition(run.runKind == .manualBootstrap)
            precondition(run.modelSHA256 == nil)
            precondition(run.frames.count == 30)
            for frame in run.frames {
                precondition(frame.points.isEmpty)
            }
            precondition(!run.provenanceHash.isEmpty)
            precondition(run.predictionRunID == run.provenanceHash)
        case .failure(let error):
            preconditionFailure("Failed to build manual bootstrap run: \(error)")
        }
    }

    static func testManualBootstrapRunSchema1Compatibility() {
        let json = """
        {
            "schemaVersion": 1,
            "predictionRunID": "run-001",
            "clipID": "golfer-001-dtl-001",
            "mediaSHA256": "1111111111111111111111111111111111111111111111111111111111111111",
            "timelineSHA256": "2222222222222222222222222222222222222222222222222222222222222222",
            "visionFrameworkVersion": "Vision 14.0",
            "visionRequestVersion": "v1",
            "roiAlgorithmVersion": "v1",
            "roiConfigSHA256": "3333333333333333333333333333333333333333333333333333333333333333",
            "modelSHA256": "4444444444444444444444444444444444444444444444444444444444444444",
            "decoderVersion": "v1",
            "trackerVersion": "v1",
            "createdAt": "2026-07-24T10:00:00Z",
            "frames": [],
            "provenanceHash": "prov-001"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let run = try! decoder.decode(GolfPredictionRun.self, from: json)
        precondition(run.runKind == .modelInference)
        precondition(run.modelSHA256 == "4444444444444444444444444444444444444444444444444444444444444444")
    }

    static func testManualBootstrapRunCanonicalProvenanceHash() {
        let clipID = "clip-A"
        let mediaSHA = "mSHA"
        let timelineSHA = "tSHA"

        let anchor = GolfSubjectAnchorDecision(
            anchorID: "anchor-001",
            clipID: clipID,
            mediaSHA256: mediaSHA,
            timelineSHA256: timelineSHA,
            sourceFrameIndex: 0,
            candidateIndex: 0,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.5, y: 0.5),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "u1",
            decidedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let candidates = [
            GolfPoseCandidateFrame(
                sourceFrameIndex: 0,
                sourceTime: 0.0,
                candidateIndex: 0,
                bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.4, y: 0.3, width: 0.2, height: 0.5),
                bodyScale: 0.5,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.1, hipWidth: 0.1, torsoLength: 0.2),
                handCenter: nil,
                identityConfidence: 0.95
            )
        ]

        let run1 = try! GolfManualBootstrapRunBuilder.build(
            clipID: clipID,
            mediaSHA256: mediaSHA,
            timelineSHA256: timelineSHA,
            anchors: [anchor],
            candidates: candidates,
            visionFrameworkVersion: "v1",
            visionRequestVersion: "r1",
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512.0
        ).get()

        let run2 = try! GolfManualBootstrapRunBuilder.build(
            clipID: clipID,
            mediaSHA256: mediaSHA,
            timelineSHA256: timelineSHA,
            anchors: [anchor],
            candidates: candidates,
            visionFrameworkVersion: "v1",
            visionRequestVersion: "r1",
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512.0
        ).get()

        precondition(run1.provenanceHash == run2.provenanceHash)
        precondition(run1.predictionRunID == run2.predictionRunID)

        let sameContentLater = GolfPredictionRun(
            schemaVersion: run1.schemaVersion,
            runKind: run1.runKind,
            predictionRunID: run1.predictionRunID,
            clipID: run1.clipID,
            mediaSHA256: run1.mediaSHA256,
            timelineSHA256: run1.timelineSHA256,
            visionFrameworkVersion: run1.visionFrameworkVersion,
            visionRequestVersion: run1.visionRequestVersion,
            roiAlgorithmVersion: run1.roiAlgorithmVersion,
            roiConfigSHA256: run1.roiConfigSHA256,
            modelSHA256: run1.modelSHA256,
            decoderVersion: run1.decoderVersion,
            trackerVersion: run1.trackerVersion,
            createdAt: run1.createdAt.addingTimeInterval(2),
            frames: run1.frames,
            manualBootstrapAnchors: run1.manualBootstrapAnchors,
            provenanceHash: run1.provenanceHash
        )
        precondition(
            run1 == sameContentLater,
            "Deterministic runs must remain idempotent regardless of creation time"
        )
        precondition(
            Set([run1, sameContentLater]).count == 1,
            "Hashable must use the same canonical fields as equality"
        )
    }

    static func testManualBootstrapRunRejectsInvalidAnchor() {
        let clipID = "clip-A"
        let mediaSHA = "mSHA"
        let timelineSHA = "tSHA"

        // Anchor with candidateIndex 99 (doesn't exist)
        let anchor = GolfSubjectAnchorDecision(
            anchorID: "anchor-99",
            clipID: clipID,
            mediaSHA256: mediaSHA,
            timelineSHA256: timelineSHA,
            sourceFrameIndex: 0,
            candidateIndex: 99,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.5, y: 0.5),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "u1",
            decidedAt: Date()
        )

        let candidates = [
            GolfPoseCandidateFrame(
                sourceFrameIndex: 0,
                sourceTime: 0.0,
                candidateIndex: 0,
                bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.4, y: 0.3, width: 0.2, height: 0.5),
                bodyScale: 0.5,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.1, hipWidth: 0.1, torsoLength: 0.2),
                handCenter: nil,
                identityConfidence: 0.95
            )
        ]

        let result = GolfManualBootstrapRunBuilder.build(
            clipID: clipID,
            mediaSHA256: mediaSHA,
            timelineSHA256: timelineSHA,
            anchors: [anchor],
            candidates: candidates,
            visionFrameworkVersion: "v1",
            visionRequestVersion: "r1",
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512.0
        )

        if case .failure = result {
            // expected
        } else {
            preconditionFailure("Expected failure due to invalid anchor")
        }
    }

    static func testManualBootstrapRunRejectsAmbiguityExceeding150ms() {
        let clipID = "clip-A"
        let mediaSHA = "mSHA"
        let timelineSHA = "tSHA"

        // Create 20 frames with 2 candidates each (ambiguous) spanning 0.66s > 150ms with 1 anchor at frame 0
        var candidates: [GolfPoseCandidateFrame] = []
        for f in 0..<20 {
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: f,
                sourceTime: Double(f) * 0.033,
                candidateIndex: 0,
                bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.4, y: 0.3, width: 0.2, height: 0.5),
                bodyScale: 0.5,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.1, hipWidth: 0.1, torsoLength: 0.2),
                handCenter: nil,
                identityConfidence: 0.5
            ))
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: f,
                sourceTime: Double(f) * 0.033,
                candidateIndex: 1,
                bodyCenter: GolfNormalizedPoint(x: 0.51, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.41, y: 0.3, width: 0.2, height: 0.5),
                bodyScale: 0.5,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.1, hipWidth: 0.1, torsoLength: 0.2),
                handCenter: nil,
                identityConfidence: 0.5
            ))
        }

        let anchor = GolfSubjectAnchorDecision(
            anchorID: "anchor-0",
            clipID: clipID,
            mediaSHA256: mediaSHA,
            timelineSHA256: timelineSHA,
            sourceFrameIndex: 0,
            candidateIndex: 0,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.5, y: 0.5),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "u1",
            decidedAt: Date()
        )

        let result = GolfManualBootstrapRunBuilder.build(
            clipID: clipID,
            mediaSHA256: mediaSHA,
            timelineSHA256: timelineSHA,
            anchors: [anchor],
            candidates: candidates,
            visionFrameworkVersion: "v1",
            visionRequestVersion: "r1",
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512.0
        )

        if case .failure = result {
            // expected because 1 anchor at frame 0 cannot resolve long ambiguity > 150ms after frame 5
        } else {
            preconditionFailure("Expected failure due to ambiguity exceeding 150ms")
        }
    }
}

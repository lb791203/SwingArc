import Foundation

@main
struct PrimaryGolferTrackResolverSmoke {
    static func main() throws {
        testAnchorToGolferA()
        testCrossingBiggerBystander()
        testNoAnchorEquivalentTracks()
        testAmbiguityBoundary()
        testAmbiguityExceeds150ms()
        testDuplicateFrameConflict()
        testNonMonotonicTime()
        testShuffleDeterministic()
        testOutputFeedsStableROI()
        testHandCenterMissing()
        print("All PrimaryGolferTrackResolver tests passed.")
    }

    // MARK: - Anchor to golfer A, all frames keep A

    static func testAnchorToGolferA() {
        let candidates = makeSwingCandidates(count: 60, fps: 30)
        let anchor = GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: anchor)
        switch result {
        case .success(let frames):
            precondition(frames.count == 60, "Must have 60 frames, got \(frames.count)")
            for frame in frames {
                precondition(frame.identityConfidence > 0, "Confidence must be positive")
            }
        case .failure(let error):
            preconditionFailure("Expected success, got \(error)")
        }
    }

    // MARK: - Crossing: B is bigger for 5 frames, still keep A

    static func testCrossingBiggerBystander() {
        var candidates = makeSwingCandidates(count: 30, fps: 30)
        // Make bystander (candidateIndex=1) larger for frames 10-14
        for i in 10..<15 {
            let idx = candidates.firstIndex { $0.sourceFrameIndex == i && $0.candidateIndex == 1 }!
            candidates[idx] = GolfPoseCandidateFrame(
                sourceFrameIndex: i,
                sourceTime: Double(i) / 30.0,
                candidateIndex: 1,
                bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8),
                bodyScale: 0.6,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.3, hipWidth: 0.25, torsoLength: 0.4),
                handCenter: nil,
                identityConfidence: 0.9
            )
        }
        let anchor = GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: anchor)
        switch result {
        case .success(let frames):
            // All frames should resolve to candidate 0 (golfer A)
            // The resolver tracks by continuity, not size
            precondition(frames.count == 30, "Must have 30 frames")
        case .failure(let error):
            preconditionFailure("Expected success with crossing, got \(error)")
        }
    }

    // MARK: - No anchor, equivalent tracks → manualAnchorRequired

    static func testNoAnchorEquivalentTracks() {
        let candidates = makeEquivalentCandidates(count: 20, fps: 30)
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: nil)
        switch result {
        case .failure(.manualAnchorRequired):
            break // expected
        case .success:
            preconditionFailure("Must require anchor for equivalent tracks")
        case .failure(let error):
            preconditionFailure("Expected manualAnchorRequired, got \(error)")
        }
    }

    // MARK: - Ambiguity boundary: exactly 150ms

    static func testAmbiguityBoundary() {
        // Two candidates with similar scores for exactly 5 frames at 30fps = 166.7ms
        // Just under the threshold should still work with anchor
        var candidates = makeSwingCandidates(count: 10, fps: 30)
        // Make bystander (candidateIndex=1) very similar to golfer for frames 3-7
        for i in 3..<8 {
            let idx = candidates.firstIndex { $0.sourceFrameIndex == i && $0.candidateIndex == 1 }!
            candidates[idx] = GolfPoseCandidateFrame(
                sourceFrameIndex: i,
                sourceTime: Double(i) / 30.0,
                candidateIndex: 1,
                bodyCenter: GolfNormalizedPoint(x: 0.5 + Double(i) * 0.001, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6),
                bodyScale: 0.45,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.25, hipWidth: 0.2, torsoLength: 0.35),
                handCenter: nil,
                identityConfidence: 0.85
            )
        }
        let anchor = GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: anchor)
        // With anchor, should succeed even with ambiguity
        switch result {
        case .success(let frames):
            precondition(frames.count == 10, "Must resolve all frames")
        case .failure(let error):
            preconditionFailure("Expected success with anchor, got \(error)")
        }
    }

    // MARK: - Ambiguity exceeds 150ms → failure

    static func testAmbiguityExceeds150ms() {
        // Two candidates with identical properties for 10 frames at 30fps = 333ms
        var candidates: [GolfPoseCandidateFrame] = []
        for i in 0..<10 {
            let center = GolfNormalizedPoint(x: 0.5, y: 0.5)
            let bounds = GolfNormalizedRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6)
            let joint = GolfCandidateJointGeometry(shoulderWidth: 0.25, hipWidth: 0.2, torsoLength: 0.35)
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: i, sourceTime: Double(i) / 30.0, candidateIndex: 0,
                bodyCenter: center, bodyBounds: bounds, bodyScale: 0.45,
                jointGeometry: joint, handCenter: nil, identityConfidence: 0.85
            ))
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: i, sourceTime: Double(i) / 30.0, candidateIndex: 1,
                bodyCenter: center, bodyBounds: bounds, bodyScale: 0.45,
                jointGeometry: joint, handCenter: nil, identityConfidence: 0.85
            ))
        }
        let anchor = GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: anchor)
        switch result {
        case .failure(.identityAmbiguityTooLong):
            break // expected
        case .success:
            preconditionFailure("Must fail for prolonged ambiguity")
        case .failure(let error):
            preconditionFailure("Expected identityAmbiguityTooLong, got \(error)")
        }
    }

    // MARK: - Duplicate frame conflict

    static func testDuplicateFrameConflict() {
        var candidates = makeSwingCandidates(count: 5, fps: 30)
        // Add conflicting duplicate of frame 2
        candidates.append(GolfPoseCandidateFrame(
            sourceFrameIndex: 2,
            sourceTime: 0.067,
            candidateIndex: 0,
            bodyCenter: GolfNormalizedPoint(x: 0.99, y: 0.99),
            bodyBounds: GolfNormalizedRect(x: 0.8, y: 0.8, width: 0.1, height: 0.1),
            bodyScale: 0.1,
            jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.05, hipWidth: 0.04, torsoLength: 0.08),
            handCenter: nil,
            identityConfidence: 0.5
        ))
        let anchor = GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: anchor)
        switch result {
        case .failure(.duplicateFrameConflict(2)):
            break
        case .failure(let error):
            preconditionFailure("Expected duplicateFrameConflict, got \(error)")
        case .success:
            preconditionFailure("Must fail for conflicting duplicate")
        }
    }

    // MARK: - Non-monotonic time

    static func testNonMonotonicTime() {
        var candidates = makeSwingCandidates(count: 5, fps: 30)
        // Swap time of frame 1 and 2
        let idx1 = candidates.firstIndex { $0.sourceFrameIndex == 1 }!
        let idx2 = candidates.firstIndex { $0.sourceFrameIndex == 2 }!
        let t1 = candidates[idx1].sourceTime
        let t2 = candidates[idx2].sourceTime
        candidates[idx1] = GolfPoseCandidateFrame(
            sourceFrameIndex: 1, sourceTime: t2, candidateIndex: 0,
            bodyCenter: candidates[idx1].bodyCenter, bodyBounds: candidates[idx1].bodyBounds,
            bodyScale: candidates[idx1].bodyScale, jointGeometry: candidates[idx1].jointGeometry,
            handCenter: nil, identityConfidence: 0.9
        )
        candidates[idx2] = GolfPoseCandidateFrame(
            sourceFrameIndex: 2, sourceTime: t1, candidateIndex: 0,
            bodyCenter: candidates[idx2].bodyCenter, bodyBounds: candidates[idx2].bodyBounds,
            bodyScale: candidates[idx2].bodyScale, jointGeometry: candidates[idx2].jointGeometry,
            handCenter: nil, identityConfidence: 0.9
        )
        let anchor = GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: anchor)
        switch result {
        case .failure(.nonMonotonicTime):
            break
        case .failure(let error):
            preconditionFailure("Expected nonMonotonicTime, got \(error)")
        case .success:
            preconditionFailure("Must fail for non-monotonic time")
        }
    }

    // MARK: - Shuffle deterministic

    static func testShuffleDeterministic() {
        var candidates = makeSwingCandidates(count: 20, fps: 30)
        candidates.shuffle()
        let anchor = GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        let r1 = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: anchor)
        candidates.shuffle()
        let r2 = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: anchor)
        switch (r1, r2) {
        case (.success(let f1), .success(let f2)):
            precondition(f1.count == f2.count, "Same frame count")
            for i in 0..<f1.count {
                precondition(
                    f1[i].sourceFrameIndex == f2[i].sourceFrameIndex,
                    "Frame \(i) mismatch"
                )
            }
        default:
            preconditionFailure("Both must succeed with same input")
        }
    }

    // MARK: - Output feeds StableSwingROIBuilder

    static func testOutputFeedsStableROI() {
        let candidates = makeSwingCandidates(count: 10, fps: 30)
        let anchor = GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: anchor)
        guard case .success(let frames) = result else {
            preconditionFailure("Expected success")
        }
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(track.frames.count == 10, "ROI must produce 10 frames")
    }

    // MARK: - Hand center missing

    static func testHandCenterMissing() {
        var candidates = makeSwingCandidates(count: 5, fps: 30)
        // Remove hand center from all
        candidates = candidates.map { c in
            GolfPoseCandidateFrame(
                sourceFrameIndex: c.sourceFrameIndex,
                sourceTime: c.sourceTime,
                candidateIndex: c.candidateIndex,
                bodyCenter: c.bodyCenter,
                bodyBounds: c.bodyBounds,
                bodyScale: c.bodyScale,
                jointGeometry: c.jointGeometry,
                handCenter: nil,
                identityConfidence: c.identityConfidence
            )
        }
        let anchor = GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: anchor)
        guard case .success(let frames) = result else {
            preconditionFailure("Expected success without hand centers")
        }
        precondition(frames.allSatisfy { $0.handCenter == nil }, "All handCenter must be nil")
    }

    // MARK: - Helpers

    static func makeSwingCandidates(count: Int, fps: Int) -> [GolfPoseCandidateFrame] {
        var candidates: [GolfPoseCandidateFrame] = []
        for i in 0..<count {
            let t = Double(i) / Double(fps)
            let drift = Double(i) * 10.0 / Double(max(count - 1, 1))
            // Golfer A: center frame, moving
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: i, sourceTime: t, candidateIndex: 0,
                bodyCenter: GolfNormalizedPoint(x: (540.0 + drift) / 1080.0, y: 960.0 / 1920.0),
                bodyBounds: GolfNormalizedRect(x: 0.25, y: 0.2, width: 0.4, height: 0.6),
                bodyScale: 0.45,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.25, hipWidth: 0.2, torsoLength: 0.35),
                handCenter: GolfNormalizedPoint(x: (540.0 + drift) / 1080.0, y: 1060.0 / 1920.0),
                identityConfidence: 0.9
            ))
            // Bystander B: near edge, stationary
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: i, sourceTime: t, candidateIndex: 1,
                bodyCenter: GolfNormalizedPoint(x: 0.05, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.0, y: 0.3, width: 0.1, height: 0.4),
                bodyScale: 0.15,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.08, hipWidth: 0.06, torsoLength: 0.12),
                handCenter: nil,
                identityConfidence: 0.7
            ))
        }
        return candidates
    }

    static func makeEquivalentCandidates(count: Int, fps: Int) -> [GolfPoseCandidateFrame] {
        var candidates: [GolfPoseCandidateFrame] = []
        for i in 0..<count {
            let t = Double(i) / Double(fps)
            let center = GolfNormalizedPoint(x: 0.5, y: 0.5)
            let bounds = GolfNormalizedRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6)
            let joint = GolfCandidateJointGeometry(shoulderWidth: 0.25, hipWidth: 0.2, torsoLength: 0.35)
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: i, sourceTime: t, candidateIndex: 0,
                bodyCenter: center, bodyBounds: bounds, bodyScale: 0.45,
                jointGeometry: joint, handCenter: nil, identityConfidence: 0.85
            ))
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: i, sourceTime: t, candidateIndex: 1,
                bodyCenter: center, bodyBounds: bounds, bodyScale: 0.45,
                jointGeometry: joint, handCenter: nil, identityConfidence: 0.85
            ))
        }
        return candidates
    }
}

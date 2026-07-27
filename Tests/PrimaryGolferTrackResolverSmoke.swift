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
        testCandidateOrderIndependence()
        testMiddleAnchorResolvesBothDirections()
        testInvalidScaleFails()
        testInconsistentFrameTimeFails()
        testExactAmbiguityBoundaryPasses()
        testSingleCandidateWithoutAnchor()
        testMultiAnchorSplitsLongAmbiguity()
        testConflictingMultiAnchorsFail()
        testMultiAnchorNonExistentCandidateFails()
        print("All PrimaryGolferTrackResolver tests passed.")
    }

    // MARK: - Anchor to golfer A, all frames keep A with correct body position

    static func testAnchorToGolferA() {
        let candidates = makeSwingCandidates(count: 60, fps: 30)
        let anchor = GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: anchor)
        switch result {
        case .success(let frames):
            precondition(frames.count == 60, "Must have 60 frames, got \(frames.count)")
            // Assert every frame selected golfer A's actual body position
            let sorted = candidates.filter { $0.candidateIndex == 0 }.sorted { $0.sourceFrameIndex < $1.sourceFrameIndex }
            for (i, frame) in frames.enumerated() {
                let expected = sorted[i]
                precondition(
                    abs(frame.bodyCenter.x - expected.bodyCenter.x) < 1e-6 &&
                    abs(frame.bodyCenter.y - expected.bodyCenter.y) < 1e-6,
                    "Frame \(i): bodyCenter mismatch — got (\(frame.bodyCenter.x), \(frame.bodyCenter.y)), expected (\(expected.bodyCenter.x), \(expected.bodyCenter.y))"
                )
                precondition(frame.identityConfidence > 0, "Confidence must be positive")
            }
        case .failure(let error):
            preconditionFailure("Expected success, got \(error)")
        }
    }

    // MARK: - Crossing: B is bigger for 5 frames, still keep A (assert body position)

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
            precondition(frames.count == 30, "Must have 30 frames")
            // Assert every frame selected golfer A's body center (not the bystander's)
            let golferA = candidates.filter { $0.candidateIndex == 0 }.sorted { $0.sourceFrameIndex < $1.sourceFrameIndex }
            for (i, frame) in frames.enumerated() {
                let expected = golferA[i]
                precondition(
                    abs(frame.bodyCenter.x - expected.bodyCenter.x) < 1e-6 &&
                    abs(frame.bodyCenter.y - expected.bodyCenter.y) < 1e-6,
                    "Frame \(i): bodyCenter mismatch — got (\(frame.bodyCenter.x), \(frame.bodyCenter.y)), expected (\(expected.bodyCenter.x), \(expected.bodyCenter.y))"
                )
            }
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
        var candidates = makeSwingCandidates(count: 10, fps: 30)
        // Make bystander very similar to golfer for frames 3-7
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
        switch result {
        case .success(let frames):
            precondition(frames.count == 10, "Must resolve all frames")
        case .failure(let error):
            preconditionFailure("Expected success with anchor, got \(error)")
        }
    }

    // MARK: - Ambiguity exceeds 150ms → failure

    static func testAmbiguityExceeds150ms() {
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
        let candidates = makeSwingCandidates(count: 5, fps: 30).map { candidate in
            let sourceTime: Double
            if candidate.sourceFrameIndex == 1 {
                sourceTime = 2.0 / 30.0
            } else if candidate.sourceFrameIndex == 2 {
                sourceTime = 1.0 / 30.0
            } else {
                sourceTime = candidate.sourceTime
            }
            return GolfPoseCandidateFrame(
                sourceFrameIndex: candidate.sourceFrameIndex,
                sourceTime: sourceTime,
                candidateIndex: candidate.candidateIndex,
                bodyCenter: candidate.bodyCenter,
                bodyBounds: candidate.bodyBounds,
                bodyScale: candidate.bodyScale,
                jointGeometry: candidate.jointGeometry,
                handCenter: candidate.handCenter,
                identityConfidence: candidate.identityConfidence
            )
        }
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

    // MARK: - Shuffle deterministic (assert body positions match)

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
                    "Frame \(i) index mismatch"
                )
                precondition(
                    f1[i].bodyCenter == f2[i].bodyCenter,
                    "Frame \(i) bodyCenter mismatch after shuffle"
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

    // MARK: - Candidate order independence

    /// Candidate order changes across frames (index 0 = golfer in odd frames, bystander in even frames).
    /// Resolver must compare geometry, not index, and still track the golfer.
    static func testCandidateOrderIndependence() {
        var candidates: [GolfPoseCandidateFrame] = []
        for i in 0..<10 {
            let t = Double(i) / 30.0
            let golferIdx = (i % 2 == 0) ? 0 : 1
            let bystanderIdx = 1 - golferIdx
            // Golfer: center, drifting
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: i, sourceTime: t, candidateIndex: golferIdx,
                bodyCenter: GolfNormalizedPoint(x: 0.5 + Double(i) * 0.005, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6),
                bodyScale: 0.45,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.25, hipWidth: 0.2, torsoLength: 0.35),
                handCenter: nil,
                identityConfidence: 0.9
            ))
            // Bystander: near edge, stationary
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: i, sourceTime: t, candidateIndex: bystanderIdx,
                bodyCenter: GolfNormalizedPoint(x: 0.05, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.0, y: 0.3, width: 0.1, height: 0.4),
                bodyScale: 0.15,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.08, hipWidth: 0.06, torsoLength: 0.12),
                handCenter: nil,
                identityConfidence: 0.7
            ))
        }
        // Anchor at frame 0, candidate 0 = golfer
        let anchor = GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchor: anchor)
        switch result {
        case .success(let frames):
            precondition(frames.count == 10, "Must resolve all 10 frames")
            // Assert every frame tracks the golfer (center ~0.5, not edge ~0.05)
            for (i, frame) in frames.enumerated() {
                precondition(
                    frame.bodyCenter.x > 0.3,
                    "Frame \(i): resolver switched to bystander at x=\(frame.bodyCenter.x)"
                )
            }
        case .failure(let error):
            preconditionFailure("Expected success, got \(error)")
        }
    }

    // MARK: - Anchor and input validation

    static func testMiddleAnchorResolvesBothDirections() {
        var candidates: [GolfPoseCandidateFrame] = []
        for frame in 0..<9 {
            let golferIndex = frame.isMultiple(of: 2) ? 0 : 1
            let bystanderIndex = 1 - golferIndex
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: frame,
                sourceTime: Double(frame) / 30.0,
                candidateIndex: golferIndex,
                bodyCenter: GolfNormalizedPoint(x: 0.48 + Double(frame) * 0.005, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.28, y: 0.2, width: 0.4, height: 0.6),
                bodyScale: 0.45,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.25, hipWidth: 0.2, torsoLength: 0.35),
                handCenter: nil,
                identityConfidence: 0.9
            ))
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: frame,
                sourceTime: Double(frame) / 30.0,
                candidateIndex: bystanderIndex,
                bodyCenter: GolfNormalizedPoint(x: 0.08, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.0, y: 0.3, width: 0.15, height: 0.4),
                bodyScale: 0.2,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.1, hipWidth: 0.08, torsoLength: 0.15),
                handCenter: nil,
                identityConfidence: 0.75
            ))
        }
        let result = PrimaryGolferTrackResolver.resolve(
            candidates: candidates,
            manualAnchor: GolfPoseCandidateIdentifier(sourceFrameIndex: 4, candidateIndex: 0)
        )
        guard case .success(let frames) = result else {
            preconditionFailure("Middle anchor must resolve: \(result)")
        }
        precondition(frames.count == 9)
        precondition(frames.allSatisfy { $0.bodyCenter.x > 0.3 })
    }

    static func testInvalidScaleFails() {
        let invalid = GolfPoseCandidateFrame(
            sourceFrameIndex: 0,
            sourceTime: 0,
            candidateIndex: 0,
            bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
            bodyBounds: GolfNormalizedRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6),
            bodyScale: 0,
            jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.25, hipWidth: 0.2, torsoLength: 0.35),
            handCenter: nil,
            identityConfidence: 0.9
        )
        let result = PrimaryGolferTrackResolver.resolve(
            candidates: [invalid],
            manualAnchor: GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        )
        guard case .failure(.invalidCandidate(frameIndex: 0, candidateIndex: 0)) = result else {
            preconditionFailure("Invalid scale must fail: \(result)")
        }
    }

    static func testInconsistentFrameTimeFails() {
        var candidates = makeSwingCandidates(count: 2, fps: 30)
        let index = candidates.firstIndex {
            $0.sourceFrameIndex == 0 && $0.candidateIndex == 1
        }!
        let original = candidates[index]
        candidates[index] = GolfPoseCandidateFrame(
            sourceFrameIndex: original.sourceFrameIndex,
            sourceTime: 0.01,
            candidateIndex: original.candidateIndex,
            bodyCenter: original.bodyCenter,
            bodyBounds: original.bodyBounds,
            bodyScale: original.bodyScale,
            jointGeometry: original.jointGeometry,
            handCenter: original.handCenter,
            identityConfidence: original.identityConfidence
        )
        let result = PrimaryGolferTrackResolver.resolve(
            candidates: candidates,
            manualAnchor: GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        )
        guard case .failure(.inconsistentFrameTime(0)) = result else {
            preconditionFailure("Candidates in one source frame must share time: \(result)")
        }
    }

    static func testExactAmbiguityBoundaryPasses() {
        var candidates: [GolfPoseCandidateFrame] = []
        for frame in 0..<5 {
            for candidateIndex in 0..<2 {
                candidates.append(GolfPoseCandidateFrame(
                    sourceFrameIndex: frame,
                    sourceTime: Double(frame) * 0.05,
                    candidateIndex: candidateIndex,
                    bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
                    bodyBounds: GolfNormalizedRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6),
                    bodyScale: 0.45,
                    jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.25, hipWidth: 0.2, torsoLength: 0.35),
                    handCenter: nil,
                    identityConfidence: 0.85
                ))
            }
        }
        let result = PrimaryGolferTrackResolver.resolve(
            candidates: candidates,
            manualAnchor: GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        )
        guard case .success(let frames) = result else {
            preconditionFailure("Exactly 150ms of ambiguity is allowed: \(result)")
        }
        precondition(frames.count == 5)
    }

    static func testSingleCandidateWithoutAnchor() {
        let candidate = GolfPoseCandidateFrame(
            sourceFrameIndex: 0,
            sourceTime: 0,
            candidateIndex: 4,
            bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
            bodyBounds: GolfNormalizedRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6),
            bodyScale: 0.6,
            jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.25, hipWidth: 0.2, torsoLength: 0.35),
            handCenter: nil,
            identityConfidence: 0.9
        )
        let result = PrimaryGolferTrackResolver.resolve(
            candidates: [candidate],
            manualAnchor: nil
        )
        guard case .success(let frames) = result else {
            preconditionFailure("One unambiguous candidate must resolve without an anchor: \(result)")
        }
        precondition(frames.count == 1)
        precondition(frames[0].bodyCenter == candidate.bodyCenter)
    }

    // MARK: - Helpers

    static func makeSwingCandidates(count: Int, fps: Int) -> [GolfPoseCandidateFrame] {
        var candidates: [GolfPoseCandidateFrame] = []
        for i in 0..<count {
            let t = Double(i) / Double(fps)
            let drift = Double(i) * 10.0 / Double(max(count - 1, 1))
            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: i, sourceTime: t, candidateIndex: 0,
                bodyCenter: GolfNormalizedPoint(x: (540.0 + drift) / 1080.0, y: 960.0 / 1920.0),
                bodyBounds: GolfNormalizedRect(x: 0.25, y: 0.2, width: 0.4, height: 0.6),
                bodyScale: 0.45,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.25, hipWidth: 0.2, torsoLength: 0.35),
                handCenter: GolfNormalizedPoint(x: (540.0 + drift) / 1080.0, y: 1060.0 / 1920.0),
                identityConfidence: 0.9
            ))
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

    static func testMultiAnchorSplitsLongAmbiguity() {
        let candidates = makeEquivalentCandidates(count: 9, fps: 30) // frames 0..8, ambiguous everywhere without anchors
        let anchor1 = GolfPoseCandidateIdentifier(sourceFrameIndex: 0, candidateIndex: 0)
        let anchor2 = GolfPoseCandidateIdentifier(sourceFrameIndex: 4, candidateIndex: 0)
        let anchor3 = GolfPoseCandidateIdentifier(sourceFrameIndex: 8, candidateIndex: 0)
        let anchors = [anchor1, anchor2, anchor3]
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchors: anchors)
        switch result {
        case .success(let frames):
            precondition(frames.count == 9, "Must resolve all 9 frames, got \(frames.count)")
            precondition(frames[0].bodyCenter == candidates.first(where: { $0.sourceFrameIndex == 0 && $0.candidateIndex == 0 })!.bodyCenter)
            precondition(frames[4].bodyCenter == candidates.first(where: { $0.sourceFrameIndex == 4 && $0.candidateIndex == 0 })!.bodyCenter)
            precondition(frames[8].bodyCenter == candidates.first(where: { $0.sourceFrameIndex == 8 && $0.candidateIndex == 0 })!.bodyCenter)
        case .failure(let err):
            preconditionFailure("Expected success for multi-anchor split, got \(err)")
        }
    }

    static func testConflictingMultiAnchorsFail() {
        let candidates = makeEquivalentCandidates(count: 30, fps: 30)
        let anchor1 = GolfPoseCandidateIdentifier(sourceFrameIndex: 5, candidateIndex: 0)
        let anchor2 = GolfPoseCandidateIdentifier(sourceFrameIndex: 5, candidateIndex: 1) // conflict on frame 5!
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchors: [anchor1, anchor2])
        if case .success = result {
            preconditionFailure("Expected failure on conflicting anchors")
        }
    }

    static func testMultiAnchorNonExistentCandidateFails() {
        let candidates = makeEquivalentCandidates(count: 30, fps: 30)
        let anchor = GolfPoseCandidateIdentifier(sourceFrameIndex: 5, candidateIndex: 99)
        let result = PrimaryGolferTrackResolver.resolve(candidates: candidates, manualAnchors: [anchor])
        if case .success = result {
            preconditionFailure("Expected failure on non-existent candidate anchor")
        }
    }
}

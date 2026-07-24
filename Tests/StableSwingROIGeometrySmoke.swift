import Foundation

@main
struct StableSwingROIGeometrySmoke {
    static func main() throws {
        testRoundTripAccuracy()
        testCenterMovementP95()
        testDeterministicOutput()
        testInterpolatedGap()
        testPoseGapTooLong()
        testNonMonotonicTime()
        testIdentityUnstable()
        testCoverageFailed()
        testEmptyInputNoCrash()
        testIllegalDimensionsNoCrash()
        print("All StableSwingROIGeometry tests passed.")
    }

    // MARK: - Round-trip accuracy: 0.5 source pixels

    static func testRoundTripAccuracy() {
        let frames = makeDriftFrames(count: 60, driftPixels: 20, fps: 30)
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: .init(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(track.frames.count == 60, "Must have 60 frames, got \(track.frames.count)")

        for frame in track.frames {
            let source = GolfNormalizedPoint(x: 0.42, y: 0.63)
            let roi = frame.transform.fullFramePointToROI(source)
            let restored = frame.transform.roiPointToFullFrame(roi)
            let sourcePixelError = hypot(
                (restored.x - source.x) * 1080,
                (restored.y - source.y) * 1920
            )
            precondition(
                sourcePixelError <= 0.5,
                "Round-trip error \(sourcePixelError) exceeds 0.5 source pixels at frame \(frame.sourceFrameIndex)"
            )
        }
    }

    // MARK: - Center movement P95 ≤ 12 target pixels

    static func testCenterMovementP95() {
        let frames = makeDriftFrames(count: 60, driftPixels: 20, fps: 30)
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: .init(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(
            track.centerMovementP95InTargetPixels <= 12,
            "Center movement P95 \(track.centerMovementP95InTargetPixels) exceeds 12"
        )
    }

    // MARK: - Deterministic output

    static func testDeterministicOutput() {
        let frames = makeDriftFrames(count: 60, driftPixels: 20, fps: 30)
        let track1 = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: .init(width: 1080, height: 1920),
            targetSize: 512
        )
        let track2 = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: .init(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(track1 == track2, "Builder must be deterministic")
    }

    // MARK: - 3-frame gap (~133ms at 30fps) interpolation allowed

    static func testInterpolatedGap() {
        var frames = makeDriftFrames(count: 60, driftPixels: 10, fps: 30)
        // Remove frames 28,29,30 to create a ~133ms gap (4 intervals)
        frames = frames.filter { $0.sourceFrameIndex < 28 || $0.sourceFrameIndex > 30 }
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: .init(width: 1080, height: 1920),
            targetSize: 512
        )
        // Should still produce 60 frames (interpolated)
        precondition(track.frames.count == 60, "Interpolation must fill 3-frame gap, got \(track.frames.count)")
    }

    // MARK: - 5-frame gap (~200ms) must fail

    static func testPoseGapTooLong() {
        var frames = makeDriftFrames(count: 60, driftPixels: 10, fps: 30)
        // Remove frames 27-31 to create a ~200ms gap (6 intervals)
        frames = frames.filter { $0.sourceFrameIndex < 27 || $0.sourceFrameIndex > 31 }
        do {
            _ = try StableSwingROIBuilder.build(
                poseFrames: frames,
                orientedFrameSize: .init(width: 1080, height: 1920),
                targetSize: 512
            )
            preconditionFailure("6-frame gap must throw .poseGapTooLong")
        } catch {}
    }

    // MARK: - Non-monotonic time must fail

    static func testNonMonotonicTime() {
        var frames = makeDriftFrames(count: 10, driftPixels: 0, fps: 30)
        // Swap timestamps to create non-monotonicity
        let t0 = frames[0].sourceTime
        let t1 = frames[1].sourceTime
        frames[0] = GolfPoseTrackFrame(
            sourceFrameIndex: frames[0].sourceFrameIndex,
            sourceTime: t1,
            bodyCenter: frames[0].bodyCenter,
            bodyBounds: frames[0].bodyBounds,
            handCenter: frames[0].handCenter,
            identityConfidence: frames[0].identityConfidence
        )
        frames[1] = GolfPoseTrackFrame(
            sourceFrameIndex: frames[1].sourceFrameIndex,
            sourceTime: t0,
            bodyCenter: frames[1].bodyCenter,
            bodyBounds: frames[1].bodyBounds,
            handCenter: frames[1].handCenter,
            identityConfidence: frames[1].identityConfidence
        )
        do {
            _ = try StableSwingROIBuilder.build(
                poseFrames: frames,
                orientedFrameSize: .init(width: 1080, height: 1920),
                targetSize: 512
            )
            preconditionFailure("Non-monotonic time must throw error")
        } catch {}
    }

    // MARK: - Low identity confidence must fail

    static func testIdentityUnstable() {
        var frames = makeDriftFrames(count: 10, driftPixels: 0, fps: 30)
        // Set all confidence below 0.5
        frames = frames.map { f in
            GolfPoseTrackFrame(
                sourceFrameIndex: f.sourceFrameIndex,
                sourceTime: f.sourceTime,
                bodyCenter: f.bodyCenter,
                bodyBounds: f.bodyBounds,
                handCenter: f.handCenter,
                identityConfidence: 0.3
            )
        }
        do {
            _ = try StableSwingROIBuilder.build(
                poseFrames: frames,
                orientedFrameSize: .init(width: 1080, height: 1920),
                targetSize: 512
            )
            preconditionFailure("Low confidence must throw .identityUnstable")
        } catch {}
    }

    // MARK: - Coverage failure

    static func testCoverageFailed() {
        // Zero-size body bounds
        let frames = (0..<10).map { i in
            GolfPoseTrackFrame(
                sourceFrameIndex: i,
                sourceTime: Double(i) / 30.0,
                bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
                bodyBounds: GolfAxisAlignedRect(x: 0, y: 0, width: 0, height: 0),
                handCenter: nil,
                identityConfidence: 0.9
            )
        }
        do {
            _ = try StableSwingROIBuilder.build(
                poseFrames: frames,
                orientedFrameSize: .init(width: 1080, height: 1920),
                targetSize: 512
            )
            preconditionFailure("Zero bounds must throw .coverageFailed")
        } catch {}
    }

    // MARK: - Empty input no crash

    static func testEmptyInputNoCrash() {
        let result = try? StableSwingROIBuilder.build(
            poseFrames: [],
            orientedFrameSize: .init(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(result == nil || result!.frames.isEmpty, "Empty input must not crash")
    }

    // MARK: - Illegal dimensions no crash

    static func testIllegalDimensionsNoCrash() {
        let frames = makeDriftFrames(count: 5, driftPixels: 0, fps: 30)
        let result1 = try? StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: .init(width: 0, height: 1920),
            targetSize: 512
        )
        precondition(result1 == nil || result1!.frames.isEmpty, "Zero width must not crash")

        let result2 = try? StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: .init(width: 1080, height: 1920),
            targetSize: 0
        )
        precondition(result2 == nil || result2!.frames.isEmpty, "Zero target size must not crash")
    }

    // MARK: - Helpers

    static func makeDriftFrames(count: Int, driftPixels: Double, fps: Int) -> [GolfPoseTrackFrame] {
        (0..<count).map { i in
            let t = Double(i) / Double(fps)
            let drift = Double(i) * driftPixels / Double(count - 1)
            let cx = (540.0 + drift) / 1080.0
            let cy = 960.0 / 1920.0
            return GolfPoseTrackFrame(
                sourceFrameIndex: i,
                sourceTime: t,
                bodyCenter: GolfNormalizedPoint(x: cx, y: cy),
                bodyBounds: GolfAxisAlignedRect(x: cx * 1080 - 200, y: cy * 1920 - 400, width: 400, height: 800),
                handCenter: GolfNormalizedPoint(x: cx, y: cy + 0.1),
                identityConfidence: 0.95
            )
        }
    }
}

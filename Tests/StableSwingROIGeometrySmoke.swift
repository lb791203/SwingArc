import Foundation

@main
struct StableSwingROIGeometrySmoke {
    static func main() throws {
        testRoundTripAccuracy()
        testCropCornerMapping()
        testBodyBoundsEnterROI()
        testSmoothingSatisfiesThreshold()
        testSmoothingPureFunction()
        testSmoothingDeterministic()
        testDeterministicOutput()
        testInterpolatedGap()
        testInterpolatedFrameFlag()
        testOriginalFrameFlag()
        testPoseGapTooLong()
        testPoseGapExactThreshold()
        testNonMonotonicTime()
        testIdentityUnstable()
        testSingleLowConfidenceFrame()
        testCoverageFailed()
        testEmptyInputNoCrash()
        testIllegalDimensionsNoCrash()
        testDuplicateFramesDeduped()
        testDuplicateFrameConflict()
        testShuffleDeterministic()
        testSourceFrameIndexOffset()
        testNominalFrameDurationFromTimestamps()
        testPaddingRecorded()
        testEdgeProximityPadding()
        testEdgeProximityRoundTrip()
        print("All StableSwingROIGeometry tests passed.")
    }

    // MARK: - Round-trip accuracy

    static func testRoundTripAccuracy() {
        let frames = makeDriftFrames(count: 60, driftPixels: 20, fps: 30)
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
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

    // MARK: - Crop corner mapping

    static func testCropCornerMapping() {
        let frames = makeDriftFrames(count: 10, driftPixels: 0, fps: 30)
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        let frame = track.frames[0]

        let topLeft = frame.transform.roiPointToFullFrame(GolfNormalizedPoint(x: 0, y: 0))
        let cropTopLeft = GolfNormalizedPoint(
            x: frame.cropRect.x / 1080.0,
            y: frame.cropRect.y / 1920.0
        )
        let topLeftError = hypot(
            (topLeft.x - cropTopLeft.x) * 1080,
            (topLeft.y - cropTopLeft.y) * 1920
        )
        precondition(topLeftError <= 0.5, "Crop top-left mapping error \(topLeftError)")

        let cropCenterX = (frame.cropRect.x + frame.cropRect.width / 2) / 1080.0
        let cropCenterY = (frame.cropRect.y + frame.cropRect.height / 2) / 1920.0
        let roiCenter = frame.transform.fullFramePointToROI(GolfNormalizedPoint(x: cropCenterX, y: cropCenterY))
        precondition(
            abs(roiCenter.x - 0.5) < 0.01 && abs(roiCenter.y - 0.5) < 0.01,
            "Crop center should map to ~(0.5,0.5), got \(roiCenter)"
        )

        let cropBR = GolfNormalizedPoint(
            x: (frame.cropRect.x + frame.cropRect.width) / 1080.0,
            y: (frame.cropRect.y + frame.cropRect.height) / 1920.0
        )
        let roiBR = frame.transform.fullFramePointToROI(cropBR)
        precondition(
            abs(roiBR.x - 1.0) < 0.01 && abs(roiBR.y - 1.0) < 0.01,
            "Crop bottom-right should map to ~(1,1), got \(roiBR)"
        )

        precondition(
            frame.cropRect.width < 5000 && frame.cropRect.height < 5000,
            "Crop size \(frame.cropRect.width)x\(frame.cropRect.height) is unreasonably large"
        )
    }

    // MARK: - Body bounds enter ROI

    static func testBodyBoundsEnterROI() {
        let frames = makeDriftFrames(count: 10, driftPixels: 0, fps: 30)
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        let frame = track.frames[0]
        let bounds = frames[0].bodyBounds
        // bounds is now GolfNormalizedRect (normalized [0,1])
        let corners = [
            GolfNormalizedPoint(x: bounds.x, y: bounds.y),
            GolfNormalizedPoint(x: bounds.x + bounds.width, y: bounds.y),
            GolfNormalizedPoint(x: bounds.x, y: bounds.y + bounds.height),
            GolfNormalizedPoint(x: bounds.x + bounds.width, y: bounds.y + bounds.height),
        ]
        for corner in corners {
            let roi = frame.transform.fullFramePointToROI(corner)
            precondition(
                roi.x >= -0.01 && roi.x <= 1.01 && roi.y >= -0.01 && roi.y <= 1.01,
                "Body corner \(corner) maps outside ROI: \(roi)"
            )
        }
        precondition(frame.coverageOK, "coverageOK must be true when bounds are covered")
    }

    // MARK: - Smoothing satisfies threshold

    static func testSmoothingSatisfiesThreshold() {
        var frames = makeDriftFrames(count: 60, driftPixels: 2, fps: 30)
        frames[30] = GolfPoseTrackFrame(
            sourceFrameIndex: 30,
            sourceTime: frames[30].sourceTime,
            bodyCenter: GolfNormalizedPoint(x: (540.0 + 50.0) / 1080.0, y: 960.0 / 1920.0),
            bodyBounds: frames[30].bodyBounds,
            handCenter: frames[30].handCenter,
            identityConfidence: 0.95
        )
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(
            track.centerMovementP95InTargetPixels <= 12,
            "Smoothed P95 \(track.centerMovementP95InTargetPixels) exceeds 12"
        )
    }

    // MARK: - Smoothing pure function

    static func testSmoothingPureFunction() {
        // Synthetic sequence with a large spike
        let centers: [(Double, Double)] = [
            (100, 100), (101, 100), (102, 100), (103, 100),
            (200, 100),  // spike
            (104, 100), (105, 100), (106, 100), (107, 100),
        ]
        let maxCorrection = 10.0
        let smoothed = StableSwingROIBuilder.bidirectionalSmooth(centers, maxCorrection: maxCorrection)

        // Verify each step <= maxCorrection
        for i in 1..<smoothed.count {
            let dist = hypot(smoothed[i].0 - smoothed[i-1].0, smoothed[i].1 - smoothed[i-1].1)
            precondition(
                dist <= maxCorrection + 0.001,
                "Step \(i) distance \(dist) exceeds maxCorrection \(maxCorrection)"
            )
        }

        // Unsmoothed P95 would exceed threshold
        var rawMovements: [Double] = []
        for i in 1..<centers.count {
            rawMovements.append(hypot(centers[i].0 - centers[i-1].0, centers[i].1 - centers[i-1].1))
        }
        rawMovements.sort()
        let rawP95 = rawMovements[rawMovements.count * 95 / 100]
        precondition(rawP95 > 12, "Raw P95 (\(rawP95)) should exceed 12 for unsmoothed spike")

        // Smoothed P95 must be <= 12
        var smoothMovements: [Double] = []
        for i in 1..<smoothed.count {
            smoothMovements.append(hypot(smoothed[i].0 - smoothed[i-1].0, smoothed[i].1 - smoothed[i-1].1))
        }
        smoothMovements.sort()
        let smoothP95 = smoothMovements[smoothMovements.count * 95 / 100]
        precondition(smoothP95 <= 12, "Smoothed P95 (\(smoothP95)) must be <= 12")
    }

    // MARK: - Smoothing deterministic

    static func testSmoothingDeterministic() {
        let centers: [(Double, Double)] = [
            (0, 0), (5, 0), (10, 0), (50, 0), (15, 0), (20, 0),
        ]
        let r1 = StableSwingROIBuilder.bidirectionalSmooth(centers, maxCorrection: 8)
        let r2 = StableSwingROIBuilder.bidirectionalSmooth(centers, maxCorrection: 8)
        precondition(r1.count == r2.count, "Smoothing must produce same count")
        for i in 0..<r1.count {
            precondition(
                r1[i].0 == r2[i].0 && r1[i].1 == r2[i].1,
                "Smoothing must be deterministic at index \(i)"
            )
        }
    }

    // MARK: - Deterministic output

    static func testDeterministicOutput() {
        let frames = makeDriftFrames(count: 60, driftPixels: 20, fps: 30)
        let track1 = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        let track2 = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(track1 == track2, "Builder must be deterministic")
    }

    // MARK: - 3-frame gap interpolation allowed

    static func testInterpolatedGap() {
        var frames = makeDriftFrames(count: 60, driftPixels: 10, fps: 30)
        frames = frames.filter { $0.sourceFrameIndex < 28 || $0.sourceFrameIndex > 30 }
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(track.frames.count == 60, "Interpolation must fill 3-frame gap, got \(track.frames.count)")
    }

    // MARK: - Interpolated frame flag

    static func testInterpolatedFrameFlag() {
        var frames = makeDriftFrames(count: 10, driftPixels: 5, fps: 30)
        frames = frames.filter { $0.sourceFrameIndex < 3 || $0.sourceFrameIndex > 5 }
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        let interpFrames = track.frames.filter { $0.interpolated }
        let originalFrames = track.frames.filter { !$0.interpolated }
        precondition(!interpFrames.isEmpty, "Must have interpolated frames")
        precondition(originalFrames.count >= 7, "Must have at least 7 original frames")
    }

    // MARK: - Original frame flag

    static func testOriginalFrameFlag() {
        let frames = makeDriftFrames(count: 10, driftPixels: 0, fps: 30)
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        let interpCount = track.frames.filter { $0.interpolated }.count
        precondition(interpCount == 0, "No frames should be interpolated when no gaps")
    }

    // MARK: - 5-frame gap must fail

    static func testPoseGapTooLong() {
        var frames = makeDriftFrames(count: 60, driftPixels: 10, fps: 30)
        frames = frames.filter { $0.sourceFrameIndex < 27 || $0.sourceFrameIndex > 31 }
        do {
            _ = try StableSwingROIBuilder.build(
                poseFrames: frames,
                orientedFrameSize: CGSize(width: 1080, height: 1920),
                targetSize: 512
            )
            preconditionFailure("5-frame gap must throw .poseGapTooLong")
        } catch StableSwingROIError.poseGapTooLong {} catch {
            preconditionFailure("Expected .poseGapTooLong, got \(error)")
        }
    }

    // MARK: - Pose gap exact threshold

    static func testPoseGapExactThreshold() {
        // 4 missing frames at 30fps: gap = 5 * 33.3ms = 166.7ms
        // missingDuration = 166.7 - 33.3 = 133.3ms < 150ms → should pass
        var frames = makeDriftFrames(count: 20, driftPixels: 5, fps: 30)
        frames = frames.filter { $0.sourceFrameIndex < 8 || $0.sourceFrameIndex > 11 }
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(track.frames.count == 20, "4-frame gap must pass, got \(track.frames.count)")
    }

    // MARK: - Non-monotonic time must fail

    static func testNonMonotonicTime() {
        var frames = makeDriftFrames(count: 10, driftPixels: 0, fps: 30)
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
                orientedFrameSize: CGSize(width: 1080, height: 1920),
                targetSize: 512
            )
            preconditionFailure("Non-monotonic time must throw error")
        } catch StableSwingROIError.nonMonotonicTime {} catch {
            preconditionFailure("Expected .nonMonotonicTime, got \(error)")
        }
    }

    // MARK: - Low identity confidence must fail

    static func testIdentityUnstable() {
        let frames = (0..<10).map { i in
            GolfPoseTrackFrame(
                sourceFrameIndex: i,
                sourceTime: Double(i) / 30.0,
                bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.3, y: 0.25, width: 0.37, height: 0.42),
                handCenter: nil,
                identityConfidence: 0.3
            )
        }
        do {
            _ = try StableSwingROIBuilder.build(
                poseFrames: frames,
                orientedFrameSize: CGSize(width: 1080, height: 1920),
                targetSize: 512
            )
            preconditionFailure("Low confidence must throw .identityUnstable")
        } catch StableSwingROIError.identityUnstable {} catch {
            preconditionFailure("Expected .identityUnstable, got \(error)")
        }
    }

    // MARK: - Single low confidence frame rejected

    static func testSingleLowConfidenceFrame() {
        var frames = makeDriftFrames(count: 10, driftPixels: 0, fps: 30)
        frames[5] = GolfPoseTrackFrame(
            sourceFrameIndex: 5,
            sourceTime: frames[5].sourceTime,
            bodyCenter: frames[5].bodyCenter,
            bodyBounds: frames[5].bodyBounds,
            handCenter: nil,
            identityConfidence: 0.1
        )
        do {
            _ = try StableSwingROIBuilder.build(
                poseFrames: frames,
                orientedFrameSize: CGSize(width: 1080, height: 1920),
                targetSize: 512
            )
            preconditionFailure("Single low-confidence frame must throw .identityUnstable")
        } catch StableSwingROIError.identityUnstable {} catch {
            preconditionFailure("Expected .identityUnstable, got \(error)")
        }
    }

    // MARK: - Coverage failure

    static func testCoverageFailed() {
        let frames = (0..<10).map { i in
            GolfPoseTrackFrame(
                sourceFrameIndex: i,
                sourceTime: Double(i) / 30.0,
                bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.5, y: 0.5, width: 0, height: 0),
                handCenter: nil,
                identityConfidence: 0.9
            )
        }
        do {
            _ = try StableSwingROIBuilder.build(
                poseFrames: frames,
                orientedFrameSize: CGSize(width: 1080, height: 1920),
                targetSize: 512
            )
            preconditionFailure("Zero bounds must throw .coverageFailed")
        } catch StableSwingROIError.coverageFailed {} catch {
            preconditionFailure("Expected .coverageFailed, got \(error)")
        }
    }

    // MARK: - Empty input no crash

    static func testEmptyInputNoCrash() {
        let result = try? StableSwingROIBuilder.build(
            poseFrames: [],
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(result == nil || result!.frames.isEmpty, "Empty input must not crash")
    }

    // MARK: - Illegal dimensions no crash

    static func testIllegalDimensionsNoCrash() {
        let frames = makeDriftFrames(count: 5, driftPixels: 0, fps: 30)
        let result1 = try? StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 0, height: 1920),
            targetSize: 512
        )
        precondition(result1 == nil || result1!.frames.isEmpty, "Zero width must not crash")

        let result2 = try? StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 0
        )
        precondition(result2 == nil || result2!.frames.isEmpty, "Zero target size must not crash")
    }

    // MARK: - Duplicate frames deduped

    static func testDuplicateFramesDeduped() {
        var frames = makeDriftFrames(count: 10, driftPixels: 0, fps: 30)
        frames.append(frames[5])
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(track.frames.count == 10, "Duplicates must be deduped, got \(track.frames.count)")
    }

    // MARK: - Duplicate frame conflict

    static func testDuplicateFrameConflict() {
        var frames = makeDriftFrames(count: 10, driftPixels: 0, fps: 30)
        let conflicting = GolfPoseTrackFrame(
            sourceFrameIndex: 5,
            sourceTime: frames[5].sourceTime + 1.0,
            bodyCenter: GolfNormalizedPoint(x: 0.99, y: 0.99),
            bodyBounds: frames[5].bodyBounds,
            handCenter: nil,
            identityConfidence: 0.5
        )
        frames.append(conflicting)
        do {
            _ = try StableSwingROIBuilder.build(
                poseFrames: frames,
                orientedFrameSize: CGSize(width: 1080, height: 1920),
                targetSize: 512
            )
            preconditionFailure("Conflicting duplicate must throw .duplicateFrameConflict")
        } catch StableSwingROIError.duplicateFrameConflict(5) {} catch {
            preconditionFailure("Expected .duplicateFrameConflict, got \(error)")
        }
    }

    // MARK: - Shuffle deterministic

    static func testShuffleDeterministic() {
        var frames = makeDriftFrames(count: 20, driftPixels: 15, fps: 30)
        frames.shuffle()
        let track1 = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        frames.shuffle()
        let track2 = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(track1 == track2, "Shuffled input must produce same output")
    }

    // MARK: - Source frame index offset

    static func testSourceFrameIndexOffset() {
        let frames = (100..<110).map { i in
            GolfPoseTrackFrame(
                sourceFrameIndex: i,
                sourceTime: Double(i) / 30.0,
                bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.3, y: 0.25, width: 0.37, height: 0.42),
                handCenter: nil,
                identityConfidence: 0.95
            )
        }
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(track.frames.count == 10, "Must have 10 frames")
        precondition(track.frames.first?.sourceFrameIndex == 100, "First frame must be index 100")
        precondition(track.frames.last?.sourceFrameIndex == 109, "Last frame must be index 109")
    }

    // MARK: - Nominal frame duration from timestamps

    static func testNominalFrameDurationFromTimestamps() {
        let frames = (0..<10).map { i in
            GolfPoseTrackFrame(
                sourceFrameIndex: i,
                sourceTime: Double(i) / 60.0,
                bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
                bodyBounds: GolfNormalizedRect(x: 0.3, y: 0.25, width: 0.37, height: 0.42),
                handCenter: nil,
                identityConfidence: 0.95
            )
        }
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        precondition(track.frames.count == 10, "Must have 10 frames at 60fps")
    }

    // MARK: - Padding recorded

    static func testPaddingRecorded() {
        let frames = makeDriftFrames(count: 10, driftPixels: 0, fps: 30)
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        let frame = track.frames[0]
        let totalPad = frame.paddingLeft + frame.paddingTop + frame.paddingRight + frame.paddingBottom
        precondition(totalPad >= 0, "Padding values must be non-negative")
    }

    // MARK: - Edge proximity padding

    static func testEdgeProximityPadding() {
        // Body near top-left corner
        let frames = (0..<10).map { i in
            GolfPoseTrackFrame(
                sourceFrameIndex: i,
                sourceTime: Double(i) / 30.0,
                bodyCenter: GolfNormalizedPoint(x: 0.1, y: 0.1),
                bodyBounds: GolfNormalizedRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2),
                handCenter: GolfNormalizedPoint(x: 0.05, y: 0.05),
                identityConfidence: 0.95
            )
        }
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        let frame = track.frames[0]
        // Crop should extend beyond frame boundary → padding > 0
        precondition(
            frame.paddingLeft > 0 || frame.paddingTop > 0,
            "Near top-left should have padding, got L=\(frame.paddingLeft) T=\(frame.paddingTop)"
        )
        // Crop origin can be negative (stored in cropRect)
        precondition(
            frame.cropRect.x < 0 || frame.cropRect.y < 0,
            "Crop origin should be negative for edge-proximate body"
        )
        // Transform must still map body into ROI
        let bodyCenter = GolfNormalizedPoint(x: 0.1, y: 0.1)
        let roi = frame.transform.fullFramePointToROI(bodyCenter)
        precondition(
            roi.x >= -0.01 && roi.x <= 1.01 && roi.y >= -0.01 && roi.y <= 1.01,
            "Body center must be in ROI: \(roi)"
        )
    }

    // MARK: - Edge proximity round-trip

    static func testEdgeProximityRoundTrip() {
        let frames = (0..<10).map { i in
            GolfPoseTrackFrame(
                sourceFrameIndex: i,
                sourceTime: Double(i) / 30.0,
                bodyCenter: GolfNormalizedPoint(x: 0.1, y: 0.1),
                bodyBounds: GolfNormalizedRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2),
                handCenter: GolfNormalizedPoint(x: 0.05, y: 0.05),
                identityConfidence: 0.95
            )
        }
        let track = try! StableSwingROIBuilder.build(
            poseFrames: frames,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            targetSize: 512
        )
        for frame in track.frames {
            let source = GolfNormalizedPoint(x: 0.15, y: 0.15)
            let roi = frame.transform.fullFramePointToROI(source)
            let restored = frame.transform.roiPointToFullFrame(roi)
            let error = hypot(
                (restored.x - source.x) * 1080,
                (restored.y - source.y) * 1920
            )
            precondition(
                error <= 0.5,
                "Edge round-trip error \(error) exceeds 0.5 pixels at frame \(frame.sourceFrameIndex)"
            )
        }
    }

    // MARK: - Helpers

    static func makeDriftFrames(count: Int, driftPixels: Double, fps: Int) -> [GolfPoseTrackFrame] {
        (0..<count).map { i in
            let t = Double(i) / Double(fps)
            let drift = Double(i) * driftPixels / Double(max(count - 1, 1))
            let cx = (540.0 + drift) / 1080.0
            let cy = 960.0 / 1920.0
            return GolfPoseTrackFrame(
                sourceFrameIndex: i,
                sourceTime: t,
                bodyCenter: GolfNormalizedPoint(x: cx, y: cy),
                bodyBounds: GolfNormalizedRect(
                    x: (cx * 1080 - 200) / 1080.0,
                    y: (cy * 1920 - 400) / 1920.0,
                    width: 400.0 / 1080.0,
                    height: 800.0 / 1920.0
                ),
                handCenter: GolfNormalizedPoint(x: cx, y: cy + 0.1),
                identityConfidence: 0.95
            )
        }
    }
}

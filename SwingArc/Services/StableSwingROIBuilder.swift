import Foundation

public enum StableSwingROIBuilder {
    private static let maxInterpolationGapSeconds = 0.150
    private static let minIdentityConfidence = 0.5

    public static func build(
        poseFrames: [GolfPoseTrackFrame],
        orientedFrameSize: CGSize,
        targetSize: Int,
        configuration: StableSwingROIConfiguration = .v1
    ) throws -> StableSwingROITrack {
        guard poseFrames.count >= 2,
              orientedFrameSize.width > 0, orientedFrameSize.height > 0,
              targetSize > 0 else {
            return StableSwingROITrack(
                frames: [],
                centerMovementP95InTargetPixels: 0,
                configuration: configuration
            )
        }

        let frameW = orientedFrameSize.width
        let frameH = orientedFrameSize.height

        // 1. Sort and deduplicate by source frame
        var unique: [Int: GolfPoseTrackFrame] = [:]
        for frame in poseFrames {
            unique[frame.sourceFrameIndex] = frame
        }
        let sorted = unique.values.sorted { $0.sourceFrameIndex < $1.sourceFrameIndex }

        // 2. Validate monotonic time
        for i in 1..<sorted.count {
            guard sorted[i].sourceTime > sorted[i - 1].sourceTime else {
                throw StableSwingROIError.nonMonotonicTime
            }
        }

        // 3. Validate identity confidence
        let avgConfidence = sorted.map(\.identityConfidence).reduce(0, +) / Double(sorted.count)
        guard avgConfidence >= Self.minIdentityConfidence else {
            throw StableSwingROIError.identityUnstable
        }

        // 4. Estimate frame duration from actual timestamps
        let estimatedFrameDuration: Double
        if sorted.count >= 2 {
            let totalTime = sorted.last!.sourceTime - sorted.first!.sourceTime
            estimatedFrameDuration = totalTime / Double(sorted.count - 1)
        } else {
            estimatedFrameDuration = 1.0 / 30.0
        }

        // 5. Interpolate gaps
        var interpolatedFrames = sorted
        var idx = 0
        while idx < interpolatedFrames.count - 1 {
            let gapDuration = interpolatedFrames[idx + 1].sourceTime - interpolatedFrames[idx].sourceTime
            let prevFrame = interpolatedFrames[idx]
            let nextFrame = interpolatedFrames[idx + 1]
            let prevIndex = prevFrame.sourceFrameIndex
            let nextIndex = nextFrame.sourceFrameIndex
            let missingCount = nextIndex - prevIndex - 1

            if missingCount > 0 {
                let missingDuration = gapDuration - estimatedFrameDuration
                if missingDuration > Self.maxInterpolationGapSeconds {
                    throw StableSwingROIError.poseGapTooLong
                }
                for m in 1...missingCount {
                    let t = Double(m) / Double(missingCount + 1)
                    let interpFrame = GolfPoseTrackFrame(
                        sourceFrameIndex: prevIndex + m,
                        sourceTime: prevFrame.sourceTime + t * (nextFrame.sourceTime - prevFrame.sourceTime),
                        bodyCenter: GolfNormalizedPoint(
                            x: prevFrame.bodyCenter.x + t * (nextFrame.bodyCenter.x - prevFrame.bodyCenter.x),
                            y: prevFrame.bodyCenter.y + t * (nextFrame.bodyCenter.y - prevFrame.bodyCenter.y)
                        ),
                        bodyBounds: GolfAxisAlignedRect(
                            x: prevFrame.bodyBounds.x + t * (nextFrame.bodyBounds.x - prevFrame.bodyBounds.x),
                            y: prevFrame.bodyBounds.y + t * (nextFrame.bodyBounds.y - prevFrame.bodyBounds.y),
                            width: prevFrame.bodyBounds.width + t * (nextFrame.bodyBounds.width - prevFrame.bodyBounds.width),
                            height: prevFrame.bodyBounds.height + t * (nextFrame.bodyBounds.height - prevFrame.bodyBounds.height)
                        ),
                        handCenter: interpolatePoint(prevFrame.handCenter, nextFrame.handCenter, t: t),
                        identityConfidence: prevFrame.identityConfidence + t * (nextFrame.identityConfidence - prevFrame.identityConfidence)
                    )
                    interpolatedFrames.insert(interpFrame, at: prevIndex + m)
                }
                idx += missingCount + 1
            } else {
                idx += 1
            }
        }

        // 6. Compute clip anchor from motion envelope (bounds are in source pixels)
        let allBounds = interpolatedFrames.map(\.bodyBounds)
        let minX = allBounds.map(\.x).min()!
        let minY = allBounds.map(\.y).min()!
        let maxX = allBounds.map({ $0.x + $0.width }).max()!
        let maxY = allBounds.map({ $0.y + $0.height }).max()!
        let envelopeW = maxX - minX
        let envelopeH = maxY - minY

        // Anchor center from robust percentiles (normalized)
        let centers = interpolatedFrames.map(\.bodyCenter)
        let sortedX = centers.map(\.x).sorted()
        let sortedY = centers.map(\.y).sorted()
        let p10 = max(0, sortedX.count / 10)
        let p90 = min(sortedX.count - 1, sortedX.count * 9 / 10)
        let anchorCenterX = (sortedX[p10] + sortedX[p90]) / 2.0
        let anchorCenterY = (sortedY[p10] + sortedY[p90]) / 2.0

        // Anchor scale from envelope + safety margins (source pixels)
        let safetyMargin = configuration.clubBallSafetyMarginFraction + configuration.framePaddingFraction
        let anchorSide = max(envelopeW, envelopeH) * (1.0 + safetyMargin)

        guard anchorSide > 0 else {
            throw StableSwingROIError.coverageFailed
        }

        // Square crop in source pixels
        let cropSide = anchorSide
        guard cropSide > 0, cropSide < frameW * 2 else {
            throw StableSwingROIError.coverageFailed
        }

        // 7. Compute per-frame raw crop centers (anchor-based, not per-frame tracking)
        let rawCropCenters = interpolatedFrames.map { frame -> (Double, Double) in
            let cx = anchorCenterX * frameW
            let cy = anchorCenterY * frameH
            return (cx, cy)
        }

        // 8. Bidirectional smoothing with limited correction
        let maxCorrection = cropSide * configuration.maxBidirectionalCorrectionFraction
        let smoothedCenters = bidirectionalSmooth(
            rawCropCenters,
            maxCorrection: maxCorrection
        )

        // 9. Build ROI frames
        var roiFrames: [StableSwingROIFrame] = []
        for (i, frame) in interpolatedFrames.enumerated() {
            let cx = smoothedCenters[i].0
            let cy = smoothedCenters[i].1
            var cropX = cx - cropSide / 2.0
            var cropY = cy - cropSide / 2.0

            let paddingApplied = cropX < 0 || cropY < 0 ||
                cropX + cropSide > frameW || cropY + cropSide > frameH
            cropX = max(0, min(cropX, frameW - cropSide))
            cropY = max(0, min(cropY, frameH - cropSide))

            let touchesEdge = cropX <= 0 || cropY <= 0 ||
                cropX + cropSide >= frameW - 1 || cropY + cropSide >= frameH - 1

            // Normalized transform: source normalized [0,1] -> ROI normalized [0,1]
            // roiX = (srcX * frameW - cropX) / cropSide
            // roiY = (srcY * frameH - cropY) / cropSide
            let a = frameW / cropSide
            let b = 0.0
            let c = 0.0
            let d = frameH / cropSide
            let tx = -cropX / cropSide
            let ty = -cropY / cropSide

            // Inverse: srcX = (roiX * cropSide + cropX) / frameW
            let invA = cropSide / frameW
            let invB = 0.0
            let invC = 0.0
            let invD = cropSide / frameH
            let invTx = cropX / frameW
            let invTy = cropY / frameH

            let transform = GolfROIAffineTransform(
                a: a, b: b, c: c, d: d, tx: tx, ty: ty,
                invA: invA, invB: invB, invC: invC, invD: invD, invTx: invTx, invTy: invTy
            )

            roiFrames.append(StableSwingROIFrame(
                sourceFrameIndex: frame.sourceFrameIndex,
                sourceTime: frame.sourceTime,
                transform: transform,
                cropRect: GolfAxisAlignedRect(x: cropX, y: cropY, width: cropSide, height: cropSide),
                paddingApplied: paddingApplied,
                touchesEdge: touchesEdge,
                configurationVersion: configuration.version,
                interpolated: frame.sourceFrameIndex != poseFrames.first(where: { $0.sourceFrameIndex == frame.sourceFrameIndex })?.sourceFrameIndex
                    && !unique.keys.contains(frame.sourceFrameIndex),
                coverageOK: true,
                qualityScore: frame.identityConfidence
            ))
        }

        // 10. Compute P95 center movement in target pixels
        var movements: [Double] = []
        for i in 1..<smoothedCenters.count {
            let dx = smoothedCenters[i].0 - smoothedCenters[i - 1].0
            let dy = smoothedCenters[i].1 - smoothedCenters[i - 1].1
            movements.append(hypot(dx, dy) * Double(targetSize) / cropSide)
        }
        let sortedMovements = movements.sorted()
        let p95Index = min(sortedMovements.count - 1, Int(Double(sortedMovements.count) * 0.95))
        let p95Movement = sortedMovements.isEmpty ? 0.0 : sortedMovements[max(0, p95Index)]

        return StableSwingROITrack(
            frames: roiFrames,
            centerMovementP95InTargetPixels: p95Movement,
            configuration: configuration
        )
    }

    private static func bidirectionalSmooth(
        _ centers: [(Double, Double)],
        maxCorrection: Double
    ) -> [(Double, Double)] {
        guard centers.count >= 3 else { return centers }

        var smoothed = centers

        // Forward pass: limit frame-to-frame change
        for i in 1..<smoothed.count {
            let dx = smoothed[i].0 - smoothed[i - 1].0
            let dy = smoothed[i].1 - smoothed[i - 1].1
            let dist = hypot(dx, dy)
            if dist > maxCorrection {
                let scale = maxCorrection / dist
                smoothed[i] = (
                    smoothed[i - 1].0 + dx * scale,
                    smoothed[i - 1].1 + dy * scale
                )
            }
        }

        // Backward pass
        for i in stride(from: smoothed.count - 2, through: 0, by: -1) {
            let dx = smoothed[i].0 - smoothed[i + 1].0
            let dy = smoothed[i].1 - smoothed[i + 1].1
            let dist = hypot(dx, dy)
            if dist > maxCorrection {
                let scale = maxCorrection / dist
                smoothed[i] = (
                    smoothed[i + 1].0 + dx * scale,
                    smoothed[i + 1].1 + dy * scale
                )
            }
        }

        return smoothed
    }

    private static func interpolatePoint(
        _ a: GolfNormalizedPoint?,
        _ b: GolfNormalizedPoint?,
        t: Double
    ) -> GolfNormalizedPoint? {
        guard let a = a, let b = b else { return nil }
        return GolfNormalizedPoint(
            x: a.x + t * (b.x - a.x),
            y: a.y + t * (b.y - a.y)
        )
    }
}

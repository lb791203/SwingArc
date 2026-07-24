import Foundation

public enum StableSwingROIBuilder {
    private static let maxInterpolationGapSeconds = 0.150
    private static let minIdentityConfidence = 0.5
    private static let maxCorrectionAttempts = 10

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

        // 4. Interpolate gaps ≤150ms
        var interpolatedFrames = sorted
        var i = 0
        while i < interpolatedFrames.count - 1 {
            let gap = interpolatedFrames[i + 1].sourceTime - interpolatedFrames[i].sourceTime
            let expectedGap = 1.0 / 30.0  // assume 30fps base
            if gap > expectedGap * 1.5 {
                let gapDuration = interpolatedFrames[i + 1].sourceTime - interpolatedFrames[i].sourceTime
                if gapDuration > Self.maxInterpolationGapSeconds {
                    throw StableSwingROIError.poseGapTooLong
                }
                // Linear interpolation
                let prev = interpolatedFrames[i]
                let next = interpolatedFrames[i + 1]
                let nextIndex = next.sourceFrameIndex
                let prevIndex = prev.sourceFrameIndex
                let missingCount = nextIndex - prevIndex - 1
                for m in 1...missingCount {
                    let t = Double(m) / Double(missingCount + 1)
                    let interpFrame = GolfPoseTrackFrame(
                        sourceFrameIndex: prevIndex + m,
                        sourceTime: prev.sourceTime + t * (next.sourceTime - prev.sourceTime),
                        bodyCenter: GolfNormalizedPoint(
                            x: prev.bodyCenter.x + t * (next.bodyCenter.x - prev.bodyCenter.x),
                            y: prev.bodyCenter.y + t * (next.bodyCenter.y - prev.bodyCenter.y)
                        ),
                        bodyBounds: GolfAxisAlignedRect(
                            x: prev.bodyBounds.x + t * (next.bodyBounds.x - prev.bodyBounds.x),
                            y: prev.bodyBounds.y + t * (next.bodyBounds.y - prev.bodyBounds.y),
                            width: prev.bodyBounds.width + t * (next.bodyBounds.width - prev.bodyBounds.width),
                            height: prev.bodyBounds.height + t * (next.bodyBounds.height - prev.bodyBounds.height)
                        ),
                        handCenter: interpolatePoint(prev.handCenter, next.handCenter, t: t),
                        identityConfidence: prev.identityConfidence + t * (next.identityConfidence - prev.identityConfidence)
                    )
                    interpolatedFrames.insert(interpFrame, at: prevIndex + m)
                }
                i += missingCount + 1
            } else {
                i += 1
            }
        }

        // 5. Compute clip anchor from robust percentiles
        let centers = interpolatedFrames.map(\.bodyCenter)
        let xs = centers.map(\.x).sorted()
        let ys = centers.map(\.y).sorted()
        let widths = interpolatedFrames.map(\.bodyBounds.width).sorted()
        let heights = interpolatedFrames.map(\.bodyBounds.height).sorted()

        let p10 = max(0, xs.count / 10)
        let p90 = min(xs.count - 1, xs.count * 9 / 10)
        let anchorCenterX = (xs[p10] + xs[p90]) / 2.0
        let anchorCenterY = (ys[p10] + ys[p90]) / 2.0
        let anchorWidth = widths[p90]
        let anchorHeight = heights[p90]

        // 6. Apply safety margins
        let safetyW = anchorWidth * (1.0 + configuration.clubBallSafetyMarginFraction + configuration.framePaddingFraction)
        let safetyH = anchorHeight * (1.0 + configuration.clubBallSafetyMarginFraction + configuration.framePaddingFraction)

        // 7. Validate coverage
        guard safetyW > 0, safetyH > 0 else {
            throw StableSwingROIError.coverageFailed
        }

        // 8. Build per-frame ROI with limited bidirectional smoothing
        let frameW = orientedFrameSize.width
        let frameH = orientedFrameSize.height
        let scale = Double(targetSize) / max(safetyW * frameW, safetyH * frameH)

        var roiFrames: [StableSwingROIFrame] = []
        var centerOffsets: [(Double, Double)] = []

        for frame in interpolatedFrames {
            let cropW = safetyW * frameW
            let cropH = safetyH * frameH
            let cropX = (frame.bodyCenter.x * frameW) - cropW / 2.0
            let cropY = (frame.bodyCenter.y * frameH) - cropH / 2.0

            let clampedX = max(0, min(cropX, frameW - cropW))
            let clampedY = max(0, min(cropY, frameH - cropH))

            let paddingApplied = clampedX != cropX || clampedY != cropY
            let touchesEdge = clampedX <= 0 || clampedY <= 0 ||
                clampedX + cropW >= frameW - 1 || clampedY + cropH >= frameH - 1

            let roiScale = Double(targetSize) / max(cropW, cropH)
            let tx = -clampedX * roiScale
            let ty = -clampedY * roiScale
            let a = roiScale
            let b = 0.0
            let c = 0.0
            let d = roiScale

            let invScale = 1.0 / roiScale
            let invA = invScale
            let invB = 0.0
            let invC = 0.0
            let invD = invScale
            let invTX = clampedX
            let invTY = clampedY

            let transform = GolfROIAffineTransform(
                a: a, b: b, c: c, d: d, tx: tx, ty: ty,
                invA: invA, invB: invB, invC: invC, invD: invD, invTx: invTX, invTy: invTY
            )

            let roiCenterX = Double(targetSize) / 2.0
            let roiCenterY = Double(targetSize) / 2.0
            centerOffsets.append((roiCenterX, roiCenterY))

            roiFrames.append(StableSwingROIFrame(
                sourceFrameIndex: frame.sourceFrameIndex,
                sourceTime: frame.sourceTime,
                transform: transform,
                cropRect: GolfAxisAlignedRect(x: clampedX, y: clampedY, width: cropW, height: cropH),
                paddingApplied: paddingApplied,
                touchesEdge: touchesEdge,
                configurationVersion: configuration.version,
                interpolated: false,
                coverageOK: true,
                qualityScore: frame.identityConfidence
            ))
        }

        // 9. Compute center movement P95 in target pixels
        var movements: [Double] = []
        for i in 1..<centerOffsets.count {
            let dx = centerOffsets[i].0 - centerOffsets[i - 1].0
            let dy = centerOffsets[i].1 - centerOffsets[i - 1].1
            movements.append(hypot(dx, dy))
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

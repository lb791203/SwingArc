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

        // 1. Sort and deduplicate with conflict detection
        var seen: [Int: GolfPoseTrackFrame] = [:]
        var sortedFrames: [GolfPoseTrackFrame] = []
        let sorted = poseFrames.sorted { $0.sourceFrameIndex < $1.sourceFrameIndex }
        for frame in sorted {
            if let existing = seen[frame.sourceFrameIndex] {
                if existing != frame {
                    throw StableSwingROIError.duplicateFrameConflict(frame.sourceFrameIndex)
                }
                continue
            }
            seen[frame.sourceFrameIndex] = frame
            sortedFrames.append(frame)
        }

        // 2. Validate monotonic time
        for i in 1..<sortedFrames.count {
            guard sortedFrames[i].sourceTime > sortedFrames[i - 1].sourceTime else {
                throw StableSwingROIError.nonMonotonicTime
            }
        }

        // 3. Validate identity confidence: any frame below threshold fails
        for frame in sortedFrames {
            guard frame.identityConfidence >= Self.minIdentityConfidence else {
                throw StableSwingROIError.identityUnstable
            }
        }

        // 4. Estimate nominal frame duration from robust median of time deltas
        var durations: [Double] = []
        for i in 1..<sortedFrames.count {
            let dt = sortedFrames[i].sourceTime - sortedFrames[i - 1].sourceTime
            let di = sortedFrames[i].sourceFrameIndex - sortedFrames[i - 1].sourceFrameIndex
            if di > 0 {
                durations.append(dt / Double(di))
            }
        }
        durations.sort()
        let estimatedFrameDuration: Double
        if durations.count >= 2 {
            let mid = durations.count / 2
            estimatedFrameDuration = durations[mid]
        } else if !durations.isEmpty {
            estimatedFrameDuration = durations[0]
        } else {
            estimatedFrameDuration = 1.0 / 30.0
        }

        // 5. Interpolate gaps by iterating sorted originals sequentially
        var interpolatedFrames: [GolfPoseTrackFrame] = []
        for i in 0..<sortedFrames.count {
            if i > 0 {
                let prev = sortedFrames[i - 1]
                let curr = sortedFrames[i]
                let prevIndex = prev.sourceFrameIndex
                let currIndex = curr.sourceFrameIndex
                let missingCount = currIndex - prevIndex - 1

                if missingCount > 0 {
                    let gapDuration = curr.sourceTime - prev.sourceTime
                    let missingDuration = gapDuration - estimatedFrameDuration
                    if missingDuration > Self.maxInterpolationGapSeconds {
                        throw StableSwingROIError.poseGapTooLong
                    }
                    for m in 1...missingCount {
                        let t = Double(m) / Double(missingCount + 1)
                        let interpFrame = GolfPoseTrackFrame(
                            sourceFrameIndex: prevIndex + m,
                            sourceTime: prev.sourceTime + t * (curr.sourceTime - prev.sourceTime),
                            bodyCenter: GolfNormalizedPoint(
                                x: prev.bodyCenter.x + t * (curr.bodyCenter.x - prev.bodyCenter.x),
                                y: prev.bodyCenter.y + t * (curr.bodyCenter.y - prev.bodyCenter.y)
                            ),
                            bodyBounds: GolfAxisAlignedRect(
                                x: prev.bodyBounds.x + t * (curr.bodyBounds.x - prev.bodyBounds.x),
                                y: prev.bodyBounds.y + t * (curr.bodyBounds.y - prev.bodyBounds.y),
                                width: prev.bodyBounds.width + t * (curr.bodyBounds.width - prev.bodyBounds.width),
                                height: prev.bodyBounds.height + t * (curr.bodyBounds.height - prev.bodyBounds.height)
                            ),
                            handCenter: interpolatePoint(prev.handCenter, curr.handCenter, t: t),
                            identityConfidence: prev.identityConfidence + t * (curr.identityConfidence - prev.identityConfidence)
                        )
                        interpolatedFrames.append(interpFrame)
                    }
                }
            }
            interpolatedFrames.append(sortedFrames[i])
        }

        // 6. Compute clip anchor from motion envelope
        let allBounds = interpolatedFrames.map(\.bodyBounds)
        let minX = allBounds.map(\.x).min()!
        let minY = allBounds.map(\.y).min()!
        let maxX = allBounds.map({ $0.x + $0.width }).max()!
        let maxY = allBounds.map({ $0.y + $0.height }).max()!
        let envelopeW = maxX - minX
        let envelopeH = maxY - minY

        let centers = interpolatedFrames.map(\.bodyCenter)
        let sortedX = centers.map(\.x).sorted()
        let sortedY = centers.map(\.y).sorted()
        let p10 = max(0, sortedX.count / 10)
        let p90 = min(sortedX.count - 1, sortedX.count * 9 / 10)
        let anchorCenterX = (sortedX[p10] + sortedX[p90]) / 2.0
        let anchorCenterY = (sortedY[p10] + sortedY[p90]) / 2.0

        let safetyMargin = configuration.clubBallSafetyMarginFraction + configuration.framePaddingFraction
        let envelopeSide = max(envelopeW, envelopeH)
        let anchorToEdge = envelopeSide / 2.0
        let cropSideHalf = anchorToEdge * (1.0 + safetyMargin)
        let cropSide = cropSideHalf * 2.0

        guard cropSide > 0 else {
            throw StableSwingROIError.coverageFailed
        }

        let cropOriginX = anchorCenterX * frameW - cropSide / 2.0
        let cropOriginY = anchorCenterY * frameH - cropSide / 2.0

        // 7. Verify all body bounds corners and hand centers map into ROI
        for frame in interpolatedFrames {
            let corners = [
                GolfNormalizedPoint(x: frame.bodyBounds.x / frameW, y: frame.bodyBounds.y / frameH),
                GolfNormalizedPoint(x: (frame.bodyBounds.x + frame.bodyBounds.width) / frameW, y: frame.bodyBounds.y / frameH),
                GolfNormalizedPoint(x: frame.bodyBounds.x / frameW, y: (frame.bodyBounds.y + frame.bodyBounds.height) / frameH),
                GolfNormalizedPoint(x: (frame.bodyBounds.x + frame.bodyBounds.width) / frameW, y: (frame.bodyBounds.y + frame.bodyBounds.height) / frameH),
            ]
            for corner in corners {
                let roiX = (corner.x * frameW - cropOriginX) / cropSide
                let roiY = (corner.y * frameH - cropOriginY) / cropSide
                guard roiX >= -0.01 && roiX <= 1.01 && roiY >= -0.01 && roiY <= 1.01 else {
                    throw StableSwingROIError.coverageFailed
                }
            }
            if let hand = frame.handCenter {
                let roiHX = (hand.x * frameW - cropOriginX) / cropSide
                let roiHY = (hand.y * frameH - cropOriginY) / cropSide
                guard roiHX >= -0.01 && roiHX <= 1.01 && roiHY >= -0.01 && roiHY <= 1.01 else {
                    throw StableSwingROIError.coverageFailed
                }
            }
        }

        // 8. Per-frame correction (only when envelope approaches edge)
        let maxCorrection = cropSide * configuration.maxBidirectionalCorrectionFraction
        var rawCenters = interpolatedFrames.map { _ -> (Double, Double) in
            (anchorCenterX * frameW, anchorCenterY * frameH)
        }

        // Compute raw crop origins and check if any approach edge
        for i in 0..<interpolatedFrames.count {
            let cx = rawCenters[i].0
            let cy = rawCenters[i].1
            let ox = cx - cropSide / 2.0
            let oy = cy - cropSide / 2.0
            let distToLeft = ox
            let distToTop = oy
            let distToRight = frameW - (ox + cropSide)
            let distToBottom = frameH - (oy + cropSide)
            let minDist = min(distToLeft, distToTop, distToRight, distToBottom)

            if minDist < maxCorrection * 2.0 {
                // Envelope approaches edge: compute minimal correction
                let clampOx = max(0, min(ox, frameW - cropSide))
                let clampOy = max(0, min(oy, frameH - cropSide))
                let correctedCx = clampOx + cropSide / 2.0
                let correctedCy = clampOy + cropSide / 2.0
                let dcx = correctedCx - cx
                let dcy = correctedCy - cy
                let dist = hypot(dcx, dcy)
                if dist > maxCorrection {
                    let scale = maxCorrection / dist
                    rawCenters[i] = (cx + dcx * scale, cy + dcy * scale)
                } else {
                    rawCenters[i] = (correctedCx, correctedCy)
                }
            }
        }

        // 9. Bidirectional smoothing
        let smoothedCenters = bidirectionalSmooth(rawCenters, maxCorrection: maxCorrection)

        // 10. Build ROI frames
        var roiFrames: [StableSwingROIFrame] = []

        for (i, frame) in interpolatedFrames.enumerated() {
            let cx = smoothedCenters[i].0
            let cy = smoothedCenters[i].1
            var cropX = cx - cropSide / 2.0
            var cropY = cy - cropSide / 2.0

            let padLeft = max(0, -cropX)
            let padTop = max(0, -cropY)
            let padRight = max(0, cropX + cropSide - frameW)
            let padBottom = max(0, cropY + cropSide - frameH)

            cropX = max(0, min(cropX, frameW - cropSide))
            cropY = max(0, min(cropY, frameH - cropSide))

            // Normalized transform: source normalized [0,1] -> ROI normalized [0,1]
            let a = frameW / cropSide
            let b = 0.0
            let c = 0.0
            let d = frameH / cropSide
            let tx = -cropX / cropSide
            let ty = -cropY / cropSide

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

            let isInterpolated = !seen.keys.contains(frame.sourceFrameIndex)

            roiFrames.append(StableSwingROIFrame(
                sourceFrameIndex: frame.sourceFrameIndex,
                sourceTime: frame.sourceTime,
                transform: transform,
                cropRect: GolfAxisAlignedRect(x: cropX, y: cropY, width: cropSide, height: cropSide),
                paddingLeft: padLeft,
                paddingTop: padTop,
                paddingRight: padRight,
                paddingBottom: padBottom,
                configurationVersion: configuration.version,
                interpolated: isInterpolated,
                coverageOK: true,
                qualityScore: frame.identityConfidence
            ))
        }

        // 11. Compute P95 center movement in target pixels
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

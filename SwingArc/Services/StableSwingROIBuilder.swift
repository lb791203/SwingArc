import Foundation
import CommonCrypto
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum StableSwingROIBuilder {
    public static let algorithmVersion = "roi-v1"

    public static func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        #if canImport(CryptoKit)
        if #available(macOS 10.15, iOS 13.0, *) {
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        }
        #endif
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func configurationSHA256(
        orientedFrameSize: CGSize,
        targetSize: Double,
        configuration: StableSwingROIConfiguration = .v1
    ) -> String {
        let str = "\(algorithmVersion):\(orientedFrameSize.width):\(orientedFrameSize.height):\(targetSize):\(configuration.clubBallSafetyMarginFraction):\(configuration.framePaddingFraction):\(configuration.maxBidirectionalCorrectionFraction)"
        return sha256Hex(str)
    }

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
                            bodyBounds: GolfNormalizedRect(
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

        // 6. Convert all bounds/centers to source pixels and compute envelope
        struct PixelPoint { let x: Double; let y: Double }

        var allPixelPoints: [PixelPoint] = []
        for frame in interpolatedFrames {
            // Body bounds corners (normalized → pixels)
            let bx = frame.bodyBounds.x * frameW
            let by = frame.bodyBounds.y * frameH
            let bw = frame.bodyBounds.width * frameW
            let bh = frame.bodyBounds.height * frameH
            allPixelPoints.append(PixelPoint(x: bx, y: by))
            allPixelPoints.append(PixelPoint(x: bx + bw, y: by))
            allPixelPoints.append(PixelPoint(x: bx, y: by + bh))
            allPixelPoints.append(PixelPoint(x: bx + bw, y: by + bh))
            // Body center (pixels)
            allPixelPoints.append(PixelPoint(x: frame.bodyCenter.x * frameW, y: frame.bodyCenter.y * frameH))
            // Hand center (pixels)
            if let hand = frame.handCenter {
                allPixelPoints.append(PixelPoint(x: hand.x * frameW, y: hand.y * frameH))
            }
        }

        let minX = allPixelPoints.map(\.x).min()!
        let minY = allPixelPoints.map(\.y).min()!
        let maxX = allPixelPoints.map(\.x).max()!
        let maxY = allPixelPoints.map(\.y).max()!

        // 7. Robust anchor from body center percentiles (pixels)
        let centers = interpolatedFrames.map { PixelPoint(x: $0.bodyCenter.x * frameW, y: $0.bodyCenter.y * frameH) }
        let sortedCX = centers.map(\.x).sorted()
        let sortedCY = centers.map(\.y).sorted()
        let p10 = max(0, sortedCX.count / 10)
        let p90 = min(sortedCX.count - 1, sortedCX.count * 9 / 10)
        let anchorCX = (sortedCX[p10] + sortedCX[p90]) / 2.0
        let anchorCY = (sortedCY[p10] + sortedCY[p90]) / 2.0

        // 8. Compute cropSide to cover entire envelope from anchor
        let halfSide = max(
            anchorCX - minX,
            maxX - anchorCX,
            anchorCY - minY,
            maxY - anchorCY
        )
        let safetyMargin = configuration.clubBallSafetyMarginFraction + configuration.framePaddingFraction
        let cropSide = 2.0 * halfSide * (1.0 + safetyMargin)

        guard cropSide > 0 else {
            throw StableSwingROIError.coverageFailed
        }

        // 9. Per-frame raw centers = anchor (fixed clip anchor)
        var rawCenters = interpolatedFrames.map { _ -> (Double, Double) in
            (anchorCX, anchorCY)
        }

        // 11. Per-frame correction only when approaching edge
        let maxCorrection = cropSide * configuration.maxBidirectionalCorrectionFraction
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
                let clampOx = max(-cropSide * 0.1, min(ox, frameW - cropSide + cropSide * 0.1))
                let clampOy = max(-cropSide * 0.1, min(oy, frameH - cropSide + cropSide * 0.1))
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

        // 12. Bidirectional smoothing
        let smoothedCenters = bidirectionalSmooth(rawCenters, maxCorrection: maxCorrection)

        // 13. Build ROI frames with real padding (no clamping of crop origin)
        var roiFrames: [StableSwingROIFrame] = []

        for (i, frame) in interpolatedFrames.enumerated() {
            let cx = smoothedCenters[i].0
            let cy = smoothedCenters[i].1
            let cropX = cx - cropSide / 2.0
            let cropY = cy - cropSide / 2.0

            let padLeft = max(0, -cropX)
            let padTop = max(0, -cropY)
            let padRight = max(0, cropX + cropSide - frameW)
            let padBottom = max(0, cropY + cropSide - frameH)

            // Normalized transform: source normalized [0,1] -> ROI normalized [0,1]
            // roiX = (srcX * frameW - cropX) / cropSide
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

            // Verify all body corners and hand center map into ROI
            var frameCoverageOK = true
            let bodyCorners = [
                GolfNormalizedPoint(x: frame.bodyBounds.x, y: frame.bodyBounds.y),
                GolfNormalizedPoint(x: frame.bodyBounds.x + frame.bodyBounds.width, y: frame.bodyBounds.y),
                GolfNormalizedPoint(x: frame.bodyBounds.x, y: frame.bodyBounds.y + frame.bodyBounds.height),
                GolfNormalizedPoint(x: frame.bodyBounds.x + frame.bodyBounds.width, y: frame.bodyBounds.y + frame.bodyBounds.height),
            ]
            for corner in bodyCorners {
                let roi = transform.fullFramePointToROI(corner)
                if roi.x < -0.01 || roi.x > 1.01 || roi.y < -0.01 || roi.y > 1.01 {
                    frameCoverageOK = false
                }
            }
            if let hand = frame.handCenter {
                let roiH = transform.fullFramePointToROI(hand)
                if roiH.x < -0.01 || roiH.x > 1.01 || roiH.y < -0.01 || roiH.y > 1.01 {
                    frameCoverageOK = false
                }
            }
            if !frameCoverageOK {
                throw StableSwingROIError.coverageFailed
            }

            let isInterpolated = !seen.keys.contains(frame.sourceFrameIndex)

            roiFrames.append(StableSwingROIFrame(
                sourceFrameIndex: frame.sourceFrameIndex,
                sourceTime: frame.sourceTime,
                transform: transform,
                cropRect: GolfSourcePixelRect(x: cropX, y: cropY, width: cropSide, height: cropSide),
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

        // 14. Compute P95 center movement in target pixels
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

    public static func bidirectionalSmooth(
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

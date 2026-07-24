import Foundation

public struct GolfCandidateJointGeometry: Equatable, Sendable {
    public let shoulderWidth: Double
    public let hipWidth: Double
    public let torsoLength: Double

    public init(shoulderWidth: Double, hipWidth: Double, torsoLength: Double) {
        self.shoulderWidth = shoulderWidth
        self.hipWidth = hipWidth
        self.torsoLength = torsoLength
    }
}

public struct GolfPoseCandidateFrame: Equatable, Sendable {
    public let sourceFrameIndex: Int
    public let sourceTime: Double
    public let candidateIndex: Int
    public let bodyCenter: GolfNormalizedPoint
    public let bodyBounds: GolfNormalizedRect
    public let bodyScale: Double
    public let jointGeometry: GolfCandidateJointGeometry
    public let handCenter: GolfNormalizedPoint?
    public let identityConfidence: Double

    public init(
        sourceFrameIndex: Int,
        sourceTime: Double,
        candidateIndex: Int,
        bodyCenter: GolfNormalizedPoint,
        bodyBounds: GolfNormalizedRect,
        bodyScale: Double,
        jointGeometry: GolfCandidateJointGeometry,
        handCenter: GolfNormalizedPoint?,
        identityConfidence: Double
    ) {
        self.sourceFrameIndex = sourceFrameIndex
        self.sourceTime = sourceTime
        self.candidateIndex = candidateIndex
        self.bodyCenter = bodyCenter
        self.bodyBounds = bodyBounds
        self.bodyScale = bodyScale
        self.jointGeometry = jointGeometry
        self.handCenter = handCenter
        self.identityConfidence = identityConfidence
    }
}

public struct GolfPoseCandidateIdentifier: Equatable, Sendable {
    public let sourceFrameIndex: Int
    public let candidateIndex: Int

    public init(sourceFrameIndex: Int, candidateIndex: Int) {
        self.sourceFrameIndex = sourceFrameIndex
        self.candidateIndex = candidateIndex
    }
}

public enum PrimaryGolferTrackResolverError: Error, Equatable, CustomStringConvertible {
    case manualAnchorRequired
    case identityAmbiguityTooLong
    case duplicateFrameConflict(Int)
    case nonMonotonicTime
    case emptyCandidates
    case anchorNotFound(GolfPoseCandidateIdentifier)

    public var description: String {
        switch self {
        case .manualAnchorRequired:
            return "Manual anchor required to resolve identity"
        case .identityAmbiguityTooLong:
            return "Identity ambiguity exceeds 150ms threshold"
        case .duplicateFrameConflict(let idx):
            return "Conflicting candidates for frame \(idx)"
        case .nonMonotonicTime:
            return "Source timestamps are not monotonically increasing"
        case .emptyCandidates:
            return "No candidates provided"
        case .anchorNotFound(let id):
            return "Anchor not found: frame \(id.sourceFrameIndex) candidate \(id.candidateIndex)"
        }
    }
}

public enum PrimaryGolferTrackResolver {
    private static let maxAmbiguityDuration = 0.150

    public static func resolve(
        candidates: [GolfPoseCandidateFrame],
        manualAnchor: GolfPoseCandidateIdentifier?
    ) -> Result<[GolfPoseTrackFrame], PrimaryGolferTrackResolverError> {
        guard !candidates.isEmpty else {
            return .failure(.emptyCandidates)
        }

        // 1. Group by frame and validate
        var byFrame: [Int: [GolfPoseCandidateFrame]] = [:]
        for c in candidates {
            byFrame[c.sourceFrameIndex, default: []].append(c)
        }

        // Check for conflicting duplicates (same candidateIndex twice in same frame)
        for (frameIdx, frameCandidates) in byFrame {
            var seenIndices: Set<Int> = []
            for c in frameCandidates {
                if seenIndices.contains(c.candidateIndex) {
                    return .failure(.duplicateFrameConflict(frameIdx))
                }
                seenIndices.insert(c.candidateIndex)
            }
        }

        let sortedFrames = byFrame.keys.sorted()
        let frameTimes = sortedFrames.map { byFrame[$0]!.first!.sourceTime }
        for i in 1..<frameTimes.count {
            guard frameTimes[i] > frameTimes[i - 1] else {
                return .failure(.nonMonotonicTime)
            }
        }

        // 2. Determine anchor
        let anchorFrame: Int
        let anchorCandidate: Int
        if let anchor = manualAnchor {
            guard byFrame[anchor.sourceFrameIndex]?.contains(where: { $0.candidateIndex == anchor.candidateIndex }) ?? false else {
                return .failure(.anchorNotFound(anchor))
            }
            anchorFrame = anchor.sourceFrameIndex
            anchorCandidate = anchor.candidateIndex
        } else {
            let allCandidates = Set(candidates.map { $0.candidateIndex })
            if allCandidates.count > 1 {
                return .failure(.manualAnchorRequired)
            }
            anchorFrame = sortedFrames[0]
            anchorCandidate = candidates[0].candidateIndex
        }

        // 3. Viterbi-style DP
        struct State {
            let candidate: Int
            let cost: Double
        }

        // Initialize: only anchor candidate at anchor frame
        var dp: [Int: (cost: Double, backpointer: Int?)] = [:]
        dp[anchorCandidate] = (cost: 0, backpointer: nil)

        // Track ambiguity: frames where candidates are too similar
        var ambiguityStartTime: Double?

        for frameIdx in sortedFrames {
            let frameCandidates = byFrame[frameIdx]!
            var newDp: [Int: (cost: Double, backpointer: Int?)] = [:]

            for curr in frameCandidates {
                var bestCost = Double.infinity
                var bestPrev: Int?

                for (prevCandidate, prevCost) in dp {
                    let tc = transitionCost(
                        from: prevCandidate, to: curr.candidateIndex,
                        candidates: byFrame, frameIdx: frameIdx, sortedFrames: sortedFrames
                    )
                    let total = prevCost.cost + tc
                    if total < bestCost {
                        bestCost = total
                        bestPrev = prevCandidate
                    }
                }

                if bestCost < Double.infinity {
                    newDp[curr.candidateIndex] = (cost: bestCost, backpointer: bestPrev)
                }
            }

            // Check ambiguity: if multiple candidates in this frame are too similar
            let frameCandidateList = byFrame[frameIdx]!
            if frameCandidateList.count >= 2 {
                // Check if any two candidates are very similar
                var isAmbiguousFrame = false
                for i in 0..<frameCandidateList.count {
                    for j in (i+1)..<frameCandidateList.count {
                        let a = frameCandidateList[i]
                        let b = frameCandidateList[j]
                        let centerDist = hypot(a.bodyCenter.x - b.bodyCenter.x, a.bodyCenter.y - b.bodyCenter.y)
                        let scaleDist = abs(a.bodyScale - b.bodyScale)
                        let jointDist = hypot(
                            a.jointGeometry.shoulderWidth - b.jointGeometry.shoulderWidth,
                            a.jointGeometry.hipWidth - b.jointGeometry.hipWidth
                        )
                        // Similar if all distances are small
                        if centerDist < 0.05 && scaleDist < 0.05 && jointDist < 0.05 {
                            isAmbiguousFrame = true
                        }
                    }
                }

                let frameTime = byFrame[frameIdx]!.first!.sourceTime
                if isAmbiguousFrame {
                    if let start = ambiguityStartTime {
                        if frameTime - start > maxAmbiguityDuration {
                            return .failure(.identityAmbiguityTooLong)
                        }
                    } else {
                        ambiguityStartTime = frameTime
                    }
                } else {
                    ambiguityStartTime = nil
                }
            } else {
                ambiguityStartTime = nil
            }

            dp = newDp
        }

        // 4. Find best final candidate
        guard let bestFinal = dp.min(by: { $0.value.cost < $1.value.cost }) else {
            return .failure(.anchorNotFound(GolfPoseCandidateIdentifier(sourceFrameIndex: anchorFrame, candidateIndex: anchorCandidate)))
        }

        // 5. Backtrack to reconstruct path
        var path: [Int: Int] = [:] // frameIndex -> candidateIndex
        var current = bestFinal.key
        for frameIdx in sortedFrames.reversed() {
            path[frameIdx] = current
            if let bp = dp[current]?.backpointer {
                current = bp
            }
        }

        // 6. Build output frames
        var trackFrames: [GolfPoseTrackFrame] = []
        for frameIdx in sortedFrames {
            guard let chosenIdx = path[frameIdx],
                  let chosen = byFrame[frameIdx]?.first(where: { $0.candidateIndex == chosenIdx }) else {
                continue
            }

            let confidence = computeConfidence(chosen: chosen, allCandidates: byFrame[frameIdx] ?? [])

            trackFrames.append(GolfPoseTrackFrame(
                sourceFrameIndex: chosen.sourceFrameIndex,
                sourceTime: chosen.sourceTime,
                bodyCenter: chosen.bodyCenter,
                bodyBounds: chosen.bodyBounds,
                handCenter: chosen.handCenter,
                identityConfidence: confidence
            ))
        }

        return .success(trackFrames)
    }

    private static func transitionCost(
        from prevCandidate: Int,
        to currCandidate: Int,
        candidates: [Int: [GolfPoseCandidateFrame]],
        frameIdx: Int,
        sortedFrames: [Int]
    ) -> Double {
        guard prevCandidate == currCandidate else {
            return 10.0
        }

        guard let frameIndex = sortedFrames.firstIndex(of: frameIdx), frameIndex > 0 else {
            return 0
        }

        let prevFrameIdx = sortedFrames[frameIndex - 1]
        guard let currFrame = candidates[frameIdx]?.first(where: { $0.candidateIndex == currCandidate }),
              let prevFrame = candidates[prevFrameIdx]?.first(where: { $0.candidateIndex == currCandidate }) else {
            return 0
        }

        let centerDistance = hypot(
            currFrame.bodyCenter.x - prevFrame.bodyCenter.x,
            currFrame.bodyCenter.y - prevFrame.bodyCenter.y
        )
        let scaleRatio = currFrame.bodyScale / max(prevFrame.bodyScale, 0.001)
        let scaleCost = abs(log(scaleRatio))
        let jointDist = hypot(
            currFrame.jointGeometry.shoulderWidth - prevFrame.jointGeometry.shoulderWidth,
            currFrame.jointGeometry.hipWidth - prevFrame.jointGeometry.hipWidth
        )
        let confidencePenalty = currFrame.identityConfidence < 0.5 ? 1.0 : 0.0

        return 3.0 * centerDistance + 1.5 * scaleCost + 2.0 * jointDist + confidencePenalty
    }

    private static func computeConfidence(
        chosen: GolfPoseCandidateFrame,
        allCandidates: [GolfPoseCandidateFrame]
    ) -> Double {
        guard allCandidates.count > 1 else {
            return chosen.identityConfidence
        }
        let maxOtherScale = allCandidates.filter { $0.candidateIndex != chosen.candidateIndex }.map(\.bodyScale).max() ?? 0
        let scaleGap = abs(chosen.bodyScale - maxOtherScale)
        return min(1.0, chosen.identityConfidence * (1.0 + scaleGap))
    }
}

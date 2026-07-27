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
    case invalidCandidate(frameIndex: Int, candidateIndex: Int)
    case inconsistentFrameTime(Int)
    case pathResolutionFailed(Int)

    public var description: String {
        switch self {
        case .manualAnchorRequired:
            return "Manual anchor required to resolve identity"
        case .identityAmbiguityTooLong:
            return "Identity ambiguity exceeds 150ms threshold"
        case .duplicateFrameConflict(let index):
            return "Conflicting candidates for frame \(index)"
        case .nonMonotonicTime:
            return "Source timestamps are not monotonically increasing"
        case .emptyCandidates:
            return "No candidates provided"
        case .anchorNotFound(let identifier):
            return "Anchor not found: frame \(identifier.sourceFrameIndex) candidate \(identifier.candidateIndex)"
        case .invalidCandidate(let frameIndex, let candidateIndex):
            return "Invalid candidate \(candidateIndex) at frame \(frameIndex)"
        case .inconsistentFrameTime(let index):
            return "Candidates at frame \(index) do not share one source time"
        case .pathResolutionFailed(let index):
            return "Unable to resolve a primary golfer candidate at frame \(index)"
        }
    }
}

public enum PrimaryGolferTrackResolver {
    private static let maximumAmbiguityDuration = 0.150
    private static let ambiguityCostMargin = 0.05
    private static let comparisonEpsilon = 1e-12

    private struct PathState {
        let cost: Double
        let previousCandidateIndex: Int?
    }

    private struct DirectionSolution {
        let path: [Int: Int]
        let statesByFrame: [Int: [Int: PathState]]
    }

    public static func resolve(
        candidates: [GolfPoseCandidateFrame],
        manualAnchor: GolfPoseCandidateIdentifier?
    ) -> Result<[GolfPoseTrackFrame], PrimaryGolferTrackResolverError> {
        resolve(candidates: candidates, manualAnchors: manualAnchor != nil ? [manualAnchor!] : [])
    }

    public static func resolve(
        candidates: [GolfPoseCandidateFrame],
        manualAnchors: [GolfPoseCandidateIdentifier]
    ) -> Result<[GolfPoseTrackFrame], PrimaryGolferTrackResolverError> {
        guard !candidates.isEmpty else {
            return .failure(.emptyCandidates)
        }

        let prepared: [Int: [GolfPoseCandidateFrame]]
        switch prepare(candidates: candidates) {
        case .success(let frames):
            prepared = frames
        case .failure(let error):
            return .failure(error)
        }

        let sortedFrames = prepared.keys.sorted()
        let frameTimes = sortedFrames.compactMap { prepared[$0]?.first?.sourceTime }
        for index in 1..<frameTimes.count
        where frameTimes[index] <= frameTimes[index - 1] {
            return .failure(.nonMonotonicTime)
        }

        // Validate anchors
        var anchorsByFrame: [Int: GolfPoseCandidateIdentifier] = [:]
        let sortedAnchors = manualAnchors.sorted { $0.sourceFrameIndex < $1.sourceFrameIndex }
        for anchor in sortedAnchors {
            if let existing = anchorsByFrame[anchor.sourceFrameIndex] {
                if existing.candidateIndex != anchor.candidateIndex {
                    return .failure(.duplicateFrameConflict(anchor.sourceFrameIndex))
                }
            } else {
                guard prepared[anchor.sourceFrameIndex]?.contains(where: {
                    $0.candidateIndex == anchor.candidateIndex
                }) == true else {
                    return .failure(.anchorNotFound(anchor))
                }
                anchorsByFrame[anchor.sourceFrameIndex] = anchor
            }
        }

        let effectiveAnchors: [GolfPoseCandidateIdentifier]
        if anchorsByFrame.isEmpty {
            guard prepared.values.allSatisfy({ $0.count == 1 }),
                  let firstFrame = sortedFrames.first,
                  let firstCandidate = prepared[firstFrame]?.first else {
                return .failure(.manualAnchorRequired)
            }
            effectiveAnchors = [GolfPoseCandidateIdentifier(
                sourceFrameIndex: firstFrame,
                candidateIndex: firstCandidate.candidateIndex
            )]
        } else {
            effectiveAnchors = sortedAnchors
        }

        var selectedByFrame: [Int: Int] = [:]
        var statesByFrame: [Int: [Int: PathState]] = [:]

        // Solve segment before first anchor
        if let firstAnchor = effectiveAnchors.first,
           let firstPos = sortedFrames.firstIndex(of: firstAnchor.sourceFrameIndex),
           firstPos > 0 {
            let segmentFrames = Array(sortedFrames[...firstPos].reversed())
            switch solveDirection(
                frameIndices: segmentFrames,
                anchorCandidateIndex: firstAnchor.candidateIndex,
                targetCandidateIndex: nil,
                candidatesByFrame: prepared
            ) {
            case .success(let sol):
                selectedByFrame.merge(sol.path) { _, new in new }
                statesByFrame.merge(sol.statesByFrame) { _, new in new }
            case .failure(let err):
                return .failure(err)
            }
        }

        // Solve segments between consecutive anchors
        if effectiveAnchors.count > 1 {
            for i in 0..<(effectiveAnchors.count - 1) {
                let currAnchor = effectiveAnchors[i]
                let nextAnchor = effectiveAnchors[i + 1]
                guard let currPos = sortedFrames.firstIndex(of: currAnchor.sourceFrameIndex),
                      let nextPos = sortedFrames.firstIndex(of: nextAnchor.sourceFrameIndex),
                      currPos < nextPos else {
                    return .failure(.duplicateFrameConflict(currAnchor.sourceFrameIndex))
                }
                let segmentFrames = Array(sortedFrames[currPos...nextPos])
                switch solveDirection(
                    frameIndices: segmentFrames,
                    anchorCandidateIndex: currAnchor.candidateIndex,
                    targetCandidateIndex: nextAnchor.candidateIndex,
                    candidatesByFrame: prepared
                ) {
                case .success(let sol):
                    selectedByFrame.merge(sol.path) { _, new in new }
                    statesByFrame.merge(sol.statesByFrame) { _, new in new }
                case .failure(let err):
                    return .failure(err)
                }
            }
        }

        // Solve segment after last anchor
        if let lastAnchor = effectiveAnchors.last,
           let lastPos = sortedFrames.firstIndex(of: lastAnchor.sourceFrameIndex) {
            if lastPos < sortedFrames.count - 1 {
                let segmentFrames = Array(sortedFrames[lastPos...])
                switch solveDirection(
                    frameIndices: segmentFrames,
                    anchorCandidateIndex: lastAnchor.candidateIndex,
                    targetCandidateIndex: nil,
                    candidatesByFrame: prepared
                ) {
                case .success(let sol):
                    selectedByFrame.merge(sol.path) { _, new in new }
                    statesByFrame.merge(sol.statesByFrame) { _, new in new }
                case .failure(let err):
                    return .failure(err)
                }
            } else {
                selectedByFrame[lastAnchor.sourceFrameIndex] = lastAnchor.candidateIndex
                statesByFrame[lastAnchor.sourceFrameIndex] = [
                    lastAnchor.candidateIndex: PathState(cost: 0, previousCandidateIndex: nil)
                ]
            }
        }

        // Enforce all explicit anchors in selectedByFrame
        for anchor in effectiveAnchors {
            selectedByFrame[anchor.sourceFrameIndex] = anchor.candidateIndex
        }

        // Ambiguity check with multi-anchor resets
        var ambiguityStart: Double?
        for frameIndex in sortedFrames {
            guard let frameTime = prepared[frameIndex]?.first?.sourceTime else {
                return .failure(.pathResolutionFailed(frameIndex))
            }
            let isAnchorFrame = anchorsByFrame[frameIndex] != nil
            if isAnchorFrame {
                ambiguityStart = nil
                continue
            }
            let costs = statesByFrame[frameIndex]?.values
                .map(\PathState.cost)
                .sorted() ?? []
            let isAmbiguous = costs.count > 1
                && costs[1] - costs[0] <= ambiguityCostMargin + comparisonEpsilon
            if isAmbiguous {
                if ambiguityStart == nil { ambiguityStart = frameTime }
                if let ambiguityStart,
                   frameTime - ambiguityStart > maximumAmbiguityDuration + comparisonEpsilon {
                    return .failure(.identityAmbiguityTooLong)
                }
            } else {
                ambiguityStart = nil
            }
        }

        var resolved: [GolfPoseTrackFrame] = []
        resolved.reserveCapacity(sortedFrames.count)
        for frameIndex in sortedFrames {
            guard let selectedIndex = selectedByFrame[frameIndex],
                  let selected = prepared[frameIndex]?.first(where: {
                      $0.candidateIndex == selectedIndex
                  }) else {
                return .failure(.pathResolutionFailed(frameIndex))
            }
            resolved.append(GolfPoseTrackFrame(
                sourceFrameIndex: selected.sourceFrameIndex,
                sourceTime: selected.sourceTime,
                bodyCenter: selected.bodyCenter,
                bodyBounds: selected.bodyBounds,
                handCenter: selected.handCenter,
                identityConfidence: resolvedConfidence(
                    selected: selected,
                    states: statesByFrame[frameIndex] ?? [:]
                )
            ))
        }
        return .success(resolved)
    }

    private static func prepare(
        candidates: [GolfPoseCandidateFrame]
    ) -> Result<[Int: [GolfPoseCandidateFrame]], PrimaryGolferTrackResolverError> {
        var indexed: [Int: [Int: GolfPoseCandidateFrame]] = [:]
        for candidate in candidates {
            guard isValid(candidate) else {
                return .failure(.invalidCandidate(
                    frameIndex: candidate.sourceFrameIndex,
                    candidateIndex: candidate.candidateIndex
                ))
            }
            if let existing = indexed[candidate.sourceFrameIndex]?[candidate.candidateIndex] {
                guard existing == candidate else {
                    return .failure(.duplicateFrameConflict(candidate.sourceFrameIndex))
                }
                continue
            }
            indexed[candidate.sourceFrameIndex, default: [:]][candidate.candidateIndex] = candidate
        }

        var prepared: [Int: [GolfPoseCandidateFrame]] = [:]
        for frameIndex in indexed.keys.sorted() {
            let frameCandidates = indexed[frameIndex]?.values.sorted {
                $0.candidateIndex < $1.candidateIndex
            } ?? []
            guard let sourceTime = frameCandidates.first?.sourceTime,
                  frameCandidates.allSatisfy({
                      abs($0.sourceTime - sourceTime) <= comparisonEpsilon
                  }) else {
                return .failure(.inconsistentFrameTime(frameIndex))
            }
            prepared[frameIndex] = frameCandidates
        }
        return .success(prepared)
    }

    private static func solveDirection(
        frameIndices: [Int],
        anchorCandidateIndex: Int,
        targetCandidateIndex: Int? = nil,
        candidatesByFrame: [Int: [GolfPoseCandidateFrame]]
    ) -> Result<DirectionSolution, PrimaryGolferTrackResolverError> {
        guard let anchorFrame = frameIndices.first else {
            return .failure(.emptyCandidates)
        }
        var statesByFrame: [Int: [Int: PathState]] = [
            anchorFrame: [
                anchorCandidateIndex: PathState(
                    cost: 0,
                    previousCandidateIndex: nil
                )
            ]
        ]

        if frameIndices.count > 1 {
            for position in 1..<frameIndices.count {
                let previousFrame = frameIndices[position - 1]
                let currentFrame = frameIndices[position]
                guard let previousStates = statesByFrame[previousFrame],
                      let previousCandidates = candidatesByFrame[previousFrame],
                      let currentCandidates = candidatesByFrame[currentFrame] else {
                    return .failure(.pathResolutionFailed(currentFrame))
                }

                var currentStates: [Int: PathState] = [:]
                for current in currentCandidates {
                    var best: (cost: Double, previousCandidateIndex: Int)?
                    for previousIndex in previousStates.keys.sorted() {
                        guard let previousState = previousStates[previousIndex],
                              let previous = previousCandidates.first(where: {
                                  $0.candidateIndex == previousIndex
                              }) else {
                            continue
                        }
                        let cost = previousState.cost + transitionCost(
                            from: previous,
                            to: current
                        )
                        if best == nil
                            || cost < best!.cost - comparisonEpsilon
                            || (abs(cost - best!.cost) <= comparisonEpsilon
                                && previousIndex < best!.previousCandidateIndex) {
                            best = (cost, previousIndex)
                        }
                    }
                    if let best {
                        currentStates[current.candidateIndex] = PathState(
                            cost: best.cost,
                            previousCandidateIndex: best.previousCandidateIndex
                        )
                    }
                }
                guard !currentStates.isEmpty else {
                    return .failure(.pathResolutionFailed(currentFrame))
                }
                statesByFrame[currentFrame] = currentStates
            }
        }

        guard let lastFrame = frameIndices.last,
              let lastStates = statesByFrame[lastFrame] else {
            return .failure(.pathResolutionFailed(anchorFrame))
        }

        let lastCandidate: Int
        if let target = targetCandidateIndex {
            guard lastStates[target] != nil else {
                return .failure(.pathResolutionFailed(lastFrame))
            }
            lastCandidate = target
        } else {
            guard let best = lastStates.keys.min(by: { lhs, rhs in
                guard let left = lastStates[lhs], let right = lastStates[rhs] else {
                    return lhs < rhs
                }
                if abs(left.cost - right.cost) <= comparisonEpsilon {
                    return lhs < rhs
                }
                return left.cost < right.cost
            }) else {
                return .failure(.pathResolutionFailed(anchorFrame))
            }
            lastCandidate = best
        }

        var path: [Int: Int] = [:]
        var currentCandidate = lastCandidate
        for position in stride(from: frameIndices.count - 1, through: 0, by: -1) {
            let frameIndex = frameIndices[position]
            path[frameIndex] = currentCandidate
            if position > 0 {
                guard let previous = statesByFrame[frameIndex]?[currentCandidate]?
                    .previousCandidateIndex else {
                    return .failure(.pathResolutionFailed(frameIndex))
                }
                currentCandidate = previous
            }
        }
        return .success(DirectionSolution(path: path, statesByFrame: statesByFrame))
    }

    private static func transitionCost(
        from previous: GolfPoseCandidateFrame,
        to current: GolfPoseCandidateFrame
    ) -> Double {
        let centerDistance = hypot(
            current.bodyCenter.x - previous.bodyCenter.x,
            current.bodyCenter.y - previous.bodyCenter.y
        )
        let scaleChange = abs(log(current.bodyScale / previous.bodyScale))
        let previousShape = normalizedShape(for: previous)
        let currentShape = normalizedShape(for: current)
        let jointShapeDistance = sqrt(
            pow(currentShape.shoulder - previousShape.shoulder, 2)
                + pow(currentShape.hip - previousShape.hip, 2)
                + pow(currentShape.torso - previousShape.torso, 2)
        )
        let confidencePenalty = current.identityConfidence < 0.5 ? 1.0 : 0.0
        return 3.0 * centerDistance
            + 1.5 * scaleChange
            + 2.0 * jointShapeDistance
            + confidencePenalty
    }

    private static func normalizedShape(
        for candidate: GolfPoseCandidateFrame
    ) -> (shoulder: Double, hip: Double, torso: Double) {
        (
            candidate.jointGeometry.shoulderWidth / candidate.bodyScale,
            candidate.jointGeometry.hipWidth / candidate.bodyScale,
            candidate.jointGeometry.torsoLength / candidate.bodyScale
        )
    }

    private static func resolvedConfidence(
        selected: GolfPoseCandidateFrame,
        states: [Int: PathState]
    ) -> Double {
        guard let selectedCost = states[selected.candidateIndex]?.cost else {
            return selected.identityConfidence
        }
        let alternative = states
            .filter { $0.key != selected.candidateIndex }
            .map { $0.value.cost }
            .min()
        guard let alternative else { return selected.identityConfidence }
        let gap = max(0, alternative - selectedCost)
        let pathConfidence = 0.55 + 0.45 * (1.0 - exp(-gap))
        return min(selected.identityConfidence, pathConfidence)
    }

    private static func isValid(_ candidate: GolfPoseCandidateFrame) -> Bool {
        guard candidate.sourceFrameIndex >= 0,
              candidate.candidateIndex >= 0,
              candidate.sourceTime.isFinite,
              candidate.sourceTime >= 0,
              candidate.bodyScale.isFinite,
              candidate.bodyScale > 0,
              candidate.identityConfidence.isFinite,
              (0...1).contains(candidate.identityConfidence),
              isValid(point: candidate.bodyCenter),
              candidate.bodyBounds.x.isFinite,
              candidate.bodyBounds.y.isFinite,
              candidate.bodyBounds.width.isFinite,
              candidate.bodyBounds.height.isFinite,
              candidate.bodyBounds.x >= 0,
              candidate.bodyBounds.y >= 0,
              candidate.bodyBounds.width > 0,
              candidate.bodyBounds.height > 0,
              candidate.bodyBounds.x + candidate.bodyBounds.width <= 1 + comparisonEpsilon,
              candidate.bodyBounds.y + candidate.bodyBounds.height <= 1 + comparisonEpsilon,
              candidate.jointGeometry.shoulderWidth.isFinite,
              candidate.jointGeometry.hipWidth.isFinite,
              candidate.jointGeometry.torsoLength.isFinite,
              candidate.jointGeometry.shoulderWidth >= 0,
              candidate.jointGeometry.hipWidth >= 0,
              candidate.jointGeometry.torsoLength >= 0 else {
            return false
        }
        return candidate.handCenter.map(isValid(point:)) ?? true
    }

    private static func isValid(point: GolfNormalizedPoint) -> Bool {
        point.x.isFinite
            && point.y.isFinite
            && (0...1).contains(point.x)
            && (0...1).contains(point.y)
    }
}

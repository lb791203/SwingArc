import Foundation
import CoreGraphics
import CoreMedia

struct SwingPoseSample: Equatable {
    let time: Double
    let sourceFrameIndex: Int?
    let leftWrist: CGPoint?
    let rightWrist: CGPoint?
    let leftElbow: CGPoint?
    let rightElbow: CGPoint?
    let leftShoulder: CGPoint?
    let rightShoulder: CGPoint?
    let leftHip: CGPoint?
    let rightHip: CGPoint?
    let leftKnee: CGPoint?
    let rightKnee: CGPoint?
    let leftAnkle: CGPoint?
    let rightAnkle: CGPoint?
    let head: CGPoint?
    let spineAngle: Double?
    let aggregateConfidence: Float

    init(time: Double, wristY: CGFloat) {
        self.init(
            time: time,
            leftWrist: nil,
            rightWrist: CGPoint(x: 0.5, y: wristY),
            leftElbow: nil,
            rightElbow: nil,
            leftShoulder: nil,
            rightShoulder: nil,
            leftHip: nil,
            rightHip: nil,
            head: nil,
            spineAngle: nil,
            aggregateConfidence: 1,
            sourceFrameIndex: nil
        )
    }

    init(
        time: Double,
        leftWrist: CGPoint?, rightWrist: CGPoint?,
        leftElbow: CGPoint?, rightElbow: CGPoint?,
        leftShoulder: CGPoint?, rightShoulder: CGPoint?,
        leftHip: CGPoint?, rightHip: CGPoint?,
        head: CGPoint?, spineAngle: Double?, aggregateConfidence: Float,
        sourceFrameIndex: Int? = nil,
        leftKnee: CGPoint? = nil, rightKnee: CGPoint? = nil,
        leftAnkle: CGPoint? = nil, rightAnkle: CGPoint? = nil
    ) {
        self.time = time
        self.sourceFrameIndex = sourceFrameIndex
        self.leftWrist = leftWrist
        self.rightWrist = rightWrist
        self.leftElbow = leftElbow
        self.rightElbow = rightElbow
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        self.leftHip = leftHip
        self.rightHip = rightHip
        self.leftKnee = leftKnee
        self.rightKnee = rightKnee
        self.leftAnkle = leftAnkle
        self.rightAnkle = rightAnkle
        self.head = head
        self.spineAngle = spineAngle
        self.aggregateConfidence = aggregateConfidence
    }

    var wristY: CGFloat { rightWrist?.y ?? leftWrist?.y ?? .nan }
}

enum LeadArmSide: String, Equatable {
    case left
    case right
    case unknown
}

struct ClubShaftEvidence: Equatable {
    let start: CGPoint
    let end: CGPoint
    let confidence: Double

    var length: Double {
        hypot(Double(end.x - start.x), Double(end.y - start.y))
    }

    var angle: Double {
        SwingGeometry.lineAngle(from: start, to: end)
    }

    func isConnected(to point: CGPoint, tolerance: Double) -> Bool {
        min(
            hypot(Double(point.x - start.x), Double(point.y - start.y)),
            hypot(Double(point.x - end.x), Double(point.y - end.y))
        ) <= tolerance
    }

    func distanceFromExtendedLine(to point: CGPoint) -> Double {
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        let denominator = hypot(dx, dy)
        guard denominator > .leastNonzeroMagnitude else {
            return hypot(Double(point.x - start.x), Double(point.y - start.y))
        }
        let numerator = abs(
            dy * Double(point.x - start.x) - dx * Double(point.y - start.y)
        )
        return numerator / denominator
    }
}

struct BallEvidence: Equatable {
    let center: CGPoint
    let radius: Double
    let confidence: Double
}

struct BallTrackUpdate: Equatable {
    let stableBall: BallEvidence?
    let localChange: Double
}

struct BallPositionTracker: Equatable {
    private let requiredHits: Int
    private let maximumMisses: Int
    private(set) var stableBall: BallEvidence?
    private var candidateCenter: CGPoint?
    private var hitCount = 0
    private var missCount = 0
    private var previousSourceFrameIndex: Int?

    init(requiredHits: Int = 3, maximumMisses: Int = 2, seed: BallEvidence? = nil) {
        self.requiredHits = max(1, requiredHits)
        self.maximumMisses = max(0, maximumMisses)
        stableBall = seed
        candidateCenter = seed?.center
        hitCount = seed == nil ? 0 : self.requiredHits
    }

    mutating func update(
        _ observation: BallEvidence?,
        sourceFrameIndex: Int
    ) -> BallTrackUpdate {
        let isContiguous = previousSourceFrameIndex.map {
            sourceFrameIndex == $0 + 1
        } ?? true
        previousSourceFrameIndex = sourceFrameIndex
        if !isContiguous {
            // Sparse P1/P2/P6/P8 candidate neighborhoods are not a continuous
            // disappearance sequence and must not share one miss streak.
            missCount = 0
        }
        guard let observation else {
            missCount += 1
            let changed = stableBall != nil && missCount > maximumMisses ? 1.0 : 0
            if missCount > maximumMisses {
                // Once the address ball has been stable for several frames it
                // becomes the fixed reference for this swing window. Its
                // disappearance is impact evidence, not a reason to erase the
                // location the shaft is measured against.
                candidateCenter = stableBall?.center
                hitCount = stableBall == nil ? 0 : requiredHits
            }
            return BallTrackUpdate(stableBall: stableBall, localChange: changed)
        }

        missCount = 0
        if let candidateCenter {
            let separation = hypot(
                Double(observation.center.x - candidateCenter.x),
                Double(observation.center.y - candidateCenter.y)
            )
            if separation <= 0.04 {
                let weight = Double(max(1, hitCount))
                self.candidateCenter = CGPoint(
                    x: (candidateCenter.x * weight + observation.center.x) / (weight + 1),
                    y: (candidateCenter.y * weight + observation.center.y) / (weight + 1)
                )
                hitCount += 1
            } else {
                self.candidateCenter = observation.center
                hitCount = 1
            }
        } else {
            candidateCenter = observation.center
            hitCount = 1
        }

        if hitCount >= requiredHits, let candidateCenter {
            stableBall = BallEvidence(
                center: candidateCenter,
                radius: observation.radius,
                confidence: observation.confidence
            )
        }
        return BallTrackUpdate(stableBall: stableBall, localChange: 0)
    }
}

struct SwingObjectEvidence: Equatable {
    let shaft: ClubShaftEvidence?
    let ball: BallEvidence?
    let stableBall: CGPoint?
    let ballLocalChange: Double
    let trackedPoints: [SwingLandmark: TrackedSwingPoint]

    init(
        shaft: ClubShaftEvidence?,
        ball: BallEvidence?,
        stableBall: CGPoint?,
        ballLocalChange: Double,
        trackedPoints: [SwingLandmark: TrackedSwingPoint] = [:]
    ) {
        self.shaft = shaft
        self.ball = ball
        self.stableBall = stableBall
        self.ballLocalChange = ballLocalChange
        self.trackedPoints = trackedPoints
    }

    static let empty = SwingObjectEvidence(
        shaft: nil,
        ball: nil,
        stableBall: nil,
        ballLocalChange: 0
    )
}

struct SwingFrameSample: Equatable {
    let sourceFrameIndex: Int
    let time: Double
    let pose: SwingPoseSample?
    let rawPose: SwingPoseSample?
    let objectEvidence: SwingObjectEvidence

    init(
        sourceFrameIndex: Int,
        time: Double,
        pose: SwingPoseSample?,
        objectEvidence: SwingObjectEvidence
    ) {
        self.sourceFrameIndex = sourceFrameIndex
        self.time = time
        self.pose = pose
        self.rawPose = pose
        self.objectEvidence = objectEvidence
    }

    init(
        sourceFrameIndex: Int,
        time: Double,
        pose: SwingPoseSample?,
        rawPose: SwingPoseSample?,
        objectEvidence: SwingObjectEvidence
    ) {
        self.sourceFrameIndex = sourceFrameIndex
        self.time = time
        self.pose = pose
        self.rawPose = rawPose
        self.objectEvidence = objectEvidence
    }
}

struct SwingFrameEvidence: Equatable {
    let sourceFrameIndex: Int
    let time: Double
    let pose: SwingPoseSample?
    let rawPose: SwingPoseSample?
    let objectEvidence: SwingObjectEvidence
    let leadArm: LeadArmSide
    let leadArmAngle: Double?
    let leadArmExtension: Double?
    let shoulderAngle: Double?
    let hipAngle: Double?
    let handCenter: CGPoint?
    let hipCenter: CGPoint?
    let handVelocity: CGPoint
    let handAcceleration: CGPoint
    let headSpeed: Double
    let hipSpeed: Double
    let poseCoverage: Double

    init(
        sourceFrameIndex: Int,
        time: Double,
        pose: SwingPoseSample?,
        rawPose: SwingPoseSample? = nil,
        objectEvidence: SwingObjectEvidence,
        leadArm: LeadArmSide,
        leadArmAngle: Double?,
        leadArmExtension: Double?,
        shoulderAngle: Double?,
        hipAngle: Double?,
        handCenter: CGPoint?,
        hipCenter: CGPoint?,
        handVelocity: CGPoint,
        handAcceleration: CGPoint,
        headSpeed: Double,
        hipSpeed: Double,
        poseCoverage: Double
    ) {
        self.sourceFrameIndex = sourceFrameIndex
        self.time = time
        self.pose = pose
        self.rawPose = rawPose
        self.objectEvidence = objectEvidence
        self.leadArm = leadArm
        self.leadArmAngle = leadArmAngle
        self.leadArmExtension = leadArmExtension
        self.shoulderAngle = shoulderAngle
        self.hipAngle = hipAngle
        self.handCenter = handCenter
        self.hipCenter = hipCenter
        self.handVelocity = handVelocity
        self.handAcceleration = handAcceleration
        self.headSpeed = headSpeed
        self.hipSpeed = hipSpeed
        self.poseCoverage = poseCoverage
    }
}

enum SwingMotionDirection: Equatable {
    case backswing
    case downswing
    case stable
}

enum SwingEvidenceQualityFlag: Hashable {
    case missingHands
    case missingLeadArm
    case labelSwapSuspected
}

struct SwingTemporalFrame: Equatable {
    let frame: SwingFrameEvidence
    let direction: SwingMotionDirection
    let sustainedBackswing: Bool
    let sustainedDownswing: Bool
    let sustainedFollowThrough: Bool
    let isAddressBoundary: Bool
    let isTopPlateauEnd: Bool
    /// Legacy terminal-pose diagnostic. It is not used to close canonical
    /// P1–P8 analysis or to resolve P8.
    let isFinishPlateauStart: Bool
    let shaftAngleContinuity: Double
    let ballStability: Double
    let qualityFlags: Set<SwingEvidenceQualityFlag>
}

enum SwingEvidenceTimeline {
    static let directionWindow = 0.15
    static let stableWindow = 0.25
    static let directionVoteRatio = 0.75
    static let stableVoteRatio = 0.75
    static let handDirectionThreshold = 0.12
    static let bodyStabilityThreshold = 0.08

    private static let handStabilityThreshold = 0.18
    private static let takeawayBodyStabilityThreshold = 0.10
    private static let takeawayOnsetSpeedThreshold = 0.08
    private static let isolatedVisionJitterSpeedThreshold = 0.20
    private static let takeawayConfirmationDisplacement = 0.05
    private static let takeawayConfirmationWindow = 0.75
    private static let maximumAddressHandHipDistance = 0.14
    private static let followThroughConfirmationDisplacement = 0.04
    private static let topPlateauHandSpeedThreshold = 0.01
    private static let minimumWindowCoverage = 0.80
    private static let stableBallDistanceThreshold = 0.025
    private static let labelSwapAxisTolerance = 12.0

    static func build(from rawEvidence: [SwingFrameEvidence]) -> [SwingTemporalFrame] {
        let evidence = rawEvidence.sorted {
            $0.time == $1.time
                ? $0.sourceFrameIndex < $1.sourceFrameIndex
                : $0.time < $1.time
        }
        guard !evidence.isEmpty else { return [] }

        let rawDirections = evidence.map(frameDirection)
        let pastWindows = evidence.indices.map {
            timedIndices(endingAt: $0, duration: directionWindow, evidence: evidence)
        }
        let futureWindows = evidence.indices.map {
            timedIndices(startingAt: $0, duration: directionWindow, evidence: evidence)
        }
        let pastDirections = pastWindows.map {
            directionVote(indices: $0, duration: directionWindow, evidence: evidence)
        }
        let futureDirections = futureWindows.map { indices in
            directionVote(
                indices: Array(indices.dropFirst()),
                duration: directionWindow,
                evidence: evidence
            )
        }
        let stablePast = evidence.indices.map {
            stabilityVote(
                indices: timedIndices(endingAt: $0, duration: stableWindow, evidence: evidence),
                duration: stableWindow,
                evidence: evidence
            )
        }
        let directionalAddressIndex = evidence.indices.first { index in
            stablePast[index]
                && rawDirections[index] == .stable
                && sustainedDirectionBegins(
                    after: index,
                    direction: .backswing,
                    rawDirections: rawDirections,
                    evidence: evidence
                )
        }
        let motionOnsetAddressIndex = evidence.indices.dropFirst().first {
            takeawayMotionOnset(at: $0, evidence: evidence)
        }.map { $0 - 1 }
        let addressIndex = [directionalAddressIndex, motionOnsetAddressIndex]
            .compactMap { $0 }
            .min()
        let topTransitionIndex = evidence.indices.first { index in
            guard index > (addressIndex ?? -1) else { return false }
            return rawDirections[index] == .stable
                && pastDirections[index] != .downswing
                && sustainedDirectionBegins(
                    after: index,
                    direction: .downswing,
                    rawDirections: rawDirections,
                    evidence: evidence
                )
        }
        let topIndex = topTransitionIndex.map {
            lastNearStationaryTopFrame(endingAt: $0, evidence: evidence) ?? $0
        }
        let finishIndex = evidence.indices.first { index in
            guard index > (topIndex ?? addressIndex ?? -1),
                  pastDirections[index] == .backswing
                    || directionPrecedes(
                        index,
                        direction: .backswing,
                        rawDirections: rawDirections,
                        evidence: evidence
                    )
                    || horizontalFollowThroughPrecedes(at: index, evidence: evidence) else {
                return false
            }
            return sustainedStabilityBegins(
                at: index,
                pastDirection: .backswing,
                rawDirections: rawDirections,
                evidence: evidence
            )
        }
        let followThroughIndex = evidence.indices.first { index in
            index > (topIndex ?? -1) && futureDirections[index] == .backswing
        }

        return evidence.indices.map { index in
            let surrounding = uniqueSorted(pastWindows[index] + futureWindows[index])
            let isBackswingPhase: Bool
            if let addressIndex, let topIndex {
                isBackswingPhase = index >= addressIndex && index < topIndex
            } else {
                isBackswingPhase = false
            }
            let isDownswingPhase: Bool
            if let topIndex, let followThroughIndex {
                isDownswingPhase = index >= topIndex && index < followThroughIndex
            } else {
                isDownswingPhase = false
            }
            return SwingTemporalFrame(
                frame: evidence[index],
                direction: directionVote(
                    indices: surrounding,
                    duration: directionWindow,
                    evidence: evidence
                ),
                sustainedBackswing: futureDirections[index] == .backswing || isBackswingPhase,
                sustainedDownswing: futureDirections[index] == .downswing || isDownswingPhase,
                sustainedFollowThrough: futureDirections[index] == .backswing,
                isAddressBoundary: index == addressIndex,
                isTopPlateauEnd: index == topIndex,
                isFinishPlateauStart: index == finishIndex,
                shaftAngleContinuity: shaftContinuity(at: index, evidence: evidence),
                ballStability: stableBallVote(at: index, evidence: evidence),
                qualityFlags: qualityFlags(at: index, evidence: evidence)
            )
        }
    }

    private static func timedIndices(
        endingAt index: Int,
        duration: Double,
        evidence: [SwingFrameEvidence]
    ) -> [Int] {
        var start = index
        while start > evidence.startIndex,
              evidence[index].time - evidence[start].time < duration {
            start -= 1
        }
        return Array(start...index)
    }

    private static func timedIndices(
        startingAt index: Int,
        duration: Double,
        evidence: [SwingFrameEvidence]
    ) -> [Int] {
        var end = index
        while end < evidence.index(before: evidence.endIndex),
              evidence[end].time - evidence[index].time < duration {
            end += 1
        }
        return Array(index...end)
    }

    private static func directionVote(
        indices: [Int],
        duration: Double,
        evidence: [SwingFrameEvidence]
    ) -> SwingMotionDirection {
        let indices = uniqueSorted(indices)
        guard windowSpans(indices, duration: duration, evidence: evidence) else { return .stable }
        let directions = indices.compactMap { frameDirection(evidence[$0]) }
        guard !directions.isEmpty else { return .stable }
        let backswingRatio = Double(directions.filter { $0 == .backswing }.count) / Double(directions.count)
        if backswingRatio >= directionVoteRatio { return .backswing }
        let downswingRatio = Double(directions.filter { $0 == .downswing }.count) / Double(directions.count)
        return downswingRatio >= directionVoteRatio ? .downswing : .stable
    }

    private static func stabilityVote(
        indices: [Int],
        duration: Double,
        evidence: [SwingFrameEvidence]
    ) -> Bool {
        let indices = uniqueSorted(indices)
        guard windowSpans(indices, duration: duration, evidence: evidence) else { return false }
        let validFrames = indices.compactMap { index -> SwingFrameEvidence? in
            let frame = evidence[index]
            return frameStability(frame) == nil ? nil : frame
        }
        guard !validFrames.isEmpty else { return false }
        let stableCount = validFrames.filter { frameStability($0) == true }.count
        return Double(stableCount) / Double(validFrames.count) >= stableVoteRatio
    }

    private static func sustainedDirectionBegins(
        after index: Int,
        direction: SwingMotionDirection,
        rawDirections: [SwingMotionDirection?],
        evidence: [SwingFrameEvidence]
    ) -> Bool {
        let transitionIndices = Array(
            timedIndices(startingAt: index, duration: directionWindow, evidence: evidence)
                .dropFirst()
        )
        var skippedOutlier = false
        for futureIndex in transitionIndices {
            if rawDirections[futureIndex] == direction {
                let sustainedIndices = timedIndices(
                    startingAt: futureIndex,
                    duration: directionWindow,
                    evidence: evidence
                )
                return directionVote(
                    indices: sustainedIndices,
                    duration: directionWindow,
                    evidence: evidence
                ) == direction
            }
            let disagreesWithTarget = rawDirections[futureIndex].map {
                $0 != .stable && $0 != direction
            } ?? false
            guard !skippedOutlier,
                  frameStability(evidence[futureIndex]) == false
                    || disagreesWithTarget else { return false }
            skippedOutlier = true
        }
        return false
    }

    private static func takeawayMotionOnset(
        at index: Int,
        evidence: [SwingFrameEvidence]
    ) -> Bool {
        guard index > evidence.startIndex,
              evidence[index].headSpeed.isFinite,
              evidence[index].hipSpeed.isFinite,
              evidence[index].headSpeed <= takeawayBodyStabilityThreshold,
              evidence[index].hipSpeed <= takeawayBodyStabilityThreshold,
              let start = evidence[index].handCenter,
              let hip = evidence[index].hipCenter,
              SwingGeometry.distance(start, hip) <= maximumAddressHandHipDistance,
              hasQuietAddressHistory(endingBefore: index, evidence: evidence) else {
            return false
        }
        let currentSpeed = hypot(
            Double(evidence[index].handVelocity.x),
            Double(evidence[index].handVelocity.y)
        )
        let previousSpeed = hypot(
            Double(evidence[index - 1].handVelocity.x),
            Double(evidence[index - 1].handVelocity.y)
        )
        guard currentSpeed >= takeawayOnsetSpeedThreshold,
              currentSpeed <= handStabilityThreshold,
              previousSpeed < takeawayOnsetSpeedThreshold else { return false }

        let confirmationIndices = timedIndices(
            startingAt: index,
            duration: takeawayConfirmationWindow,
            evidence: evidence
        )
        guard windowSpans(
            confirmationIndices,
            duration: takeawayConfirmationWindow,
            evidence: evidence
        ) else { return false }
        return confirmationIndices.contains { futureIndex in
            guard let future = evidence[futureIndex].handCenter else { return false }
            return hypot(Double(future.x - start.x), Double(future.y - start.y))
                >= takeawayConfirmationDisplacement
        }
    }

    private static func lastNearStationaryTopFrame(
        endingAt transitionIndex: Int,
        evidence: [SwingFrameEvidence]
    ) -> Int? {
        timedIndices(
            endingAt: transitionIndex,
            duration: stableWindow,
            evidence: evidence
        ).last { index in
            let velocity = evidence[index].handVelocity
            return velocity.x.isFinite
                && velocity.y.isFinite
                && hypot(Double(velocity.x), Double(velocity.y))
                    <= topPlateauHandSpeedThreshold
        }
    }

    private static func hasQuietAddressHistory(
        endingBefore index: Int,
        evidence: [SwingFrameEvidence]
    ) -> Bool {
        let history = Array(
            timedIndices(
                endingAt: index,
                duration: stableWindow,
                evidence: evidence
            ).dropLast()
        )
        guard windowSpans(history, duration: stableWindow, evidence: evidence) else {
            return false
        }
        let trustedHistory = history.filter {
            !isIsolatedVisionHandJitter(at: $0, evidence: evidence)
        }
        guard !trustedHistory.isEmpty else { return false }
        let quietCount = trustedHistory.filter { historyIndex in
            let velocity = evidence[historyIndex].handVelocity
            return hypot(Double(velocity.x), Double(velocity.y))
                < takeawayOnsetSpeedThreshold
        }.count
        return Double(quietCount) / Double(trustedHistory.count) > stableVoteRatio
    }

    private static func isIsolatedVisionHandJitter(
        at index: Int,
        evidence: [SwingFrameEvidence]
    ) -> Bool {
        guard index > evidence.startIndex,
              index < evidence.index(before: evidence.endIndex) else { return false }
        let speed = handSpeed(evidence[index])
        guard speed >= isolatedVisionJitterSpeedThreshold else { return false }
        return handSpeed(evidence[index - 1]) < takeawayOnsetSpeedThreshold
            && handSpeed(evidence[index + 1]) < takeawayOnsetSpeedThreshold
    }

    private static func handSpeed(_ frame: SwingFrameEvidence) -> Double {
        hypot(Double(frame.handVelocity.x), Double(frame.handVelocity.y))
    }

    private static func sustainedStabilityBegins(
        at index: Int,
        pastDirection: SwingMotionDirection,
        rawDirections: [SwingMotionDirection?],
        evidence: [SwingFrameEvidence]
    ) -> Bool {
        guard frameStability(evidence[index]) == true else { return false }
        let indices = timedIndices(startingAt: index, duration: stableWindow, evidence: evidence)
        guard stabilityVote(indices: indices, duration: stableWindow, evidence: evidence) else {
            return false
        }

        var consecutiveUnstable = 0
        for candidateIndex in indices {
            if frameStability(evidence[candidateIndex]) == true {
                consecutiveUnstable = 0
            } else {
                consecutiveUnstable += 1
                if consecutiveUnstable > 1 { return false }
            }
        }

        var skippedOutlier = false
        for futureIndex in indices {
            if frameStability(evidence[futureIndex]) == true { return true }
            guard !skippedOutlier,
                  rawDirections[futureIndex] != pastDirection else { return false }
            skippedOutlier = true
        }
        return false
    }

    private static func horizontalFollowThroughPrecedes(
        at index: Int,
        evidence: [SwingFrameEvidence]
    ) -> Bool {
        let preceding = timedIndices(
            endingAt: index,
            duration: stableWindow,
            evidence: evidence
        )
        guard windowSpans(preceding, duration: stableWindow, evidence: evidence),
              let first = preceding.first.flatMap({ evidence[$0].handCenter }),
              let last = evidence[index].handCenter else { return false }
        return SwingGeometry.distance(first, last)
            >= followThroughConfirmationDisplacement
    }

    private static func directionPrecedes(
        _ index: Int,
        direction: SwingMotionDirection,
        rawDirections: [SwingMotionDirection?],
        evidence: [SwingFrameEvidence]
    ) -> Bool {
        let preceding = Array(
            timedIndices(endingAt: index, duration: directionWindow, evidence: evidence)
                .dropLast()
        )
        let observed = preceding.compactMap { rawDirections[$0] }
        let matchingCount = observed.filter { $0 == direction }.count
        let opposingCount = observed.filter {
            $0 != .stable && $0 != direction
        }.count
        return matchingCount >= 2 && opposingCount <= 1
    }

    private static func frameStability(_ frame: SwingFrameEvidence) -> Bool? {
        guard frame.handCenter != nil,
              frame.hipCenter != nil,
              frame.pose?.head != nil,
              frame.headSpeed.isFinite,
              frame.hipSpeed.isFinite,
              frame.handVelocity.x.isFinite,
              frame.handVelocity.y.isFinite else { return nil }
        return frame.headSpeed <= bodyStabilityThreshold
            && frame.hipSpeed <= bodyStabilityThreshold
            && hypot(Double(frame.handVelocity.x), Double(frame.handVelocity.y))
                <= handStabilityThreshold
    }

    private static func frameDirection(_ frame: SwingFrameEvidence) -> SwingMotionDirection? {
        guard frame.handCenter != nil, frame.handVelocity.y.isFinite else { return nil }
        if frame.handVelocity.y <= -handDirectionThreshold { return .backswing }
        if frame.handVelocity.y >= handDirectionThreshold { return .downswing }
        return .stable
    }

    private static func shaftContinuity(
        at index: Int,
        evidence: [SwingFrameEvidence]
    ) -> Double {
        let indices = surroundingIndices(at: index, duration: directionWindow, evidence: evidence)
        let angles = indices.compactMap { evidence[$0].objectEvidence.shaft }.map { shaft in
            normalizedAxisAngle(SwingGeometry.lineAngle(from: shaft.start, to: shaft.end))
        }
        guard angles.count >= 2 else { return 0 }
        let deltas = zip(angles, angles.dropFirst()).map(angularAxisDistance)
        guard let medianDelta = median(deltas) else { return 0 }
        return 1 - min(1, medianDelta / 25)
    }

    private static func stableBallVote(
        at index: Int,
        evidence: [SwingFrameEvidence]
    ) -> Double {
        let centers = surroundingIndices(
            at: index,
            duration: directionWindow,
            evidence: evidence
        ).compactMap { frameIndex in
            evidence[frameIndex].objectEvidence.stableBall
                ?? evidence[frameIndex].objectEvidence.ball?.center
        }
        guard !centers.isEmpty,
              let medianX = median(centers.map { Double($0.x) }),
              let medianY = median(centers.map { Double($0.y) }) else { return 0 }
        let stableCount = centers.filter { center in
            hypot(Double(center.x) - medianX, Double(center.y) - medianY)
                <= stableBallDistanceThreshold
        }.count
        return Double(stableCount) / Double(centers.count)
    }

    private static func qualityFlags(
        at index: Int,
        evidence: [SwingFrameEvidence]
    ) -> Set<SwingEvidenceQualityFlag> {
        var flags: Set<SwingEvidenceQualityFlag> = []
        let frame = evidence[index]
        if frame.handCenter == nil { flags.insert(.missingHands) }
        if frame.leadArm == .unknown || !rawPoseObservesLeadArm(frame) {
            flags.insert(.missingLeadArm)
        }
        if index > evidence.startIndex,
           labelEndpointsReversed(
               previous: evidence[index - 1].rawPose ?? evidence[index - 1].pose,
               current: frame.rawPose ?? frame.pose
           ) {
            flags.insert(.labelSwapSuspected)
        }
        return flags
    }

    private static func rawPoseObservesLeadArm(_ frame: SwingFrameEvidence) -> Bool {
        guard let rawPose = frame.rawPose else { return false }
        switch frame.leadArm {
        case .left:
            return rawPose.leftShoulder != nil
                && rawPose.leftElbow != nil
                && rawPose.leftWrist != nil
        case .right:
            return rawPose.rightShoulder != nil
                && rawPose.rightElbow != nil
                && rawPose.rightWrist != nil
        case .unknown:
            return false
        }
    }

    private static func labelEndpointsReversed(
        previous: SwingPoseSample?,
        current: SwingPoseSample?
    ) -> Bool {
        guard let previous, let current else { return false }
        return axisEndpointsReversed(
            previousFirst: previous.leftShoulder,
            previousSecond: previous.rightShoulder,
            currentFirst: current.leftShoulder,
            currentSecond: current.rightShoulder
        ) || axisEndpointsReversed(
            previousFirst: previous.leftHip,
            previousSecond: previous.rightHip,
            currentFirst: current.leftHip,
            currentSecond: current.rightHip
        )
    }

    private static func axisEndpointsReversed(
        previousFirst: CGPoint?,
        previousSecond: CGPoint?,
        currentFirst: CGPoint?,
        currentSecond: CGPoint?
    ) -> Bool {
        guard let previousFirst, let previousSecond, let currentFirst, let currentSecond else {
            return false
        }
        let previousVector = CGVector(
            dx: previousSecond.x - previousFirst.x,
            dy: previousSecond.y - previousFirst.y
        )
        let currentVector = CGVector(
            dx: currentSecond.x - currentFirst.x,
            dy: currentSecond.y - currentFirst.y
        )
        let dotProduct = previousVector.dx * currentVector.dx + previousVector.dy * currentVector.dy
        guard dotProduct < 0 else { return false }
        let previousAngle = normalizedAxisAngle(
            atan2(Double(previousVector.dy), Double(previousVector.dx)) * 180 / .pi
        )
        let currentAngle = normalizedAxisAngle(
            atan2(Double(currentVector.dy), Double(currentVector.dx)) * 180 / .pi
        )
        return angularAxisDistance(previousAngle, currentAngle) <= labelSwapAxisTolerance
    }

    private static func surroundingIndices(
        at index: Int,
        duration: Double,
        evidence: [SwingFrameEvidence]
    ) -> [Int] {
        uniqueSorted(
            timedIndices(endingAt: index, duration: duration, evidence: evidence)
                + timedIndices(startingAt: index, duration: duration, evidence: evidence)
        )
    }

    private static func windowSpans(
        _ indices: [Int],
        duration: Double,
        evidence: [SwingFrameEvidence]
    ) -> Bool {
        guard let first = indices.first, let last = indices.last else { return false }
        return evidence[last].time - evidence[first].time + 0.000_000_001
            >= duration * minimumWindowCoverage
    }

    private static func uniqueSorted(_ indices: [Int]) -> [Int] {
        Array(Set(indices)).sorted()
    }

    private static func normalizedAxisAngle(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 180)
        if normalized < 0 { normalized += 180 }
        return normalized
    }

    private static func angularAxisDistance(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second)
        return min(difference, 180 - difference)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

extension Array where Element == SwingTemporalFrame {
    var adaptiveBoundaryEvidence: AdaptiveBoundaryEvidence {
        // This runs before sparse shaft/ball sampling. A sustained body-level
        // follow-through is enough to close the adaptive search window; it is
        // not a P8 decision. The final constrained solver still requires
        // reliable shaft evidence before it resolves P8.
        AdaptiveBoundaryEvidence(
            hasAddressBoundary: contains(where: \.isAddressBoundary),
            hasPostImpactBoundary: contains(where: \.sustainedFollowThrough)
        )
    }
}

enum SwingGeometry {
    nonisolated static func lineAngle(from: CGPoint, to: CGPoint) -> Double {
        atan2(Double(to.y - from.y), Double(to.x - from.x)) * 180 / .pi
    }

    nonisolated static func angleFromHorizontal(from: CGPoint, to: CGPoint) -> Double {
        let normalized = abs(lineAngle(from: from, to: to)).truncatingRemainder(dividingBy: 180)
        return min(normalized, 180 - normalized)
    }

    nonisolated static func jointAngle(a: CGPoint, vertex: CGPoint, c: CGPoint) -> Double {
        let first = CGVector(dx: a.x - vertex.x, dy: a.y - vertex.y)
        let second = CGVector(dx: c.x - vertex.x, dy: c.y - vertex.y)
        let magnitude = hypot(first.dx, first.dy) * hypot(second.dx, second.dy)
        guard magnitude > .leastNonzeroMagnitude else { return 0 }
        let cosine = min(1, max(-1, (first.dx * second.dx + first.dy * second.dy) / magnitude))
        return acos(Double(cosine)) * 180 / .pi
    }

    nonisolated static func center(_ first: CGPoint?, _ second: CGPoint?) -> CGPoint? {
        if let first, let second {
            return CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
        }
        return first ?? second
    }

    nonisolated static func distance(_ first: CGPoint?, _ second: CGPoint?) -> Double {
        guard let first, let second else { return 0 }
        return hypot(Double(first.x - second.x), Double(first.y - second.y))
    }
}

enum SwingFeatureExtractor {
    private static let poseSmoothingRadius = 2

    static func extract(frames rawFrames: [SwingFrameSample]) -> [SwingFrameEvidence] {
        let sortedFrames = rawFrames.sorted { $0.time < $1.time }
        let frames = smoothedFrames(sortedFrames)
        let leadArm = resolveLeadArm(frames: frames)
        var previousHand: CGPoint?
        var previousVelocity = CGPoint.zero
        var previousHead: CGPoint?
        var previousHip: CGPoint?
        var previousTime: Double?

        return frames.enumerated().map { index, frame in
            let pose = frame.pose
            let hand = pose.flatMap { SwingGeometry.center($0.leftWrist, $0.rightWrist) }
            let hip = pose.flatMap { SwingGeometry.center($0.leftHip, $0.rightHip) }
            let elapsed = max(frame.time - (previousTime ?? frame.time), 0)
            let velocity: CGPoint
            let acceleration: CGPoint
            let headSpeed: Double
            let hipSpeed: Double
            if elapsed > 0 {
                velocity = CGPoint(
                    x: ((hand?.x ?? previousHand?.x ?? 0) - (previousHand?.x ?? hand?.x ?? 0)) / elapsed,
                    y: ((hand?.y ?? previousHand?.y ?? 0) - (previousHand?.y ?? hand?.y ?? 0)) / elapsed
                )
                acceleration = CGPoint(
                    x: (velocity.x - previousVelocity.x) / elapsed,
                    y: (velocity.y - previousVelocity.y) / elapsed
                )
                headSpeed = SwingGeometry.distance(pose?.head, previousHead) / elapsed
                hipSpeed = SwingGeometry.distance(hip, previousHip) / elapsed
            } else {
                velocity = .zero
                acceleration = .zero
                headSpeed = 0
                hipSpeed = 0
            }

            let armPoints = points(for: leadArm, pose: pose)
            let shoulderAngle = axisAngle(pose?.leftShoulder, pose?.rightShoulder)
            let hipAngle = axisAngle(pose?.leftHip, pose?.rightHip)
            let coverage = pose.map(poseCoverage) ?? 0
            let evidence = SwingFrameEvidence(
                sourceFrameIndex: frame.sourceFrameIndex,
                time: frame.time,
                pose: pose,
                rawPose: sortedFrames[index].rawPose,
                objectEvidence: frame.objectEvidence,
                leadArm: leadArm,
                leadArmAngle: angleFromHorizontal(armPoints.shoulder, armPoints.wrist),
                leadArmExtension: jointAngle(armPoints.shoulder, armPoints.elbow, armPoints.wrist),
                shoulderAngle: shoulderAngle,
                hipAngle: hipAngle,
                handCenter: hand,
                hipCenter: hip,
                handVelocity: velocity,
                handAcceleration: acceleration,
                headSpeed: headSpeed,
                hipSpeed: hipSpeed,
                poseCoverage: coverage
            )
            previousHand = hand ?? previousHand
            previousVelocity = velocity
            previousHead = pose?.head ?? previousHead
            previousHip = hip ?? previousHip
            previousTime = frame.time
            return evidence
        }
    }

    private static func smoothedFrames(_ frames: [SwingFrameSample]) -> [SwingFrameSample] {
        let poses = frames.map(\.pose)
        return frames.indices.map { index in
            let frame = frames[index]
            guard let rawPose = frame.pose else { return frame }
            let pose = SwingPoseSample(
                time: frame.time,
                leftWrist: medianPoint(poses, at: index, keyPath: \.leftWrist),
                rightWrist: medianPoint(poses, at: index, keyPath: \.rightWrist),
                leftElbow: medianPoint(poses, at: index, keyPath: \.leftElbow),
                rightElbow: medianPoint(poses, at: index, keyPath: \.rightElbow),
                leftShoulder: medianPoint(poses, at: index, keyPath: \.leftShoulder),
                rightShoulder: medianPoint(poses, at: index, keyPath: \.rightShoulder),
                leftHip: medianPoint(poses, at: index, keyPath: \.leftHip),
                rightHip: medianPoint(poses, at: index, keyPath: \.rightHip),
                head: medianPoint(poses, at: index, keyPath: \.head),
                spineAngle: medianValue(poses, at: index, keyPath: \.spineAngle),
                aggregateConfidence: rawPose.aggregateConfidence,
                sourceFrameIndex: frame.sourceFrameIndex,
                leftKnee: medianPoint(poses, at: index, keyPath: \.leftKnee),
                rightKnee: medianPoint(poses, at: index, keyPath: \.rightKnee),
                leftAnkle: medianPoint(poses, at: index, keyPath: \.leftAnkle),
                rightAnkle: medianPoint(poses, at: index, keyPath: \.rightAnkle)
            )
            return SwingFrameSample(
                sourceFrameIndex: frame.sourceFrameIndex,
                time: frame.time,
                pose: pose,
                rawPose: frame.rawPose,
                objectEvidence: frame.objectEvidence
            )
        }
    }

    private static func medianPoint(
        _ poses: [SwingPoseSample?],
        at index: Int,
        keyPath: KeyPath<SwingPoseSample, CGPoint?>
    ) -> CGPoint? {
        let start = max(0, index - poseSmoothingRadius)
        let end = min(poses.count - 1, index + poseSmoothingRadius)
        let points = poses[start...end].compactMap { $0?[keyPath: keyPath] }
        let requiredCount = max(1, (end - start + 2) / 2)
        guard points.count >= requiredCount else { return nil }
        let xValues = points.map(\.x).sorted()
        let yValues = points.map(\.y).sorted()
        return CGPoint(
            x: xValues[xValues.count / 2],
            y: yValues[yValues.count / 2]
        )
    }

    private static func medianValue(
        _ poses: [SwingPoseSample?],
        at index: Int,
        keyPath: KeyPath<SwingPoseSample, Double?>
    ) -> Double? {
        let start = max(0, index - poseSmoothingRadius)
        let end = min(poses.count - 1, index + poseSmoothingRadius)
        let values = poses[start...end].compactMap { $0?[keyPath: keyPath] }.sorted()
        let requiredCount = max(1, (end - start + 2) / 2)
        guard values.count >= requiredCount else { return nil }
        return values[values.count / 2]
    }

    private static func resolveLeadArm(frames: [SwingFrameSample]) -> LeadArmSide {
        var leftScore = 0.0
        var rightScore = 0.0
        var ballSideBalance = 0
        for frame in frames {
            guard let pose = frame.pose else { continue }
            leftScore += armScore(shoulder: pose.leftShoulder, elbow: pose.leftElbow, wrist: pose.leftWrist)
            rightScore += armScore(shoulder: pose.rightShoulder, elbow: pose.rightElbow, wrist: pose.rightWrist)
            if let ball = frame.objectEvidence.stableBall,
               let hips = SwingGeometry.center(pose.leftHip, pose.rightHip) {
                if ball.x < hips.x {
                    leftScore += 2
                    ballSideBalance += 1
                } else {
                    rightScore += 2
                    ballSideBalance -= 1
                }
            }
        }

        // Visibility alone is not handedness evidence: the trailing arm is
        // frequently clearer through impact and follow-through. Prefer the arm
        // that produces a sustained, long shoulder-to-wrist horizontal crossing,
        // which is the defining observation for P3/P5.
        let leftParallel = parallelReachEvidence(for: .left, frames: frames)
        let rightParallel = parallelReachEvidence(for: .right, frames: frames)
        switch (leftParallel.onsetTime, rightParallel.onsetTime) {
        case let (.some(leftTime), .some(rightTime))
            where abs(leftTime - rightTime) >= 0.05:
            return leftTime < rightTime ? .left : .right
        case (.some, .none):
            return .left
        case (.none, .some):
            return .right
        default:
            break
        }
        let parallelSeparation = abs(leftParallel.score - rightParallel.score)
        if max(leftParallel.score, rightParallel.score) >= 0.055,
           parallelSeparation >= 0.04 {
            return leftParallel.score > rightParallel.score ? .left : .right
        }

        let separation = abs(leftScore - rightScore)
        guard separation >= max(2, max(leftScore, rightScore) * 0.03) else {
            if ballSideBalance > 0 { return .left }
            if ballSideBalance < 0 { return .right }
            return .unknown
        }
        return leftScore > rightScore ? .left : .right
    }

    private struct ParallelReachObservation {
        let time: Double
        let score: Double
    }

    private struct ParallelReachResolution {
        let score: Double
        let onsetTime: Double?
    }

    private static func parallelReachEvidence(
        for side: LeadArmSide,
        frames: [SwingFrameSample]
    ) -> ParallelReachResolution {
        let observations = frames.compactMap { frame -> ParallelReachObservation? in
            guard let pose = frame.pose else { return nil }
            let arm = points(for: side, pose: pose)
            guard let shoulder = arm.shoulder,
                  let wrist = arm.wrist,
                  let shoulderCenter = SwingGeometry.center(
                    pose.leftShoulder,
                    pose.rightShoulder
                  ),
                  let hipCenter = SwingGeometry.center(pose.leftHip, pose.rightHip) else {
                return nil
            }
            let torsoScale = SwingGeometry.distance(shoulderCenter, hipCenter)
            guard torsoScale.isFinite, torsoScale > 0.001 else { return nil }
            let angle = SwingGeometry.angleFromHorizontal(from: shoulder, to: wrist)
            let horizontal = max(0, 1 - angle / 30)
            let normalizedReach = SwingGeometry.distance(shoulder, wrist) / torsoScale
            let reach = min(1, max(0, (normalizedReach - 0.35) / 0.55))
            return ParallelReachObservation(
                time: frame.time,
                score: horizontal * reach
            )
        }

        let onsetTime = zip(observations, observations.dropFirst()).first { first, second in
            first.score >= 0.02
                && second.score >= 0.02
                && second.time - first.time <= 0.12
        }?.0.time
        let ranked = observations.map(\.score).sorted(by: >)

        guard let strongest = ranked.first,
              ranked.count > 1,
              ranked[1] >= 0.02 else {
            return ParallelReachResolution(score: 0, onsetTime: onsetTime)
        }
        return ParallelReachResolution(
            score: strongest * 0.65 + ranked[1] * 0.35,
            onsetTime: onsetTime
        )
    }

    private static func armScore(shoulder: CGPoint?, elbow: CGPoint?, wrist: CGPoint?) -> Double {
        guard let shoulder, let elbow, let wrist else { return 0 }
        let armExtension = SwingGeometry.jointAngle(a: shoulder, vertex: elbow, c: wrist)
        let reach = SwingGeometry.distance(shoulder, wrist) * 100
        return max(0, armExtension - 90) + reach
    }

    private static func points(
        for side: LeadArmSide,
        pose: SwingPoseSample?
    ) -> (shoulder: CGPoint?, elbow: CGPoint?, wrist: CGPoint?) {
        guard let pose else { return (nil, nil, nil) }
        switch side {
        case .left:
            return (pose.leftShoulder, pose.leftElbow, pose.leftWrist)
        case .right:
            return (pose.rightShoulder, pose.rightElbow, pose.rightWrist)
        case .unknown:
            // Lead-arm identity is run-wide. Never switch arms frame by frame
            // merely because one side happens to be visible in this frame.
            return (nil, nil, nil)
        }
    }

    private static func lineAngle(_ first: CGPoint?, _ second: CGPoint?) -> Double? {
        guard let first, let second else { return nil }
        return SwingGeometry.lineAngle(from: first, to: second)
    }

    private static func axisAngle(_ first: CGPoint?, _ second: CGPoint?) -> Double? {
        guard var angle = lineAngle(first, second) else { return nil }
        while angle > 90 { angle -= 180 }
        while angle <= -90 { angle += 180 }
        return angle
    }

    private static func angleFromHorizontal(_ first: CGPoint?, _ second: CGPoint?) -> Double? {
        guard let first, let second else { return nil }
        return SwingGeometry.angleFromHorizontal(from: first, to: second)
    }

    private static func jointAngle(_ first: CGPoint?, _ vertex: CGPoint?, _ third: CGPoint?) -> Double? {
        guard let first, let vertex, let third else { return nil }
        return SwingGeometry.jointAngle(a: first, vertex: vertex, c: third)
    }

    private static func poseCoverage(_ sample: SwingPoseSample) -> Double {
        let joints: [CGPoint?] = [
            sample.leftWrist, sample.rightWrist, sample.leftElbow, sample.rightElbow,
            sample.leftShoulder, sample.rightShoulder, sample.leftHip, sample.rightHip,
            sample.leftKnee, sample.rightKnee, sample.leftAnkle, sample.rightAnkle, sample.head
        ]
        return Double(joints.compactMap { $0 }.count) / Double(joints.count)
    }
}

enum SwingStageDetectionStatus: String, Codable, Equatable {
    case confirmed
    case lowConfidence
    case unresolved
}

struct StageCandidate: Equatable {
    let stage: SwingStage
    let evidenceIndex: Int
    let sourceFrameIndex: Int
    let time: Double
    let score: Double
    let requirementsSatisfied: Bool
    let maximumStatus: SwingStageDetectionStatus
    let hasClubEvidence: Bool
    let hasBallEvidence: Bool
    let hasBallChangeEvidence: Bool

    init(
        stage: SwingStage,
        evidenceIndex: Int,
        sourceFrameIndex: Int,
        time: Double,
        score: Double,
        requirementsSatisfied: Bool,
        maximumStatus: SwingStageDetectionStatus,
        hasClubEvidence: Bool,
        hasBallEvidence: Bool,
        hasBallChangeEvidence: Bool = false
    ) {
        self.stage = stage
        self.evidenceIndex = evidenceIndex
        self.sourceFrameIndex = sourceFrameIndex
        self.time = time
        self.score = score
        self.requirementsSatisfied = requirementsSatisfied
        self.maximumStatus = maximumStatus
        self.hasClubEvidence = hasClubEvidence
        self.hasBallEvidence = hasBallEvidence
        self.hasBallChangeEvidence = hasBallChangeEvidence
    }
}

struct ImpactCorridor: Equatable {
    let candidates: [StageCandidate]
}

struct StageCandidateSet: Equatable {
    let impact: StageCandidate
    let candidatesByStage: [SwingStage: [StageCandidate]]

    func candidates(for stage: SwingStage) -> [StageCandidate] {
        candidatesByStage[stage] ?? []
    }
}

enum StableBodyScaleEvidence {
    static func estimate(from poses: [SwingPoseSample]) -> Double? {
        median(poses.compactMap(scale))
    }

    private static func scale(_ pose: SwingPoseSample) -> Double? {
        let shoulderWidth = SwingGeometry.distance(pose.leftShoulder, pose.rightShoulder)
        let hipWidth = SwingGeometry.distance(pose.leftHip, pose.rightHip)
        let torsoLength = SwingGeometry.distance(
            SwingGeometry.center(pose.leftShoulder, pose.rightShoulder),
            SwingGeometry.center(pose.leftHip, pose.rightHip)
        )
        if torsoLength.isFinite, torsoLength > 0.001 {
            return torsoLength
        }
        return median([shoulderWidth, hipWidth].filter {
            $0.isFinite && $0 > 0.001
        })
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

enum TakeawayStageEvidence {
    static func stageScore(
        hand: CGPoint?,
        hip: CGPoint?,
        shoulder: CGPoint?,
        bodyScale: Double?,
        leadArmAngle: Double?,
        leadArmExtension: Double?,
        shoulderTurn: Double?
    ) -> Double {
        guard let hand, let hip, let shoulder, let bodyScale,
              bodyScale.isFinite, bodyScale > 0.001 else { return 0 }
        let lateralOffset = abs(Double(hand.x - hip.x)) / bodyScale
        let shoulderRelativeHeight = Double(hand.y - shoulder.y) / bodyScale
        let lateralProgress = ramp(
            lateralOffset,
            minimum: 0.60,
            maximum: 1.30
        )
        let handHeight = closeness(
            shoulderRelativeHeight,
            target: 0.70,
            tolerance: 0.55
        )
        let armDirection = leadArmAngle.map {
            closeness(abs($0), target: 35, tolerance: 35)
        } ?? 0
        let turnProgress = shoulderTurn.map {
            ramp(abs($0), minimum: 3, maximum: 15)
        } ?? 0
        let armExtension = leadArmExtension.map {
            ramp($0, minimum: 145, maximum: 170)
        } ?? 0

        // P2 is an agreement among body-relative hand position, lead-arm
        // direction/extension, and early shoulder rotation. No single normalized
        // image coordinate can dominate the fallback decision.
        return clamp(
            lateralProgress * 0.15
                + handHeight * 0.25
                + armDirection * 0.30
                + turnProgress * 0.20
                + armExtension * 0.10
        )
    }

    private static func ramp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        guard value.isFinite, maximum > minimum else { return 0 }
        return clamp((value - minimum) / (maximum - minimum))
    }

    private static func closeness(_ value: Double, target: Double, tolerance: Double) -> Double {
        guard value.isFinite, tolerance > 0 else { return 0 }
        return clamp(1 - abs(value - target) / tolerance)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

enum StagePathTieBreakEvidence {
    /// Small, observed-evidence-only tie break. Timestamps and phase position
    /// deliberately do not participate, so tempo variants receive no prior.
    static func score(_ path: [StageCandidate]) -> Double {
        guard path.count == SwingStage.pStages.count else { return 0 }
        let requirementQuality = Double(path.filter(\.requirementsSatisfied).count)
            / Double(path.count)
        let objectQuality = Double(path.filter { $0.hasClubEvidence || $0.hasBallEvidence }.count)
            / Double(path.count)
        return min(0.06, requirementQuality * 0.04 + objectQuality * 0.02)
    }
}

enum ParallelStageEvidence {
    private static let minimumDownswingCandidateScore = 0.25

    static func downswingArmHorizontalEvidence(angle: Double?) -> Double {
        guard let angle, angle.isFinite else { return 0 }
        return clamp(1 - abs(angle) / 30)
    }

    static func shouldRetainDownswingCandidate(score: Double) -> Bool {
        score.isFinite && score >= minimumDownswingCandidateScore
    }

    static func downswingScore(
        armHorizontal: Double,
        armExtension: Double,
        downward: Double,
        hipOpen: Double,
        coverage: Double
    ) -> Double {
        let jointAgreement = min(armHorizontal, armExtension)
        return clamp(
            jointAgreement * 0.55
                + armHorizontal * 0.15
                + downward * 0.15
                + hipOpen * 0.07
                + coverage * 0.08
        )
    }

    static func followThroughScore(
        parallelEvidence: Double,
        armExtension: Double?,
        postImpactRise: Double,
        hipTurn: Double,
        chestTurn: Double,
        hasContinuedTurn: Bool,
        coverage: Double
    ) -> Double {
        // P8 is a narrow horizontal band, not a single noisy angle minimum.
        // Velocity only contributes after it clears the same requirement used
        // to confirm the stage; tiny optical-flow noise cannot win the frame.
        let horizontalBand = ramp(parallelEvidence, minimum: 0.55, maximum: 0.75)
        let geometryAgreement = armExtension.map {
            min(horizontalBand, clamp($0))
        } ?? horizontalBand * 0.65
        let qualifiedRise = postImpactRise >= 0.35 ? postImpactRise : 0
        return clamp(
            geometryAgreement * 0.45
                + qualifiedRise * 0.10
                + hipTurn * 0.12
                + chestTurn * 0.13
                + (hasContinuedTurn ? 0.10 : 0)
                + coverage * 0.10
        )
    }

    private static func ramp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        guard value.isFinite, maximum > minimum else { return 0 }
        return clamp((value - minimum) / (maximum - minimum))
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

enum ImpactCorridorResolver {
    /// Body-only candidates seed the sparse object pass. Front-view swings can
    /// have little projected hip rotation, so provisional low-confidence
    /// frames must survive until shaft and ball evidence can disambiguate P7.
    private static let minimumCandidateScore = 0.30
    private static let maximumCandidateCount = 5

    static func candidates(in timeline: [SwingTemporalFrame]) -> [StageCandidate] {
        var downswingStarted = false
        var followThroughStarted = false
        var candidates: [StageCandidate] = []

        for (evidenceIndex, temporalFrame) in timeline.enumerated() {
            if temporalFrame.sustainedDownswing {
                downswingStarted = true
            }
            if downswingStarted && temporalFrame.sustainedFollowThrough {
                followThroughStarted = true
            }
            guard downswingStarted, !followThroughStarted else { continue }

            let frame = temporalFrame.frame
            let handNearHip = distance(frame.handCenter, frame.hipCenter).map {
                clamp(1 - $0 / 0.24)
            } ?? 0
            let downwardSpeed = ramp(
                Double(frame.handVelocity.y),
                minimum: 0.15,
                maximum: 1.0
            )
            let accelerationMagnitude = hypot(
                Double(frame.handAcceleration.x),
                Double(frame.handAcceleration.y)
            )
            let localAcceleration = ramp(
                accelerationMagnitude,
                minimum: 0.50,
                maximum: 4.0
            )
            let hipOpen = ramp(
                abs(frame.hipAngle ?? 0),
                minimum: 8,
                maximum: 32
            )
            let shaftBallAlignment = shaftBallAlignment(frame.objectEvidence)
            let ballLocalChange = clamp(frame.objectEvidence.ballLocalChange)
            let score = clamp(
                handNearHip * 0.28
                    + downwardSpeed * 0.08
                    + localAcceleration * 0.04
                    + hipOpen * 0.08
                    + shaftBallAlignment * 0.22
                    + ballLocalChange * 0.11
                    + clamp(temporalFrame.shaftAngleContinuity) * 0.06
                    + clamp(frame.poseCoverage) * 0.13
            )
            guard score >= minimumCandidateScore else { continue }

            let objectEvidence = frame.objectEvidence
            let hasDetectedClubhead = objectEvidence.trackedPoints[.clubhead]?.state
                == .detected
            let hasDetectedBall = objectEvidence.ball != nil
                || objectEvidence.stableBall != nil
                || objectEvidence.trackedPoints[.ball]?.state == .detected
            let hasRequiredObjects = (hasDetectedClubhead && hasDetectedBall)
                || ballLocalChange >= 0.55
            candidates.append(StageCandidate(
                stage: .impact,
                evidenceIndex: evidenceIndex,
                sourceFrameIndex: frame.sourceFrameIndex,
                time: frame.time,
                score: score,
                requirementsSatisfied: hasRequiredObjects,
                maximumStatus: hasRequiredObjects ? .confirmed : .lowConfidence,
                hasClubEvidence: objectEvidence.shaft != nil || hasDetectedClubhead,
                hasBallEvidence: hasDetectedBall,
                hasBallChangeEvidence: ballLocalChange >= 0.55
            ))
        }

        return candidates
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.time != $1.time { return $0.time < $1.time }
                return $0.sourceFrameIndex < $1.sourceFrameIndex
            }
            .prefix(maximumCandidateCount)
            .sorted {
                if $0.sourceFrameIndex != $1.sourceFrameIndex {
                    return $0.sourceFrameIndex < $1.sourceFrameIndex
                }
                return $0.time < $1.time
            }
    }

    private static func shaftBallAlignment(_ objectEvidence: SwingObjectEvidence) -> Double {
        guard let shaft = objectEvidence.shaft,
              let stableBall = objectEvidence.stableBall else { return 0 }
        let alignment = 1 - min(
            1,
            shaft.distanceFromExtendedLine(to: stableBall) / 0.08
        )
        return clamp(alignment * shaft.confidence)
    }

    private static func distance(_ first: CGPoint?, _ second: CGPoint?) -> Double? {
        guard let first, let second else { return nil }
        let distance = SwingGeometry.distance(first, second)
        return distance.isFinite ? distance : nil
    }

    private static func ramp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        guard value.isFinite, maximum > minimum else { return 0 }
        return clamp((value - minimum) / (maximum - minimum))
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

enum BidirectionalStageCandidateResolver {
    private static let maximumCandidateCount = 5

    static func candidates(
        timeline: [SwingTemporalFrame],
        impact: StageCandidate
    ) -> StageCandidateSet {
        resolvedCandidates(
            timeline: timeline,
            impact: impact,
            includesProvisionalDeliveryShaft: false
        )
    }

    /// Provides pose-only P6 neighborhoods for the sparse object pass. These
    /// candidates are never used by the final constrained solver: they are
    /// explicitly low-confidence and exist only so the detector can look for
    /// the shaft evidence that final P6 resolution requires.
    static func objectSamplingCandidates(
        timeline: [SwingTemporalFrame],
        impact: StageCandidate
    ) -> StageCandidateSet {
        resolvedCandidates(
            timeline: timeline,
            impact: impact,
            includesProvisionalDeliveryShaft: true
        )
    }

    private static func resolvedCandidates(
        timeline: [SwingTemporalFrame],
        impact: StageCandidate,
        includesProvisionalDeliveryShaft: Bool
    ) -> StageCandidateSet {
        guard impact.stage == .impact,
              timeline.indices.contains(impact.evidenceIndex),
              timeline[impact.evidenceIndex].frame.sourceFrameIndex == impact.sourceFrameIndex else {
            return StageCandidateSet(
                impact: impact,
                candidatesByStage: [.impact: [impact]]
            )
        }

        let p5 = descendingCandidates(
            before: impact.evidenceIndex,
            timeline: timeline
        )
        let p4 = topPlateauEndCandidates(before: p5, timeline: timeline)
        let p3 = ascendingParallelCandidates(before: p4, timeline: timeline)
        let p2 = takeawayShaftCandidates(before: p3, timeline: timeline)
        let p1 = addressBoundaryCandidates(before: p2, timeline: timeline)
        let p6 = deliveryShaftCandidates(
            before: impact.evidenceIndex,
            timeline: timeline
        )
        let provisionalP6 = provisionalDeliveryShaftCandidates(
            before: impact.evidenceIndex,
            timeline: timeline
        )
        let p6ForThisPass: [StageCandidate]
        if p6.isEmpty {
            p6ForThisPass = includesProvisionalDeliveryShaft
                ? provisionalP6
                : unresolvedCandidates(provisionalP6)
        } else {
            p6ForThisPass = p6
        }
        let detectedP8 = followThroughCandidates(
            after: impact.evidenceIndex,
            impact: impact,
            timeline: timeline
        )
        let p8 = detectedP8.isEmpty
            ? unresolvedCandidates(provisionalFollowThroughCandidates(
                after: impact.evidenceIndex,
                timeline: timeline
            ))
            : detectedP8

        return StageCandidateSet(
            impact: impact,
            candidatesByStage: [
                .address: p1,
                .takeaway: p2,
                .leadArmParallelBackswing: p3,
                .top: p4,
                .leadArmParallelDownswing: p5,
                .shaftParallelDownswing: p6ForThisPass,
                .impact: [impact],
                .followThrough: p8
            ]
        )
    }

    private static func descendingCandidates(
        before upperBound: Int,
        timeline: [SwingTemporalFrame]
    ) -> [StageCandidate] {
        guard upperBound > timeline.startIndex else { return [] }
        return retainedCandidates(
            (timeline.startIndex..<upperBound).compactMap { index in
                let temporal = timeline[index]
                let frame = temporal.frame
                guard temporal.sustainedDownswing,
                      frame.leadArmAngle != nil else { return nil }
                let armHorizontal = ParallelStageEvidence.downswingArmHorizontalEvidence(
                    angle: frame.leadArmAngle
                )
                let armExtended = ramp(
                    frame.leadArmExtension,
                    minimum: 145,
                    maximum: 175
                )
                let downward = ramp(
                    Double(frame.handVelocity.y),
                    minimum: 0.15,
                    maximum: 1
                )
                let hipOpen = ramp(
                    abs(frame.hipAngle ?? 0),
                    minimum: 8,
                    maximum: 32
                )
                let requirements = armHorizontal >= 0.55
                    && armExtended >= 0.55
                    && downward >= 0.35
                    && abs(frame.hipAngle ?? 0) >= 8
                let score = ParallelStageEvidence.downswingScore(
                    armHorizontal: armHorizontal,
                    armExtension: armExtended,
                    downward: downward,
                    hipOpen: hipOpen,
                    coverage: frame.poseCoverage
                )
                guard ParallelStageEvidence.shouldRetainDownswingCandidate(
                    score: score
                ) else { return nil }
                return candidate(
                    stage: .leadArmParallelDownswing,
                    index: index,
                    score: score,
                    requirementsSatisfied: requirements,
                    timeline: timeline
                )
            }
        )
    }

    private static func topPlateauEndCandidates(
        before laterCandidates: [StageCandidate],
        timeline: [SwingTemporalFrame]
    ) -> [StageCandidate] {
        guard let upperBound = laterCandidates.map(\.evidenceIndex).max(),
              upperBound > timeline.startIndex else { return [] }
        return retainedCandidates(
            (timeline.startIndex..<upperBound).compactMap { index in
                let temporal = timeline[index]
                guard temporal.isTopPlateauEnd else { return nil }
                let frame = temporal.frame
                let shoulderTurn = ramp(
                    abs(frame.shoulderAngle ?? 0),
                    minimum: 5,
                    maximum: 28
                )
                let highHands = highHandsScore(frame)
                let requirements = temporal.sustainedDownswing
                let score = clamp(
                    0.42
                        + (temporal.sustainedDownswing ? 0.20 : 0)
                        + highHands * 0.14
                        + shoulderTurn * 0.14
                        + frame.poseCoverage * 0.10
                )
                return candidate(
                    stage: .top,
                    index: index,
                    score: score,
                    requirementsSatisfied: requirements,
                    timeline: timeline
                )
            },
            preferLaterSourceFrame: true
        )
    }

    private static func ascendingParallelCandidates(
        before laterCandidates: [StageCandidate],
        timeline: [SwingTemporalFrame]
    ) -> [StageCandidate] {
        guard let upperBound = laterCandidates.map(\.evidenceIndex).max(),
              upperBound > timeline.startIndex else { return [] }
        return retainedCandidates(
            (timeline.startIndex..<upperBound).compactMap { index in
                let temporal = timeline[index]
                let frame = temporal.frame
                guard temporal.sustainedBackswing,
                      frame.leadArmAngle != nil else { return nil }
                let armHorizontal = closeness(
                    frame.leadArmAngle,
                    target: 0,
                    tolerance: 18
                )
                let armExtended = ramp(
                    frame.leadArmExtension,
                    minimum: 145,
                    maximum: 175
                )
                let shoulderTurn = ramp(
                    abs(frame.shoulderAngle ?? 0),
                    minimum: 5,
                    maximum: 28
                )
                let increasingTurn = shoulderTurnIsIncreasing(at: index, timeline: timeline)
                let requirements = armHorizontal >= 0.55
                    && armExtended >= 0.55
                    && increasingTurn
                let score = clamp(
                    armHorizontal * 0.40
                        + armExtended * 0.20
                        + shoulderTurn * 0.16
                        + (increasingTurn ? 0.14 : 0)
                        + frame.poseCoverage * 0.10
                )
                guard score >= 0.32 else { return nil }
                return candidate(
                    stage: .leadArmParallelBackswing,
                    index: index,
                    score: score,
                    requirementsSatisfied: requirements,
                    timeline: timeline
                )
            }
        )
    }

    private static func takeawayShaftCandidates(
        before laterCandidates: [StageCandidate],
        timeline: [SwingTemporalFrame]
    ) -> [StageCandidate] {
        guard let upperBound = laterCandidates.map(\.evidenceIndex).max(),
              upperBound > timeline.startIndex else { return [] }
        let bodyScale = StableBodyScaleEvidence.estimate(
            from: timeline.compactMap(\.frame.pose)
        )
        return retainedCandidates(
            (timeline.startIndex..<upperBound).compactMap { index in
                let temporal = timeline[index]
                let frame = temporal.frame
                guard temporal.sustainedBackswing else { return nil }
                let shaftHorizontal = frame.objectEvidence.shaft.map { shaft in
                    closeness(
                        horizontalAngle(shaft.angle),
                        target: 0,
                        tolerance: 18
                    ) * clamp(shaft.confidence)
                }
                if let shaftHorizontal, shaftHorizontal < 0.20 { return nil }
                let handsBelowShoulders = handsBelowShouldersScore(frame)
                let shoulderCenter = frame.pose.flatMap {
                    SwingGeometry.center($0.leftShoulder, $0.rightShoulder)
                }
                let stageEvidence = TakeawayStageEvidence.stageScore(
                    hand: frame.handCenter,
                    hip: frame.hipCenter,
                    shoulder: shoulderCenter,
                    bodyScale: bodyScale,
                    leadArmAngle: frame.leadArmAngle,
                    leadArmExtension: frame.leadArmExtension,
                    shoulderTurn: frame.shoulderAngle
                )
                guard shaftHorizontal != nil || stageEvidence >= 0.20 else { return nil }
                let backswingSpeed = ramp(
                    -Double(frame.handVelocity.y),
                    minimum: 0.12,
                    maximum: 0.80
                )
                let requirements = (shaftHorizontal ?? 0) >= 0.55
                    && handsBelowShoulders == 1
                let score: Double
                if let shaftHorizontal {
                    score = clamp(
                        shaftHorizontal * 0.35
                            + handsBelowShoulders * 0.10
                            + backswingSpeed * 0.10
                            + stageEvidence * 0.30
                            + frame.poseCoverage * 0.15
                    )
                } else {
                    score = clamp(
                        handsBelowShoulders * 0.15
                            + backswingSpeed * 0.15
                            + stageEvidence * 0.50
                            + frame.poseCoverage * 0.20
                    )
                }
                return candidate(
                    stage: .takeaway,
                    index: index,
                    score: score,
                    requirementsSatisfied: requirements,
                    timeline: timeline
                )
            }
        )
    }

    private static func addressBoundaryCandidates(
        before laterCandidates: [StageCandidate],
        timeline: [SwingTemporalFrame]
    ) -> [StageCandidate] {
        guard let upperBound = laterCandidates.map(\.evidenceIndex).max(),
              upperBound > timeline.startIndex else { return [] }
        return retainedCandidates(
            (timeline.startIndex..<upperBound).compactMap { index in
                let temporal = timeline[index]
                guard temporal.isAddressBoundary else { return nil }
                let frame = temporal.frame
                let bodyStable = clamp(
                    1 - (frame.headSpeed + frame.hipSpeed) / 0.16
                )
                let handsStable = clamp(
                    1 - hypot(
                        Double(frame.handVelocity.x),
                        Double(frame.handVelocity.y)
                    ) / 0.30
                )
                let requirements = temporal.sustainedBackswing
                let score = clamp(
                    0.42
                        + (temporal.sustainedBackswing ? 0.22 : 0)
                        + bodyStable * 0.14
                        + handsStable * 0.12
                        + frame.poseCoverage * 0.10
                )
                return candidate(
                    stage: .address,
                    index: index,
                    score: score,
                    requirementsSatisfied: requirements,
                    timeline: timeline
                )
            }
        )
    }

    /// P6 is a delivery position: it requires a trustworthy, horizontal shaft
    /// observation while the hands are still travelling down toward impact.
    /// Pose-only evidence must never substitute for this club-defined stage.
    private static func deliveryShaftCandidates(
        before upperBound: Int,
        timeline: [SwingTemporalFrame]
    ) -> [StageCandidate] {
        guard upperBound > timeline.startIndex else { return [] }
        return retainedCandidates(
            (timeline.startIndex..<upperBound).compactMap { index in
                let temporal = timeline[index]
                let frame = temporal.frame
                guard temporal.sustainedDownswing,
                      let shaftHorizontal = reliableHorizontalShaftEvidence(frame) else {
                    return nil
                }
                let handsNearHip: Double
                if let hand = frame.handCenter, let hip = frame.hipCenter {
                    let distance = SwingGeometry.distance(hand, hip)
                    handsNearHip = distance.isFinite
                        ? clamp(1 - distance / 0.30)
                        : 0
                } else {
                    handsNearHip = 0
                }
                let downward = ramp(
                    Double(frame.handVelocity.y),
                    minimum: 0.15,
                    maximum: 1
                )
                let hipOpen = ramp(
                    abs(frame.hipAngle ?? 0),
                    minimum: 8,
                    maximum: 32
                )
                let requirements = shaftHorizontal >= 0.55
                    && handsNearHip >= 0.40
                    && downward >= 0.35
                let score = clamp(
                    shaftHorizontal * 0.48
                        + handsNearHip * 0.20
                        + downward * 0.16
                        + hipOpen * 0.06
                        + frame.poseCoverage * 0.10
                )
                guard score >= 0.32 else { return nil }
                return candidate(
                    stage: .shaftParallelDownswing,
                    index: index,
                    score: score,
                    requirementsSatisfied: requirements,
                    timeline: timeline
                )
            }
        )
    }

    private static func provisionalDeliveryShaftCandidates(
        before upperBound: Int,
        timeline: [SwingTemporalFrame]
    ) -> [StageCandidate] {
        guard upperBound > timeline.startIndex else { return [] }
        return retainedCandidates(
            (timeline.startIndex..<upperBound).compactMap { index in
                let temporal = timeline[index]
                let frame = temporal.frame
                guard temporal.sustainedDownswing else { return nil }
                let handsNearHip: Double
                if let hand = frame.handCenter, let hip = frame.hipCenter {
                    let distance = SwingGeometry.distance(hand, hip)
                    handsNearHip = distance.isFinite
                        ? clamp(1 - distance / 0.30)
                        : 0
                } else {
                    handsNearHip = 0
                }
                let downward = ramp(
                    Double(frame.handVelocity.y),
                    minimum: 0.15,
                    maximum: 1
                )
                let hipOpen = ramp(
                    abs(frame.hipAngle ?? 0),
                    minimum: 8,
                    maximum: 32
                )
                guard handsNearHip >= 0.25, downward >= 0.25 else { return nil }
                let score = clamp(
                    handsNearHip * 0.42
                        + downward * 0.30
                        + hipOpen * 0.10
                        + frame.poseCoverage * 0.18
                )
                guard score >= 0.32 else { return nil }
                let provisional = candidate(
                    stage: .shaftParallelDownswing,
                    index: index,
                    score: score,
                    requirementsSatisfied: false,
                    timeline: timeline
                )
                return StageCandidate(
                    stage: provisional.stage,
                    evidenceIndex: provisional.evidenceIndex,
                    sourceFrameIndex: provisional.sourceFrameIndex,
                    time: provisional.time,
                    score: provisional.score,
                    requirementsSatisfied: false,
                    maximumStatus: .lowConfidence,
                    hasClubEvidence: false,
                    hasBallEvidence: false
                )
            }
        )
    }

    private static func followThroughCandidates(
        after lowerBound: Int,
        impact: StageCandidate,
        timeline: [SwingTemporalFrame]
    ) -> [StageCandidate] {
        guard lowerBound < timeline.index(before: timeline.endIndex) else { return [] }
        let impactFrame = timeline[lowerBound].frame
        let hipDirection = signedRotationDirection(
            endingAt: lowerBound,
            angle: \SwingFrameEvidence.hipAngle,
            timeline: timeline
        )
        let chestDirection = signedRotationDirection(
            endingAt: lowerBound,
            angle: \SwingFrameEvidence.shoulderAngle,
            timeline: timeline
        )
        return retainedCandidates(
            ((lowerBound + 1)..<timeline.endIndex).compactMap { index in
                let temporal = timeline[index]
                let frame = temporal.frame
                guard temporal.sustainedFollowThrough,
                      let shaftHorizontal = reliableHorizontalShaftEvidence(frame) else {
                    return nil
                }
                let armHorizontal = closeness(
                    frame.leadArmAngle,
                    target: 0,
                    tolerance: 18
                )
                // P8's shaft is defining evidence. The lead arm can increase
                // confidence but must not create a release frame by itself.
                let parallelEvidence = shaftHorizontal
                let armExtension = frame.leadArmExtension.map {
                    ramp($0, minimum: 145, maximum: 175)
                }
                let postImpactRise = ramp(
                    -Double(frame.handVelocity.y),
                    minimum: 0.15,
                    maximum: 1
                )
                let hipContinuation = signedRotationProgress(
                    from: impactFrame.hipAngle,
                    to: frame.hipAngle,
                    direction: hipDirection
                )
                let chestContinuation = signedRotationProgress(
                    from: impactFrame.shoulderAngle,
                    to: frame.shoulderAngle,
                    direction: chestDirection
                )
                let continuedHipTurn = hipContinuation.map { $0 >= 0.5 } ?? false
                let continuedChestTurn = chestContinuation.map { $0 >= 0.5 } ?? false
                let requirements = postImpactRise >= 0.35
                    && parallelEvidence >= 0.55
                    && (armExtension ?? 0) >= 0.55
                    && continuedHipTurn
                    && continuedChestTurn
                let hipTurnScore = ramp(hipContinuation, minimum: 0, maximum: 10)
                let chestTurnScore = ramp(chestContinuation, minimum: 0, maximum: 12)
                let score = clamp(ParallelStageEvidence.followThroughScore(
                    parallelEvidence: parallelEvidence,
                    armExtension: armExtension,
                    postImpactRise: postImpactRise,
                    hipTurn: hipTurnScore,
                    chestTurn: chestTurnScore,
                    hasContinuedTurn: continuedHipTurn && continuedChestTurn,
                    coverage: frame.poseCoverage
                ) + armHorizontal * 0.06)
                guard score >= 0.32 else { return nil }
                return candidate(
                    stage: .followThrough,
                    index: index,
                    score: score,
                    requirementsSatisfied: requirements,
                    timeline: timeline
                )
            }
        )
    }

    private static func provisionalFollowThroughCandidates(
        after lowerBound: Int,
        timeline: [SwingTemporalFrame]
    ) -> [StageCandidate] {
        guard lowerBound < timeline.index(before: timeline.endIndex) else { return [] }
        return retainedCandidates(
            ((lowerBound + 1)..<timeline.endIndex).compactMap { index in
                let temporal = timeline[index]
                let frame = temporal.frame
                guard temporal.sustainedFollowThrough else { return nil }
                let armHorizontal = closeness(
                    frame.leadArmAngle,
                    target: 0,
                    tolerance: 18
                )
                let postImpactRise = ramp(
                    -Double(frame.handVelocity.y),
                    minimum: 0.15,
                    maximum: 1
                )
                let score = clamp(
                    armHorizontal * 0.36
                        + postImpactRise * 0.34
                        + frame.poseCoverage * 0.30
                )
                guard score >= 0.32 else { return nil }
                return candidate(
                    stage: .followThrough,
                    index: index,
                    score: score,
                    requirementsSatisfied: false,
                    timeline: timeline
                )
            }
        )
    }

    private static func unresolvedCandidates(
        _ candidates: [StageCandidate]
    ) -> [StageCandidate] {
        candidates.map {
            StageCandidate(
                stage: $0.stage,
                evidenceIndex: $0.evidenceIndex,
                sourceFrameIndex: $0.sourceFrameIndex,
                time: $0.time,
                score: $0.score,
                requirementsSatisfied: false,
                maximumStatus: .unresolved,
                hasClubEvidence: $0.hasClubEvidence,
                hasBallEvidence: $0.hasBallEvidence,
                hasBallChangeEvidence: $0.hasBallChangeEvidence
            )
        }
    }

    private static func reliableHorizontalShaftEvidence(
        _ frame: SwingFrameEvidence
    ) -> Double? {
        guard let shaft = frame.objectEvidence.shaft,
              shaft.confidence.isFinite,
              shaft.confidence >= 0.70,
              shaft.length.isFinite,
              shaft.length >= 0.04 else {
            return nil
        }
        let horizontal = closeness(
            horizontalAngle(shaft.angle),
            target: 0,
            tolerance: 18
        ) * clamp(shaft.confidence)
        return horizontal >= 0.55 ? horizontal : nil
    }

    private static func retainedCandidates(
        _ candidates: [StageCandidate],
        preferLaterSourceFrame: Bool = false
    ) -> [StageCandidate] {
        Array(candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.sourceFrameIndex != $1.sourceFrameIndex {
                return preferLaterSourceFrame
                    ? $0.sourceFrameIndex > $1.sourceFrameIndex
                    : $0.sourceFrameIndex < $1.sourceFrameIndex
            }
            return preferLaterSourceFrame ? $0.time > $1.time : $0.time < $1.time
        }.prefix(maximumCandidateCount))
    }

    private static func candidate(
        stage: SwingStage,
        index: Int,
        score: Double,
        requirementsSatisfied: Bool,
        timeline: [SwingTemporalFrame]
    ) -> StageCandidate {
        let frame = timeline[index].frame
        let armDefinedStage: Bool
        switch stage {
        case .leadArmParallelBackswing, .leadArmParallelDownswing, .followThrough:
            armDefinedStage = true
        default:
            armDefinedStage = false
        }
        let armEvidenceLimited = armDefinedStage && (
            timeline[index].qualityFlags.contains(.missingLeadArm)
                || timeline[index].qualityFlags.contains(.labelSwapSuspected)
        )
        let verifiedRequirements = requirementsSatisfied && !armEvidenceLimited
        return StageCandidate(
            stage: stage,
            evidenceIndex: index,
            sourceFrameIndex: frame.sourceFrameIndex,
            time: frame.time,
            score: clamp(score),
            requirementsSatisfied: verifiedRequirements,
            maximumStatus: verifiedRequirements ? .confirmed : .lowConfidence,
            hasClubEvidence: frame.objectEvidence.shaft != nil,
            hasBallEvidence: frame.objectEvidence.ball != nil
                || frame.objectEvidence.stableBall != nil
        )
    }

    private static func shoulderTurnIsIncreasing(
        at index: Int,
        timeline: [SwingTemporalFrame]
    ) -> Bool {
        guard index > timeline.startIndex,
              let current = timeline[index].frame.shoulderAngle,
              let previous = timeline[index - 1].frame.shoulderAngle else { return false }
        return abs(current) + 0.5 >= abs(previous)
    }

    private static func signedRotationDirection(
        endingAt index: Int,
        angle: KeyPath<SwingFrameEvidence, Double?>,
        timeline: [SwingTemporalFrame]
    ) -> Double? {
        guard timeline.indices.contains(index),
              let current = timeline[index].frame[keyPath: angle] else { return nil }
        let currentTime = timeline[index].frame.time
        var earliest: Double?
        var priorIndex = index - 1
        while timeline.indices.contains(priorIndex),
              currentTime - timeline[priorIndex].frame.time
                <= SwingEvidenceTimeline.directionWindow + 0.000_000_001 {
            earliest = timeline[priorIndex].frame[keyPath: angle] ?? earliest
            priorIndex -= 1
        }
        guard let earliest else { return nil }
        let change = current - earliest
        guard abs(change) >= 0.5 else { return nil }
        return change > 0 ? 1 : -1
    }

    private static func signedRotationProgress(
        from start: Double?,
        to end: Double?,
        direction: Double?
    ) -> Double? {
        guard let start, let end, let direction else { return nil }
        return (end - start) * direction
    }

    private static func highHandsScore(_ frame: SwingFrameEvidence) -> Double {
        guard let handY = frame.handCenter?.y,
              let shoulderY = SwingGeometry.center(
                  frame.pose?.leftShoulder,
                  frame.pose?.rightShoulder
              )?.y else { return 0 }
        return handY < shoulderY ? 1 : 0
    }

    private static func handsBelowShouldersScore(_ frame: SwingFrameEvidence) -> Double {
        guard let handY = frame.handCenter?.y,
              let shoulderY = SwingGeometry.center(
                  frame.pose?.leftShoulder,
                  frame.pose?.rightShoulder
              )?.y else { return 0 }
        return handY > shoulderY ? 1 : 0
    }

    private static func horizontalAngle(_ angle: Double) -> Double {
        let normalized = abs(angle).truncatingRemainder(dividingBy: 180)
        return min(normalized, 180 - normalized)
    }

    private static func closeness(
        _ value: Double?,
        target: Double,
        tolerance: Double
    ) -> Double {
        guard let value, tolerance > 0 else { return 0 }
        return clamp(1 - abs(value - target) / tolerance)
    }

    private static func ramp(
        _ value: Double?,
        minimum: Double,
        maximum: Double
    ) -> Double {
        guard let value, value.isFinite, maximum > minimum else { return 0 }
        return clamp((value - minimum) / (maximum - minimum))
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

struct SwingStageDetection: Equatable {
    let stage: SwingStage
    let time: Double?
    let sourceFrameIndex: Int?
    let confidence: Double
    let status: SwingStageDetectionStatus
    let hasClubEvidence: Bool
    let hasBallEvidence: Bool
    let hasBallChangeEvidence: Bool
    let evidence: StageEvidenceSummary

    init(
        stage: SwingStage,
        time: Double?,
        sourceFrameIndex: Int? = nil,
        confidence: Double,
        status: SwingStageDetectionStatus,
        hasClubEvidence: Bool = false,
        hasBallEvidence: Bool = false,
        hasBallChangeEvidence: Bool = false,
        evidence: StageEvidenceSummary = .empty
    ) {
        self.stage = stage
        self.time = time
        self.sourceFrameIndex = sourceFrameIndex
        self.confidence = confidence
        self.status = status
        self.hasClubEvidence = hasClubEvidence
        self.hasBallEvidence = hasBallEvidence
        self.hasBallChangeEvidence = hasBallChangeEvidence
        self.evidence = evidence
    }

    var marker: KeyframeMarker? {
        guard let time, status != .unresolved else { return nil }
        return KeyframeMarker(time: time, stage: stage, source: .automatic)
    }
}

enum StageEvidenceSource: String, Codable, Hashable {
    case bodyPose
    case grip
    case shaft
    case clubhead
    case ball
    case temporalTransition
    case manual
}

struct StageEvidenceSummary: Codable, Equatable {
    let sources: Set<StageEvidenceSource>
    let detectedPointCount: Int
    let estimatedPointCount: Int

    static let empty = StageEvidenceSummary(
        sources: [],
        detectedPointCount: 0,
        estimatedPointCount: 0
    )

    static func make(
        frame: SwingFrameEvidence,
        candidate: StageCandidate
    ) -> StageEvidenceSummary {
        let points = frame.objectEvidence.trackedPoints
        var sources: Set<StageEvidenceSource> = [.temporalTransition]
        if frame.pose != nil { sources.insert(.bodyPose) }
        if points[.grip]?.state == .detected { sources.insert(.grip) }
        if frame.objectEvidence.shaft != nil { sources.insert(.shaft) }
        if points[.clubhead]?.state == .detected { sources.insert(.clubhead) }
        if frame.objectEvidence.ball != nil
            || frame.objectEvidence.stableBall != nil
            || points[.ball]?.state == .detected {
            sources.insert(.ball)
        }
        if points.values.contains(where: { $0.source == .manual }) {
            sources.insert(.manual)
        }
        if candidate.hasBallChangeEvidence {
            sources.insert(.ball)
        }
        return StageEvidenceSummary(
            sources: sources,
            detectedPointCount: points.values.filter { $0.state == .detected }.count,
            estimatedPointCount: points.values.filter { $0.state == .estimated }.count
        )
    }
}

struct SwingAnalysisResult: Equatable {
    let detectedMarkers: [KeyframeMarker]
    let unresolvedStages: Set<SwingStage>
    let detections: [SwingStageDetection]

    init(
        detectedMarkers: [KeyframeMarker],
        unresolvedStages: Set<SwingStage>,
        detections: [SwingStageDetection] = []
    ) {
        self.detectedMarkers = detectedMarkers
        self.unresolvedStages = unresolvedStages
        self.detections = detections
    }
}

enum ConstrainedSwingPathSolver {
    private struct ScoredPath {
        let candidates: [StageCandidate]
        let total: Double
    }

    static func solve(
        candidateSets: [StageCandidateSet],
        timeline: [SwingTemporalFrame]
    ) -> SwingAnalysisResult {
        guard !timeline.isEmpty else { return unresolvedResult() }

        var best: ScoredPath?
        var secondBest: ScoredPath?
        for candidateSet in candidateSets {
            guard hasConsistentImpactAnchor(candidateSet, timeline: timeline) else {
                continue
            }
            enumeratePaths(in: candidateSet, timeline: timeline) { path in
                guard isLegalCompletePath(path, timeline: timeline) else { return }
                let evidenceScore = path.reduce(0.0) { $0 + $1.score }
                let missingPenalty = Double(
                    path.filter { !$0.requirementsSatisfied }.count
                ) * 0.35
                let transitionScore = directionTransitionScore(
                    path: path,
                    timeline: timeline
                )
                let stageTransitionScore = StagePathTieBreakEvidence.score(path)
                let scored = ScoredPath(
                    candidates: path,
                    total: evidenceScore + transitionScore + stageTransitionScore
                        - missingPenalty
                )
                if isBetter(scored, than: best) {
                    secondBest = best
                    best = scored
                } else if isBetter(scored, than: secondBest) {
                    secondBest = scored
                }
            }
        }

        guard let best else { return unresolvedResult() }
        let pathMargin = max(0, best.total - (secondBest?.total ?? best.total))
        let detections = zip(SwingStage.pStages, best.candidates).map {
            stage, candidate -> SwingStageDetection in
            guard timeline.indices.contains(candidate.evidenceIndex) else {
                return unresolvedDetection(stage: stage)
            }
            let frame = timeline[candidate.evidenceIndex].frame
            var confidence = clamp(
                candidate.score * 0.70
                    + frame.poseCoverage * 0.20
                    + min(0.10, pathMargin)
            )
            var status: SwingStageDetectionStatus
            switch candidate.maximumStatus {
            case .unresolved:
                confidence = 0
                status = .unresolved
            case .lowConfidence:
                confidence = min(confidence, 0.69)
                status = .lowConfidence
            case .confirmed:
                status = confidence >= 0.72 ? .confirmed : .lowConfidence
            }
            let evidence = StageEvidenceSummary.make(
                frame: frame,
                candidate: candidate
            )
            if !hasCanonicalEvidence(
                for: stage,
                summary: evidence,
                candidate: candidate
            ) {
                confidence = 0
                status = .unresolved
            }
            return SwingStageDetection(
                stage: stage,
                time: status == .unresolved ? nil : candidate.time,
                sourceFrameIndex: status == .unresolved
                    ? nil
                    : candidate.sourceFrameIndex,
                confidence: confidence,
                status: status,
                hasClubEvidence: candidate.hasClubEvidence,
                hasBallEvidence: candidate.hasBallEvidence,
                hasBallChangeEvidence: candidate.hasBallChangeEvidence,
                evidence: evidence
            )
        }
        let unresolved = Set(
            detections.filter { $0.status == .unresolved }.map(\.stage)
        )
        return SwingAnalysisResult(
            detectedMarkers: detections.compactMap(\.marker),
            unresolvedStages: unresolved,
            detections: detections
        )
    }

    private static func enumeratePaths(
        in candidateSet: StageCandidateSet,
        timeline: [SwingTemporalFrame],
        visit: ([StageCandidate]) -> Void
    ) {
        let stages = SwingStage.pStages
        func append(stageIndex: Int, path: [StageCandidate]) {
            guard stageIndex < stages.count else {
                visit(path)
                return
            }
            let stage = stages[stageIndex]
            for candidate in candidateSet.candidates(for: stage) {
                guard candidate.stage == stage,
                      directionMatches(
                          candidate: candidate,
                          stage: stage,
                          timeline: timeline
                      ) else { continue }
                if let previous = path.last {
                    guard previous.sourceFrameIndex < candidate.sourceFrameIndex,
                          previous.time < candidate.time else { continue }
                }
                append(stageIndex: stageIndex + 1, path: path + [candidate])
            }
        }
        append(stageIndex: 0, path: [])
    }

    private static func hasConsistentImpactAnchor(
        _ candidateSet: StageCandidateSet,
        timeline: [SwingTemporalFrame]
    ) -> Bool {
        let declared = candidateSet.impact
        let impactCandidates = candidateSet.candidatesByStage[.impact] ?? []
        guard declared.stage == .impact,
              impactCandidates == [declared],
              timeline.indices.contains(declared.evidenceIndex) else { return false }
        let frame = timeline[declared.evidenceIndex].frame
        return frame.sourceFrameIndex == declared.sourceFrameIndex
            && frame.time == declared.time
    }

    private static func directionMatches(
        candidate: StageCandidate,
        stage: SwingStage,
        timeline: [SwingTemporalFrame]
    ) -> Bool {
        guard timeline.indices.contains(candidate.evidenceIndex) else { return false }
        let temporal = timeline[candidate.evidenceIndex]
        switch stage {
        case .address:
            return temporal.isAddressBoundary
        case .takeaway, .leadArmParallelBackswing:
            return temporal.sustainedBackswing
        case .top:
            return temporal.isTopPlateauEnd && temporal.sustainedDownswing
        case .leadArmParallelDownswing, .shaftParallelDownswing, .impact:
            return temporal.sustainedDownswing
        case .followThrough:
            return temporal.sustainedFollowThrough
        case .finish:
            return temporal.isFinishPlateauStart
        }
    }

    private static func isLegalCompletePath(
        _ path: [StageCandidate],
        timeline: [SwingTemporalFrame]
    ) -> Bool {
        guard path.count == SwingStage.pStages.count,
              zip(path, path.dropFirst()).allSatisfy({
                  $0.sourceFrameIndex < $1.sourceFrameIndex && $0.time < $1.time
              }),
              let first = path.first,
              let last = path.last else { return false }
        let swingDuration = max(0.001, last.time - first.time)
        let normalizedGaps = zip(path, path.dropFirst()).map {
            ($1.time - $0.time) / swingDuration
        }
        guard normalizedGaps.allSatisfy({ (0.01...0.45).contains($0) }) else {
            return false
        }
        return hasRequiredDirectionTransitions(path: path, timeline: timeline)
    }

    private static func hasRequiredDirectionTransitions(
        path: [StageCandidate],
        timeline: [SwingTemporalFrame]
    ) -> Bool {
        guard path.allSatisfy({ timeline.indices.contains($0.evidenceIndex) }) else {
            return false
        }
        let frames = path.map { timeline[$0.evidenceIndex] }
        return frames[0].isAddressBoundary
            && frames[1].sustainedBackswing
            && frames[2].sustainedBackswing
            && frames[3].isTopPlateauEnd
            && frames[3].sustainedDownswing
            && frames[4].sustainedDownswing
            && frames[5].sustainedDownswing
            && frames[6].sustainedDownswing
            && frames[7].sustainedFollowThrough
            && path[7].evidenceIndex > path[6].evidenceIndex
    }

    private static func directionTransitionScore(
        path: [StageCandidate],
        timeline: [SwingTemporalFrame]
    ) -> Double {
        guard hasRequiredDirectionTransitions(path: path, timeline: timeline) else {
            return -Double.greatestFiniteMagnitude
        }
        let backswing = durationWeightedSupport(
            from: path[0].evidenceIndex,
            through: path[2].evidenceIndex,
            timeline: timeline,
            matches: { $0.sustainedBackswing }
        )
        let downswing = durationWeightedSupport(
            from: path[3].evidenceIndex,
            through: path[6].evidenceIndex,
            timeline: timeline,
            matches: { $0.sustainedDownswing }
        )
        let followThrough = durationWeightedSupport(
            from: path[6].evidenceIndex,
            through: path[7].evidenceIndex,
            timeline: timeline,
            matches: { $0.sustainedFollowThrough }
        )
        let topTime = path[3].time
        let topPlateau = elapsedStabilitySupport(
            from: topTime - 0.08,
            through: topTime,
            timeline: timeline
        )
        return backswing * 0.20
            + downswing * 0.30
            + followThrough * 0.20
            + topPlateau * 0.10
    }

    private static func durationWeightedSupport(
        from lowerBound: Int,
        through upperBound: Int,
        timeline: [SwingTemporalFrame],
        matches: (SwingTemporalFrame) -> Bool
    ) -> Double {
        guard timeline.indices.contains(lowerBound),
              timeline.indices.contains(upperBound),
              lowerBound < upperBound else { return 0 }
        let slice = timeline[lowerBound...upperBound]
        let intervals = zip(slice, slice.dropFirst())
        var supportedDuration = 0.0
        for (first, second) in intervals {
            let duration = max(0, second.frame.time - first.frame.time)
            guard duration <= SwingEvidenceTimeline.directionWindow
                    + 0.000_000_001 else { continue }
            let support = (matches(first) ? 0.5 : 0) + (matches(second) ? 0.5 : 0)
            supportedDuration += duration * support
        }
        let elapsed = timeline[upperBound].frame.time - timeline[lowerBound].frame.time
        guard elapsed > 0 else { return 0 }
        return clamp(supportedDuration / elapsed)
    }

    private static func elapsedStabilitySupport(
        from startTime: Double,
        through endTime: Double,
        timeline: [SwingTemporalFrame]
    ) -> Double {
        guard endTime > startTime else { return 0 }
        var observedDuration = 0.0
        var supportedDuration = 0.0
        for (first, second) in zip(timeline, timeline.dropFirst()) {
            guard second.frame.time - first.frame.time
                    <= SwingEvidenceTimeline.directionWindow + 0.000_000_001 else {
                continue
            }
            let intervalStart = max(startTime, first.frame.time)
            let intervalEnd = min(endTime, second.frame.time)
            let duration = intervalEnd - intervalStart
            guard duration > 0 else { continue }
            observedDuration += duration
            let support = (isStable(first) ? 0.5 : 0) + (isStable(second) ? 0.5 : 0)
            supportedDuration += duration * support
        }
        guard observedDuration > 0 else { return 0 }
        return clamp(supportedDuration / (endTime - startTime))
    }

    private static func isStable(_ temporal: SwingTemporalFrame) -> Bool {
        let frame = temporal.frame
        return temporal.direction == .stable
            && frame.handCenter != nil
            && frame.hipCenter != nil
            && frame.pose?.head != nil
            && frame.headSpeed.isFinite
            && frame.hipSpeed.isFinite
            && frame.headSpeed <= SwingEvidenceTimeline.bodyStabilityThreshold
            && frame.hipSpeed <= SwingEvidenceTimeline.bodyStabilityThreshold
            && hypot(Double(frame.handVelocity.x), Double(frame.handVelocity.y)) <= 0.18
    }

    private static func isBetter(
        _ candidate: ScoredPath,
        than incumbent: ScoredPath?
    ) -> Bool {
        guard let incumbent else { return true }
        if candidate.total != incumbent.total {
            return candidate.total > incumbent.total
        }
        return lexicographicallyEarlier(candidate.candidates, incumbent.candidates)
    }

    private static func lexicographicallyEarlier(
        _ first: [StageCandidate],
        _ second: [StageCandidate]
    ) -> Bool {
        for (lhs, rhs) in zip(first, second) where lhs.sourceFrameIndex != rhs.sourceFrameIndex {
            if lhs.stage == .top {
                return lhs.sourceFrameIndex > rhs.sourceFrameIndex
            }
            return lhs.sourceFrameIndex < rhs.sourceFrameIndex
        }
        return false
    }

    private static func unresolvedDetection(stage: SwingStage) -> SwingStageDetection {
        SwingStageDetection(
            stage: stage,
            time: nil,
            confidence: 0,
            status: .unresolved
        )
    }

    private static func hasCanonicalEvidence(
        for stage: SwingStage,
        summary: StageEvidenceSummary,
        candidate: StageCandidate
    ) -> Bool {
        switch stage {
        case .takeaway, .shaftParallelDownswing, .followThrough:
            return summary.sources.contains(.shaft)
        case .impact:
            return candidate.hasBallChangeEvidence
                || summary.sources.isSuperset(of: [.clubhead, .ball])
        default:
            return true
        }
    }

    private static func unresolvedResult() -> SwingAnalysisResult {
        let detections = SwingStage.pStages.map(unresolvedDetection)
        return SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: Set(SwingStage.pStages),
            detections: detections
        )
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

enum AnalysisFailure: Equatable {
    case noVideo
    case invalidDuration
    case insufficientPoseEvidence
    case insufficientStageEvidence
    case noStableGolfer
    case noSwingMotion
    case ambiguousSwingWindows
    case swingWindowTooLong
    case frameExtractionFailed
    case missingAddressBoundary
    case missingTopTransition
    case noImpactCorridor
    case missingPostImpactBoundary
    case incompleteSwingClip
    case unsupportedInput([SwingInputQualityIssue])
    case analysisCancelled
}

enum SwingAnalysisState: Equatable {
    case idle
    case scanning(progress: Double)
    case completed(SwingAnalysisResult)
    case failed(AnalysisFailure)

    var hasCompletedResult: Bool {
        if case .completed = self { return true }
        return false
    }
}

struct AnalysisWorkspacePresentation: Equatable {
    let markers: [KeyframeMarker]
    let unresolvedStages: Set<SwingStage>
    let detections: [SwingStageDetection]
    let allowsPoseOverlays: Bool

    init(state: SwingAnalysisState) {
        guard case let .completed(result) = state else {
            markers = []
            unresolvedStages = Set(SwingStage.pStages)
            detections = []
            allowsPoseOverlays = false
            return
        }
        markers = result.detectedMarkers
        unresolvedStages = result.unresolvedStages
        detections = result.detections
        allowsPoseOverlays = true
    }

    func detection(for stage: SwingStage) -> SwingStageDetection? {
        detections.first { $0.stage == stage }
    }
}

enum OrderedStageSolver {
    private static let minimumResolvedScore = 0.32
    private static let confirmedConfidence = 0.72

    static func solve(evidence rawEvidence: [SwingFrameEvidence]) -> SwingAnalysisResult {
        let evidence = rawEvidence.sorted { $0.time < $1.time }
        guard evidence.count >= SwingStage.pStages.count,
              zip(evidence, evidence.dropFirst()).allSatisfy({ $0.time < $1.time }) else {
            return unresolvedResult()
        }

        let stages = SwingStage.pStages
        let scores = stages.map { stage in
            evidence.indices.map { index in stageScore(stage, index: index, evidence: evidence) }
        }
        let negativeInfinity = -Double.greatestFiniteMagnitude
        var totals = Array(
            repeating: Array(repeating: negativeInfinity, count: evidence.count),
            count: stages.count
        )
        var predecessors = Array(
            repeating: Array(repeating: -1, count: evidence.count),
            count: stages.count
        )

        for index in evidence.indices {
            totals[0][index] = scores[0][index]
        }
        if stages.count > 1 {
            for stageIndex in 1..<stages.count {
                for frameIndex in evidence.indices where frameIndex >= stageIndex {
                    var bestTotal = negativeInfinity
                    var bestPrior = -1
                    for priorIndex in stageIndex..<frameIndex {
                        let priorTotal = totals[stageIndex - 1][priorIndex]
                        guard priorTotal > negativeInfinity / 2 else { continue }
                        let transition = transitionScore(
                            from: evidence[priorIndex],
                            to: evidence[frameIndex]
                        )
                        let total = priorTotal + transition + scores[stageIndex][frameIndex]
                        if total > bestTotal {
                            bestTotal = total
                            bestPrior = priorIndex
                        }
                    }
                    totals[stageIndex][frameIndex] = bestTotal
                    predecessors[stageIndex][frameIndex] = bestPrior
                }
            }
        }

        guard let lastFrame = evidence.indices.max(by: {
            totals[stages.count - 1][$0] < totals[stages.count - 1][$1]
        }), totals[stages.count - 1][lastFrame] > negativeInfinity / 2 else {
            return unresolvedResult()
        }

        var selected = Array(repeating: -1, count: stages.count)
        var cursor = lastFrame
        for stageIndex in stride(from: stages.count - 1, through: 0, by: -1) {
            selected[stageIndex] = cursor
            if stageIndex > 0 {
                cursor = predecessors[stageIndex][cursor]
                guard cursor >= 0 else { return unresolvedResult() }
            }
        }

        let detections = stages.indices.map { stageIndex -> SwingStageDetection in
            let stage = stages[stageIndex]
            let frameIndex = selected[stageIndex]
            let frame = evidence[frameIndex]
            let rawScore = scores[stageIndex][frameIndex]
            let legalStart = stageIndex == 0 ? 0 : selected[stageIndex - 1] + 1
            let legalEnd = stageIndex == stages.count - 1 ? evidence.count : selected[stageIndex + 1]
            let alternate = (legalStart..<legalEnd)
                .filter { $0 != frameIndex }
                .map { scores[stageIndex][$0] }
                .max() ?? 0
            let margin = max(0, rawScore - alternate)
            var confidence = clamp(rawScore * 0.72 + frame.poseCoverage * 0.23 + min(0.05, margin))
            var status: SwingStageDetectionStatus
            if rawScore < minimumResolvedScore {
                status = .unresolved
                confidence = min(confidence, 0.44)
            } else if confidence >= confirmedConfidence {
                status = .confirmed
            } else {
                status = .lowConfidence
            }

            let hasClub = frame.objectEvidence.shaft != nil
            let hasBall = frame.objectEvidence.stableBall != nil
            let hasReliableHorizontalShaft = reliableHorizontalShaftEvidence(frame)
                != nil
            if (stage == .shaftParallelDownswing || stage == .followThrough)
                && !hasReliableHorizontalShaft {
                status = .unresolved
                confidence = 0
            }
            if (stage == .takeaway && !hasClub) ||
                (stage == .impact && !(hasClub && hasBall)) ||
                ((stage == .leadArmParallelBackswing || stage == .leadArmParallelDownswing) && frame.leadArm == .unknown) {
                if status == .confirmed { status = .lowConfidence }
                confidence = min(confidence, 0.69)
            }

            return SwingStageDetection(
                stage: stage,
                time: status == .unresolved ? nil : frame.time,
                sourceFrameIndex: status == .unresolved ? nil : frame.sourceFrameIndex,
                confidence: confidence,
                status: status,
                hasClubEvidence: hasClub,
                hasBallEvidence: hasBall
            )
        }

        let markers = detections.compactMap(\.marker)
        let unresolved = Set(detections.filter { $0.status == .unresolved }.map(\.stage))
        return SwingAnalysisResult(
            detectedMarkers: markers,
            unresolvedStages: unresolved,
            detections: detections
        )
    }

    private static func stageScore(
        _ stage: SwingStage,
        index: Int,
        evidence: [SwingFrameEvidence]
    ) -> Double {
        let frame = evidence[index]
        let coverage = frame.poseCoverage
        let handY = frame.handCenter?.y
        let hipY = frame.hipCenter?.y
        let shoulderY = SwingGeometry.center(frame.pose?.leftShoulder, frame.pose?.rightShoulder)?.y
        let armHorizontal = closeness(frame.leadArmAngle, target: 0, tolerance: 18)
        let armExtended = ramp(frame.leadArmExtension, minimum: 145, maximum: 175)
        let upward = ramp(-Double(frame.handVelocity.y), minimum: 0.15, maximum: 1.0)
        let downward = ramp(Double(frame.handVelocity.y), minimum: 0.15, maximum: 1.0)
        let shoulderTurn = ramp(abs(frame.shoulderAngle ?? 0), minimum: 5, maximum: 28)
        let hipTurn = ramp(abs(frame.hipAngle ?? 0), minimum: 8, maximum: 32)
        let shaftHorizontal = frame.objectEvidence.shaft.map {
            closeness(horizontalAngle($0.angle), target: 0, tolerance: 18) * $0.confidence
        } ?? 0

        switch stage {
        case .address:
            let stable = 1 - min(1, hypot(Double(frame.handVelocity.x), Double(frame.handVelocity.y)) / 0.30)
            let bodyStable = 1 - min(1, (frame.headSpeed + frame.hipSpeed) / 0.16)
            let lowHands = (handY != nil && hipY != nil && handY! >= hipY! + 0.04) ? 1.0 : 0.0
            let nearBall = distance(frame.handCenter, frame.objectEvidence.stableBall).map {
                1 - min(1, $0 / 0.38)
            } ?? 0
            return clamp(stable * 0.25 + bodyStable * 0.20 + lowHands * 0.25 + nearBall * 0.10 + coverage * 0.20)

        case .takeaway:
            let lowerTorso = (handY != nil && shoulderY != nil && handY! > shoulderY!) ? 1.0 : 0.0
            return clamp(upward * 0.27 + shaftHorizontal * 0.33 + lowerTorso * 0.15 + coverage * 0.25)

        case .leadArmParallelBackswing:
            return clamp(armHorizontal * 0.34 + armExtended * 0.20 + upward * 0.23 + shoulderTurn * 0.13 + coverage * 0.10)

        case .top:
            let reversal: Double
            if index + 1 < evidence.count {
                let currentUp = frame.handVelocity.y < -0.10
                let nextDown = evidence[index + 1].handVelocity.y > 0.10
                reversal = currentUp && nextDown ? 1 : 0
            } else {
                reversal = 0
            }
            let highHands = (handY != nil && shoulderY != nil && handY! < shoulderY!) ? 1.0 : 0.0
            return clamp(reversal * 0.38 + highHands * 0.22 + shoulderTurn * 0.22 + coverage * 0.18)

        case .leadArmParallelDownswing:
            return clamp(armHorizontal * 0.34 + armExtended * 0.18 + downward * 0.26 + hipTurn * 0.12 + coverage * 0.10)

        case .shaftParallelDownswing:
            let handNearHip = distance(frame.handCenter, frame.hipCenter).map {
                1 - min(1, $0 / 0.30)
            } ?? 0
            guard reliableHorizontalShaftEvidence(frame) != nil else { return 0 }
            return clamp(
                shaftHorizontal * 0.48
                    + handNearHip * 0.20
                    + downward * 0.16
                    + hipTurn * 0.06
                    + coverage * 0.10
            )

        case .impact:
            let handNearHip = distance(frame.handCenter, frame.hipCenter).map {
                1 - min(1, $0 / 0.24)
            } ?? 0
            let shaftBall = shaftBallScore(frame.objectEvidence)
            let ballChange = min(1, frame.objectEvidence.ballLocalChange)
            return clamp(handNearHip * 0.17 + downward * 0.16 + shaftBall * 0.32 + ballChange * 0.16 + coverage * 0.19)

        case .followThrough:
            guard reliableHorizontalShaftEvidence(frame) != nil else { return 0 }
            return clamp(
                shaftHorizontal * 0.35
                    + armHorizontal * 0.18
                    + upward * 0.22
                    + hipTurn * 0.15
                    + coverage * 0.10
            )

        case .finish:
            // Decodable legacy compatibility only; it is never part of a
            // canonical P1–P8 solve.
            return 0
        }
    }

    private static func shaftBallScore(_ object: SwingObjectEvidence) -> Double {
        guard let shaft = object.shaft, let ball = object.stableBall else { return 0 }
        let alignment = 1 - min(1, shaft.distanceFromExtendedLine(to: ball) / 0.08)
        return clamp(alignment * shaft.confidence)
    }

    private static func reliableHorizontalShaftEvidence(
        _ frame: SwingFrameEvidence
    ) -> Double? {
        guard let shaft = frame.objectEvidence.shaft,
              shaft.confidence.isFinite,
              shaft.confidence >= 0.70,
              shaft.length.isFinite,
              shaft.length >= 0.04 else {
            return nil
        }
        let horizontal = closeness(
            horizontalAngle(shaft.angle),
            target: 0,
            tolerance: 18
        ) * shaft.confidence
        return horizontal >= 0.55 ? horizontal : nil
    }

    private static func transitionScore(from: SwingFrameEvidence, to: SwingFrameEvidence) -> Double {
        let gap = to.time - from.time
        guard gap > 0 else { return -1000 }
        return -max(0, gap - 1.25) * 0.20
    }

    private static func horizontalAngle(_ angle: Double) -> Double {
        let normalized = abs(angle).truncatingRemainder(dividingBy: 180)
        return min(normalized, 180 - normalized)
    }

    private static func closeness(_ value: Double?, target: Double, tolerance: Double) -> Double {
        guard let value else { return 0 }
        return max(0, 1 - abs(value - target) / tolerance)
    }

    private static func ramp(_ value: Double?, minimum: Double, maximum: Double) -> Double {
        guard let value, maximum > minimum else { return 0 }
        return clamp((value - minimum) / (maximum - minimum))
    }

    private static func distance(_ first: CGPoint?, _ second: CGPoint?) -> Double? {
        guard let first, let second else { return nil }
        return SwingGeometry.distance(first, second)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func unresolvedResult() -> SwingAnalysisResult {
        let detections = SwingStage.pStages.map {
            SwingStageDetection(stage: $0, time: nil, confidence: 0, status: .unresolved)
        }
        return SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: Set(SwingStage.pStages),
            detections: detections
        )
    }
}

enum SwingStageDetector {
    private static let directionChangeThreshold: CGFloat = 0.015

    static func detect(frames: [SwingFrameSample]) -> SwingAnalysisResult {
        let evidence = SwingFeatureExtractor.extract(frames: frames)
        let timeline = SwingEvidenceTimeline.build(from: evidence)
        let candidateSets = ImpactCorridorResolver.candidates(in: timeline).map {
            BidirectionalStageCandidateResolver.candidates(
                timeline: timeline,
                impact: $0
            )
        }
        return ConstrainedSwingPathSolver.solve(
            candidateSets: candidateSets,
            timeline: timeline
        )
    }

    /// Returns conservative body-only candidates when the strict body + club
    /// solver cannot complete. Club-defined P6/P8 deliberately stay unresolved.
    static func detectPoseOnlyCandidates(
        _ rawSamples: [SwingPoseSample]
    ) -> SwingAnalysisResult {
        let samples = rawSamples
            .filter { !$0.wristY.isNaN }
            .sorted { $0.time < $1.time }
        guard samples.count >= 9,
              zip(samples, samples.dropFirst()).allSatisfy({ $0.time < $1.time }) else {
            return unresolvedResult()
        }

        var resolved: [SwingStage: SwingPoseSample] = [:]
        guard let p4Index = backswingTopIndex(in: samples) else {
            return unresolvedResult()
        }

        // Repeated video frames at P1 and P4 are normal. This compatibility
        // path is not part of the production candidate/solver pipeline.
        if p4Index >= 3 {
            let p1Index = (0..<p4Index).reduce(0) { best, index in
                samples[index].wristY >= samples[best].wristY ? index : best
            }
            let ascentLength = p4Index - p1Index
            let p2Index = p1Index + max(1, ascentLength / 3)
            let p3Index = p1Index + max(2, (ascentLength * 2) / 3)
            let p1 = samples[p1Index]
            let p2 = samples[p2Index]
            let p3 = samples[p3Index]
            let p4 = samples[p4Index]
            // Slow-motion Vision tracks commonly contain short reversals or
            // repeated frames. Preserve ordered correction candidates when
            // the full address-to-top movement is clear instead of requiring
            // every interpolated third to be strictly monotonic.
            if p1Index < p2Index, p2Index < p3Index, p3Index < p4Index,
               p1.wristY > p4.wristY + directionChangeThreshold {
                resolved[.address] = p1
                resolved[.takeaway] = p2
                resolved[.leadArmParallelBackswing] = p3
                resolved[.top] = p4
            }
        }

        // P5 is lead-arm-parallel on the downswing. It happens when the hands
        // cross the shoulder line, not at the first frame that leaves P4.
        if let p5Index = downswingParallelIndex(after: p4Index, in: samples) {
            resolved[.leadArmParallelDownswing] = samples[p5Index]

            // Legacy pose-only samples cannot establish P6 (shaft-parallel
            // delivery) or P8 (shaft-parallel release). They stay unresolved
            // rather than being inferred from hand motion. P7 can still be
            // retained as an impact compatibility signal.
            if let p7Index = impactIndex(after: p5Index, in: samples) {
                resolved[.impact] = samples[p7Index]
            }
        }

        let detections = SwingStage.pStages.map { stage -> SwingStageDetection in
            guard let sample = resolved[stage] else {
                return SwingStageDetection(stage: stage, time: nil, confidence: 0, status: .unresolved)
            }
            let confidence = evidenceConfidence(for: stage, sample: sample)
            let status: SwingStageDetectionStatus
            if confidence >= 0.75 {
                status = .confirmed
            } else if confidence >= 0.35 {
                status = .lowConfidence
            } else {
                status = .unresolved
            }
            return SwingStageDetection(
                stage: stage,
                time: status == .unresolved ? nil : sample.time,
                sourceFrameIndex: status == .unresolved ? nil : sample.sourceFrameIndex,
                confidence: confidence,
                status: status
            )
        }
        let markers = detections.compactMap(\.marker)
        let unresolved = Set(detections.filter { $0.status == .unresolved }.map(\.stage))
        return SwingAnalysisResult(detectedMarkers: markers, unresolvedStages: unresolved, detections: detections)
    }

    /// Compatibility adapter retained only for standalone legacy smoke fixtures.
    @available(iOS, unavailable, message: "Legacy smoke-test adapter; use detect(frames:) in production")
    static func detectLegacySamplesForSmokeTests(
        _ rawSamples: [SwingPoseSample]
    ) -> SwingAnalysisResult {
        detectPoseOnlyCandidates(rawSamples)
    }

    private static func unresolvedResult() -> SwingAnalysisResult {
        let detections = SwingStage.pStages.map {
            SwingStageDetection(stage: $0, time: nil, confidence: 0, status: .unresolved)
        }
        return SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: Set(SwingStage.pStages),
            detections: detections
        )
    }

    private static func evidenceConfidence(for stage: SwingStage, sample: SwingPoseSample) -> Double {
        let hasWrist = sample.leftWrist != nil || sample.rightWrist != nil
        let hasElbow = sample.leftElbow != nil || sample.rightElbow != nil
        let hasShoulders = sample.leftShoulder != nil && sample.rightShoulder != nil
        let hasHips = sample.leftHip != nil && sample.rightHip != nil
        let hasHeadAndSpine = sample.head != nil && sample.spineAngle != nil
        let coverage =
            (hasWrist ? 0.20 : 0) +
            (hasElbow ? 0.15 : 0) +
            (hasShoulders ? 0.25 : 0) +
            (hasHips ? 0.25 : 0) +
            (hasHeadAndSpine ? 0.15 : 0)
        let base = coverage * Double(sample.aggregateConfidence)
        guard let hipY = midpointY(sample.leftHip, sample.rightHip) else { return base }

        let postureMatchesStage: Bool
        switch stage {
        case .address:
            postureMatchesStage = sample.wristY > hipY
        case .takeaway, .leadArmParallelBackswing:
            postureMatchesStage = sample.leftElbow != nil || sample.rightElbow != nil
        case .top:
            postureMatchesStage = sample.wristY < (midpointY(sample.leftShoulder, sample.rightShoulder) ?? hipY)
        case .leadArmParallelDownswing, .shaftParallelDownswing,
                .impact, .followThrough, .finish:
            postureMatchesStage = abs(sample.wristY - hipY) <= 0.35
        }
        return postureMatchesStage ? base : base * 0.55
    }

    private static func midpointY(_ first: CGPoint?, _ second: CGPoint?) -> CGFloat? {
        guard let first, let second else { return nil }
        return (first.y + second.y) / 2
    }

    private static func downswingParallelIndex(after topIndex: Int, in samples: [SwingPoseSample]) -> Int? {
        guard topIndex + 2 < samples.count else { return nil }
        return ((topIndex + 1)..<(samples.count - 1)).first { index in
            guard let shoulderY = midpointY(samples[index].leftShoulder, samples[index].rightShoulder) else {
                return false
            }
            return samples[index].wristY > samples[topIndex].wristY + directionChangeThreshold &&
                samples[index + 1].wristY > samples[index].wristY + directionChangeThreshold &&
                samples[index].wristY >= shoulderY
        }
    }

    private static func impactIndex(after downswingIndex: Int, in samples: [SwingPoseSample]) -> Int? {
        guard downswingIndex + 1 < samples.count else { return nil }
        let finalIndices = (samples.count - 3)..<samples.count
        let candidates = ((downswingIndex + 1)..<(samples.count - 1)).compactMap { index -> (index: Int, score: CGFloat)? in
            guard !finalIndices.contains(index),
                  let hipY = midpointY(samples[index].leftHip, samples[index].rightHip),
                  let shoulderY = midpointY(samples[index].leftShoulder, samples[index].rightShoulder),
                  let hand = handCenter(in: samples[index]),
                  let hip = center(samples[index].leftHip, samples[index].rightHip) else {
                return nil
            }
            guard hand.y >= shoulderY,
                  abs(hand.y - hipY) <= 0.25,
                  abs(hand.x - hip.x) <= 0.30 else {
                return nil
            }
            let hipAlignment = max(0, 1 - (abs(hand.x - hip.x) / 0.30 + abs(hand.y - hipY) / 0.25) / 2)
            let score = handSpeed(at: index, in: samples) * (0.35 + 0.65 * hipAlignment)
            return (index, score)
        }
        return candidates.max { $0.score < $1.score }?.index
    }

    private static func handSpeed(at index: Int, in samples: [SwingPoseSample]) -> CGFloat {
        guard index > 0 else { return 0 }
        let elapsed = max(samples[index].time - samples[index - 1].time, .leastNonzeroMagnitude)
        guard let current = handCenter(in: samples[index]),
              let previous = handCenter(in: samples[index - 1]) else {
            return abs(samples[index].wristY - samples[index - 1].wristY) / elapsed
        }
        return hypot(current.x - previous.x, current.y - previous.y) / elapsed
    }

    private static func handCenter(in sample: SwingPoseSample) -> CGPoint? {
        center(sample.leftWrist, sample.rightWrist) ?? sample.rightWrist ?? sample.leftWrist
    }

    private static func center(_ first: CGPoint?, _ second: CGPoint?) -> CGPoint? {
        guard let first, let second else { return nil }
        return CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }

    /// P4 is the earliest high-hand apex that reverses into a downswing.  A
    /// global minimum would incorrectly select a later follow-through or
    /// finish position when the hands finish higher than the backswing top.
    private static func backswingTopIndex(in samples: [SwingPoseSample]) -> Int? {
        guard samples.count >= 5 else { return nil }
        let torsoScales = samples.compactMap { sample -> CGFloat? in
            guard let shoulder = center(sample.leftShoulder, sample.rightShoulder),
                  let hip = center(sample.leftHip, sample.rightHip) else {
                return nil
            }
            return hypot(shoulder.x - hip.x, shoulder.y - hip.y)
        }.sorted()
        let torsoScale = torsoScales.isEmpty
            ? 0.20
            : torsoScales[torsoScales.count / 2]
        let minimumRise = max(0.05, min(0.14, torsoScale * 0.35))

        var addressBaseline = samples[0].wristY
        var apexIndex: Int?
        var apexY = CGFloat.greatestFiniteMagnitude
        for index in 1..<samples.count {
            let wristY = samples[index].wristY
            guard wristY.isFinite else { continue }

            if apexIndex == nil {
                addressBaseline = max(addressBaseline, wristY)
                guard addressBaseline - wristY >= minimumRise else { continue }
                apexIndex = index
                apexY = wristY
                continue
            }

            if wristY < apexY {
                apexIndex = index
                apexY = wristY
                continue
            }

            let completedRise = addressBaseline - apexY
            let downswingRetrace = wristY - apexY
            let requiredRetrace = max(
                directionChangeThreshold * 2,
                completedRise * 0.45
            )
            if downswingRetrace >= requiredRetrace {
                return apexIndex
            }
        }
        return nil
    }
}

enum ProductAnalysisFallback {
    static func resolve(
        strictResult: SwingAnalysisResult,
        poseSamples: [SwingPoseSample],
        supplementalPoseSamples: [SwingPoseSample] = []
    ) -> SwingAnalysisResult {
        guard strictResult.detectedMarkers.isEmpty else { return strictResult }
        let poseOnly = SwingStageDetector.detectPoseOnlyCandidates(
            mergedPoseSamples(
                primary: poseSamples,
                supplemental: supplementalPoseSamples
            )
        )
        let detections = poseOnly.detections.map { detection -> SwingStageDetection in
            guard detection.status != .unresolved else { return detection }
            return SwingStageDetection(
                stage: detection.stage,
                time: detection.time,
                sourceFrameIndex: detection.sourceFrameIndex,
                confidence: min(0.69, detection.confidence),
                status: .lowConfidence,
                evidence: detection.evidence
            )
        }
        return SwingAnalysisResult(
            detectedMarkers: detections.compactMap(\.marker),
            unresolvedStages: Set(
                detections.filter { $0.status == .unresolved }.map(\.stage)
            ),
            detections: detections
        )
    }

    static func mergedPoseSamples(
        primary: [SwingPoseSample],
        supplemental: [SwingPoseSample]
    ) -> [SwingPoseSample] {
        let ordered = (supplemental + primary).sorted {
            if abs($0.time - $1.time) > 0.000_001 {
                return $0.time < $1.time
            }
            return $0.aggregateConfidence > $1.aggregateConfidence
        }
        var retained: [SwingPoseSample] = []
        var retainedSourceFrames = Set<Int>()
        for sample in ordered {
            if let sourceFrameIndex = sample.sourceFrameIndex {
                guard retainedSourceFrames.insert(sourceFrameIndex).inserted else {
                    continue
                }
            } else if let prior = retained.last,
                      abs(prior.time - sample.time) <= 0.000_001 {
                continue
            }
            retained.append(sample)
        }
        return retained
    }
}

enum CandidateAttemptAcceptancePolicy {
    static func hasUsableStages(_ result: SwingAnalysisResult) -> Bool {
        result.detections.contains(where: {
            $0.status != .unresolved && $0.sourceFrameIndex != nil
        })
    }
}

enum CoarseFallbackSelectionPolicy {
    static func samples(
        all samples: [CoarseSwingSample],
        preferredAttempt: SwingAttempt?,
        requiresFullSequence: Bool
    ) -> [CoarseSwingSample] {
        guard !requiresFullSequence, let preferredAttempt else {
            return samples
        }
        return samples.filter {
            $0.time >= preferredAttempt.startTime
                && $0.time <= preferredAttempt.endTime
        }
    }
}

/// Keeps full-swing analysis dense enough to resolve the short motion interval
/// inside a much longer imported video. Eight samples per second gives the
/// detector at least 9 observations for a typical 0.8–1.0 second swing.
enum SwingAnalysisSamplingPlan {
    static let samplesPerSecond = 8.0

    static func sampleTimes(duration: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        let interval = 1.0 / samplesPerSecond
        let intervals = max(1, Int(ceil(duration / interval)))
        return (0...intervals).map { index in
            min(duration, Double(index) * interval)
        }
    }
}

// MARK: - Two-stage scan planning

enum TwoStageScanPass: Equatable {
    case coarse
    case fine
}

enum TwoStageScanPolicy {
    static func extractsObjectEvidence(during pass: TwoStageScanPass) -> Bool {
        pass == .fine
    }
}

struct CoarseSwingSample: Equatable {
    let time: Double
    let pose: SwingPoseSample?
}

struct SwingWindow: Equatable {
    let startTime: Double
    let endTime: Double

    var duration: Double { max(0, endTime - startTime) }
}

struct SwingCore: Equatable {
    let startTime: Double
    let endTime: Double
    let peakTime: Double
}

enum SwingCoreLocationResult: Equatable {
    case located(SwingCore)
    case failed(SwingWindowFailure)
}

struct AdaptiveBoundaryEvidence: Equatable {
    let hasAddressBoundary: Bool
    /// Body-only coverage used while deciding how far to scan. This is
    /// deliberately broader than P8, whose final resolution is shaft-strict.
    let hasPostImpactBoundary: Bool
}

enum AdaptiveSwingWindowAction: Equatable {
    case expand(SwingWindow)
    case ready(SwingWindow)
    case failed(AnalysisFailure)
}

enum AdaptiveWindowShiftDirection: Equatable {
    case earlier
    case later
}

/// Run-local adaptive search state. Once the maximum-width window starts
/// moving, it may continue only in that direction; evicted fine frames can
/// therefore never re-enter the active window.
struct AdaptiveWindowSearchState {
    private(set) var shiftDirection: AdaptiveWindowShiftDirection?

    mutating func nextAction(
        current: SwingWindow,
        duration: Double,
        evidence: AdaptiveBoundaryEvidence
    ) -> AdaptiveSwingWindowAction {
        if evidence.hasAddressBoundary && evidence.hasPostImpactBoundary {
            return AdaptiveSwingWindowPlanner.nextAction(
                current: current,
                duration: duration,
                evidence: evidence
            )
        }

        let requiredDirection: AdaptiveWindowShiftDirection = evidence.hasAddressBoundary
            ? .later
            : .earlier
        if current.duration >= AdaptiveSwingWindowPlanner.maximumSpan - 0.000_000_001,
           let shiftDirection,
           shiftDirection != requiredDirection {
            return .failed(
                evidence.hasAddressBoundary
                    ? .missingPostImpactBoundary
                    : .missingAddressBoundary
            )
        }

        let action = AdaptiveSwingWindowPlanner.nextAction(
            current: current,
            duration: duration,
            evidence: evidence
        )
        if case let .expand(next) = action,
           next.duration >= AdaptiveSwingWindowPlanner.maximumSpan - 0.000_000_001,
           abs(next.startTime - current.startTime) > 0.000_000_001,
           abs(next.endTime - current.endTime) > 0.000_000_001 {
            shiftDirection = requiredDirection
        }
        return action
    }
}

enum AdaptiveSwingWindowPlanner {
    static let expansionStep = 0.5
    static let initialPadding = 0.5
    static let maximumSpan = 8.0

    static func initialWindow(core: SwingCore, duration: Double) -> SwingWindow {
        SwingWindow(
            startTime: max(0, core.startTime - initialPadding),
            endTime: min(duration, core.endTime + initialPadding)
        )
    }

    static func nextAction(
        current: SwingWindow,
        duration: Double,
        evidence: AdaptiveBoundaryEvidence
    ) -> AdaptiveSwingWindowAction {
        let epsilon = 0.000_000_001
        guard current.duration <= maximumSpan + epsilon else {
            return .failed(.swingWindowTooLong)
        }
        if evidence.hasAddressBoundary && evidence.hasPostImpactBoundary { return .ready(current) }
        if !evidence.hasAddressBoundary {
            guard current.startTime > 0 else { return .failed(.incompleteSwingClip) }
            let proposedStart = max(0, current.startTime - expansionStep)
            if current.endTime - proposedStart <= maximumSpan + epsilon {
                return .expand(SwingWindow(
                    startTime: max(current.endTime - maximumSpan, proposedStart),
                    endTime: current.endTime
                ))
            }
            return .expand(SwingWindow(
                startTime: proposedStart,
                endTime: proposedStart + maximumSpan
            ))
        }
        guard current.endTime < duration else { return .failed(.incompleteSwingClip) }
        let proposedEnd = min(duration, current.endTime + expansionStep)
        if proposedEnd - current.startTime <= maximumSpan + epsilon {
            return .expand(SwingWindow(
                startTime: current.startTime,
                endTime: min(current.startTime + maximumSpan, proposedEnd)
            ))
        }
        return .expand(SwingWindow(
            startTime: proposedEnd - maximumSpan,
            endTime: proposedEnd
        ))
    }
}

enum SwingWindowFailure: Equatable {
    case insufficientPoseEvidence
    case noSwingMotion
    case ambiguousCandidates
    case windowTooLong
}

enum SwingWindowLocationResult: Equatable {
    case located(SwingWindow)
    case failed(SwingWindowFailure)
}

enum SwingCoreLocator {
    static let samplesPerSecond = 8.0
    /// A brief real-time top pause becomes close to a second in a 240 fps
    /// slow-motion export. Keep the backswing and downswing in one motion core.
    private static let bridgeGapDuration = 1.5
    private static let featureSmoothingRadius = 2

    static func sampleTimes(duration: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        let interval = 1.0 / samplesPerSecond
        let count = max(1, Int(ceil(duration / interval)))
        return (0...count).map { min(duration, Double($0) * interval) }
    }

    static func locate(samples rawSamples: [CoarseSwingSample]) -> SwingCoreLocationResult {
        let samples = rawSamples
            .filter { $0.time.isFinite }
            .sorted { $0.time < $1.time }
        guard samples.count >= 5 else { return .failed(.insufficientPoseEvidence) }

        let poseCoverage = Double(samples.filter { $0.pose != nil }.count) / Double(samples.count)
        guard poseCoverage >= 0.5 else { return .failed(.insufficientPoseEvidence) }

        let hands = samples.map { $0.pose.flatMap(handCenterRelativeToHip) }
        let shoulderAxes = samples.map { $0.pose.flatMap { lineAngle($0.leftShoulder, $0.rightShoulder) } }
        let hipAxes = samples.map { $0.pose.flatMap { lineAngle($0.leftHip, $0.rightHip) } }
        let smoothedHands = hands.indices.map {
            medianPoint(hands, at: $0, radius: featureSmoothingRadius)
        }
        let smoothedShoulderAxes = shoulderAxes.indices.map {
            meanAxisAngle(shoulderAxes, at: $0, radius: featureSmoothingRadius)
        }
        let smoothedHipAxes = hipAxes.indices.map {
            meanAxisAngle(hipAxes, at: $0, radius: featureSmoothingRadius)
        }

        var energies = Array(repeating: 0.0, count: samples.count)
        for index in 1..<samples.count {
            guard samples[index].pose != nil,
                  samples[index - 1].pose != nil else { continue }
            let elapsed = samples[index].time - samples[index - 1].time
            guard elapsed > 0 else { continue }

            let handMotion = normalizedDistance(
                smoothedHands[index],
                smoothedHands[index - 1]
            ) / elapsed
            let shoulderMotion = angularDistance(
                smoothedShoulderAxes[index],
                smoothedShoulderAxes[index - 1]
            ) / elapsed
            let hipMotion = angularDistance(
                smoothedHipAxes[index],
                smoothedHipAxes[index - 1]
            ) / elapsed
            energies[index] = handMotion + shoulderMotion * 0.20 + hipMotion * 0.15
        }

        let nonZero = energies.filter { $0 > 0.000_1 }.sorted()
        guard !nonZero.isEmpty else { return .failed(.noSwingMotion) }
        let observedHands = smoothedHands.compactMap { $0 }
        guard let minimumX = observedHands.map(\.x).min(),
              let maximumX = observedHands.map(\.x).max(),
              let minimumY = observedHands.map(\.y).min(),
              let maximumY = observedHands.map(\.y).max() else {
            return .failed(.noSwingMotion)
        }
        let handExcursion = hypot(
            Double(maximumX - minimumX),
            Double(maximumY - minimumY)
        )
        let torsoScales = samples.compactMap { sample -> Double? in
            guard let pose = sample.pose,
                  let shoulder = SwingGeometry.center(
                    pose.leftShoulder,
                    pose.rightShoulder
                  ),
                  let hip = SwingGeometry.center(pose.leftHip, pose.rightHip) else {
                return nil
            }
            return SwingGeometry.distance(shoulder, hip)
        }.sorted()
        let referenceScale = max(
            0.08,
            torsoScales.isEmpty
                ? 0.20
                : torsoScales[torsoScales.count / 2]
        )
        guard handExcursion / referenceScale >= 0.35 else {
            return .failed(.noSwingMotion)
        }
        let median = nonZero[nonZero.count / 2]
        let peak = nonZero.last ?? 0
        // Playback speed changes velocity, not the actual swing arc. Use a
        // relative energy threshold after validating a real torso-scaled hand
        // excursion so iPhone slow-motion exports are not classified as still.
        let threshold = max(0.005, min(peak * 0.45, median * 2.2))
        let activeIndices = energies.indices.filter { energies[$0] >= threshold }
        guard !activeIndices.isEmpty else { return .failed(.noSwingMotion) }

        let typicalInterval = medianInterval(samples.map(\.time))
        let maximumIndexGap = max(1, Int(ceil(bridgeGapDuration / typicalInterval)))
        var groups: [[Int]] = []
        for index in activeIndices {
            if let last = groups.indices.last,
               let priorIndex = groups[last].last,
               index - priorIndex <= maximumIndexGap {
                groups[last].append(index)
            } else {
                groups.append([index])
            }
        }

        let candidates = groups.compactMap { group in
            candidate(
                from: group,
                samples: samples,
                energies: energies
            )
        }.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.core.startTime < rhs.core.startTime : lhs.score > rhs.score
        }

        guard let best = candidates.first else { return .failed(.noSwingMotion) }
        if candidates.count > 1, candidates[1].score >= best.score * 0.85 {
            return .failed(.ambiguousCandidates)
        }
        return .located(best.core)
    }

    private static func candidate(
        from group: [Int],
        samples: [CoarseSwingSample],
        energies: [Double]
    ) -> (core: SwingCore, score: Double)? {
        guard let first = group.first, let last = group.last else { return nil }
        let peakIndex = group.max { energies[$0] < energies[$1] } ?? first
        return (
            core: SwingCore(
                startTime: samples[max(0, first - 1)].time,
                endTime: samples[last].time,
                peakTime: samples[peakIndex].time
            ),
            group.reduce(0.0) { $0 + energies[$1] }
        )
    }

    private static func handCenter(_ sample: SwingPoseSample) -> CGPoint? {
        if let left = sample.leftWrist, let right = sample.rightWrist {
            return CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        }
        return sample.leftWrist ?? sample.rightWrist
    }

    private static func handCenterRelativeToHip(_ sample: SwingPoseSample) -> CGPoint? {
        guard let hand = handCenter(sample) else { return nil }
        guard let hip = SwingGeometry.center(sample.leftHip, sample.rightHip) else {
            return hand
        }
        return CGPoint(x: hand.x - hip.x, y: hand.y - hip.y)
    }

    private static func lineAngle(_ first: CGPoint?, _ second: CGPoint?) -> Double? {
        guard let first, let second else { return nil }
        return atan2(Double(second.y - first.y), Double(second.x - first.x))
    }

    private static func medianPoint(
        _ values: [CGPoint?],
        at index: Int,
        radius: Int
    ) -> CGPoint? {
        let start = max(0, index - radius)
        let end = min(values.count - 1, index + radius)
        let points = values[start...end].compactMap { $0 }
        guard !points.isEmpty else { return nil }
        let xValues = points.map(\.x).sorted()
        let yValues = points.map(\.y).sorted()
        return CGPoint(
            x: xValues[xValues.count / 2],
            y: yValues[yValues.count / 2]
        )
    }

    private static func meanAxisAngle(
        _ values: [Double?],
        at index: Int,
        radius: Int
    ) -> Double? {
        let start = max(0, index - radius)
        let end = min(values.count - 1, index + radius)
        let angles = values[start...end].compactMap { $0 }
        guard !angles.isEmpty else { return nil }
        let sine = angles.reduce(0.0) { $0 + sin($1 * 2) }
        let cosine = angles.reduce(0.0) { $0 + cos($1 * 2) }
        return atan2(sine, cosine) / 2
    }

    private static func normalizedDistance(_ first: CGPoint?, _ second: CGPoint?) -> Double {
        guard let first, let second else { return 0 }
        return hypot(Double(first.x - second.x), Double(first.y - second.y))
    }

    private static func angularDistance(_ first: Double?, _ second: Double?) -> Double {
        guard let first, let second else { return 0 }
        // Shoulder and hip lines are axes, not directed vectors. Vision can
        // exchange left/right labels in side-on poses; a 180-degree endpoint
        // reversal must therefore remain zero motion instead of a huge spike.
        let raw = abs(first - second).truncatingRemainder(dividingBy: .pi)
        return min(raw, .pi - raw)
    }

    private static func medianInterval(_ times: [Double]) -> Double {
        let intervals = zip(times, times.dropFirst())
            .map { $1 - $0 }
            .filter { $0 > 0 }
            .sorted()
        return intervals.isEmpty ? 1.0 / samplesPerSecond : intervals[intervals.count / 2]
    }
}

/// Finds independent motion windows in a continuous practice video. This is
/// intentionally body-only: the expensive per-window solver still validates
/// P1–P8 and object evidence before any attempt can become completed.
enum SwingAttemptSegmenter {
    private static let bridgeGapDuration = 0.5
    private static let padding = AdaptiveSwingWindowPlanner.initialPadding
    private static let minimumDuration = 0.8

    static func segment(
        samples rawSamples: [CoarseSwingSample],
        sourceDuration: Double
    ) -> [SwingAttempt] {
        guard sourceDuration.isFinite, sourceDuration > 0 else { return [] }
        let samples = rawSamples.filter { $0.time.isFinite }.sorted { $0.time < $1.time }
        guard samples.count >= 5 else { return [] }

        let energies = motionEnergies(samples)
        let nonZero = energies.filter { $0 > 0.000_1 }.sorted()
        guard let peak = nonZero.last else { return [] }
        let median = nonZero[nonZero.count / 2]
        let threshold = max(0.30, min(peak * 0.45, median * 2.2))
        let activeIndices = energies.indices.filter { energies[$0] >= threshold }
        guard !activeIndices.isEmpty else { return [] }

        let intervals = zip(samples, samples.dropFirst()).map { $1.time - $0.time }
            .filter { $0 > 0 }.sorted()
        let interval = intervals.isEmpty ? 0.125 : intervals[intervals.count / 2]
        let maximumIndexGap = max(1, Int(ceil(bridgeGapDuration / interval)))
        var groups: [[Int]] = []
        for index in activeIndices {
            if let groupIndex = groups.indices.last,
               let previous = groups[groupIndex].last,
               index - previous <= maximumIndexGap {
                groups[groupIndex].append(index)
            } else {
                groups.append([index])
            }
        }

        let windows = groups.compactMap { group -> SwingWindow? in
            guard let first = group.first, let last = group.last else { return nil }
            let window = SwingWindow(
                startTime: max(0, samples[max(0, first - 1)].time - padding),
                endTime: min(sourceDuration, samples[last].time + padding)
            )
            return window.duration >= minimumDuration
                && window.duration <= AdaptiveSwingWindowPlanner.maximumSpan ? window : nil
        }

        let merged = windows.sorted { $0.startTime < $1.startTime }.reduce(into: [SwingWindow]()) {
            partial, candidate in
            guard let previous = partial.last else {
                partial.append(candidate)
                return
            }
            guard candidate.startTime <= previous.endTime else {
                partial.append(candidate)
                return
            }
            partial[partial.count - 1] = SwingWindow(
                startTime: previous.startTime,
                endTime: max(previous.endTime, candidate.endTime)
            )
        }

        return merged.enumerated().compactMap { index, window in
            guard window.duration >= minimumDuration,
                  window.duration <= AdaptiveSwingWindowPlanner.maximumSpan else { return nil }
            return SwingAttempt(ordinal: index + 1, startTime: window.startTime, endTime: window.endTime)
        }
    }

    private static func motionEnergies(_ samples: [CoarseSwingSample]) -> [Double] {
        guard samples.count > 1 else { return [] }
        var energies = Array(repeating: 0.0, count: samples.count)
        for index in 1..<samples.count {
            guard let previous = samples[index - 1].pose.flatMap(handRelativeToHip),
                  let current = samples[index].pose.flatMap(handRelativeToHip) else { continue }
            let elapsed = samples[index].time - samples[index - 1].time
            guard elapsed > 0 else { continue }
            energies[index] = SwingGeometry.distance(previous, current) / elapsed
        }
        return energies
    }

    private static func handRelativeToHip(_ sample: SwingPoseSample) -> CGPoint? {
        guard let hand = SwingGeometry.center(sample.leftWrist, sample.rightWrist) else { return nil }
        guard let hip = SwingGeometry.center(sample.leftHip, sample.rightHip) else { return hand }
        return CGPoint(x: hand.x - hip.x, y: hand.y - hip.y)
    }
}

/// Chooses the motion window that most resembles a full golf swing instead of
/// simply accepting the largest body movement in the clip. Walking toward the
/// ball or bending to retrieve it can carry more total motion energy than the
/// swing itself, while the swing retains a substantially larger vertical hand
/// arc relative to the player's torso scale.
enum SwingAttemptSelectionPolicy {
    static func preferredAttempt(
        in attempts: [SwingAttempt],
        samples: [CoarseSwingSample]
    ) -> SwingAttempt? {
        rankedAttempts(in: attempts, samples: samples).first
    }

    static func rankedAttempts(
        in attempts: [SwingAttempt],
        samples: [CoarseSwingSample]
    ) -> [SwingAttempt] {
        attempts.compactMap { attempt -> (attempt: SwingAttempt, score: Double)? in
            let poses = samples
                .filter { $0.time >= attempt.startTime && $0.time <= attempt.endTime }
                .compactMap(\.pose)
            guard poses.count >= 3 else { return nil }

            let handHeights = poses.map(\.wristY)
            guard let minimumHandHeight = handHeights.min(),
                  let maximumHandHeight = handHeights.max() else { return nil }
            let torsoScales = poses.compactMap(torsoScale).sorted()
            guard !torsoScales.isEmpty else { return nil }
            let scale = max(0.000_001, torsoScales[torsoScales.count / 2])
            let verticalArc = Double(maximumHandHeight - minimumHandHeight) / scale

            let highHandBonus = poses.compactMap { pose -> Double? in
                guard let leftShoulder = pose.leftShoulder,
                      let rightShoulder = pose.rightShoulder else { return nil }
                let shoulderY = (leftShoulder.y + rightShoulder.y) / 2
                return max(0, Double(shoulderY - pose.wristY) / scale)
            }.max() ?? 0
            return (attempt, verticalArc + highHandBonus * 0.25)
        }.sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.000_001 {
                return lhs.score > rhs.score
            }
            return lhs.attempt.startTime < rhs.attempt.startTime
        }.map(\.attempt)
    }

    private static func torsoScale(_ pose: SwingPoseSample) -> Double? {
        guard let shoulder = SwingGeometry.center(pose.leftShoulder, pose.rightShoulder),
              let hip = SwingGeometry.center(pose.leftHip, pose.rightHip) else { return nil }
        return SwingGeometry.distance(shoulder, hip)
    }
}

/// Temporary compatibility adapter for the production orchestration, which is
/// migrated to the adaptive planner in a later task.
enum SwingWindowLocator {
    static func sampleTimes(duration: Double) -> [Double] {
        SwingCoreLocator.sampleTimes(duration: duration)
    }

    static func locate(samples: [CoarseSwingSample]) -> SwingWindowLocationResult {
        switch SwingCoreLocator.locate(samples: samples) {
        case let .located(core):
            return .located(SwingWindow(startTime: core.startTime, endTime: core.endTime))
        case let .failed(reason):
            return .failed(reason)
        }
    }
}

struct FineFrameReference: Equatable {
    let sourceFrameIndex: Int
    let time: Double
}

enum FineSwingSamplingPlan {
    /// Boundary/P-stage discovery is intentionally bounded. A slow-motion
    /// eight-second window therefore uses at most about 96 Vision frames;
    /// exact source-frame stepping remains available for manual correction.
    static let maximumSamplesPerSecond = 12.0

    static func frames(
        window: SwingWindow,
        sourceFrameTimeline: SourceFrameTimeline
    ) -> [FineFrameReference] {
        guard window.duration > 0,
              sourceFrameTimeline.count > 0 else { return [] }
        let firstFrame = sourceFrameTimeline.firstSourceFrameIndex(
            atOrAfter: window.startTime
        )
        guard firstFrame <= sourceFrameTimeline.maximumSourceFrameIndex,
              let lastFrame = sourceFrameTimeline.lastSourceFrameIndex(
                atOrBefore: window.endTime
              ),
              firstFrame <= lastFrame else { return [] }

        let minimumInterval = 1.0 / maximumSamplesPerSecond
        let firstSlot = Int(ceil((window.startTime - 0.000_000_001) / minimumInterval))
        let lastSlot = Int(floor((window.endTime + 0.000_000_001) / minimumInterval))
        var references: [FineFrameReference] = []
        var retainedSourceFrames: Set<Int> = []
        if firstSlot <= lastSlot {
            for slot in firstSlot...lastSlot {
                let targetTime = Double(slot) * minimumInterval
                let sourceFrameIndex = sourceFrameTimeline.firstSourceFrameIndex(
                    atOrAfter: targetTime
                )
                guard sourceFrameIndex >= firstFrame,
                      sourceFrameIndex <= lastFrame,
                      retainedSourceFrames.insert(sourceFrameIndex).inserted,
                      let time = sourceFrameTimeline.presentationTime(
                        sourceFrameIndex: sourceFrameIndex
                      )?.seconds else { continue }
                references.append(FineFrameReference(
                    sourceFrameIndex: sourceFrameIndex,
                    time: time
                ))
            }
        }
        if references.isEmpty,
           let time = sourceFrameTimeline.presentationTime(
            sourceFrameIndex: firstFrame
           )?.seconds {
            references.append(FineFrameReference(
                sourceFrameIndex: firstFrame,
                time: time
            ))
        }
        return references
    }

    static func frames(
        window: SwingWindow,
        sourceFrameRate: Double,
        duration: Double,
        maximumSourceFrameIndex explicitMaximumSourceFrameIndex: Int? = nil
    ) -> [FineFrameReference] {
        guard sourceFrameRate.isFinite,
              sourceFrameRate > 0,
              duration.isFinite,
              duration > 0,
              window.duration > 0 else { return [] }

        let boundedStart = max(0, min(window.startTime, duration))
        let boundedEnd = max(boundedStart, min(window.endTime, duration))
        let firstFrame = Int(ceil(boundedStart * sourceFrameRate))
        let maximumSourceFrameIndex = explicitMaximumSourceFrameIndex
            ?? SourceFrameBounds.maximumSourceFrameIndex(
                duration: duration,
                sourceFrameRate: sourceFrameRate
            )
        let lastFrame = min(
            maximumSourceFrameIndex,
            Int(floor(boundedEnd * sourceFrameRate))
        )
        guard firstFrame <= lastFrame else { return [] }

        let frameStride = max(1, Int(ceil(sourceFrameRate / maximumSamplesPerSecond)))
        let firstAlignedFrame = ((firstFrame + frameStride - 1) / frameStride) * frameStride
        guard firstAlignedFrame <= lastFrame else {
            return [FineFrameReference(
                sourceFrameIndex: firstFrame,
                time: Double(firstFrame) / sourceFrameRate
            )]
        }
        return stride(from: firstAlignedFrame, through: lastFrame, by: frameStride).map {
            FineFrameReference(sourceFrameIndex: $0, time: Double($0) / sourceFrameRate)
        }
    }
}

enum SourceFrameBounds {
    static func maximumSourceFrameIndex(
        duration: Double,
        sourceFrameRate: Double
    ) -> Int {
        guard duration.isFinite,
              duration > 0,
              sourceFrameRate.isFinite,
              sourceFrameRate > 0 else { return -1 }
        return max(0, Int(ceil(duration * sourceFrameRate)) - 1)
    }
}

enum SparseObjectSamplingPlan {
    static let maximumFrameCount = 32
    private static let neighborRadius = 1
    private static let sampledStages: Set<SwingStage> = [
        .address,
        .takeaway,
        .shaftParallelDownswing,
        .impact,
        .followThrough
    ]

    static func frames(
        from references: [FineFrameReference],
        candidates: [StageCandidate]
    ) -> [FineFrameReference] {
        guard !references.isEmpty else { return [] }
        let sortedReferences = references.sorted {
            if $0.time != $1.time { return $0.time < $1.time }
            return $0.sourceFrameIndex < $1.sourceFrameIndex
        }
        guard !candidates.isEmpty else {
            return evenlySpacedFallback(from: sortedReferences)
        }

        let eligible = candidates.filter { sampledStages.contains($0.stage) }
        guard !eligible.isEmpty else { return [] }
        let neighborhoods = eligible.map { candidate in
            (candidate: candidate, indices: neighborhood(
                around: candidate.time,
                in: sortedReferences
            ))
        }
        let allIndices = neighborhoods.reduce(into: Set<Int>()) {
            $0.formUnion($1.indices)
        }
        if allIndices.count <= maximumFrameCount {
            return allIndices.sorted().map { sortedReferences[$0] }
        }

        let prioritized = neighborhoods.sorted { first, second in
            let firstIsImpact = first.candidate.stage == .impact
            let secondIsImpact = second.candidate.stage == .impact
            if firstIsImpact != secondIsImpact { return firstIsImpact }
            if first.candidate.score != second.candidate.score {
                return first.candidate.score > second.candidate.score
            }
            if first.candidate.time != second.candidate.time {
                return first.candidate.time < second.candidate.time
            }
            return first.candidate.sourceFrameIndex < second.candidate.sourceFrameIndex
        }
        var selectedIndices = Set<Int>()

        // Impact contours are the most time-sensitive object evidence, so keep
        // their complete three-frame neighborhoods whenever the fixed budget
        // permits it.
        for entry in prioritized where entry.candidate.stage == .impact {
            let additions = entry.indices.subtracting(selectedIndices)
            guard selectedIndices.count + additions.count <= maximumFrameCount else {
                continue
            }
            selectedIndices.formUnion(entry.indices)
        }

        // Dense, overlapping high-score neighborhoods can otherwise consume the
        // whole budget before a temporally distinct alternative is sampled. Keep
        // the centers of up to three plausible alternatives per non-impact stage;
        // the normal priority pass below fills their neighboring frames when
        // space remains.
        for stage in [
            SwingStage.address,
            .takeaway,
            .shaftParallelDownswing,
            .followThrough
        ] {
            for center in diverseCandidateCenters(
                for: stage,
                from: neighborhoods,
                references: sortedReferences,
                excluding: selectedIndices
            ) where selectedIndices.count < maximumFrameCount {
                selectedIndices.insert(center)
            }
        }

        for entry in prioritized {
            let additions = entry.indices.subtracting(selectedIndices)
            guard selectedIndices.count + additions.count <= maximumFrameCount else {
                continue
            }
            selectedIndices.formUnion(entry.indices)
        }
        return selectedIndices
            .sorted()
            .map { sortedReferences[$0] }
    }

    private static func diverseCandidateCenters(
        for stage: SwingStage,
        from neighborhoods: [(candidate: StageCandidate, indices: Set<Int>)],
        references: [FineFrameReference],
        excluding excludedIndices: Set<Int>
    ) -> [Int] {
        let entries = neighborhoods
            .filter { $0.candidate.stage == stage }
            .sorted {
                if $0.candidate.score != $1.candidate.score {
                    return $0.candidate.score > $1.candidate.score
                }
                if $0.candidate.time != $1.candidate.time {
                    return $0.candidate.time < $1.candidate.time
                }
                return $0.candidate.sourceFrameIndex < $1.candidate.sourceFrameIndex
            }
        guard let topScore = entries.first?.candidate.score else { return [] }

        var centers: [Int] = []
        for entry in entries {
            guard let center = entry.indices.min(by: {
                let firstDistance = abs(references[$0].time - entry.candidate.time)
                let secondDistance = abs(references[$1].time - entry.candidate.time)
                if firstDistance != secondDistance { return firstDistance < secondDistance }
                return references[$0].sourceFrameIndex < references[$1].sourceFrameIndex
            }) else { continue }
            guard excludedIndices.allSatisfy({
                abs($0 - center) > neighborRadius * 2
            }) else { continue }
            guard centers.allSatisfy({ abs($0 - center) > neighborRadius * 2 }) else {
                continue
            }
            if centers.count >= 2,
               entry.candidate.score < topScore * 0.75 {
                break
            }
            centers.append(center)
            if centers.count == 3 { break }
        }
        return centers
    }

    /// Compatibility bridge for the current player pipeline. Task 6 will pass
    /// the ordered candidates directly after its orchestration migration.
    static func frames(
        from references: [FineFrameReference],
        preliminaryResult: SwingAnalysisResult
    ) -> [FineFrameReference] {
        let candidates = preliminaryResult.detections.enumerated().compactMap {
            evidenceIndex, detection -> StageCandidate? in
            guard let time = detection.time,
                  let nearestReference = references.min(by: {
                      let firstDistance = abs($0.time - time)
                      let secondDistance = abs($1.time - time)
                      if firstDistance != secondDistance {
                          return firstDistance < secondDistance
                      }
                      return $0.sourceFrameIndex < $1.sourceFrameIndex
                  }) else { return nil }
            return StageCandidate(
                stage: detection.stage,
                evidenceIndex: evidenceIndex,
                sourceFrameIndex: detection.sourceFrameIndex ?? nearestReference.sourceFrameIndex,
                time: time,
                score: detection.confidence,
                requirementsSatisfied: detection.status != .unresolved,
                maximumStatus: detection.status,
                hasClubEvidence: detection.hasClubEvidence,
                hasBallEvidence: detection.hasBallEvidence
            )
        }
        return frames(from: references, candidates: candidates)
    }

    private static func neighborhood(
        around time: Double,
        in references: [FineFrameReference]
    ) -> Set<Int> {
        guard let nearest = references.indices.min(by: {
            let firstDistance = abs(references[$0].time - time)
            let secondDistance = abs(references[$1].time - time)
            if firstDistance != secondDistance { return firstDistance < secondDistance }
            return references[$0].sourceFrameIndex < references[$1].sourceFrameIndex
        }) else { return [] }
        let lowerBound = max(references.startIndex, nearest - neighborRadius)
        let upperBound = min(
            references.index(before: references.endIndex),
            nearest + neighborRadius
        )
        return Set(lowerBound...upperBound)
    }

    private static func evenlySpacedFallback(
        from references: [FineFrameReference]
    ) -> [FineFrameReference] {
        let fallbackCount = min(12, references.count)
        let selectedIndices = (0..<fallbackCount).map { offset in
            let fraction = fallbackCount == 1
                ? 0
                : Double(offset) / Double(fallbackCount - 1)
            return Int((fraction * Double(references.count - 1)).rounded())
        }
        return Array(Set(selectedIndices)).sorted().map { references[$0] }
    }
}

enum SwingObjectRegionPolicy {
    static let maximumImageDimension = 256

    /// Returns a normalized Vision ROI. Input points use the app's top-left
    /// coordinate system; Vision expects the ROI origin at the bottom-left.
    static func visionRegion(points: [CGPoint]) -> CGRect {
        let valid = points.filter {
            $0.x.isFinite && $0.y.isFinite &&
                (0...1).contains($0.x) && (0...1).contains($0.y)
        }
        guard let minimumX = valid.map(\.x).min(),
              let maximumX = valid.map(\.x).max(),
              let minimumY = valid.map(\.y).min(),
              let maximumY = valid.map(\.y).max() else {
            return CGRect(x: 0.15, y: 0.06, width: 0.70, height: 0.88)
        }

        let bodyWidth = max(0.10, maximumX - minimumX)
        let bodyHeight = max(0.20, maximumY - minimumY)
        let horizontalPadding = max(0.12, bodyWidth * 1.10)
        let topPadding = max(0.08, bodyHeight * 0.25)
        let bottomPadding = max(0.15, bodyHeight * 0.75)
        let left = max(0, minimumX - horizontalPadding)
        let right = min(1, maximumX + horizontalPadding)
        let top = max(0, minimumY - topPadding)
        let bottom = min(1, maximumY + bottomPadding)
        return CGRect(
            x: left,
            y: 1 - bottom,
            width: max(0.01, right - left),
            height: max(0.01, bottom - top)
        )
    }
}

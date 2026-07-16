import Foundation
import CoreGraphics

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

    init(requiredHits: Int = 3, maximumMisses: Int = 2, seed: BallEvidence? = nil) {
        self.requiredHits = max(1, requiredHits)
        self.maximumMisses = max(0, maximumMisses)
        stableBall = seed
        candidateCenter = seed?.center
        hitCount = seed == nil ? 0 : self.requiredHits
    }

    mutating func update(_ observation: BallEvidence?) -> BallTrackUpdate {
        guard let observation else {
            missCount += 1
            let changed = stableBall == nil ? 0 : 1.0
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
    let objectEvidence: SwingObjectEvidence
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
        let addressIndex = evidence.indices.first { index in
            return stablePast[index]
                && rawDirections[index] == .stable
                && sustainedDirectionBegins(
                    after: index,
                    direction: .backswing,
                    rawDirections: rawDirections,
                    evidence: evidence
                )
        }
        let topIndex = evidence.indices.first { index in
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
        let finishIndex = evidence.indices.first { index in
            guard index > (topIndex ?? addressIndex ?? -1),
                  pastDirections[index] == .backswing else { return false }
            return sustainedStabilityBegins(
                at: index,
                pastDirection: .backswing,
                rawDirections: rawDirections,
                evidence: evidence
            )
        }

        return evidence.indices.map { index in
            let surrounding = uniqueSorted(pastWindows[index] + futureWindows[index])
            return SwingTemporalFrame(
                frame: evidence[index],
                direction: directionVote(
                    indices: surrounding,
                    duration: directionWindow,
                    evidence: evidence
                ),
                sustainedBackswing: futureDirections[index] == .backswing,
                sustainedDownswing: futureDirections[index] == .downswing,
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

    private static func sustainedStabilityBegins(
        at index: Int,
        pastDirection: SwingMotionDirection,
        rawDirections: [SwingMotionDirection?],
        evidence: [SwingFrameEvidence]
    ) -> Bool {
        let indices = timedIndices(startingAt: index, duration: stableWindow, evidence: evidence)
        guard stabilityVote(indices: indices, duration: stableWindow, evidence: evidence) else {
            return false
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
        if frame.leadArm == .unknown { flags.insert(.missingLeadArm) }
        if index > evidence.startIndex,
           labelEndpointsReversed(
               previous: evidence[index - 1].rawPose ?? evidence[index - 1].pose,
               current: frame.rawPose ?? frame.pose
           ) {
            flags.insert(.labelSwapSuspected)
        }
        return flags
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
        AdaptiveBoundaryEvidence(
            hasAddressBoundary: contains(where: \.isAddressBoundary),
            hasFinishBoundary: contains(where: \.isFinishPlateauStart)
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
                rawPose: sortedFrames[index].pose,
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
        for frame in frames {
            guard let pose = frame.pose else { continue }
            leftScore += armScore(shoulder: pose.leftShoulder, elbow: pose.leftElbow, wrist: pose.leftWrist)
            rightScore += armScore(shoulder: pose.rightShoulder, elbow: pose.rightElbow, wrist: pose.rightWrist)
            if let ball = frame.objectEvidence.stableBall,
               let hips = SwingGeometry.center(pose.leftHip, pose.rightHip) {
                if ball.x < hips.x { leftScore += 2 } else { rightScore += 2 }
            }
        }
        let separation = abs(leftScore - rightScore)
        guard separation >= max(2, max(leftScore, rightScore) * 0.03) else { return .unknown }
        return leftScore > rightScore ? .left : .right
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
            let leftComplete = pose.leftShoulder != nil && pose.leftElbow != nil && pose.leftWrist != nil
            return leftComplete
                ? (pose.leftShoulder, pose.leftElbow, pose.leftWrist)
                : (pose.rightShoulder, pose.rightElbow, pose.rightWrist)
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

enum ImpactCorridorResolver {
    private static let minimumCandidateScore = 0.38
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
            guard !followThroughStarted,
                  temporalFrame.sustainedDownswing else { continue }

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
                handNearHip * 0.16
                    + downwardSpeed * 0.15
                    + localAcceleration * 0.09
                    + hipOpen * 0.10
                    + shaftBallAlignment * 0.22
                    + ballLocalChange * 0.11
                    + clamp(temporalFrame.shaftAngleContinuity) * 0.07
                    + clamp(frame.poseCoverage) * 0.10
            )
            guard score >= minimumCandidateScore else { continue }

            let hasRequiredObjects = shaftBallAlignment >= 0.55
                || ballLocalChange >= 0.55
            let objectEvidence = frame.objectEvidence
            candidates.append(StageCandidate(
                stage: .impact,
                evidenceIndex: evidenceIndex,
                sourceFrameIndex: frame.sourceFrameIndex,
                time: frame.time,
                score: score,
                requirementsSatisfied: hasRequiredObjects,
                maximumStatus: hasRequiredObjects ? .confirmed : .lowConfidence,
                hasClubEvidence: objectEvidence.shaft != nil,
                hasBallEvidence: objectEvidence.ball != nil || objectEvidence.stableBall != nil
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
        let p7 = followThroughCandidates(
            after: impact.evidenceIndex,
            impact: impact,
            timeline: timeline
        )
        let p8 = firstFinishPlateauCandidates(after: p7, timeline: timeline)

        return StageCandidateSet(
            impact: impact,
            candidatesByStage: [
                .address: p1,
                .takeaway: p2,
                .leadArmParallelBackswing: p3,
                .top: p4,
                .leadArmParallelDownswing: p5,
                .impact: [impact],
                .followThrough: p7,
                .finish: p8
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
                let score = clamp(
                    armHorizontal * 0.38
                        + armExtended * 0.18
                        + downward * 0.24
                        + hipOpen * 0.12
                        + frame.poseCoverage * 0.08
                )
                guard score >= 0.32 else { return nil }
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
                guard shaftHorizontal != nil || handsBelowShoulders == 1 else { return nil }
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
                        shaftHorizontal * 0.46
                            + handsBelowShoulders * 0.20
                            + backswingSpeed * 0.18
                            + frame.poseCoverage * 0.16
                    )
                } else {
                    score = clamp(
                        handsBelowShoulders * 0.23
                            + backswingSpeed * 0.25
                            + frame.poseCoverage * 0.17
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
                guard temporal.sustainedFollowThrough else { return nil }
                let armHorizontal = closeness(
                    frame.leadArmAngle,
                    target: 0,
                    tolerance: 18
                )
                let shaftHorizontal = frame.objectEvidence.shaft.map {
                    closeness(
                        horizontalAngle($0.angle),
                        target: 0,
                        tolerance: 18
                    ) * clamp($0.confidence)
                } ?? 0
                let parallelEvidence = max(armHorizontal, shaftHorizontal)
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
                    && continuedHipTurn
                    && continuedChestTurn
                let hipTurnScore = ramp(hipContinuation, minimum: 0, maximum: 10)
                let chestTurnScore = ramp(chestContinuation, minimum: 0, maximum: 12)
                let score = clamp(
                    parallelEvidence * 0.34
                        + postImpactRise * 0.23
                        + hipTurnScore * 0.13
                        + chestTurnScore * 0.10
                        + (continuedHipTurn && continuedChestTurn ? 0.10 : 0)
                        + frame.poseCoverage * 0.10
                )
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

    private static func firstFinishPlateauCandidates(
        after earlierCandidates: [StageCandidate],
        timeline: [SwingTemporalFrame]
    ) -> [StageCandidate] {
        guard let lowerBound = earlierCandidates.map(\.evidenceIndex).min(),
              lowerBound < timeline.index(before: timeline.endIndex) else { return [] }
        return retainedCandidates(
            ((lowerBound + 1)..<timeline.endIndex).compactMap { index in
                let temporal = timeline[index]
                guard temporal.isFinishPlateauStart else { return nil }
                let frame = temporal.frame
                let turn = max(
                    ramp(abs(frame.shoulderAngle ?? 0), minimum: 5, maximum: 28),
                    ramp(abs(frame.hipAngle ?? 0), minimum: 8, maximum: 38)
                )
                let score = clamp(
                    0.55
                        + highHandsScore(frame) * 0.15
                        + turn * 0.15
                        + frame.poseCoverage * 0.15
                )
                return candidate(
                    stage: .finish,
                    index: index,
                    score: score,
                    requirementsSatisfied: true,
                    timeline: timeline
                )
            }
        )
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
        return StageCandidate(
            stage: stage,
            evidenceIndex: index,
            sourceFrameIndex: frame.sourceFrameIndex,
            time: frame.time,
            score: clamp(score),
            requirementsSatisfied: requirementsSatisfied,
            maximumStatus: requirementsSatisfied ? .confirmed : .lowConfidence,
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

    init(
        stage: SwingStage,
        time: Double?,
        sourceFrameIndex: Int? = nil,
        confidence: Double,
        status: SwingStageDetectionStatus,
        hasClubEvidence: Bool = false,
        hasBallEvidence: Bool = false
    ) {
        self.stage = stage
        self.time = time
        self.sourceFrameIndex = sourceFrameIndex
        self.confidence = confidence
        self.status = status
        self.hasClubEvidence = hasClubEvidence
        self.hasBallEvidence = hasBallEvidence
    }

    var marker: KeyframeMarker? {
        guard let time, status != .unresolved else { return nil }
        return KeyframeMarker(time: time, stage: stage, source: .automatic)
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
                let scored = ScoredPath(
                    candidates: path,
                    total: evidenceScore + transitionScore - missingPenalty
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
        let detections = zip(SwingStage.allCases, best.candidates).map {
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
            let status: SwingStageDetectionStatus
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
            return SwingStageDetection(
                stage: stage,
                time: status == .unresolved ? nil : candidate.time,
                sourceFrameIndex: status == .unresolved
                    ? nil
                    : candidate.sourceFrameIndex,
                confidence: confidence,
                status: status,
                hasClubEvidence: candidate.hasClubEvidence,
                hasBallEvidence: candidate.hasBallEvidence
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
        let stages = SwingStage.allCases
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
        case .leadArmParallelDownswing, .impact:
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
        guard path.count == SwingStage.allCases.count,
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
            && frames[6].sustainedFollowThrough
            && path[6].evidenceIndex > path[5].evidenceIndex
            && frames[7].isFinishPlateauStart
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
            through: path[5].evidenceIndex,
            timeline: timeline,
            matches: { $0.sustainedDownswing }
        )
        let followThrough = durationWeightedSupport(
            from: path[5].evidenceIndex,
            through: path[6].evidenceIndex,
            timeline: timeline,
            matches: { $0.sustainedFollowThrough }
        )
        let topTime = path[3].time
        let topPlateau = elapsedStabilitySupport(
            from: topTime - 0.08,
            through: topTime,
            timeline: timeline
        )
        let finishTime = path[7].time
        let finishPlateau = elapsedStabilitySupport(
            from: finishTime,
            through: finishTime + SwingEvidenceTimeline.stableWindow,
            timeline: timeline
        )
        return backswing * 0.20
            + downswing * 0.25
            + followThrough * 0.20
            + topPlateau * 0.10
            + finishPlateau * 0.15
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

    private static func unresolvedResult() -> SwingAnalysisResult {
        let detections = SwingStage.allCases.map(unresolvedDetection)
        return SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: Set(SwingStage.allCases),
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
    case noStableGolfer
    case noSwingMotion
    case ambiguousSwingWindows
    case swingWindowTooLong
    case frameExtractionFailed
    case missingAddressBoundary
    case missingTopTransition
    case noImpactCorridor
    case missingFinishBoundary
    case incompleteSwingClip
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
            unresolvedStages = Set(SwingStage.allCases)
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
        guard evidence.count >= SwingStage.allCases.count,
              zip(evidence, evidence.dropFirst()).allSatisfy({ $0.time < $1.time }) else {
            return unresolvedResult()
        }

        let stages = SwingStage.allCases
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

        if let followThroughStageIndex = stages.firstIndex(of: .followThrough),
           let finishStageIndex = stages.firstIndex(of: .finish) {
            let firstPostFollowThrough = selected[followThroughStageIndex] + 1
            if firstPostFollowThrough < evidence.count,
               let earliestFinish = (firstPostFollowThrough..<evidence.count).first(where: {
                   isStableFinish(startingAt: $0, evidence: evidence)
               }) {
                selected[finishStageIndex] = earliestFinish
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

        case .impact:
            let handNearHip = distance(frame.handCenter, frame.hipCenter).map {
                1 - min(1, $0 / 0.24)
            } ?? 0
            let shaftBall = shaftBallScore(frame.objectEvidence)
            let ballChange = min(1, frame.objectEvidence.ballLocalChange)
            return clamp(handNearHip * 0.17 + downward * 0.16 + shaftBall * 0.32 + ballChange * 0.16 + coverage * 0.19)

        case .followThrough:
            return clamp(armHorizontal * 0.28 + upward * 0.27 + hipTurn * 0.17 + shaftHorizontal * 0.13 + coverage * 0.15)

        case .finish:
            let stable = isStableFinish(startingAt: index, evidence: evidence) ? 1.0 : 0.0
            let highHands = (handY != nil && shoulderY != nil && handY! < shoulderY!) ? 1.0 : 0.0
            return clamp(stable * 0.55 + highHands * 0.15 + max(shoulderTurn, hipTurn) * 0.15 + coverage * 0.15)
        }
    }

    private static func isStableFinish(
        startingAt index: Int,
        evidence: [SwingFrameEvidence]
    ) -> Bool {
        let start = evidence[index]
        guard isLocallyStable(start) else { return false }
        let targetDuration = 0.30
        let minimumObservedDuration = 0.25
        var observed = 0
        var stable = 0
        var lastTime = start.time
        for candidate in evidence[index...] {
            guard candidate.time - start.time <= targetDuration + 0.001 else { break }
            observed += 1
            if isLocallyStable(candidate) { stable += 1 }
            lastTime = candidate.time
        }
        guard lastTime - start.time >= minimumObservedDuration, observed > 0 else { return false }
        return Double(stable) / Double(observed) >= 0.75
    }

    private static func isLocallyStable(_ frame: SwingFrameEvidence) -> Bool {
        frame.headSpeed <= 0.08 &&
            frame.hipSpeed <= 0.08 &&
            hypot(Double(frame.handVelocity.x), Double(frame.handVelocity.y)) <= 0.18
    }

    private static func shaftBallScore(_ object: SwingObjectEvidence) -> Double {
        guard let shaft = object.shaft, let ball = object.stableBall else { return 0 }
        let alignment = 1 - min(1, shaft.distanceFromExtendedLine(to: ball) / 0.08)
        return clamp(alignment * shaft.confidence)
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
        let detections = SwingStage.allCases.map {
            SwingStageDetection(stage: $0, time: nil, confidence: 0, status: .unresolved)
        }
        return SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: Set(SwingStage.allCases),
            detections: detections
        )
    }
}

enum SwingStageDetector {
    private static let finishStabilityThreshold: CGFloat = 0.04
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

    static func detect(samples rawSamples: [SwingPoseSample]) -> SwingAnalysisResult {
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

        // Repeated video frames at P1 and P4 are normal.  Choose the latest
        // address plateau before the top, then select observed one-third and
        // two-third samples along that measured ascent instead of requiring
        // three immediately-adjacent, strictly decreasing frames.
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
            if p1Index < p2Index, p2Index < p3Index, p3Index < p4Index,
               p1.wristY > p2.wristY,
               p2.wristY > p3.wristY,
               p3.wristY > p4.wristY {
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

            // P6 couples 2D hand velocity with the hands' position over the
            // hip centre. Vertical velocity alone fires too early in a steep
            // downswing, before the club reaches the ball.
            if let p6Index = impactIndex(after: p5Index, in: samples) {
                resolved[.impact] = samples[p6Index]

                // P7 must similarly demonstrate a sustained rising hand path,
                // so one noisy post-impact frame cannot create a false follow-through.
                if let p7Index = sustainedFollowThroughIndex(after: p6Index, in: samples) {
                    resolved[.followThrough] = samples[p7Index]

                    // A clip may continue long after the golfer finishes, so
                    // P8 is the first stable post-P7 plateau, never simply the
                    // last frame of the source video.
                    if let p8Index = finishIndex(after: p7Index, in: samples) {
                        let finish = samples[p8Index]
                        resolved[.finish] = finish
                    }
                }
            }
        }

        let detections = SwingStage.allCases.map { stage -> SwingStageDetection in
            guard let sample = resolved[stage] else {
                return SwingStageDetection(stage: stage, time: nil, confidence: 0, status: .unresolved)
            }
            let confidence = evidenceConfidence(for: stage, sample: sample)
            let status: SwingStageDetectionStatus
            if confidence >= 0.75 {
                status = .confirmed
            } else if confidence >= 0.45 {
                status = .lowConfidence
            } else {
                status = .unresolved
            }
            return SwingStageDetection(
                stage: stage,
                time: status == .unresolved ? nil : sample.time,
                confidence: confidence,
                status: status
            )
        }
        let markers = detections.compactMap(\.marker)
        let unresolved = Set(detections.filter { $0.status == .unresolved }.map(\.stage))
        return SwingAnalysisResult(detectedMarkers: markers, unresolvedStages: unresolved, detections: detections)
    }

    private static func unresolvedResult() -> SwingAnalysisResult {
        let detections = SwingStage.allCases.map {
            SwingStageDetection(stage: $0, time: nil, confidence: 0, status: .unresolved)
        }
        return SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: Set(SwingStage.allCases),
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
        case .leadArmParallelDownswing, .impact, .followThrough, .finish:
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

    private static func sustainedFollowThroughIndex(after impactIndex: Int, in samples: [SwingPoseSample]) -> Int? {
        guard impactIndex + 2 < samples.count else { return nil }
        return ((impactIndex + 1)..<(samples.count - 1)).first { index in
            samples[index].wristY < samples[impactIndex].wristY - directionChangeThreshold &&
            samples[index + 1].wristY < samples[index].wristY - directionChangeThreshold
        }
    }

    private static func finishIndex(after followThroughIndex: Int, in samples: [SwingPoseSample]) -> Int? {
        guard followThroughIndex + 2 < samples.count else { return nil }
        return ((followThroughIndex + 1)..<(samples.count - 1)).first { index in
            let first = samples[index]
            let second = samples[index + 1]
            return first.wristY < samples[followThroughIndex].wristY - directionChangeThreshold &&
                abs(second.wristY - first.wristY) <= finishStabilityThreshold
        }.map { $0 + 1 }
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

        let candidates = (2..<(samples.count - 2)).compactMap { index -> (index: Int, score: CGFloat)? in
            let candidateY = samples[index].wristY
            let priorHigh = samples[..<index].map(\.wristY).max() ?? candidateY
            let followingRange = (index + 1)...min(samples.count - 1, index + 3)
            let followingLowHand = samples[followingRange].map(\.wristY).max() ?? candidateY
            guard priorHigh > candidateY + directionChangeThreshold,
                  followingLowHand > candidateY + directionChangeThreshold else {
                return nil
            }
            return (index, (priorHigh - candidateY) + (followingLowHand - candidateY))
        }

        return candidates.max { lhs, rhs in
            lhs.score == rhs.score ? lhs.index > rhs.index : lhs.score < rhs.score
        }?.index
    }
}

/// Keeps full-swing analysis dense enough to resolve the short motion interval
/// inside a much longer imported video.  Twelve samples per second gives the
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
    let hasFinishBoundary: Bool
}

enum AdaptiveSwingWindowAction: Equatable {
    case expand(SwingWindow)
    case ready(SwingWindow)
    case failed(AnalysisFailure)
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
        if evidence.hasAddressBoundary && evidence.hasFinishBoundary { return .ready(current) }
        if current.duration >= maximumSpan {
            return .failed(
                evidence.hasAddressBoundary ? .missingFinishBoundary : .missingAddressBoundary
            )
        }
        if !evidence.hasAddressBoundary {
            guard current.startTime > 0 else { return .failed(.incompleteSwingClip) }
            return .expand(SwingWindow(
                startTime: max(0, current.startTime - expansionStep),
                endTime: current.endTime
            ))
        }
        guard current.endTime < duration else { return .failed(.incompleteSwingClip) }
        return .expand(SwingWindow(
            startTime: current.startTime,
            endTime: min(duration, current.endTime + expansionStep)
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
    private static let bridgeGapDuration = 0.5
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

        let hands = samples.map { $0.pose.flatMap(handCenter) }
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
        let median = nonZero[nonZero.count / 2]
        let peak = nonZero.last ?? 0
        let threshold = max(0.30, min(peak * 0.45, median * 2.2))
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
    static let maximumSamplesPerSecond = 120.0

    static func frames(
        window: SwingWindow,
        sourceFrameRate: Double,
        duration: Double
    ) -> [FineFrameReference] {
        guard sourceFrameRate.isFinite,
              sourceFrameRate > 0,
              duration.isFinite,
              duration > 0,
              window.duration > 0 else { return [] }

        let boundedStart = max(0, min(window.startTime, duration))
        let boundedEnd = max(boundedStart, min(window.endTime, duration))
        let firstFrame = Int(ceil(boundedStart * sourceFrameRate))
        let lastFrame = Int(floor(boundedEnd * sourceFrameRate))
        guard firstFrame <= lastFrame else { return [] }

        let frameStride = max(1, Int(ceil(sourceFrameRate / maximumSamplesPerSecond)))
        var references = stride(from: firstFrame, through: lastFrame, by: frameStride).map {
            FineFrameReference(sourceFrameIndex: $0, time: Double($0) / sourceFrameRate)
        }
        if references.last?.sourceFrameIndex != lastFrame,
           Double(lastFrame - (references.last?.sourceFrameIndex ?? firstFrame)) / sourceFrameRate >= 1.0 / maximumSamplesPerSecond {
            references.append(FineFrameReference(sourceFrameIndex: lastFrame, time: Double(lastFrame) / sourceFrameRate))
        }
        return references
    }
}

enum SparseObjectSamplingPlan {
    static let maximumFrameCount = 32
    private static let neighborRadius = 1
    private static let sampledStages: Set<SwingStage> = [
        .address,
        .takeaway,
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

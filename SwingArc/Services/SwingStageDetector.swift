import Foundation

struct SwingPoseSample: Equatable {
    let time: Double
    let leftWrist: CGPoint?
    let rightWrist: CGPoint?
    let leftElbow: CGPoint?
    let rightElbow: CGPoint?
    let leftShoulder: CGPoint?
    let rightShoulder: CGPoint?
    let leftHip: CGPoint?
    let rightHip: CGPoint?
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
            aggregateConfidence: 1
        )
    }

    init(
        time: Double,
        leftWrist: CGPoint?, rightWrist: CGPoint?,
        leftElbow: CGPoint?, rightElbow: CGPoint?,
        leftShoulder: CGPoint?, rightShoulder: CGPoint?,
        leftHip: CGPoint?, rightHip: CGPoint?,
        head: CGPoint?, spineAngle: Double?, aggregateConfidence: Float
    ) {
        self.time = time
        self.leftWrist = leftWrist
        self.rightWrist = rightWrist
        self.leftElbow = leftElbow
        self.rightElbow = rightElbow
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        self.leftHip = leftHip
        self.rightHip = rightHip
        self.head = head
        self.spineAngle = spineAngle
        self.aggregateConfidence = aggregateConfidence
    }

    var wristY: CGFloat { rightWrist?.y ?? leftWrist?.y ?? .nan }
}

enum SwingStageDetectionStatus: String, Codable, Equatable {
    case confirmed
    case lowConfidence
    case unresolved
}

struct SwingStageDetection: Equatable {
    let stage: SwingStage
    let time: Double?
    let confidence: Double
    let status: SwingStageDetectionStatus

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

enum AnalysisFailure: Equatable {
    case noVideo
    case invalidDuration
    case insufficientPoseEvidence
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

enum SwingStageDetector {
    private static let finishStabilityThreshold: CGFloat = 0.04
    private static let directionChangeThreshold: CGFloat = 0.015

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

        // P5 requires a sustained transition out of the P4 plateau. A single
        // lower hand frame is commonly pose jitter, not the downswing.
        if let p5Index = sustainedDownswingIndex(after: p4Index, in: samples) {
            resolved[.leadArmParallelDownswing] = samples[p5Index]

            // P6 is the fastest hand movement through the hip zone, rather
            // than the lowest observed wrist. That avoids a slow post-impact
            // dip being reported as impact.
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

    private static func sustainedDownswingIndex(after topIndex: Int, in samples: [SwingPoseSample]) -> Int? {
        guard topIndex + 2 < samples.count else { return nil }
        return ((topIndex + 1)..<(samples.count - 1)).first { index in
            samples[index].wristY > samples[topIndex].wristY + directionChangeThreshold &&
            samples[index + 1].wristY > samples[index].wristY + directionChangeThreshold
        }
    }

    private static func impactIndex(after downswingIndex: Int, in samples: [SwingPoseSample]) -> Int? {
        guard downswingIndex + 1 < samples.count else { return nil }
        let finalIndices = (samples.count - 3)..<samples.count
        let candidates = ((downswingIndex + 1)..<(samples.count - 1)).filter { index in
            guard !finalIndices.contains(index),
                  let hipY = midpointY(samples[index].leftHip, samples[index].rightHip) else {
                return false
            }
            return abs(samples[index].wristY - hipY) <= 0.35
        }
        return candidates.max { left, right in
            handSpeed(at: left, in: samples) < handSpeed(at: right, in: samples)
        }
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
        return abs(samples[index].wristY - samples[index - 1].wristY) / elapsed
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
    static let samplesPerSecond = 12.0

    static func sampleTimes(duration: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        let interval = 1.0 / samplesPerSecond
        let intervals = max(1, Int(ceil(duration / interval)))
        return (0...intervals).map { index in
            min(duration, Double(index) * interval)
        }
    }
}

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
        guard let p4Index = samples.indices.min(by: { samples[$0].wristY < samples[$1].wristY }) else {
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

        // The first measurable reversal after P4 is P5.  Do not assume it is
        // the next frame: high-frame-rate clips often contain a P4 plateau.
        if let p5Index = samples.indices.first(where: {
            $0 > p4Index && samples[$0].wristY > samples[p4Index].wristY + directionChangeThreshold
        }) {
            resolved[.leadArmParallelDownswing] = samples[p5Index]

            let finalIndices = (samples.count - 3)..<samples.count
            let impactCandidates = samples.indices.filter { $0 >= p5Index && !finalIndices.contains($0) }
            if let p6Index = impactCandidates.max(by: { samples[$0].wristY < samples[$1].wristY }),
               samples[p6Index].wristY > samples[p5Index].wristY {
                resolved[.impact] = samples[p6Index]

                if let p7Index = samples.indices.first(where: {
                    $0 > p6Index && samples[$0].wristY < samples[p6Index].wristY - directionChangeThreshold
                }) {
                    resolved[.followThrough] = samples[p7Index]

                    let penultimate = samples[samples.count - 2]
                    let finish = samples[samples.count - 1]
                    if abs(penultimate.wristY - finish.wristY) <= finishStabilityThreshold,
                       finish.wristY < samples[p7Index].wristY {
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

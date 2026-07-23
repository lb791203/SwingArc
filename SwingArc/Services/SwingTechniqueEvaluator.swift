import Foundation
import CoreGraphics

enum SwingTechniqueKind: String, Equatable {
    case postureLoss
    case overTheTop
    case chickenWing
}

enum TechniqueSeverity: Equatable {
    case attention
    case significant
}

struct TechniqueEvidence: Equatable {
    let stages: [SwingStage]
    let normalizedMagnitude: Double
}

struct TechniqueFinding: Equatable {
    let kind: SwingTechniqueKind
    let severity: TechniqueSeverity
    let evidence: TechniqueEvidence
}

struct TechniqueFeedbackPresentation: Equatable {
    let title: String
    let detail: String
    let evidenceStages: [SwingStage]
    let drill: DrillRecommendation?
    let showsEvidence: Bool

    static func make(
        feedback: PriorityFeedback,
        analysis: SwingAnalysisResult
    ) -> TechniqueFeedbackPresentation {
        switch feedback {
        case let .finding(finding):
            let title: String
            let detail: String
            switch finding.kind {
            case .postureLoss:
                title = "上杆时身体有起身趋势"
                detail = "请先保持头部与躯干角度稳定，再提高挥杆速度。"
            case .overTheTop:
                title = "下杆略偏外"
                detail = "先让手臂从身体内侧落下，避免急着把杆推向目标线。"
            case .chickenWing:
                title = "送杆手臂略收紧"
                detail = "让引导手臂在击球后自然伸展，再完成转身。"
            }
            let showsEvidence = finding.evidence.stages.allSatisfy { stage in
                analysis.detections.contains {
                    $0.stage == stage && $0.status == .confirmed && $0.sourceFrameIndex != nil
                }
            }
            return TechniqueFeedbackPresentation(
                title: title,
                detail: detail,
                evidenceStages: finding.evidence.stages,
                drill: showsEvidence ? DrillRecommendation.forFinding(finding) : nil,
                showsEvidence: showsEvidence
            )
        case .unresolved:
            let missing = analysis.unresolvedStages
                .sorted { $0.rawValue < $1.rawValue }
                .first
                .map(stageReference) ?? "关键帧"
            return TechniqueFeedbackPresentation(
                title: "本球未能判定",
                detail: "\(missing) 的人体或动作证据不足；不会给出猜测性的纠错建议。",
                evidenceStages: [],
                drill: nil,
                showsEvidence: false
            )
        }
    }

    nonisolated private static func stageReference(_ stage: SwingStage) -> String {
        switch stage {
        case .address: return "P1"
        case .takeaway: return "P2"
        case .leadArmParallelBackswing: return "P3"
        case .top: return "P4"
        case .leadArmParallelDownswing: return "P5"
        case .shaftParallelDownswing: return "P6"
        case .impact: return "P7"
        case .followThrough: return "P8"
        case .finish: return "收杆（兼容）"
        }
    }
}

/// Manual P-point edits are the truth for the current video. A corrected
/// source frame may participate in technique evaluation only when that exact
/// Vision sample exists; otherwise its low-confidence state intentionally
/// withholds the diagnosis rather than borrowing a neighbouring frame.
enum ManualStageDetectionPolicy {
    static func applying(
        manualMarkers: [KeyframeMarker],
        sourceFrameRate: Double,
        automatic: [SwingStageDetection],
        availablePoseSamples: [SwingPoseSample]
    ) -> [SwingStageDetection] {
        guard sourceFrameRate.isFinite, sourceFrameRate > 0 else { return automatic }
        var manualByStage: [SwingStage: KeyframeMarker] = [:]
        for marker in manualMarkers where marker.source == .manual {
            guard let stage = SwingStage(rawValue: marker.stage) else { continue }
            manualByStage[stage] = marker
        }
        let availableFrames = Set(availablePoseSamples.compactMap(\.sourceFrameIndex))
        return automatic.map { detection in
            guard let marker = manualByStage[detection.stage] else { return detection }
            let frame = Int((marker.time * sourceFrameRate).rounded())
            return SwingStageDetection(
                stage: detection.stage,
                time: marker.time,
                sourceFrameIndex: frame,
                confidence: availableFrames.contains(frame) ? 1 : 0,
                status: availableFrames.contains(frame) ? .confirmed : .lowConfidence,
                hasClubEvidence: detection.hasClubEvidence,
                hasBallEvidence: detection.hasBallEvidence,
                hasBallChangeEvidence: detection.hasBallChangeEvidence
            )
        }
    }
}

/// Conservative, pure geometry checks. The evaluator never invents a finding:
/// missing confirmed stages, low pose confidence, or an unsupported camera view
/// produce no result and are presented as unresolved by the caller.
enum SwingTechniqueEvaluator {
    static let minimumAggregateConfidence: Float = 0.65

    static func measuredMetricEvidence(
        _ id: SwingMetricID,
        metrics: [SwingMetricValue]
    ) -> Double? {
        guard id.isMotionAnalysisOutput,
              let metric = metrics.first(where: { $0.id == id }),
              metric.availability == .measured,
              metric.confidence >= Double(minimumAggregateConfidence),
              let value = metric.value,
              value.isFinite else { return nil }
        return value
    }

    static func evaluate(
        samples: [SwingPoseSample],
        stages: [SwingStageDetection],
        view: PracticeCameraView,
        leadArm: LeadArmSide
    ) -> [TechniqueFinding] {
        let stageSamples = stageSamples(samples: samples, stages: stages)
        var findings: [TechniqueFinding] = []
        if let finding = postureLoss(in: stageSamples) {
            findings.append(finding)
        }
        if view == .downTheLine, let finding = overTheTop(in: stageSamples) {
            findings.append(finding)
        }
        if view == .faceOn, let finding = chickenWing(in: stageSamples, leadArm: leadArm) {
            findings.append(finding)
        }
        return findings.sorted { severityRank($0.severity) > severityRank($1.severity) }
    }

    private static func postureLoss(
        in samples: [SwingStage: SwingPoseSample]
    ) -> TechniqueFinding? {
        guard let address = valid(samples[.address]),
              let top = valid(samples[.top]),
              let impact = valid(samples[.impact]),
              let addressTorso = torsoLength(address),
              addressTorso > 0,
              let addressAngle = address.spineAngle,
              let topAngle = top.spineAngle,
              let impactAngle = impact.spineAngle,
              let addressHead = address.head,
              let topHead = top.head,
              let impactHead = impact.head else {
            return nil
        }
        let angleChange = max(abs(topAngle - addressAngle), abs(impactAngle - addressAngle))
        let headShift = max(distance(addressHead, topHead), distance(addressHead, impactHead)) / addressTorso
        guard angleChange >= 5 || headShift >= 0.12 else { return nil }
        let magnitude = max(angleChange / 10, headShift / 0.20)
        return TechniqueFinding(
            kind: .postureLoss,
            severity: magnitude >= 1 ? .significant : .attention,
            evidence: TechniqueEvidence(
                stages: [.address, .top, .impact],
                normalizedMagnitude: magnitude
            )
        )
    }

    private static func overTheTop(
        in samples: [SwingStage: SwingPoseSample]
    ) -> TechniqueFinding? {
        guard let takeaway = valid(samples[.takeaway]),
              let top = valid(samples[.top]),
              let impact = valid(samples[.impact]),
              let torso = torsoLength(impact), torso > 0,
              let takeawayHand = handCenter(takeaway),
              let topHand = handCenter(top),
              let impactHand = handCenter(impact),
              let impactHip = hipCenter(impact) else {
            return nil
        }
        let backswingOffset = abs(Double(topHand.x - takeawayHand.x))
        let downswingOffset = abs(Double(impactHand.x - impactHip.x))
        let externalIncrease = (downswingOffset - backswingOffset) / torso
        guard externalIncrease >= 0.18 else { return nil }
        return TechniqueFinding(
            kind: .overTheTop,
            severity: externalIncrease >= 0.35 ? .significant : .attention,
            evidence: TechniqueEvidence(
                stages: [.takeaway, .top, .impact],
                normalizedMagnitude: externalIncrease
            )
        )
    }

    private static func chickenWing(
        in samples: [SwingStage: SwingPoseSample],
        leadArm: LeadArmSide
    ) -> TechniqueFinding? {
        guard leadArm != .unknown,
              let impact = valid(samples[.impact]),
              let followThrough = valid(samples[.followThrough]),
              let torso = torsoLength(followThrough), torso > 0,
              let points = armPoints(for: leadArm, sample: followThrough),
              let shoulder = points.shoulder,
              let elbow = points.elbow,
              let wrist = points.wrist,
              let torsoCenter = torsoCenter(followThrough) else {
            return nil
        }
        let angle = jointAngle(first: shoulder, vertex: elbow, third: wrist)
        let elbowOutward = distance(elbow, torsoCenter) / torso
        let impactAngle: Double
        if let impactPoints = armPoints(for: leadArm, sample: impact),
           let impactShoulder = impactPoints.shoulder,
           let impactElbow = impactPoints.elbow,
           let impactWrist = impactPoints.wrist {
            impactAngle = jointAngle(
                first: impactShoulder,
                vertex: impactElbow,
                third: impactWrist
            )
        } else {
            impactAngle = angle
        }
        let armAngle = min(angle, impactAngle)
        guard armAngle < 160, elbowOutward >= 0.30 else { return nil }
        let magnitude = max((160 - armAngle) / 40, elbowOutward / 0.55)
        return TechniqueFinding(
            kind: .chickenWing,
            severity: magnitude >= 1 ? .significant : .attention,
            evidence: TechniqueEvidence(
                stages: [.impact, .followThrough],
                normalizedMagnitude: magnitude
            )
        )
    }

    private static func stageSamples(
        samples: [SwingPoseSample],
        stages: [SwingStageDetection]
    ) -> [SwingStage: SwingPoseSample] {
        let samplesByFrame = Dictionary(uniqueKeysWithValues: samples.compactMap { sample in
            sample.sourceFrameIndex.map { ($0, sample) }
        })
        return Dictionary(uniqueKeysWithValues: stages.compactMap { detection in
            guard detection.status == .confirmed,
                  let frame = detection.sourceFrameIndex,
                  let sample = samplesByFrame[frame] else {
                return nil
            }
            return (detection.stage, sample)
        })
    }

    private static func valid(_ sample: SwingPoseSample?) -> SwingPoseSample? {
        guard let sample, sample.aggregateConfidence >= minimumAggregateConfidence else { return nil }
        return sample
    }

    private static func armPoints(
        for side: LeadArmSide,
        sample: SwingPoseSample
    ) -> (shoulder: CGPoint?, elbow: CGPoint?, wrist: CGPoint?)? {
        switch side {
        case .left:
            return (sample.leftShoulder, sample.leftElbow, sample.leftWrist)
        case .right:
            return (sample.rightShoulder, sample.rightElbow, sample.rightWrist)
        case .unknown:
            return nil
        }
    }

    private static func torsoCenter(_ sample: SwingPoseSample) -> CGPoint? {
        guard let shoulders = center(sample.leftShoulder, sample.rightShoulder),
              let hips = hipCenter(sample) else { return nil }
        return CGPoint(x: (shoulders.x + hips.x) / 2, y: (shoulders.y + hips.y) / 2)
    }

    private static func hipCenter(_ sample: SwingPoseSample) -> CGPoint? {
        center(sample.leftHip, sample.rightHip)
    }

    private static func torsoLength(_ sample: SwingPoseSample) -> Double? {
        guard let shoulders = center(sample.leftShoulder, sample.rightShoulder),
              let hips = hipCenter(sample) else { return nil }
        return distance(shoulders, hips)
    }

    private static func handCenter(_ sample: SwingPoseSample) -> CGPoint? {
        center(sample.leftWrist, sample.rightWrist)
    }

    private static func center(_ first: CGPoint?, _ second: CGPoint?) -> CGPoint? {
        guard let first, let second else { return nil }
        return CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> Double {
        hypot(Double(first.x - second.x), Double(first.y - second.y))
    }

    private static func jointAngle(first: CGPoint, vertex: CGPoint, third: CGPoint) -> Double {
        let firstVector = (x: Double(first.x - vertex.x), y: Double(first.y - vertex.y))
        let secondVector = (x: Double(third.x - vertex.x), y: Double(third.y - vertex.y))
        let denominator = hypot(firstVector.x, firstVector.y) * hypot(secondVector.x, secondVector.y)
        guard denominator > .leastNonzeroMagnitude else { return 180 }
        let cosine = max(-1, min(1, (firstVector.x * secondVector.x + firstVector.y * secondVector.y) / denominator))
        return acos(cosine) * 180 / .pi
    }

    private static func severityRank(_ severity: TechniqueSeverity) -> Int {
        severity == .significant ? 1 : 0
    }
}

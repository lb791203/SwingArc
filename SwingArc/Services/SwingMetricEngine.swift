import Foundation

struct SwingTempo: Equatable {
    let backswingSeconds: Double
    let downswingSeconds: Double
    let ratio: Double
}

enum SwingMetricEngine {
    static let minimumMeasuredConfidence = 0.65

    static func tempo(
        addressTime: Double,
        topTime: Double,
        impactTime: Double
    ) -> SwingTempo? {
        let backswing = topTime - addressTime
        let downswing = impactTime - topTime
        guard backswing.isFinite,
              downswing.isFinite,
              backswing > 0,
              downswing > 0 else { return nil }
        return SwingTempo(
            backswingSeconds: backswing,
            downswingSeconds: downswing,
            ratio: backswing / downswing
        )
    }

    static func jointAngle(
        first: NormalizedPoint,
        vertex: NormalizedPoint,
        third: NormalizedPoint
    ) -> Double? {
        let firstVector = (
            x: first.x - vertex.x,
            y: first.y - vertex.y
        )
        let secondVector = (
            x: third.x - vertex.x,
            y: third.y - vertex.y
        )
        let denominator = hypot(firstVector.x, firstVector.y)
            * hypot(secondVector.x, secondVector.y)
        guard denominator.isFinite,
              denominator > .leastNonzeroMagnitude else { return nil }
        let cosine = min(
            1,
            max(
                -1,
                (
                    firstVector.x * secondVector.x
                    + firstVector.y * secondVector.y
                ) / denominator
            )
        )
        return acos(cosine) * 180 / .pi
    }

    static func projectionAngle(
        start: NormalizedPoint,
        end: NormalizedPoint
    ) -> Double? {
        let x = end.x - start.x
        let y = end.y - start.y
        guard x.isFinite,
              y.isFinite,
              hypot(x, y) > .leastNonzeroMagnitude else { return nil }
        return atan2(y, x) * 180 / .pi
    }

    static func normalizedDisplacement(
        id: SwingMetricID,
        from start: TrackedSwingPoint,
        to end: TrackedSwingPoint,
        personHeight: Double,
        axis: KeyPath<NormalizedPoint, Double>,
        stage: String? = nil
    ) -> SwingMetricValue {
        guard personHeight.isFinite, personHeight > 0 else {
            return unavailable(
                id: id,
                unit: "person-height",
                reason: .missingEvidence,
                stage: stage
            )
        }
        if let failure = inputFailure([start, end]) {
            return unavailable(
                id: id,
                unit: "person-height",
                reason: failure,
                stage: stage
            )
        }
        guard let startPoint = start.point,
              let endPoint = end.point else {
            return unavailable(
                id: id,
                unit: "person-height",
                reason: .missingEvidence,
                stage: stage
            )
        }
        return SwingMetricValue(
            id: id,
            value: (
                endPoint[keyPath: axis] - startPoint[keyPath: axis]
            ) / personHeight,
            unit: "person-height",
            confidence: min(start.confidence, end.confidence),
            stage: stage,
            availability: .measured
        )
    }

    static func pathLength(
        landmark: SwingLandmark,
        frames: [SwingFrameObservation],
        personHeight: Double,
        id: SwingMetricID
    ) -> SwingMetricValue {
        guard personHeight.isFinite,
              personHeight > 0,
              frames.count >= 2 else {
            return unavailable(
                id: id,
                unit: "person-height",
                reason: .missingEvidence
            )
        }
        let sorted = frames.sorted {
            $0.time == $1.time
                ? $0.sourceFrameIndex < $1.sourceFrameIndex
                : $0.time < $1.time
        }
        let points = sorted.compactMap { $0.landmarks[landmark] }
        guard points.count == sorted.count else {
            return unavailable(
                id: id,
                unit: "person-height",
                reason: .missingEvidence
            )
        }
        if let failure = inputFailure(points) {
            return unavailable(
                id: id,
                unit: "person-height",
                reason: failure
            )
        }
        let length = zip(points, points.dropFirst()).reduce(0.0) {
            total,
            pair in
            guard let start = pair.0.point,
                  let end = pair.1.point else { return total }
            return total + hypot(
                end.x - start.x,
                end.y - start.y
            ) / personHeight
        }
        return SwingMetricValue(
            id: id,
            value: length,
            unit: "person-height",
            confidence: points.map(\.confidence).min() ?? 0,
            stage: nil,
            availability: .measured
        )
    }

    static func normalizedRelativeSpeed2D(
        landmark: SwingLandmark,
        frames: [SwingFrameObservation],
        personHeight: Double
    ) -> SwingMetricValue {
        let path = pathLength(
            landmark: landmark,
            frames: frames,
            personHeight: personHeight,
            id: .clubheadRelativeSpeed2D
        )
        guard path.availability == .measured,
              let distance = path.value,
              let first = frames.min(by: { $0.time < $1.time }),
              let last = frames.max(by: { $0.time < $1.time }) else {
            return SwingMetricValue(
                id: .clubheadRelativeSpeed2D,
                value: nil,
                unit: "person-height/s",
                confidence: path.confidence,
                stage: nil,
                availability: path.availability
            )
        }
        let duration = last.time - first.time
        guard duration.isFinite, duration > 0 else {
            return unavailable(
                id: .clubheadRelativeSpeed2D,
                unit: "person-height/s",
                reason: .missingEvidence
            )
        }
        return SwingMetricValue(
            id: .clubheadRelativeSpeed2D,
            value: distance / duration,
            unit: "person-height/s",
            confidence: path.confidence,
            stage: nil,
            availability: .measured
        )
    }

    static func motionMeasurements(
        frames: [SwingFrameObservation],
        stages: [SwingStageDetection],
        personHeight: Double
    ) -> [SwingMetricValue] {
        var confirmedFrames: [SwingStage: Int] = [:]
        for detection in stages {
            guard detection.status == .confirmed,
                  detection.confidence >= minimumMeasuredConfidence,
                  let sourceFrameIndex = detection.sourceFrameIndex else {
                continue
            }
            confirmedFrames[detection.stage] = sourceFrameIndex
        }
        let framesByIndex = frames.reduce(
            into: [Int: SwingFrameObservation]()
        ) {
            $0[$1.sourceFrameIndex] = $1
        }
        var result: [SwingMetricValue] = []

        if let address = confirmedTime(.address, in: stages),
           let top = confirmedTime(.top, in: stages),
           let impact = confirmedTime(.impact, in: stages),
           let swingTempo = tempo(
                addressTime: address,
                topTime: top,
                impactTime: impact
           ) {
            let overallConfidence = minimumStageConfidence(
                [.address, .top, .impact],
                in: stages
            )
            result.append(
                SwingMetricValue(
                    id: .backswingTime,
                    value: swingTempo.backswingSeconds,
                    unit: "s",
                    confidence: overallConfidence,
                    stage: "P1-P4",
                    availability: .measured
                )
            )
            result.append(
                SwingMetricValue(
                    id: .downswingTime,
                    value: swingTempo.downswingSeconds,
                    unit: "s",
                    confidence: overallConfidence,
                    stage: "P4-P7",
                    availability: .measured
                )
            )
            result.append(
                SwingMetricValue(
                    id: .tempoRatio,
                    value: swingTempo.ratio,
                    unit: "ratio",
                    confidence: overallConfidence,
                    stage: "P1-P7",
                    availability: .measured
                )
            )
        }

        let movementStages: [SwingStage] = [
            .takeaway,
            .leadArmParallelBackswing,
            .top,
            .leadArmParallelDownswing,
            .shaftParallelDownswing,
            .impact
        ]
        let movementFrames = movementStages.compactMap {
            confirmedFrames[$0]
        }.compactMap {
            framesByIndex[$0]
        }
        if movementFrames.count == movementStages.count {
            result.append(
                pathLength(
                    landmark: .handCenter,
                    frames: movementFrames,
                    personHeight: personHeight,
                    id: .handPathLength
                )
            )
            result.append(
                pathLength(
                    landmark: .clubhead,
                    frames: movementFrames,
                    personHeight: personHeight,
                    id: .clubheadPathLength
                )
            )
            result.append(
                normalizedRelativeSpeed2D(
                    landmark: .clubhead,
                    frames: movementFrames,
                    personHeight: personHeight
                )
            )
        }

        if let addressIndex = confirmedFrames[.address],
           let impactIndex = confirmedFrames[.impact],
           let addressFrame = framesByIndex[addressIndex],
           let impactFrame = framesByIndex[impactIndex],
           let addressHead = addressFrame.landmarks[.head],
           let impactHead = impactFrame.landmarks[.head] {
            result.append(
                normalizedDisplacement(
                    id: .headHorizontalDisplacement,
                    from: addressHead,
                    to: impactHead,
                    personHeight: personHeight,
                    axis: \.x,
                    stage: "P1-P7"
                )
            )
            result.append(
                normalizedDisplacement(
                    id: .headVerticalDisplacement,
                    from: addressHead,
                    to: impactHead,
                    personHeight: personHeight,
                    axis: \.y,
                    stage: "P1-P7"
                )
            )
        }

        return result.filter { $0.id.isMotionAnalysisOutput }
    }

    private static func confirmedTime(
        _ stage: SwingStage,
        in detections: [SwingStageDetection]
    ) -> Double? {
        guard let detection = detections.first(where: {
            $0.stage == stage
        }),
        detection.status == .confirmed,
        detection.confidence >= minimumMeasuredConfidence else {
            return nil
        }
        return detection.time
    }

    private static func minimumStageConfidence(
        _ required: [SwingStage],
        in detections: [SwingStageDetection]
    ) -> Double {
        required.compactMap { stage in
            detections.first(where: { $0.stage == stage })?.confidence
        }.min() ?? 0
    }

    private static func inputFailure(
        _ points: [TrackedSwingPoint]
    ) -> SwingMetricUnavailableReason? {
        if points.contains(where: \.isEstimated) {
            return .estimatedInput
        }
        if points.contains(where: {
            $0.state != .detected || $0.point == nil
        }) {
            return .missingEvidence
        }
        if points.contains(where: {
            !$0.confidence.isFinite
                || $0.confidence < minimumMeasuredConfidence
        }) {
            return .lowConfidence
        }
        return nil
    }

    private static func unavailable(
        id: SwingMetricID,
        unit: String,
        reason: SwingMetricUnavailableReason,
        stage: String? = nil
    ) -> SwingMetricValue {
        SwingMetricValue(
            id: id,
            value: nil,
            unit: unit,
            confidence: 0,
            stage: stage,
            availability: .unavailable(reason: reason)
        )
    }
}

enum SwingMetricEvidence {
    static func personHeight(
        frames: [SwingFrameObservation],
        detections: [SwingStageDetection]
    ) -> Double {
        let stageFrames = Set(detections.compactMap(\.sourceFrameIndex))
        let heights = frames
            .filter { stageFrames.contains($0.sourceFrameIndex) }
            .compactMap { frame -> Double? in
                guard let head = frame.landmarks[.head],
                      let leftAnkle = frame.landmarks[.leftAnkle],
                      let rightAnkle = frame.landmarks[.rightAnkle],
                      head.isMeasured,
                      leftAnkle.isMeasured,
                      rightAnkle.isMeasured,
                      let headPoint = head.point,
                      let leftPoint = leftAnkle.point,
                      let rightPoint = rightAnkle.point else {
                    return nil
                }
                let ankleY = (leftPoint.y + rightPoint.y) / 2
                let height = abs(headPoint.y - ankleY)
                return height.isFinite && height > 0 ? height : nil
            }
            .sorted()
        guard !heights.isEmpty else { return 0 }
        return heights[heights.count / 2]
    }
}

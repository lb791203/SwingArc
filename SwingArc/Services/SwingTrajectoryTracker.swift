import Foundation

struct SwingTrajectoryTracker {
    private let maximumPredictionFrames: Int
    private var detectedHistory: [SwingLandmark: [TimedTrackedPoint]] = [:]

    init(maximumPredictionFrames: Int) {
        self.maximumPredictionFrames = max(0, maximumPredictionFrames)
    }

    static func track(
        _ frames: [SwingFrameObservation],
        maximumPredictionFrames: Int
    ) -> [SwingFrameObservation] {
        var tracker = SwingTrajectoryTracker(
            maximumPredictionFrames: maximumPredictionFrames
        )
        return frames.sorted {
            if $0.sourceFrameIndex != $1.sourceFrameIndex {
                return $0.sourceFrameIndex < $1.sourceFrameIndex
            }
            return $0.time < $1.time
        }.map { tracker.update($0) }
    }

    mutating func update(_ frame: SwingFrameObservation) -> SwingFrameObservation {
        var landmarks = frame.landmarks

        for (landmark, value) in frame.landmarks {
            guard value.state == .detected,
                  value.point != nil,
                  value.source != .temporalPrediction else { continue }
            var history = detectedHistory[landmark] ?? []
            history.append(TimedTrackedPoint(
                sourceFrameIndex: frame.sourceFrameIndex,
                time: frame.time,
                value: value
            ))
            detectedHistory[landmark] = Array(history.suffix(2))
        }

        for (landmark, history) in detectedHistory {
            if let current = landmarks[landmark],
               current.state == .detected,
               current.point != nil,
               current.source != .temporalPrediction {
                continue
            }
            guard let latest = history.last else { continue }
            let frameGap = frame.sourceFrameIndex - latest.sourceFrameIndex
            guard frameGap > 0, frameGap <= maximumPredictionFrames else {
                landmarks[landmark] = TrackedSwingPoint(
                    point: nil,
                    confidence: 0,
                    state: .missing,
                    source: .temporalPrediction
                )
                continue
            }

            landmarks[landmark] = TrackedSwingPoint(
                point: predictedPoint(history: history, currentTime: frame.time),
                confidence: predictionConfidence(
                    detectedConfidence: latest.value.confidence,
                    frameGap: frameGap
                ),
                state: .estimated,
                source: .temporalPrediction
            )
        }

        return SwingFrameObservation(
            sourceFrameIndex: frame.sourceFrameIndex,
            time: frame.time,
            landmarks: landmarks,
            rawLandmarks: frame.rawLandmarks
        )
    }

    private func predictedPoint(
        history: [TimedTrackedPoint],
        currentTime: Double
    ) -> NormalizedPoint? {
        guard let previous = history.last,
              let previousPoint = previous.value.point else { return nil }
        guard history.count >= 2,
              let olderPoint = history[history.count - 2].value.point else {
            return previousPoint
        }

        let older = history[history.count - 2]
        let priorDelta = previous.time - older.time
        let currentDelta = currentTime - previous.time
        guard priorDelta > 0, currentDelta >= 0 else { return previousPoint }
        let velocityX = (previousPoint.x - olderPoint.x) / priorDelta
        let velocityY = (previousPoint.y - olderPoint.y) / priorDelta
        return NormalizedPoint(
            x: min(1, max(0, previousPoint.x + velocityX * currentDelta)),
            y: min(1, max(0, previousPoint.y + velocityY * currentDelta))
        )
    }

    private func predictionConfidence(
        detectedConfidence: Double,
        frameGap: Int
    ) -> Double {
        guard maximumPredictionFrames > 0 else { return 0 }
        let retainedFraction = 1 - Double(frameGap) / Double(maximumPredictionFrames + 1)
        return min(1, max(0, detectedConfidence * retainedFraction))
    }
}

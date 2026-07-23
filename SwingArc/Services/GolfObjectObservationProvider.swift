import CoreGraphics
import Foundation

struct GolfObjectObservation: Equatable {
    let points: [SwingLandmark: TrackedSwingPoint]

    static let empty = GolfObjectObservation(points: [:])
}

protocol GolfObjectObservationProvider {
    func observe(
        image: CGImage,
        pose: PoseEstimationResult?
    ) throws -> GolfObjectObservation
}

enum GolfObjectProviderError: Error, Equatable {
    case modelUnavailable
    case invalidOutput
}

enum ContourGolfObjectObservationAdapter {
    static func observation(from evidence: SwingObjectEvidence) -> GolfObjectObservation {
        var points: [SwingLandmark: TrackedSwingPoint] = [:]
        if let shaft = evidence.shaft {
            points[.shaftStart] = trackedPoint(
                shaft.start,
                confidence: shaft.confidence
            )
            points[.shaftEnd] = trackedPoint(
                shaft.end,
                confidence: shaft.confidence
            )
        }
        if let ball = evidence.ball {
            points[.ball] = trackedPoint(
                ball.center,
                confidence: ball.confidence
            )
        }
        return GolfObjectObservation(points: points)
    }

    private static func trackedPoint(
        _ point: CGPoint,
        confidence: Double
    ) -> TrackedSwingPoint {
        TrackedSwingPoint(
            point: NormalizedPoint(x: Double(point.x), y: Double(point.y)),
            confidence: min(1, max(0, confidence)),
            state: .detected,
            source: .contour
        )
    }
}

struct GolfObjectTrajectoryTracker {
    private static let supportedLandmarks: Set<SwingLandmark> = [
        .grip, .shaftStart, .shaftEnd, .clubhead, .ball
    ]

    private var tracker: SwingTrajectoryTracker

    init(maximumPredictionFrames: Int) {
        tracker = SwingTrajectoryTracker(
            maximumPredictionFrames: maximumPredictionFrames
        )
    }

    mutating func update(
        observation: GolfObjectObservation,
        sourceFrameIndex: Int,
        time: Double
    ) -> SwingFrameObservation {
        let filtered = observation.points.filter {
            Self.supportedLandmarks.contains($0.key)
        }
        return tracker.update(SwingFrameObservation(
            sourceFrameIndex: sourceFrameIndex,
            time: time,
            landmarks: filtered
        ))
    }
}

enum TrackedGolfObjectEvidenceAdapter {
    static func evidence(
        from frame: SwingFrameObservation,
        stableBall: CGPoint?,
        ballLocalChange: Double
    ) -> SwingObjectEvidence {
        let points = frame.landmarks.filter {
            [.grip, .shaftStart, .shaftEnd, .clubhead, .ball].contains($0.key)
        }
        let shaft: ClubShaftEvidence?
        if let start = points[.shaftStart],
           let end = points[.shaftEnd],
           let startPoint = start.point,
           let endPoint = end.point,
           start.state == .detected,
           end.state == .detected {
            shaft = ClubShaftEvidence(
                start: CGPoint(x: startPoint.x, y: startPoint.y),
                end: CGPoint(x: endPoint.x, y: endPoint.y),
                confidence: min(start.confidence, end.confidence)
            )
        } else {
            shaft = nil
        }
        let ball: BallEvidence?
        if let trackedBall = points[.ball],
           let ballPoint = trackedBall.point,
           trackedBall.state == .detected {
            ball = BallEvidence(
                center: CGPoint(x: ballPoint.x, y: ballPoint.y),
                radius: 0.01,
                confidence: trackedBall.confidence
            )
        } else {
            ball = nil
        }
        return SwingObjectEvidence(
            shaft: shaft,
            ball: ball,
            stableBall: stableBall,
            ballLocalChange: ballLocalChange,
            trackedPoints: points
        )
    }
}

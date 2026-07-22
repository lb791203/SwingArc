import Foundation

@main
struct LiveSwingTriggerDetectorSmoke {
    static func main() {
        verifyCompletedSwing()
        verifyWalkingDoesNotTrigger()
        verifyIncompleteSwingTimesOut()
        verifyTimestampRegressionResets()
    }

    private static func verifyCompletedSwing() {
        var detector = LiveSwingTriggerDetector(configuration: .standard)
        for index in 0...6 {
            _ = detector.ingest(.still(at: Double(index) / 12.0))
        }
        precondition(detector.state == .ready)

        for index in 7...9 {
            _ = detector.ingest(.backswing(at: Double(index) / 12.0))
        }
        precondition(detector.state == .swingInProgress)

        for index in 10...14 {
            _ = detector.ingest(.moving(at: Double(index) / 12.0))
        }
        _ = detector.ingest(.followThrough(at: 15.0 / 12.0))
        precondition(detector.state == .finishing)

        var boundary: PracticeCaptureBoundary?
        for index in 16...22 {
            boundary = boundary ?? detector.ingest(.settled(at: Double(index) / 12.0)).boundary
        }
        precondition(boundary?.quality == .complete)
        precondition(abs((boundary?.swingStartTime ?? 0) - 7.0 / 12.0) < 0.001)
        precondition((boundary?.swingEndTime ?? 0) >= 20.0 / 12.0)
        precondition(detector.emittedBoundaryCount == 1)
        precondition(detector.state == .cooldown)

        for index in 23...35 {
            let update = detector.ingest(.still(at: Double(index) / 12.0))
            precondition(update.boundary == nil)
        }
        precondition(detector.state == .ready)
        precondition(detector.emittedBoundaryCount == 1)
    }

    private static func verifyWalkingDoesNotTrigger() {
        var detector = LiveSwingTriggerDetector(configuration: .standard)
        for index in 0...6 {
            _ = detector.ingest(.still(at: Double(index) / 12.0))
        }
        for index in 7...36 {
            _ = detector.ingest(.walking(at: Double(index) / 12.0))
        }
        precondition(detector.state == .ready)
        precondition(detector.emittedBoundaryCount == 0)
    }

    private static func verifyIncompleteSwingTimesOut() {
        var detector = LiveSwingTriggerDetector(configuration: .standard)
        for index in 0...6 {
            _ = detector.ingest(.still(at: Double(index) / 12.0))
        }
        for index in 7...9 {
            _ = detector.ingest(.backswing(at: Double(index) / 12.0))
        }

        var boundary: PracticeCaptureBoundary?
        for index in 10...75 {
            boundary = boundary ?? detector.ingest(.missing(at: Double(index) / 12.0)).boundary
        }
        precondition(boundary?.quality == .possibleIncomplete)
        precondition(detector.emittedBoundaryCount == 1)
        precondition(detector.state == .cooldown)
    }

    private static func verifyTimestampRegressionResets() {
        var detector = LiveSwingTriggerDetector(configuration: .standard)
        for index in 0...6 {
            _ = detector.ingest(.still(at: Double(index) / 12.0))
        }
        precondition(detector.state == .ready)
        _ = detector.ingest(.still(at: 0.1))
        precondition(detector.state == .searchingForPerson)
    }
}

private extension LivePoseMotionSample {
    static func missing(at time: TimeInterval) -> Self {
        Self(
            time: time,
            personVisible: false,
            normalizedWristSpeed: 0,
            normalizedTorsoSpeed: 0,
            backswingDirectionScore: 0,
            followThroughScore: 0
        )
    }

    static func still(at time: TimeInterval) -> Self {
        Self(
            time: time,
            personVisible: true,
            normalizedWristSpeed: 0.05,
            normalizedTorsoSpeed: 0.03,
            backswingDirectionScore: 0,
            followThroughScore: 0
        )
    }

    static func walking(at time: TimeInterval) -> Self {
        Self(
            time: time,
            personVisible: true,
            normalizedWristSpeed: 0.25,
            normalizedTorsoSpeed: 0.40,
            backswingDirectionScore: 0.10,
            followThroughScore: 0
        )
    }

    static func backswing(at time: TimeInterval) -> Self {
        Self(
            time: time,
            personVisible: true,
            normalizedWristSpeed: 1.15,
            normalizedTorsoSpeed: 0.24,
            backswingDirectionScore: 0.85,
            followThroughScore: 0
        )
    }

    static func moving(at time: TimeInterval) -> Self {
        Self(
            time: time,
            personVisible: true,
            normalizedWristSpeed: 1.4,
            normalizedTorsoSpeed: 0.35,
            backswingDirectionScore: 0.2,
            followThroughScore: 0.2
        )
    }

    static func followThrough(at time: TimeInterval) -> Self {
        Self(
            time: time,
            personVisible: true,
            normalizedWristSpeed: 1.0,
            normalizedTorsoSpeed: 0.25,
            backswingDirectionScore: 0,
            followThroughScore: 0.85
        )
    }

    static func settled(at time: TimeInterval) -> Self {
        Self(
            time: time,
            personVisible: true,
            normalizedWristSpeed: 0.10,
            normalizedTorsoSpeed: 0.08,
            backswingDirectionScore: 0,
            followThroughScore: 0.75
        )
    }
}

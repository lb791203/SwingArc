import Foundation

@main
struct SwingWindowLocatorSmoke {
    static func main() {
        let unique = coarseFixture(bursts: [8.0])
        switch SwingWindowLocator.locate(samples: unique) {
        case let .located(window):
            precondition(window.startTime <= 8.0)
            precondition(window.endTime >= 9.25)
            precondition(window.duration <= 6.0)
        case let .failed(reason):
            preconditionFailure("Expected one swing window, got \(reason)")
        }

        let ambiguous = coarseFixture(bursts: [4.0, 13.0])
        precondition(
            SwingWindowLocator.locate(samples: ambiguous) == .failed(.ambiguousCandidates),
            "Two equally strong separated swings must not be guessed"
        )

        let still = coarseFixture(bursts: [])
        precondition(
            SwingWindowLocator.locate(samples: still) == .failed(.noSwingMotion),
            "A stationary golfer must not create a fabricated swing window"
        )

        let swingInsideLongPreparation = longPreparationFixture()
        switch SwingWindowLocator.locate(samples: swingInsideLongPreparation) {
        case let .located(window):
            precondition(window.startTime <= 8.0)
            precondition(window.endTime >= 9.25)
            precondition(window.duration <= 6.0)
        case let .failed(reason):
            preconditionFailure("A compact swing inside long preparation must be isolated, got \(reason)")
        }

        let uniformlyMoving = stride(from: 0.0, through: 20.0, by: 0.125).map { time in
            CoarseSwingSample(
                time: time,
                pose: pose(time: time, wristY: 0.78 + time * 0.4, shoulderTurn: 0)
            )
        }
        precondition(
            SwingWindowLocator.locate(samples: uniformlyMoving) == .failed(.windowTooLong),
            "Uniform long movement must not be mislabeled as a compact swing"
        )

        let alternatingLeftRightLabels = stride(from: 0.0, through: 10.0, by: 0.125).enumerated().map { index, time in
            CoarseSwingSample(
                time: time,
                pose: poseWithAlternatingLabels(time: time, swapsLeftRight: index.isMultiple(of: 2))
            )
        }
        precondition(
            SwingWindowLocator.locate(samples: alternatingLeftRightLabels) == .failed(.noSwingMotion),
            "Swapping left/right labels on the same shoulder and hip axes must not create fake rotation"
        )

        let swingWithFinishJitter = swingWithFinishJitterFixture()
        switch SwingWindowLocator.locate(samples: swingWithFinishJitter) {
        case let .located(window):
            precondition(window.startTime <= 14.0, "Located too late: \(window)")
            precondition(window.endTime >= 16.0, "Located too early: \(window)")
            precondition(window.duration <= 6.0, "Located window is too long: \(window)")
        case let .failed(reason):
            preconditionFailure("Pose jitter after a real swing must not extend or obscure it, got \(reason)")
        }
    }

    private static func coarseFixture(bursts: [Double]) -> [CoarseSwingSample] {
        stride(from: 0.0, through: 20.0, by: 0.125).map { time in
            var wristY = 0.78
            var shoulderTurn = 0.0
            for start in bursts where time >= start && time <= start + 1.25 {
                let phase = (time - start) / 1.25
                wristY = phase <= 0.5
                    ? 0.78 - phase * 1.0
                    : 0.28 + (phase - 0.5) * 1.0
                shoulderTurn = sin(phase * .pi) * 0.08
            }
            return CoarseSwingSample(
                time: time,
                pose: pose(time: time, wristY: wristY, shoulderTurn: shoulderTurn)
            )
        }
    }

    private static func longPreparationFixture() -> [CoarseSwingSample] {
        stride(from: 0.0, through: 20.0, by: 0.125).map { time in
            var wristY = 0.78
            var shoulderTurn = 0.0
            if time >= 3.0, time <= 13.0 {
                wristY += sin(time * 12.0) * 0.04
            }
            if time >= 8.0, time <= 9.25 {
                let phase = (time - 8.0) / 1.25
                wristY = phase <= 0.5
                    ? 0.78 - phase * 1.0
                    : 0.28 + (phase - 0.5) * 1.0
                shoulderTurn = sin(phase * .pi) * 0.08
            }
            return CoarseSwingSample(
                time: time,
                pose: pose(time: time, wristY: wristY, shoulderTurn: shoulderTurn)
            )
        }
    }

    private static func swingWithFinishJitterFixture() -> [CoarseSwingSample] {
        stride(from: 0.0, through: 26.0, by: 0.125).enumerated().map { index, time in
            var wristY = 0.78
            var shoulderTurn = 0.0
            if time >= 14.0, time <= 17.0 {
                let phase = (time - 14.0) / 3.0
                if phase <= 0.25 {
                    wristY = 0.78 - phase * 2.0
                } else if phase <= 0.35 {
                    wristY = 0.28 + (phase - 0.25) * 5.0
                } else {
                    wristY = 0.78 - (phase - 0.35) * 1.5
                }
                shoulderTurn = sin(phase * .pi) * 0.08
            } else if time > 17.0, time <= 21.0 {
                wristY = -0.195
                if index.isMultiple(of: 4) {
                    wristY += 0.30
                }
            } else if time > 21.0 {
                wristY = -0.195
            }
            return CoarseSwingSample(
                time: time,
                pose: pose(time: time, wristY: wristY, shoulderTurn: shoulderTurn)
            )
        }
    }

    private static func pose(time: Double, wristY: CGFloat, shoulderTurn: CGFloat) -> SwingPoseSample {
        SwingPoseSample(
            time: time,
            leftWrist: CGPoint(x: 0.45 - shoulderTurn, y: wristY),
            rightWrist: CGPoint(x: 0.55 - shoulderTurn, y: wristY),
            leftElbow: CGPoint(x: 0.42, y: min(0.92, wristY + 0.08)),
            rightElbow: CGPoint(x: 0.58, y: min(0.92, wristY + 0.08)),
            leftShoulder: CGPoint(x: 0.38 + shoulderTurn, y: 0.34),
            rightShoulder: CGPoint(x: 0.62 - shoulderTurn, y: 0.34),
            leftHip: CGPoint(x: 0.43, y: 0.60),
            rightHip: CGPoint(x: 0.57, y: 0.60),
            head: CGPoint(x: 0.50, y: 0.16),
            spineAngle: 0,
            aggregateConfidence: 0.95
        )
    }

    private static func poseWithAlternatingLabels(
        time: Double,
        swapsLeftRight: Bool
    ) -> SwingPoseSample {
        let leftShoulder = CGPoint(x: 0.38, y: 0.34)
        let rightShoulder = CGPoint(x: 0.62, y: 0.34)
        let leftHip = CGPoint(x: 0.43, y: 0.60)
        let rightHip = CGPoint(x: 0.57, y: 0.60)
        return SwingPoseSample(
            time: time,
            leftWrist: CGPoint(x: swapsLeftRight ? 0.55 : 0.45, y: 0.78),
            rightWrist: CGPoint(x: swapsLeftRight ? 0.45 : 0.55, y: 0.78),
            leftElbow: CGPoint(x: swapsLeftRight ? 0.58 : 0.42, y: 0.70),
            rightElbow: CGPoint(x: swapsLeftRight ? 0.42 : 0.58, y: 0.70),
            leftShoulder: swapsLeftRight ? rightShoulder : leftShoulder,
            rightShoulder: swapsLeftRight ? leftShoulder : rightShoulder,
            leftHip: swapsLeftRight ? rightHip : leftHip,
            rightHip: swapsLeftRight ? leftHip : rightHip,
            head: CGPoint(x: 0.50, y: 0.16),
            spineAngle: 0,
            aggregateConfidence: 0.95
        )
    }
}

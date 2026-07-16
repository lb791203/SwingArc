import Foundation

@main
struct SwingCoreLocatorSmoke {
    static func main() {
        let samples = coarseFixture(bursts: [8.0])
        switch SwingCoreLocator.locate(samples: samples) {
        case let .located(core):
            precondition(core.startTime >= 7.75)
            precondition(core.startTime <= 8.125)
            precondition(core.endTime >= 9.125)
            precondition(core.endTime <= 9.50)
            precondition((core.startTime...core.endTime).contains(core.peakTime))
        case let .failed(reason):
            preconditionFailure("Expected unpadded swing core, got \(reason)")
        }

        precondition(
            SwingCoreLocator.locate(samples: coarseFixture(bursts: [4.0, 13.0]))
                == .failed(.ambiguousCandidates),
            "Two equally strong separated swings must not be guessed"
        )
        precondition(
            SwingCoreLocator.locate(samples: coarseFixture(bursts: []))
                == .failed(.noSwingMotion),
            "A stationary golfer must not create a fabricated swing core"
        )

        let alternatingLeftRightLabels = stride(from: 0.0, through: 10.0, by: 0.125)
            .enumerated()
            .map { index, time in
                CoarseSwingSample(
                    time: time,
                    pose: poseWithAlternatingLabels(
                        time: time,
                        swapsLeftRight: index.isMultiple(of: 2)
                    )
                )
            }
        precondition(
            SwingCoreLocator.locate(samples: alternatingLeftRightLabels)
                == .failed(.noSwingMotion),
            "Swapping left/right labels on fixed axes must not create fake rotation"
        )

        let swingThenWalk = stride(from: 0.0, through: 20.0, by: 0.125).map { time in
            let inSwing = time >= 8.0 && time <= 9.25
            let phase = inSwing ? (time - 8.0) / 1.25 : 0
            let wristY: CGFloat = inSwing
                ? (phase <= 0.5 ? 0.78 - phase : 0.28 + (phase - 0.5))
                : 0.78
            let shoulderTurn: CGFloat = inSwing ? sin(phase * .pi) * 0.08 : 0
            let translation: CGFloat = time >= 13.0 && time <= 18.0
                ? CGFloat((time - 13.0) * 0.60)
                : (time > 18.0 ? 3.0 : 0)
            return CoarseSwingSample(
                time: time,
                pose: translatedPose(
                    time: time,
                    wristY: wristY,
                    shoulderTurn: shoulderTurn,
                    translationX: translation
                )
            )
        }
        switch SwingCoreLocator.locate(samples: swingThenWalk) {
        case let .located(core):
            precondition(
                core.peakTime >= 8.0 && core.peakTime <= 9.25,
                "Whole-body translation after the swing must not replace the swing core"
            )
        case let .failed(reason):
            preconditionFailure("Expected swing core before walking, got \(reason)")
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

    private static func translatedPose(
        time: Double,
        wristY: CGFloat,
        shoulderTurn: CGFloat,
        translationX: CGFloat
    ) -> SwingPoseSample {
        let original = pose(time: time, wristY: wristY, shoulderTurn: shoulderTurn)
        func shifted(_ point: CGPoint?) -> CGPoint? {
            point.map { CGPoint(x: $0.x + translationX, y: $0.y) }
        }
        return SwingPoseSample(
            time: time,
            leftWrist: shifted(original.leftWrist),
            rightWrist: shifted(original.rightWrist),
            leftElbow: shifted(original.leftElbow),
            rightElbow: shifted(original.rightElbow),
            leftShoulder: shifted(original.leftShoulder),
            rightShoulder: shifted(original.rightShoulder),
            leftHip: shifted(original.leftHip),
            rightHip: shifted(original.rightHip),
            head: shifted(original.head),
            spineAngle: original.spineAngle,
            aggregateConfidence: original.aggregateConfidence
        )
    }
}

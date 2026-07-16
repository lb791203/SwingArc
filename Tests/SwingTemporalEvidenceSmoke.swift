import Foundation

@main
struct SwingTemporalEvidenceSmoke {
    static func main() {
        verifyFrameRateInvariantBoundaries()
        verifyBoundaryAdjacentNoiseDoesNotMoveBoundaries()
        verifySupportingTemporalEvidence()
    }

    private enum BoundaryNoise: CaseIterable {
        case address
        case top
        case finish
    }

    private static func verifyFrameRateInvariantBoundaries() {
        for fps in [30, 120] {
            let evidence = temporalFixture(fps: fps)
            let timeline = SwingEvidenceTimeline.build(from: Array(evidence.reversed()))

            precondition(timeline.map(\.frame.time) == evidence.map(\.time))
            precondition(timeline.map(\.frame.sourceFrameIndex) == evidence.map(\.sourceFrameIndex))
            precondition(timeline.last(where: \.isAddressBoundary)?.frame.time == 1.00)
            precondition(timeline.first(where: \.isTopPlateauEnd)?.frame.time == 2.50)
            precondition(timeline.first(where: \.isFinishPlateauStart)?.frame.time == 4.25)
            precondition(
                timeline.adaptiveBoundaryEvidence == AdaptiveBoundaryEvidence(
                    hasAddressBoundary: true,
                    hasFinishBoundary: true
                )
            )

            let wrongDirection = timeline.first { abs($0.frame.time - 2.60) < 0.000_001 }
            precondition(wrongDirection?.frame.handVelocity.y ?? 0 < 0)
            precondition(timeline.filter(\.isTopPlateauEnd).map(\.frame.time) == [2.50])

            let unstableFinish = timeline.first { abs($0.frame.time - 4.35) < 0.000_001 }
            precondition((unstableFinish?.frame.headSpeed ?? 0) > SwingEvidenceTimeline.bodyStabilityThreshold)
            precondition(timeline.filter(\.isFinishPlateauStart).map(\.frame.time) == [4.25])

            for boundaryTime in [1.00, 2.50, 4.25] {
                let source = evidence.first { $0.time == boundaryTime }
                let temporal = timeline.first { $0.frame.time == boundaryTime }
                precondition(temporal?.frame.sourceFrameIndex == source?.sourceFrameIndex)
            }
        }
    }

    private static func verifySupportingTemporalEvidence() {
        let continuous = (0...6).map { index in
            evidence(
                sourceFrameIndex: 4_000 + index * 7,
                time: 0.40 + Double(index) * 0.05,
                velocityY: 0,
                shaftAngle: 10 + Double(index) * 0.5,
                stableBall: index == 3
                    ? CGPoint(x: 0.62, y: 0.82)
                    : CGPoint(x: 0.50 + CGFloat(index % 2) * 0.002, y: 0.82)
            )
        }
        let continuityTimeline = SwingEvidenceTimeline.build(from: continuous)
        let middle = continuityTimeline[continuityTimeline.count / 2]
        precondition(middle.shaftAngleContinuity > 0.95)
        precondition(abs(middle.ballStability - (6.0 / 7.0)) < 0.000_001)

        let incomplete = evidence(
            sourceFrameIndex: 9_001,
            time: 0,
            velocityY: 0,
            handCenter: nil,
            leadArm: .unknown,
            pose: nil
        )
        let flags = SwingEvidenceTimeline.build(from: [incomplete])[0].qualityFlags
        precondition(flags.contains(.missingHands))
        precondition(flags.contains(.missingLeadArm))
        precondition(
            SwingEvidenceTimeline.build(from: [incomplete]).adaptiveBoundaryEvidence
                == AdaptiveBoundaryEvidence(hasAddressBoundary: false, hasFinishBoundary: false)
        )
    }

    private static func verifyBoundaryAdjacentNoiseDoesNotMoveBoundaries() {
        for fps in [30, 120] {
            for noise in BoundaryNoise.allCases {
                let evidence = temporalFixture(fps: fps, boundaryNoise: noise)
                let timeline = SwingEvidenceTimeline.build(from: evidence)

                let address = timeline.last(where: \.isAddressBoundary)?.frame
                let top = timeline.first(where: \.isTopPlateauEnd)?.frame
                let finish = timeline.first(where: \.isFinishPlateauStart)?.frame

                precondition(
                    address?.time == 1.00,
                    "\(fps) FPS \(noise) noise moved address to \(String(describing: address?.time))"
                )
                precondition(
                    top?.time == 2.50,
                    "\(fps) FPS \(noise) noise moved top to \(String(describing: top?.time))"
                )
                precondition(
                    finish?.time == 4.25,
                    "\(fps) FPS \(noise) noise moved finish to \(String(describing: finish?.time))"
                )

                for boundary in [address, top, finish] {
                    let source = evidence.first { $0.time == boundary?.time }
                    precondition(boundary?.sourceFrameIndex == source?.sourceFrameIndex)
                }
            }
        }
    }

    private static func temporalFixture(
        fps: Int,
        boundaryNoise: BoundaryNoise? = nil
    ) -> [SwingFrameEvidence] {
        let duration = 5.0
        let regularTimes = (0...Int(duration * Double(fps))).map { Double($0) / Double(fps) }
        let requiredTimes = [1.00, 2.50, 2.60, 4.25, 4.35]
        let times = Array(Set(regularTimes + requiredTimes)).sorted()
        let addressNoiseTime = times.first { $0 > 1.00 }
        let topNoiseTime = times.first { $0 > 2.50 }

        return times.enumerated().map { ordinal, time in
            let velocityY: CGFloat
            let bodySpeed: Double
            if boundaryNoise == .address, time == addressNoiseTime {
                velocityY = 0
                bodySpeed = 0.20
            } else if boundaryNoise == .top, time == topNoiseTime {
                velocityY = 0
                bodySpeed = 0.20
            } else if boundaryNoise == .finish, time == 4.25 {
                velocityY = 0.30
                bodySpeed = 0.20
            } else if time <= 1.00 {
                velocityY = 0
                bodySpeed = 0.01
            } else if time < 2.30 {
                velocityY = -0.14
                bodySpeed = 0.03
            } else if time <= 2.50 {
                velocityY = 0
                bodySpeed = 0.02
            } else if time <= 3.30 {
                velocityY = abs(time - 2.60) < 0.000_001 ? -0.14 : 0.55
                bodySpeed = 0.04
            } else if time < 4.25 {
                velocityY = -0.48
                bodySpeed = 0.04
            } else if abs(time - 4.35) < 0.000_001 {
                velocityY = 0.30
                bodySpeed = 0.20
            } else {
                velocityY = 0
                bodySpeed = 0.01
            }

            return evidence(
                sourceFrameIndex: fps * 10_000 + ordinal * 3 + 7,
                time: time,
                velocityY: velocityY,
                headSpeed: bodySpeed,
                hipSpeed: bodySpeed,
                shaftAngle: 18,
                stableBall: CGPoint(x: 0.50, y: 0.82)
            )
        }
    }

    private static func evidence(
        sourceFrameIndex: Int,
        time: Double,
        velocityY: CGFloat,
        headSpeed: Double = 0.01,
        hipSpeed: Double = 0.01,
        shaftAngle: Double? = nil,
        stableBall: CGPoint? = nil,
        handCenter: CGPoint? = CGPoint(x: 0.50, y: 0.50),
        leadArm: LeadArmSide = .left,
        pose: SwingPoseSample? = completePose(time: 0)
    ) -> SwingFrameEvidence {
        let shaft = shaftAngle.map { angle -> ClubShaftEvidence in
            let radians = angle * Double.pi / 180
            return ClubShaftEvidence(
                start: CGPoint(x: 0.45, y: 0.65),
                end: CGPoint(x: 0.45 + cos(radians) * 0.20, y: 0.65 + sin(radians) * 0.20),
                confidence: 0.95
            )
        }
        return SwingFrameEvidence(
            sourceFrameIndex: sourceFrameIndex,
            time: time,
            pose: pose,
            objectEvidence: SwingObjectEvidence(
                shaft: shaft,
                ball: stableBall.map { BallEvidence(center: $0, radius: 0.012, confidence: 0.95) },
                stableBall: stableBall,
                ballLocalChange: 0
            ),
            leadArm: leadArm,
            leadArmAngle: 45,
            leadArmExtension: 175,
            shoulderAngle: 0,
            hipAngle: 0,
            handCenter: handCenter,
            hipCenter: pose.flatMap { SwingGeometry.center($0.leftHip, $0.rightHip) },
            handVelocity: CGPoint(x: 0, y: velocityY),
            handAcceleration: .zero,
            headSpeed: headSpeed,
            hipSpeed: hipSpeed,
            poseCoverage: pose == nil ? 0 : 1
        )
    }

    private static func completePose(time: Double) -> SwingPoseSample {
        SwingPoseSample(
            time: time,
            leftWrist: CGPoint(x: 0.48, y: 0.50),
            rightWrist: CGPoint(x: 0.52, y: 0.50),
            leftElbow: CGPoint(x: 0.46, y: 0.43),
            rightElbow: CGPoint(x: 0.54, y: 0.43),
            leftShoulder: CGPoint(x: 0.44, y: 0.36),
            rightShoulder: CGPoint(x: 0.56, y: 0.36),
            leftHip: CGPoint(x: 0.45, y: 0.62),
            rightHip: CGPoint(x: 0.55, y: 0.62),
            head: CGPoint(x: 0.50, y: 0.16),
            spineAngle: 0,
            aggregateConfidence: 0.95
        )
    }
}

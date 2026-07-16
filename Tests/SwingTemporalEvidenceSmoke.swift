import Foundation

@main
struct SwingTemporalEvidenceSmoke {
    static func main() {
        verifyFrameRateInvariantBoundaries()
        verifyBoundaryAdjacentNoiseDoesNotMoveBoundaries()
        verifyBoundaryAdjacentWrongDirectionDoesNotMoveBoundaries()
        verifyHorizontalTakeawayBoundary()
        verifyHighHandsDoNotCreateAddressBoundary()
        verifyPartialTakeawayDoesNotCreateAddressBoundary()
        verifyHorizontalBackswingPhase()
        verifyHorizontalImpactRemainsDownswingPhase()
        verifyTopPlateauEndsAtLastNearStationaryFrame()
        verifyHorizontalFollowThroughFinishBoundary()
        verifyFinishBoundaryToleratesFutureVisionNoise()
        verifySupportingTemporalEvidence()
    }

    private static func verifyTopPlateauEndsAtLastNearStationaryFrame() {
        let fps = 30
        let fixture = (0...100).map { ordinal -> SwingFrameEvidence in
            let velocityY: CGFloat
            switch ordinal {
            case ...30:
                velocityY = 0
            case 31...69:
                velocityY = -0.30
            case 70...73:
                velocityY = 0
            case 74...76:
                velocityY = 0.03
            default:
                velocityY = 0.45
            }
            return evidence(
                sourceFrameIndex: 92_000 + ordinal,
                time: Double(ordinal) / Double(fps),
                velocityY: velocityY,
                handCenter: CGPoint(x: 0.40, y: ordinal < 70 ? 0.58 : 0.34)
            )
        }
        precondition(
            SwingEvidenceTimeline.build(from: fixture)
                .first(where: \.isTopPlateauEnd)?.frame.sourceFrameIndex == 92_073,
            "P4 must be the last near-stationary top frame, not the end of harmless pre-downswing drift"
        )
    }

    private enum BoundaryNoise: CaseIterable {
        case address
        case top
        case finish
    }

    private enum WrongDirectionNoise: CaseIterable {
        case address
        case top

        var velocityY: CGFloat {
            switch self {
            case .address: 0.14
            case .top: -0.14
            }
        }
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

    private static func verifyHorizontalTakeawayBoundary() {
        for fps in [30, 60, 120] {
            let times = (0...Int(2.0 * Double(fps))).map { Double($0) / Double(fps) }
            let fixture = times.enumerated().map { ordinal, time -> SwingFrameEvidence in
                let elapsed = max(0, time - 1.0)
                let x: CGFloat = time < 1.0
                    ? 0.55
                    : 0.55 - CGFloat(min(0.12, elapsed * 0.09))
                let velocityX: CGFloat
                if abs(time - 1.0) < 0.000_001 {
                    velocityX = -0.10
                } else if time > 1.0 {
                    velocityX = ordinal.isMultiple(of: 4) ? -0.03 : -0.07
                } else {
                    velocityX = 0
                }
                return evidence(
                    sourceFrameIndex: fps * 20_000 + ordinal,
                    time: time,
                    velocityX: velocityX,
                    velocityY: 0,
                    handCenter: CGPoint(x: x, y: 0.58)
                )
            }
            let timeline = SwingEvidenceTimeline.build(from: fixture)
            let expected = times.last { $0 < 1.0 }!
            let address = timeline.last(where: \.isAddressBoundary)?.frame
            precondition(
                address?.time == expected,
                "P1 must be the last stable frame before horizontal takeaway at \(fps) FPS"
            )
            precondition(
                hypot(
                    Double(address?.handVelocity.x ?? .infinity),
                    Double(address?.handVelocity.y ?? .infinity)
                ) < 0.08,
                "P1 itself must remain quiet at \(fps) FPS"
            )
        }
    }

    private static func verifyHighHandsDoNotCreateAddressBoundary() {
        let fps = 30
        let fixture = (0...30).map { ordinal -> SwingFrameEvidence in
            let time = Double(ordinal) / Double(fps)
            let velocityX: CGFloat = ordinal == 8 ? 0.10 : (ordinal > 8 ? 0.07 : 0)
            return evidence(
                sourceFrameIndex: 90_000 + ordinal,
                time: time,
                velocityX: velocityX,
                velocityY: 0,
                handCenter: CGPoint(x: 0.32 + CGFloat(ordinal) * 0.003, y: 0.35)
            )
        }
        precondition(
            SwingEvidenceTimeline.build(from: fixture).allSatisfy { !$0.isAddressBoundary },
            "A high-hands motion pulse near the top must not become an address boundary"
        )
    }

    private static func verifyPartialTakeawayDoesNotCreateAddressBoundary() {
        let fps = 30
        let fixture = (0...30).map { ordinal -> SwingFrameEvidence in
            let velocityX: CGFloat = ordinal.isMultiple(of: 3) ? -0.12 : -0.07
            return evidence(
                sourceFrameIndex: 91_000 + ordinal,
                time: Double(ordinal) / Double(fps),
                velocityX: velocityX,
                velocityY: 0,
                handCenter: CGPoint(
                    x: 0.55 - CGFloat(ordinal) * 0.003,
                    y: 0.58
                )
            )
        }
        precondition(
            SwingEvidenceTimeline.build(from: fixture).allSatisfy { !$0.isAddressBoundary },
            "A window that starts during takeaway must expand left instead of inventing P1"
        )
    }

    private static func verifyHorizontalFollowThroughFinishBoundary() {
        for fps in [30, 60, 120] {
            let times = (0...Int(5.0 * Double(fps))).map { Double($0) / Double(fps) }
            let fixture = times.enumerated().map { ordinal, time -> SwingFrameEvidence in
                let velocityX: CGFloat
                let velocityY: CGFloat
                let handX: CGFloat
                let bodySpeed: Double
                if time <= 1.0 {
                    velocityX = 0
                    velocityY = 0
                    handX = 0.55
                    bodySpeed = 0.01
                } else if time < 2.30 {
                    velocityX = 0
                    velocityY = -0.14
                    handX = 0.55
                    bodySpeed = 0.03
                } else if time <= 2.50 {
                    velocityX = 0
                    velocityY = 0
                    handX = 0.55
                    bodySpeed = 0.02
                } else if time <= 3.30 {
                    velocityX = 0
                    velocityY = 0.55
                    handX = 0.55
                    bodySpeed = 0.04
                } else if time < 4.00 {
                    velocityX = -0.40
                    velocityY = 0
                    handX = 0.65 - CGFloat(time - 3.30) * 0.20
                    bodySpeed = 0.04
                } else if time <= 4.07 {
                    let pulse = time > 4.00
                    velocityX = pulse ? -0.35 : 0
                    velocityY = 0
                    handX = 0.51 - CGFloat(max(0, time - 4.00)) * 0.30
                    bodySpeed = pulse ? 0.12 : 0.01
                } else {
                    velocityX = 0
                    velocityY = 0
                    handX = 0.49
                    bodySpeed = 0.01
                }
                return evidence(
                    sourceFrameIndex: fps * 30_000 + ordinal,
                    time: time,
                    velocityX: velocityX,
                    velocityY: velocityY,
                    headSpeed: bodySpeed,
                    hipSpeed: bodySpeed,
                    handCenter: CGPoint(x: handX, y: 0.45)
                )
            }
            let timeline = SwingEvidenceTimeline.build(from: fixture)
            let expected = times.first { $0 > 4.07 }!
            let finish = timeline.first(where: \.isFinishPlateauStart)?.frame
            precondition(
                finish?.time == expected,
                "P8 must be the first frame that is itself stable after the final motion burst at \(fps) FPS"
            )
            precondition(
                hypot(
                    Double(finish?.handVelocity.x ?? .infinity),
                    Double(finish?.handVelocity.y ?? .infinity)
                ) <= 0.18
                    && (finish?.headSpeed ?? .infinity) <= SwingEvidenceTimeline.bodyStabilityThreshold
                    && (finish?.hipSpeed ?? .infinity) <= SwingEvidenceTimeline.bodyStabilityThreshold,
                "P8 must satisfy the measured stability thresholds at \(fps) FPS"
            )
        }
    }

    private static func verifyFinishBoundaryToleratesFutureVisionNoise() {
        for fps in [30, 60, 120] {
            let times = (0...Int(5.0 * Double(fps))).map { Double($0) / Double(fps) }
            let firstStableTime = times.first { $0 > 3.90 }!
            let noiseTime = times.first { $0 >= firstStableTime + 0.10 }!
            let fixture = times.enumerated().map { ordinal, time -> SwingFrameEvidence in
                let velocityY: CGFloat
                let velocityX: CGFloat
                let handX: CGFloat
                let bodySpeed: Double
                if time <= 1.0 {
                    velocityY = 0
                    velocityX = 0
                    handX = 0.55
                    bodySpeed = 0.01
                } else if time < 2.30 {
                    velocityY = -0.35
                    velocityX = 0
                    handX = 0.55
                    bodySpeed = 0.03
                } else if time <= 2.50 {
                    velocityY = 0
                    velocityX = 0
                    handX = 0.55
                    bodySpeed = 0.01
                } else if time < 3.30 {
                    velocityY = 0.55
                    velocityX = 0
                    handX = 0.55
                    bodySpeed = 0.03
                } else if time <= 3.90 {
                    velocityY = 0
                    velocityX = -0.40
                    handX = 0.65 - CGFloat(time - 3.30) * 0.20
                    bodySpeed = 0.03
                } else if abs(time - noiseTime) < 0.000_001 {
                    velocityY = 0
                    velocityX = 0.30
                    handX = 0.52
                    bodySpeed = 0.12
                } else {
                    velocityY = 0
                    velocityX = 0
                    handX = 0.52
                    bodySpeed = 0.01
                }
                return evidence(
                    sourceFrameIndex: fps * 60_000 + ordinal,
                    time: time,
                    velocityX: velocityX,
                    velocityY: velocityY,
                    headSpeed: bodySpeed,
                    hipSpeed: bodySpeed,
                    handCenter: CGPoint(x: handX, y: 0.45)
                )
            }
            let finish = SwingEvidenceTimeline.build(from: fixture)
                .first(where: \.isFinishPlateauStart)?.frame
            precondition(
                finish?.time == firstStableTime,
                "One later Vision-noise frame must not move the first stable P8 boundary at \(fps) FPS"
            )
        }
    }

    private static func verifyHorizontalBackswingPhase() {
        for fps in [30, 120] {
            let times = (0...Int(3.5 * Double(fps))).map { Double($0) / Double(fps) }
            let fixture = times.enumerated().map { ordinal, time -> SwingFrameEvidence in
                let velocityX: CGFloat
                let velocityY: CGFloat
                let handX: CGFloat
                if time < 1.0 {
                    velocityX = 0
                    velocityY = 0
                    handX = 0.55
                } else if time < 2.50 {
                    velocityX = -0.10
                    velocityY = 0
                    handX = 0.55 - CGFloat(time - 1.0) * 0.10
                } else if time == 2.50 {
                    velocityX = 0
                    velocityY = 0
                    handX = 0.40
                } else {
                    velocityX = 0
                    velocityY = 0.55
                    handX = 0.40
                }
                return evidence(
                    sourceFrameIndex: fps * 40_000 + ordinal,
                    time: time,
                    velocityX: velocityX,
                    velocityY: velocityY,
                    handCenter: CGPoint(x: handX, y: 0.58)
                )
            }
            let timeline = SwingEvidenceTimeline.build(from: fixture)
            let middleBackswing = timeline.first { abs($0.frame.time - 2.0) < 0.000_001 }
            precondition(
                timeline.first(where: \.isAddressBoundary)?.frame.time
                    == times.last { $0 < 1.0 }!
            )
            precondition(timeline.first(where: \.isTopPlateauEnd)?.frame.time == 2.5)
            precondition(
                middleBackswing?.sustainedBackswing == true,
                "Horizontal takeaway must remain in the backswing phase at \(fps) FPS"
            )
        }
    }

    private static func verifyHorizontalImpactRemainsDownswingPhase() {
        for fps in [30, 120] {
            let times = (0...Int(4.5 * Double(fps))).map { Double($0) / Double(fps) }
            let fixture = times.enumerated().map { ordinal, time -> SwingFrameEvidence in
                let velocityX: CGFloat
                let velocityY: CGFloat
                let handX: CGFloat
                if time <= 1.0 {
                    velocityX = 0
                    velocityY = 0
                    handX = 0.55
                } else if time < 2.30 {
                    velocityX = -0.10
                    velocityY = -0.14
                    handX = 0.55 - CGFloat(time - 1.0) * 0.08
                } else if time <= 2.50 {
                    velocityX = 0
                    velocityY = 0
                    handX = 0.45
                } else if time < 3.00 {
                    velocityX = 0
                    velocityY = 0.55
                    handX = 0.45
                } else if time < 3.35 {
                    velocityX = 0.60
                    velocityY = 0
                    handX = 0.45 + CGFloat(time - 3.00) * 0.20
                } else if time < 3.90 {
                    velocityX = 0
                    velocityY = -0.48
                    handX = 0.52
                } else {
                    velocityX = 0
                    velocityY = 0
                    handX = 0.52
                }
                return evidence(
                    sourceFrameIndex: fps * 50_000 + ordinal,
                    time: time,
                    velocityX: velocityX,
                    velocityY: velocityY,
                    handCenter: CGPoint(x: handX, y: 0.50)
                )
            }
            let timeline = SwingEvidenceTimeline.build(from: fixture)
            let horizontalImpact = timeline.first { abs($0.frame.time - 3.20) < 0.000_001 }
            precondition(
                horizontalImpact?.sustainedDownswing == true,
                "Through-impact horizontal rotation must remain in the downswing phase at \(fps) FPS"
            )
        }
    }

    private static func verifyBoundaryAdjacentNoiseDoesNotMoveBoundaries() {
        for fps in [30, 120] {
            for noise in BoundaryNoise.allCases {
                let evidence = temporalFixture(fps: fps, boundaryNoise: noise)
                let timeline = SwingEvidenceTimeline.build(from: evidence)

                let address = timeline.last(where: \.isAddressBoundary)?.frame
                let top = timeline.first(where: \.isTopPlateauEnd)?.frame
                let finish = timeline.first(where: \.isFinishPlateauStart)?.frame
                let expectedFinishTime = noise == .finish
                    ? evidence.first { $0.time > 4.25 }!.time
                    : 4.25

                precondition(
                    address?.time == 1.00,
                    "\(fps) FPS \(noise) noise moved address to \(String(describing: address?.time))"
                )
                precondition(
                    top?.time == 2.50,
                    "\(fps) FPS \(noise) noise moved top to \(String(describing: top?.time))"
                )
                precondition(
                    finish?.time == expectedFinishTime,
                    "\(fps) FPS \(noise) noise moved finish to \(String(describing: finish?.time))"
                )

                for boundary in [address, top, finish] {
                    let source = evidence.first { $0.time == boundary?.time }
                    precondition(boundary?.sourceFrameIndex == source?.sourceFrameIndex)
                }
            }
        }
    }

    private static func verifyBoundaryAdjacentWrongDirectionDoesNotMoveBoundaries() {
        var failures: [String] = []

        for fps in [30, 120] {
            for noise in WrongDirectionNoise.allCases {
                let evidence = temporalFixture(fps: fps, wrongDirectionNoise: noise)
                let timeline = SwingEvidenceTimeline.build(from: evidence)
                let address = timeline.last(where: \.isAddressBoundary)?.frame
                let top = timeline.first(where: \.isTopPlateauEnd)?.frame
                let finish = timeline.first(where: \.isFinishPlateauStart)?.frame
                let boundaryTime = noise == .address ? 1.00 : 2.50
                let noiseTime = evidence.first { $0.time > boundaryTime }?.time
                let injectedFrame = evidence.first { $0.time == noiseTime }

                precondition(injectedFrame?.handVelocity.y == noise.velocityY)

                for (name, expectedTime, boundary) in [
                    ("address", 1.00, address),
                    ("top", 2.50, top),
                    ("finish", 4.25, finish),
                ] {
                    guard boundary?.time == expectedTime else {
                        failures.append(
                            "\(fps) FPS \(noise.velocityY) after \(noise) moved \(name) to \(String(describing: boundary?.time))"
                        )
                        continue
                    }
                    let source = evidence.first { $0.time == expectedTime }
                    precondition(boundary?.sourceFrameIndex == source?.sourceFrameIndex)
                }
            }
        }

        precondition(failures.isEmpty, failures.joined(separator: "\n"))
    }

    private static func temporalFixture(
        fps: Int,
        boundaryNoise: BoundaryNoise? = nil,
        wrongDirectionNoise: WrongDirectionNoise? = nil
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
            if wrongDirectionNoise == .address, time == addressNoiseTime {
                velocityY = 0.14
                bodySpeed = 0.03
            } else if wrongDirectionNoise == .top, time == topNoiseTime {
                velocityY = -0.14
                bodySpeed = 0.04
            } else if boundaryNoise == .address, time == addressNoiseTime {
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
        velocityX: CGFloat = 0,
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
            rawPose: pose,
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
            handVelocity: CGPoint(x: velocityX, y: velocityY),
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

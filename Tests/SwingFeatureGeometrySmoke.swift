import Foundation

@main
struct SwingFeatureGeometrySmoke {
    static func main() {
        let pose = SwingPoseSample(
            time: 0,
            leftWrist: CGPoint(x: 0.20, y: 0.40),
            rightWrist: CGPoint(x: 0.58, y: 0.62),
            leftElbow: CGPoint(x: 0.35, y: 0.40),
            rightElbow: CGPoint(x: 0.63, y: 0.50),
            leftShoulder: CGPoint(x: 0.50, y: 0.40),
            rightShoulder: CGPoint(x: 0.65, y: 0.40),
            leftHip: CGPoint(x: 0.48, y: 0.62),
            rightHip: CGPoint(x: 0.62, y: 0.62),
            head: CGPoint(x: 0.55, y: 0.18),
            spineAngle: 0,
            aggregateConfidence: 0.95
        )

        precondition(abs(SwingGeometry.angleFromHorizontal(from: pose.leftShoulder!, to: pose.leftWrist!)) < 0.001)
        precondition(abs(SwingGeometry.jointAngle(a: pose.leftShoulder!, vertex: pose.leftElbow!, c: pose.leftWrist!) - 180) < 0.001)
        precondition(abs(SwingGeometry.lineAngle(from: pose.leftShoulder!, to: pose.rightShoulder!)) < 0.001)
        precondition(abs(SwingGeometry.lineAngle(from: pose.leftHip!, to: pose.rightHip!)) < 0.001)

        let leftwardArmAngle = SwingGeometry.angleFromHorizontal(
            from: CGPoint(x: 0.50, y: 0.40),
            to: CGPoint(x: 0.20, y: 0.26)
        )
        let expectedAcuteAngle = atan2(0.14, 0.30) * 180 / Double.pi
        precondition(
            abs(leftwardArmAngle - expectedAcuteAngle) < 0.001,
            "A leftward arm axis must use its acute angle from horizontal, got \(leftwardArmAngle)"
        )

        let object = SwingObjectEvidence(
            shaft: nil,
            ball: BallEvidence(center: CGPoint(x: 0.25, y: 0.80), radius: 0.012, confidence: 0.9),
            stableBall: CGPoint(x: 0.25, y: 0.80),
            ballLocalChange: 0
        )
        let frames = (0..<5).map { index in
            SwingFrameSample(
                sourceFrameIndex: index,
                time: Double(index) / 60,
                pose: pose,
                objectEvidence: object
            )
        }
        let evidence = SwingFeatureExtractor.extract(frames: frames)
        precondition(evidence.count == frames.count)
        precondition(evidence.allSatisfy { $0.leadArm == .left })
        precondition(evidence.allSatisfy { abs(($0.leadArmAngle ?? 90)) < 0.001 })
        precondition(evidence.allSatisfy { ($0.leadArmExtension ?? 0) > 179.9 })

        let jumpedPose = SwingPoseSample(
            time: 0,
            leftWrist: CGPoint(x: 0.82, y: 0.10),
            rightWrist: CGPoint(x: 0.86, y: 0.10),
            leftElbow: pose.leftElbow,
            rightElbow: pose.rightElbow,
            leftShoulder: pose.leftShoulder,
            rightShoulder: pose.rightShoulder,
            leftHip: pose.leftHip,
            rightHip: pose.rightHip,
            head: pose.head,
            spineAngle: pose.spineAngle,
            aggregateConfidence: pose.aggregateConfidence
        )
        let outlierFrames = (0..<9).map { index in
            SwingFrameSample(
                sourceFrameIndex: index,
                time: Double(index) / 30,
                pose: index == 4 ? jumpedPose : pose,
                objectEvidence: .empty
            )
        }
        let outlierEvidence = SwingFeatureExtractor.extract(frames: outlierFrames)
        let maximumHandSpeed = outlierEvidence.map {
            hypot(Double($0.handVelocity.x), Double($0.handVelocity.y))
        }.max() ?? 0
        precondition(
            maximumHandSpeed < 0.5,
            "One isolated Vision wrist outlier must not create a fake high-speed phase, got \(maximumHandSpeed)"
        )

        let swappedTorsoPose = SwingPoseSample(
            time: 0,
            leftWrist: pose.rightWrist,
            rightWrist: pose.leftWrist,
            leftElbow: pose.rightElbow,
            rightElbow: pose.leftElbow,
            leftShoulder: pose.rightShoulder,
            rightShoulder: pose.leftShoulder,
            leftHip: pose.rightHip,
            rightHip: pose.leftHip,
            head: pose.head,
            spineAngle: pose.spineAngle,
            aggregateConfidence: pose.aggregateConfidence
        )
        let alternatingTorsoFrames = (0..<9).map { index in
            SwingFrameSample(
                sourceFrameIndex: index,
                time: Double(index) / 30,
                pose: index.isMultiple(of: 2) ? pose : swappedTorsoPose,
                objectEvidence: .empty
            )
        }
        let alternatingTorsoEvidence = SwingFeatureExtractor.extract(frames: alternatingTorsoFrames)
        precondition(
            alternatingTorsoEvidence.allSatisfy {
                abs($0.shoulderAngle ?? 180) < 0.001 && abs($0.hipAngle ?? 180) < 0.001
            },
            "Shoulder and hip axes must remain unchanged when Vision exchanges left/right labels"
        )
        let alternatingTorsoTimeline = SwingEvidenceTimeline.build(from: alternatingTorsoEvidence)
        precondition(
            alternatingTorsoTimeline.allSatisfy {
                $0.direction == .stable
                    && !$0.sustainedBackswing
                    && !$0.sustainedDownswing
            },
            "Alternating left/right torso labels must not create a false direction transition"
        )
        precondition(
            alternatingTorsoTimeline.contains { $0.qualityFlags.contains(.labelSwapSuspected) },
            "Reversed raw torso endpoints should be reported without changing the undirected axes"
        )

        let isolatedSwapFrames = (0..<9).map { index in
            SwingFrameSample(
                sourceFrameIndex: 100 + index,
                time: Double(index) / 30,
                pose: index == 4 ? swappedTorsoPose : pose,
                objectEvidence: .empty
            )
        }
        let isolatedSwapTimeline = SwingEvidenceTimeline.build(
            from: SwingFeatureExtractor.extract(frames: isolatedSwapFrames)
        )
        precondition(
            isolatedSwapTimeline.first { $0.frame.sourceFrameIndex == 104 }?
                .qualityFlags.contains(.labelSwapSuspected) == true,
            "A single raw label reversal must remain visible after feature smoothing"
        )

        let ambiguousPose = SwingPoseSample(
            time: 0,
            leftWrist: CGPoint(x: 0.25, y: 0.42),
            rightWrist: CGPoint(x: 0.75, y: 0.42),
            leftElbow: CGPoint(x: 0.37, y: 0.42),
            rightElbow: CGPoint(x: 0.63, y: 0.42),
            leftShoulder: CGPoint(x: 0.49, y: 0.42),
            rightShoulder: CGPoint(x: 0.51, y: 0.42),
            leftHip: CGPoint(x: 0.46, y: 0.64),
            rightHip: CGPoint(x: 0.54, y: 0.64),
            head: CGPoint(x: 0.50, y: 0.20),
            spineAngle: 0,
            aggregateConfidence: 0.95
        )
        let ambiguousFrames = (0..<7).map { index in
            SwingFrameSample(
                sourceFrameIndex: 200 + index,
                time: Double(index) / 30,
                pose: ambiguousPose,
                objectEvidence: .empty
            )
        }
        let ambiguousTimeline = SwingEvidenceTimeline.build(
            from: SwingFeatureExtractor.extract(frames: ambiguousFrames)
        )
        precondition(ambiguousTimeline.allSatisfy { $0.frame.leadArm == .unknown })
        precondition(ambiguousTimeline.allSatisfy { $0.frame.leadArmAngle == nil })
        precondition(ambiguousTimeline.allSatisfy { $0.frame.leadArmExtension == nil })
        precondition(ambiguousTimeline.allSatisfy { $0.qualityFlags.contains(.missingLeadArm) })

        let ballInformedFrames = (0..<7).map { index in
            SwingFrameSample(
                sourceFrameIndex: 220 + index,
                time: Double(index) / 30,
                pose: ambiguousPose,
                objectEvidence: SwingObjectEvidence(
                    shaft: nil,
                    ball: nil,
                    stableBall: CGPoint(x: 0.35, y: 0.82),
                    ballLocalChange: 0
                )
            )
        }
        let ballInformedEvidence = SwingFeatureExtractor.extract(frames: ballInformedFrames)
        precondition(
            ballInformedEvidence.allSatisfy { $0.leadArm == .left },
            "Stable ball position must resolve an otherwise symmetric run-wide lead arm"
        )
        precondition(ballInformedEvidence.allSatisfy { $0.leadArmAngle != nil })

        let occludedLeft = SwingPoseSample(
            time: pose.time,
            leftWrist: pose.leftWrist,
            rightWrist: pose.rightWrist,
            leftElbow: nil,
            rightElbow: pose.rightElbow,
            leftShoulder: pose.leftShoulder,
            rightShoulder: pose.rightShoulder,
            leftHip: pose.leftHip,
            rightHip: pose.rightHip,
            head: pose.head,
            spineAngle: pose.spineAngle,
            aggregateConfidence: pose.aggregateConfidence
        )
        let occludedFrames = (0..<7).map { index in
            SwingFrameSample(
                sourceFrameIndex: 300 + index,
                time: Double(index) / 30,
                pose: index == 3 ? occludedLeft : pose,
                objectEvidence: object
            )
        }
        let occludedTimeline = SwingEvidenceTimeline.build(
            from: SwingFeatureExtractor.extract(frames: occludedFrames)
        )
        let selectedOcclusion = occludedTimeline[3]
        precondition(selectedOcclusion.frame.leadArmAngle != nil, "Smoothing may retain ranking geometry")
        precondition(selectedOcclusion.qualityFlags.contains(.missingLeadArm))
    }
}

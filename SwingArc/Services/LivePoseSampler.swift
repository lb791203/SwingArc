import AVFoundation
import CoreGraphics
import ImageIO
import Vision

struct LivePoseLandmarks: Equatable {
    let leftShoulder: CGPoint
    let rightShoulder: CGPoint
    let leftHip: CGPoint
    let rightHip: CGPoint
    let leftWrist: CGPoint
    let rightWrist: CGPoint
}

struct LivePoseMotionTracker {
    private struct PreviousPose {
        let time: TimeInterval
        let wristRelativeToTorso: CGPoint
        let leftShoulderRelativeToTorso: CGPoint
        let rightShoulderRelativeToTorso: CGPoint
        let leftHipRelativeToTorso: CGPoint
        let rightHipRelativeToTorso: CGPoint
        let torsoLength: CGFloat
    }

    private var previous: PreviousPose?

    mutating func reset() {
        previous = nil
    }

    mutating func ingestMissing(at time: TimeInterval) -> LivePoseMotionSample {
        previous = nil
        return LivePoseMotionSample(
            time: time,
            personVisible: false,
            normalizedWristSpeed: 0,
            normalizedTorsoSpeed: 0,
            backswingDirectionScore: 0,
            followThroughScore: 0
        )
    }

    mutating func ingest(
        landmarks: LivePoseLandmarks,
        at time: TimeInterval
    ) -> LivePoseMotionSample {
        let shoulderCenter = midpoint(landmarks.leftShoulder, landmarks.rightShoulder)
        let hipCenter = midpoint(landmarks.leftHip, landmarks.rightHip)
        let wristCenter = midpoint(landmarks.leftWrist, landmarks.rightWrist)
        let torsoCenter = midpoint(shoulderCenter, hipCenter)
        let torsoLength = max(distance(shoulderCenter, hipCenter), 0.05)
        let wristRelativeToTorso = subtract(wristCenter, torsoCenter)
        let leftShoulderRelativeToTorso = subtract(landmarks.leftShoulder, torsoCenter)
        let rightShoulderRelativeToTorso = subtract(landmarks.rightShoulder, torsoCenter)
        let leftHipRelativeToTorso = subtract(landmarks.leftHip, torsoCenter)
        let rightHipRelativeToTorso = subtract(landmarks.rightHip, torsoCenter)

        var wristSpeed = 0.0
        var torsoSpeed = 0.0
        if let previous,
           time > previous.time {
            let elapsed = time - previous.time
            let scale = max((Double(torsoLength) + Double(previous.torsoLength)) / 2, 0.05)
            wristSpeed = distance(
                wristRelativeToTorso,
                previous.wristRelativeToTorso
            ) / scale / elapsed
            let torsoShapeDistance = [
                distance(leftShoulderRelativeToTorso, previous.leftShoulderRelativeToTorso),
                distance(rightShoulderRelativeToTorso, previous.rightShoulderRelativeToTorso),
                distance(leftHipRelativeToTorso, previous.leftHipRelativeToTorso),
                distance(rightHipRelativeToTorso, previous.rightHipRelativeToTorso)
            ].reduce(0, +) / 4
            torsoSpeed = torsoShapeDistance / scale / elapsed
        }

        previous = PreviousPose(
            time: time,
            wristRelativeToTorso: wristRelativeToTorso,
            leftShoulderRelativeToTorso: leftShoulderRelativeToTorso,
            rightShoulderRelativeToTorso: rightShoulderRelativeToTorso,
            leftHipRelativeToTorso: leftHipRelativeToTorso,
            rightHipRelativeToTorso: rightHipRelativeToTorso,
            torsoLength: torsoLength
        )

        let onsetReference = LiveSwingTriggerConfiguration.standard.wristOnsetSpeed
        let backswingScore = min(1, max(0, wristSpeed / onsetReference))
        let wristHeightAboveShoulders = Double(wristCenter.y - shoulderCenter.y)
        let followThroughScore = min(
            1,
            max(0, wristHeightAboveShoulders / max(Double(torsoLength) * 0.4, 0.02))
        )

        return LivePoseMotionSample(
            time: time,
            personVisible: true,
            normalizedWristSpeed: wristSpeed,
            normalizedTorsoSpeed: torsoSpeed,
            backswingDirectionScore: backswingScore,
            followThroughScore: followThroughScore
        )
    }

    private func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
        CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> Double {
        hypot(Double(second.x - first.x), Double(second.y - first.y))
    }

    private func subtract(_ point: CGPoint, _ origin: CGPoint) -> CGPoint {
        CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }
}

final class LivePoseSampler {
    private let request = VNDetectHumanBodyPoseRequest()
    private let confidenceThreshold: VNConfidence = 0.35
    private let minimumSampleInterval: TimeInterval
    private var lastAcceptedTime: TimeInterval?
    private var motionTracker = LivePoseMotionTracker()

    init(sampleRate: Double = LiveSwingTriggerConfiguration.standard.sampleRate) {
        minimumSampleInterval = 1 / max(sampleRate, 1)
    }

    func reset() {
        lastAcceptedTime = nil
        motionTracker.reset()
    }

    func sample(
        from sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation = .right
    ) -> LivePoseMotionSample? {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid,
              presentationTime.seconds.isFinite,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        let time = presentationTime.seconds
        if let lastAcceptedTime,
           time >= lastAcceptedTime,
           time - lastAcceptedTime < minimumSampleInterval {
            return nil
        }
        if let lastAcceptedTime, time < lastAcceptedTime {
            motionTracker.reset()
        }
        lastAcceptedTime = time

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  let landmarks = try landmarks(from: observation) else {
                return motionTracker.ingestMissing(at: time)
            }
            return motionTracker.ingest(landmarks: landmarks, at: time)
        } catch {
            return motionTracker.ingestMissing(at: time)
        }
    }

    private func landmarks(
        from observation: VNHumanBodyPoseObservation
    ) throws -> LivePoseLandmarks? {
        let points = try observation.recognizedPoints(.all)
        func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let recognized = points[joint],
                  recognized.confidence >= confidenceThreshold else {
                return nil
            }
            return recognized.location
        }

        guard let leftShoulder = point(.leftShoulder),
              let rightShoulder = point(.rightShoulder),
              let leftHip = point(.leftHip),
              let rightHip = point(.rightHip),
              let visibleWrist = point(.leftWrist) ?? point(.rightWrist) else {
            return nil
        }
        let leftWrist = point(.leftWrist) ?? visibleWrist
        let rightWrist = point(.rightWrist) ?? visibleWrist
        let torsoLength = hypot(
            midpoint(leftShoulder, rightShoulder).x - midpoint(leftHip, rightHip).x,
            midpoint(leftShoulder, rightShoulder).y - midpoint(leftHip, rightHip).y
        )
        guard torsoLength >= 0.05 else { return nil }

        return LivePoseLandmarks(
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftHip: leftHip,
            rightHip: rightHip,
            leftWrist: leftWrist,
            rightWrist: rightWrist
        )
    }

    private func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
        CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }
}

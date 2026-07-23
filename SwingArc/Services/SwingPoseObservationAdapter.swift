import CoreGraphics
import Foundation

enum SwingPoseObservationAdapter {
    private static let landmarkByVisionName: [String: SwingLandmark] = [
        "leftShoulder": .leftShoulder,
        "rightShoulder": .rightShoulder,
        "leftElbow": .leftElbow,
        "rightElbow": .rightElbow,
        "leftWrist": .leftWrist,
        "rightWrist": .rightWrist,
        "leftHip": .leftHip,
        "rightHip": .rightHip,
        "leftKnee": .leftKnee,
        "rightKnee": .rightKnee,
        "leftAnkle": .leftAnkle,
        "rightAnkle": .rightAnkle
    ]

    static func frame(
        pose: PoseEstimationResult?,
        sourceFrameIndex: Int,
        time: Double
    ) -> SwingFrameObservation {
        guard let pose else {
            return SwingFrameObservation(
                sourceFrameIndex: sourceFrameIndex,
                time: time,
                landmarks: [:]
            )
        }

        var raw: [SwingLandmark: TrackedSwingPoint] = [:]
        for (name, landmark) in landmarkByVisionName {
            guard let joint = pose.keypoints[name] else { continue }
            raw[landmark] = detectedPoint(
                joint.position,
                confidence: Double(joint.confidence)
            )
        }

        if let head = pose.headCenter {
            let headConfidence = max(
                pose.keypoints["nose"]?.confidence ?? 0,
                pose.keypoints["neck"]?.confidence ?? 0
            )
            raw[.head] = detectedPoint(
                head,
                confidence: headConfidence > 0 ? Double(headConfidence) : Double(pose.aggregateConfidence)
            )
        }

        var tracked = raw
        let wrists = [raw[.leftWrist], raw[.rightWrist]].compactMap { point -> TrackedSwingPoint? in
            guard point?.point != nil else { return nil }
            return point
        }
        if !wrists.isEmpty {
            let count = Double(wrists.count)
            let center = wrists.compactMap(\.point).reduce(
                NormalizedPoint(x: 0, y: 0)
            ) { partial, point in
                NormalizedPoint(x: partial.x + point.x, y: partial.y + point.y)
            }
            tracked[.handCenter] = TrackedSwingPoint(
                point: NormalizedPoint(x: center.x / count, y: center.y / count),
                confidence: wrists.map(\.confidence).reduce(0, +) / count,
                state: .detected,
                source: .visionPose
            )
        }

        return SwingFrameObservation(
            sourceFrameIndex: sourceFrameIndex,
            time: time,
            landmarks: tracked,
            rawLandmarks: raw
        )
    }

    static func poseSample(from frame: SwingFrameObservation) -> SwingPoseSample? {
        let visible = frame.landmarks.values.filter { $0.point != nil && $0.state != .missing }
        guard !visible.isEmpty else { return nil }

        let leftShoulder = point(.leftShoulder, in: frame)
        let rightShoulder = point(.rightShoulder, in: frame)
        let leftHip = point(.leftHip, in: frame)
        let rightHip = point(.rightHip, in: frame)
        let shoulderMid = SwingGeometry.center(leftShoulder, rightShoulder)
        let hipMid = SwingGeometry.center(leftHip, rightHip)
        let spineAngle: Double?
        if let shoulderMid, let hipMid {
            spineAngle = atan2(
                Double(shoulderMid.x - hipMid.x),
                Double(hipMid.y - shoulderMid.y)
            ) * 180 / .pi
        } else {
            spineAngle = nil
        }
        let confidence = visible.map(\.confidence).reduce(0, +) / Double(visible.count)

        return SwingPoseSample(
            time: frame.time,
            leftWrist: point(.leftWrist, in: frame),
            rightWrist: point(.rightWrist, in: frame),
            leftElbow: point(.leftElbow, in: frame),
            rightElbow: point(.rightElbow, in: frame),
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftHip: leftHip,
            rightHip: rightHip,
            head: point(.head, in: frame),
            spineAngle: spineAngle,
            aggregateConfidence: Float(confidence),
            sourceFrameIndex: frame.sourceFrameIndex,
            leftKnee: point(.leftKnee, in: frame),
            rightKnee: point(.rightKnee, in: frame),
            leftAnkle: point(.leftAnkle, in: frame),
            rightAnkle: point(.rightAnkle, in: frame)
        )
    }

    private static func detectedPoint(
        _ point: CGPoint,
        confidence: Double
    ) -> TrackedSwingPoint {
        TrackedSwingPoint(
            point: NormalizedPoint(x: Double(point.x), y: Double(point.y)),
            confidence: min(1, max(0, confidence)),
            state: .detected,
            source: .visionPose
        )
    }

    private static func point(
        _ landmark: SwingLandmark,
        in frame: SwingFrameObservation
    ) -> CGPoint? {
        frame.landmarks[landmark]?.point.map {
            CGPoint(x: $0.x, y: $0.y)
        }
    }
}

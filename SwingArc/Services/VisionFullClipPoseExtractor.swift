import CoreGraphics
import ImageIO
import Vision

public struct VisionFullClipPoseSourceFrame {
    public let sourceFrameIndex: Int
    public let sourceTime: Double
    public let image: CGImage

    public init(sourceFrameIndex: Int, sourceTime: Double, image: CGImage) {
        self.sourceFrameIndex = sourceFrameIndex
        self.sourceTime = sourceTime
        self.image = image
    }
}

public enum VisionFullClipPoseExtractorError: Error, Equatable, CustomStringConvertible {
    case duplicateFrame(Int)
    case invalidFrame(Int)
    case nonMonotonicTime
    case invalidConfidenceThreshold
    case visionRequestFailed(frameIndex: Int, message: String)

    public var description: String {
        switch self {
        case .duplicateFrame(let index):
            return "Duplicate source frame \(index)"
        case .invalidFrame(let index):
            return "Invalid source frame metadata at frame \(index)"
        case .nonMonotonicTime:
            return "Source presentation times are not monotonically increasing"
        case .invalidConfidenceThreshold:
            return "Vision confidence threshold must be finite and in [0, 1]"
        case .visionRequestFailed(let frameIndex, let message):
            return "Vision pose request failed at frame \(frameIndex): \(message)"
        }
    }
}

/// Extracts every qualified body-pose observation from already-oriented source frames.
/// Candidate ordering is local to one frame and is never treated as identity.
public enum VisionFullClipPoseExtractor {
    private typealias JointName = VNHumanBodyPoseObservation.JointName

    private struct JointSample {
        let point: GolfNormalizedPoint
        let confidence: Double
    }

    public static func extract(
        frames: [VisionFullClipPoseSourceFrame],
        candidateConfidenceThreshold: Double = 0.2
    ) throws -> [GolfPoseCandidateFrame] {
        guard candidateConfidenceThreshold.isFinite,
              (0...1).contains(candidateConfidenceThreshold) else {
            throw VisionFullClipPoseExtractorError.invalidConfidenceThreshold
        }

        var seenFrames: Set<Int> = []
        for frame in frames {
            guard frame.sourceFrameIndex >= 0,
                  frame.sourceTime.isFinite,
                  frame.sourceTime >= 0 else {
                throw VisionFullClipPoseExtractorError.invalidFrame(
                    frame.sourceFrameIndex
                )
            }
            guard seenFrames.insert(frame.sourceFrameIndex).inserted else {
                throw VisionFullClipPoseExtractorError.duplicateFrame(
                    frame.sourceFrameIndex
                )
            }
        }

        let sortedFrames = frames.sorted {
            $0.sourceFrameIndex < $1.sourceFrameIndex
        }
        if sortedFrames.count > 1 {
            for index in 1..<sortedFrames.count
            where sortedFrames[index].sourceTime <= sortedFrames[index - 1].sourceTime {
                throw VisionFullClipPoseExtractorError.nonMonotonicTime
            }
        }

        var candidates: [GolfPoseCandidateFrame] = []
        for frame in sortedFrames {
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(
                cgImage: frame.image,
                orientation: .up,
                options: [:]
            )
            do {
                try handler.perform([request])
                for (candidateIndex, observation) in (request.results ?? []).enumerated() {
                    if let candidate = try makeCandidate(
                        observation: observation,
                        frame: frame,
                        candidateIndex: candidateIndex,
                        confidenceThreshold: candidateConfidenceThreshold
                    ) {
                        candidates.append(candidate)
                    }
                }
            } catch let error as VisionFullClipPoseExtractorError {
                throw error
            } catch {
                throw VisionFullClipPoseExtractorError.visionRequestFailed(
                    frameIndex: frame.sourceFrameIndex,
                    message: String(describing: error)
                )
            }
        }
        return candidates
    }

    private static func makeCandidate(
        observation: VNHumanBodyPoseObservation,
        frame: VisionFullClipPoseSourceFrame,
        candidateIndex: Int,
        confidenceThreshold: Double
    ) throws -> GolfPoseCandidateFrame? {
        let recognized = try observation.recognizedPoints(.all)
        var joints: [JointName: JointSample] = [:]
        for (name, recognizedPoint) in recognized {
            let confidence = Double(recognizedPoint.confidence)
            guard confidence >= confidenceThreshold else { continue }
            joints[name] = JointSample(
                point: GolfNormalizedPoint(
                    x: Double(recognizedPoint.location.x),
                    y: 1.0 - Double(recognizedPoint.location.y)
                ),
                confidence: confidence
            )
        }

        guard joints.count >= 2 else { return nil }
        let confidence = joints.values.map(\JointSample.confidence).reduce(0, +)
            / Double(joints.count)
        guard confidence >= confidenceThreshold,
              let bodyBounds = bodyBounds(joints: joints),
              let bodyCenter = bodyCenter(joints: joints) else {
            return nil
        }
        let bodyScale = max(bodyBounds.width, bodyBounds.height)
        guard bodyScale > 0 else { return nil }

        return GolfPoseCandidateFrame(
            sourceFrameIndex: frame.sourceFrameIndex,
            sourceTime: frame.sourceTime,
            candidateIndex: candidateIndex,
            bodyCenter: bodyCenter,
            bodyBounds: bodyBounds,
            bodyScale: bodyScale,
            jointGeometry: jointGeometry(joints: joints),
            handCenter: handCenter(joints: joints),
            identityConfidence: min(1, max(0, confidence))
        )
    }

    private static func bodyCenter(
        joints: [JointName: JointSample]
    ) -> GolfNormalizedPoint? {
        if let leftShoulder = joints[.leftShoulder]?.point,
           let rightShoulder = joints[.rightShoulder]?.point,
           let leftHip = joints[.leftHip]?.point,
           let rightHip = joints[.rightHip]?.point {
            let shoulderMid = midpoint(leftShoulder, rightShoulder)
            let hipMid = midpoint(leftHip, rightHip)
            return midpoint(shoulderMid, hipMid)
        }
        guard !joints.isEmpty else { return nil }
        let sum = joints.values.reduce((x: 0.0, y: 0.0)) {
            (x: $0.x + $1.point.x, y: $0.y + $1.point.y)
        }
        return GolfNormalizedPoint(
            x: sum.x / Double(joints.count),
            y: sum.y / Double(joints.count)
        )
    }

    private static func bodyBounds(
        joints: [JointName: JointSample]
    ) -> GolfNormalizedRect? {
        let points = joints.values.map(\JointSample.point)
        guard let minX = points.map(\GolfNormalizedPoint.x).min(),
              let maxX = points.map(\GolfNormalizedPoint.x).max(),
              let minY = points.map(\GolfNormalizedPoint.y).min(),
              let maxY = points.map(\GolfNormalizedPoint.y).max(),
              maxX > minX,
              maxY > minY else {
            return nil
        }
        return GolfNormalizedRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func jointGeometry(
        joints: [JointName: JointSample]
    ) -> GolfCandidateJointGeometry {
        let shoulderWidth = distance(
            joints[.leftShoulder]?.point,
            joints[.rightShoulder]?.point
        )
        let hipWidth = distance(
            joints[.leftHip]?.point,
            joints[.rightHip]?.point
        )
        let torsoLength: Double
        if let leftShoulder = joints[.leftShoulder]?.point,
           let rightShoulder = joints[.rightShoulder]?.point,
           let leftHip = joints[.leftHip]?.point,
           let rightHip = joints[.rightHip]?.point {
            torsoLength = distance(
                midpoint(leftShoulder, rightShoulder),
                midpoint(leftHip, rightHip)
            )
        } else {
            torsoLength = 0
        }
        return GolfCandidateJointGeometry(
            shoulderWidth: shoulderWidth,
            hipWidth: hipWidth,
            torsoLength: torsoLength
        )
    }

    private static func handCenter(
        joints: [JointName: JointSample]
    ) -> GolfNormalizedPoint? {
        let wrists = [
            joints[.leftWrist]?.point,
            joints[.rightWrist]?.point,
        ].compactMap { $0 }
        guard let first = wrists.first else { return nil }
        if wrists.count == 1 { return first }
        return midpoint(first, wrists[1])
    }

    private static func midpoint(
        _ lhs: GolfNormalizedPoint,
        _ rhs: GolfNormalizedPoint
    ) -> GolfNormalizedPoint {
        GolfNormalizedPoint(
            x: (lhs.x + rhs.x) / 2,
            y: (lhs.y + rhs.y) / 2
        )
    }

    private static func distance(
        _ lhs: GolfNormalizedPoint?,
        _ rhs: GolfNormalizedPoint?
    ) -> Double {
        guard let lhs, let rhs else { return 0 }
        return hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

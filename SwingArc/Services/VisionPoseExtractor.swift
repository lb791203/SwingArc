import Foundation
import CoreGraphics
#if canImport(Vision)
import Vision
#endif

public enum VisionPoseExtractor {
    public static var visionFrameworkVersion: String {
        #if os(macOS)
        let osVer = ProcessInfo.processInfo.operatingSystemVersion
        return "Vision.framework/macOS\(osVer.majorVersion).\(osVer.minorVersion)/VNDetectHumanBodyPoseRequestRevision1"
        #else
        return "Vision.framework/iOS/VNDetectHumanBodyPoseRequestRevision1"
        #endif
    }

    public static var visionRequestVersion: String {
        "VNDetectHumanBodyPoseRequestRevision1"
    }

    public static func extractCandidates(
        from cgImage: CGImage,
        sourceFrameIndex: Int,
        sourceTime: Double
    ) -> [GolfPoseCandidateFrame] {
        #if canImport(Vision)
        let request = VNDetectHumanBodyPoseRequest()
        request.revision = VNDetectHumanBodyPoseRequestRevision1
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        guard let observations = request.results, !observations.isEmpty else {
            return []
        }

        var candidates: [GolfPoseCandidateFrame] = []
        for (index, obs) in observations.enumerated() {
            guard let recognizedPoints = try? obs.recognizedPoints(.all) else { continue }
            var points: [GolfNormalizedPoint] = []
            for (_, pt) in recognizedPoints where pt.confidence > 0.1 {
                points.append(GolfNormalizedPoint(x: Double(pt.location.x), y: Double(1.0 - pt.location.y)))
            }
            guard !points.isEmpty else { continue }

            let xs = points.map(\.x)
            let ys = points.map(\.y)
            let minX = xs.min()!
            let minY = ys.min()!
            let maxX = xs.max()!
            let maxY = ys.max()!

            let bounds = GolfNormalizedRect(
                x: minX,
                y: minY,
                width: max(0.01, maxX - minX),
                height: max(0.01, maxY - minY)
            )
            let center = GolfNormalizedPoint(
                x: bounds.x + bounds.width / 2.0,
                y: bounds.y + bounds.height / 2.0
            )
            let scale = hypot(bounds.width, bounds.height)

            let lShoulder = recognizedPoints[.leftShoulder]
            let rShoulder = recognizedPoints[.rightShoulder]
            let lHip = recognizedPoints[.leftHip]
            let rHip = recognizedPoints[.rightHip]
            let neck = recognizedPoints[.neck]
            let root = recognizedPoints[.root]

            let shoulderW: Double
            if let lS = lShoulder, let rS = rShoulder, lS.confidence > 0.1, rS.confidence > 0.1 {
                shoulderW = hypot(Double(lS.location.x - rS.location.x), Double(lS.location.y - rS.location.y))
            } else {
                shoulderW = bounds.width * 0.4
            }

            let hipW: Double
            if let lH = lHip, let rH = rHip, lH.confidence > 0.1, rH.confidence > 0.1 {
                hipW = hypot(Double(lH.location.x - rH.location.x), Double(lH.location.y - rH.location.y))
            } else {
                hipW = bounds.width * 0.3
            }

            let torsoL: Double
            if let n = neck, let r = root, n.confidence > 0.1, r.confidence > 0.1 {
                torsoL = hypot(Double(n.location.x - r.location.x), Double(n.location.y - r.location.y))
            } else {
                torsoL = bounds.height * 0.5
            }

            var hands: [GolfNormalizedPoint] = []
            if let lW = recognizedPoints[.leftWrist], lW.confidence > 0.1 {
                hands.append(GolfNormalizedPoint(x: Double(lW.location.x), y: Double(1.0 - lW.location.y)))
            }
            if let rW = recognizedPoints[.rightWrist], rW.confidence > 0.1 {
                hands.append(GolfNormalizedPoint(x: Double(rW.location.x), y: Double(1.0 - rW.location.y)))
            }
            let handCenter: GolfNormalizedPoint?
            if !hands.isEmpty {
                handCenter = GolfNormalizedPoint(
                    x: hands.map(\.x).reduce(0, +) / Double(hands.count),
                    y: hands.map(\.y).reduce(0, +) / Double(hands.count)
                )
            } else {
                handCenter = nil
            }

            candidates.append(GolfPoseCandidateFrame(
                sourceFrameIndex: sourceFrameIndex,
                sourceTime: sourceTime,
                candidateIndex: index,
                bodyCenter: center,
                bodyBounds: bounds,
                bodyScale: scale,
                jointGeometry: GolfCandidateJointGeometry(
                    shoulderWidth: shoulderW,
                    hipWidth: hipW,
                    torsoLength: torsoL
                ),
                handCenter: handCenter,
                identityConfidence: Double(obs.confidence)
            ))
        }
        return candidates
        #else
        return []
        #endif
    }
}

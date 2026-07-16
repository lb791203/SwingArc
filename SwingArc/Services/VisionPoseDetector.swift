import Vision
import SwiftUI
import CoreVideo

/// 单个关节关键点数据
struct JointKeypoint: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let position: CGPoint // 归一化坐标：x 为 0-1 (左到右)，y 为 0-1 (上到下)
    let confidence: Float
}

/// 姿态分析结果
struct PoseEstimationResult: Equatable {
    var keypoints: [String: JointKeypoint] = [:]
    
    // 自动计算指标
    var spineAngle: Double? = nil // 脊椎与垂直线的夹角（度数）
    var headCenter: CGPoint? = nil // 头部定位中心
    var headRadius: CGFloat? = nil // 头部估算半径
    
    var shoulderMid: CGPoint? = nil
    var hipMid: CGPoint? = nil
    
    /// 获取归一化关节点位置
    func point(for name: String) -> CGPoint? {
        return keypoints[name]?.position
    }

    var aggregateConfidence: Float {
        guard !keypoints.isEmpty else { return 0 }
        return keypoints.values.map(\.confidence).reduce(0, +) / Float(keypoints.count)
    }
}

extension SwingPoseSample {
    init(time: Double, sourceFrameIndex: Int? = nil, pose: PoseEstimationResult) {
        self.init(
            time: time,
            leftWrist: pose.point(for: "leftWrist"),
            rightWrist: pose.point(for: "rightWrist"),
            leftElbow: pose.point(for: "leftElbow"),
            rightElbow: pose.point(for: "rightElbow"),
            leftShoulder: pose.point(for: "leftShoulder"),
            rightShoulder: pose.point(for: "rightShoulder"),
            leftHip: pose.point(for: "leftHip"),
            rightHip: pose.point(for: "rightHip"),
            head: pose.headCenter,
            spineAngle: pose.spineAngle,
            aggregateConfidence: pose.aggregateConfidence,
            sourceFrameIndex: sourceFrameIndex,
            leftKnee: pose.point(for: "leftKnee"),
            rightKnee: pose.point(for: "rightKnee"),
            leftAnkle: pose.point(for: "leftAnkle"),
            rightAnkle: pose.point(for: "rightAnkle")
        )
    }
}

/// 基于 Apple Vision 的实时姿态检测器
class VisionPoseDetector {
    private var poseRequest = VNDetectHumanBodyPoseRequest()
    
    init() {}
    
    /// 在指定的像素缓冲区上执行姿态检测
    func detectPose(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) -> PoseEstimationResult? {
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        
        do {
            try requestHandler.perform([poseRequest])
            guard let results = poseRequest.results, let observation = results.first else {
                return nil
            }
            
            // 获取所有识别到的身体关节点
            let recognizedPoints = try observation.recognizedPoints(.all)
            var result = PoseEstimationResult()
            var joints: [String: JointKeypoint] = [:]
            
            // 定义关节点映射
            let landmarkMap: [String: VNHumanBodyPoseObservation.JointName] = [
                "nose": .nose,
                "neck": .neck,
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
            
            for (key, jointName) in landmarkMap {
                if let recognizedPoint = recognizedPoints[jointName], recognizedPoint.confidence > 0.3 {
                    // Vision 坐标系 (0,0) 为左下角，(1,1) 为右上角。
                    // 转换至标准绘图坐标系：x 相同，y 翻转（y = 1.0 - visionY）
                    let normalizedPoint = CGPoint(
                        x: recognizedPoint.location.x,
                        y: 1.0 - recognizedPoint.location.y
                    )
                    joints[key] = JointKeypoint(
                        name: key,
                        position: normalizedPoint,
                        confidence: recognizedPoint.confidence
                    )
                }
            }
            
            result.keypoints = joints
            
            // 自动计算脊椎中轴线与倾斜角
            calculateSpineMetrics(in: &result)
            
            // 自动计算头部稳定圈
            calculateHeadMetrics(in: &result)
            
            return result
        } catch {
            print("Vision pose detection error: \(error)")
            return nil
        }
    }
    
    /// 计算脊椎参数
    private func calculateSpineMetrics(in result: inout PoseEstimationResult) {
        guard let leftShoulder = result.point(for: "leftShoulder"),
              let rightShoulder = result.point(for: "rightShoulder"),
              let leftHip = result.point(for: "leftHip"),
              let rightHip = result.point(for: "rightHip") else {
            return
        }
        
        // 计算肩膀中点与髋部中点
        let shoulderMid = CGPoint(
            x: (leftShoulder.x + rightShoulder.x) / 2.0,
            y: (leftShoulder.y + rightShoulder.y) / 2.0
        )
        let hipMid = CGPoint(
            x: (leftHip.x + rightHip.x) / 2.0,
            y: (leftHip.y + rightHip.y) / 2.0
        )
        
        result.shoulderMid = shoulderMid
        result.hipMid = hipMid
        
        // 脊椎向量 (从髋部中点指向肩膀中点)
        let dx = shoulderMid.x - hipMid.x
        let dy = shoulderMid.y - hipMid.y
        
        // 计算与垂直线的夹角
        // 正常直立时 dy < 0 (因为肩膀的 y 坐标小于髋部的 y 坐标)，dx 接近 0
        // 使用 atan2 计算，并转换为度数
        let angleRadians = atan2(dx, -dy) // 垂直向上为0度
        let angleDegrees = angleRadians * 180.0 / .pi
        
        result.spineAngle = Double(angleDegrees)
    }
    
    /// 计算头部位置与估算半径
    private func calculateHeadMetrics(in result: inout PoseEstimationResult) {
        // 首选鼻尖作为头部中心，若无则使用颈部向上平移作为估算
        var center: CGPoint? = nil
        
        if let nose = result.point(for: "nose") {
            center = nose
        } else if let neck = result.point(for: "neck"),
                  let shoulderMid = result.shoulderMid {
            // 没有鼻尖时，沿着脊椎反方向平移颈部
            let dx = neck.x - shoulderMid.x
            let dy = neck.y - shoulderMid.y
            center = CGPoint(x: neck.x + dx * 0.8, y: neck.y + dy * 0.8)
        }
        
        guard let headCenter = center else { return }
        result.headCenter = headCenter
        
        // 根据肩膀宽度估算头部的半径
        if let leftShoulder = result.point(for: "leftShoulder"),
           let rightShoulder = result.point(for: "rightShoulder") {
            let shoulderWidth = sqrt(pow(leftShoulder.x - rightShoulder.x, 2) + pow(leftShoulder.y - rightShoulder.y, 2))
            // 头部半径约为肩膀宽度的 25% 到 30%
            result.headRadius = shoulderWidth * 0.28
        } else {
            result.headRadius = 0.06 // 默认归一化半径为 0.06
        }
    }
    
    /// 在指定的 CGImage 上执行姿态检测 (用于视频帧后台扫描)
    func detectPose(in cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) -> PoseEstimationResult? {
        detectPoses(in: cgImage, orientation: orientation).first
    }

    /// Returns every visible person so the two-stage analyzer can keep one
    /// golfer identity across the coarse and fine passes.
    func detectPoses(in cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) -> [PoseEstimationResult] {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try requestHandler.perform([poseRequest])
            guard let observations = poseRequest.results else { return [] }
            return observations.compactMap { try? poseResult(from: $0) }
        } catch {
            print("Vision pose detection error on CGImage: \(error)")
            return []
        }
    }

    private func poseResult(from observation: VNHumanBodyPoseObservation) throws -> PoseEstimationResult {
            let recognizedPoints = try observation.recognizedPoints(.all)
            var result = PoseEstimationResult()
            var joints: [String: JointKeypoint] = [:]

            let landmarkMap: [String: VNHumanBodyPoseObservation.JointName] = [
                "nose": .nose,
                "neck": .neck,
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

            for (key, jointName) in landmarkMap {
                if let recognizedPoint = recognizedPoints[jointName], recognizedPoint.confidence > 0.3 {
                    let normalizedPoint = CGPoint(
                        x: recognizedPoint.location.x,
                        y: 1.0 - recognizedPoint.location.y
                    )
                    joints[key] = JointKeypoint(
                        name: key,
                        position: normalizedPoint,
                        confidence: recognizedPoint.confidence
                    )
                }
            }

            result.keypoints = joints
            calculateSpineMetrics(in: &result)
            calculateHeadMetrics(in: &result)
            return result
    }
}

final class PrimaryGolferTracker {
    private var previousCenter: CGPoint?
    private var consecutiveMisses = 0

    func select(from candidates: [PoseEstimationResult], stableBall: CGPoint?) -> PoseEstimationResult? {
        guard !candidates.isEmpty else {
            consecutiveMisses += 1
            if consecutiveMisses > 4 { previousCenter = nil }
            return nil
        }

        let ranked = candidates.compactMap { pose -> (PoseEstimationResult, CGPoint, Double)? in
            guard let center = bodyCenter(pose) else { return nil }
            let scale = bodyScale(pose)
            let centerPreference = 1 - min(1, abs(Double(center.x - 0.5)) / 0.5)
            let continuity = previousCenter.map {
                1 - min(1, SwingGeometry.distance(center, $0) / 0.35)
            } ?? centerPreference
            let ballPreference = stableBall.map {
                1 - min(1, SwingGeometry.distance(center, $0) / 0.85)
            } ?? centerPreference
            let score = Double(pose.aggregateConfidence) * 0.30 +
                min(1, scale / 0.65) * 0.25 +
                continuity * 0.30 +
                ballPreference * 0.10 +
                centerPreference * 0.05
            return (pose, center, score)
        }.sorted { $0.2 > $1.2 }

        guard let best = ranked.first else { return nil }
        if previousCenter == nil,
           ranked.count > 1,
           ranked[1].2 >= best.2 * 0.97 {
            consecutiveMisses += 1
            return nil
        }
        previousCenter = best.1
        consecutiveMisses = 0
        return best.0
    }

    private func bodyCenter(_ pose: PoseEstimationResult) -> CGPoint? {
        pose.hipMid ?? pose.shoulderMid ?? SwingGeometry.center(
            pose.point(for: "leftHip"),
            pose.point(for: "rightHip")
        )
    }

    private func bodyScale(_ pose: PoseEstimationResult) -> Double {
        let points = pose.keypoints.values.map(\.position)
        guard let minimumX = points.map(\.x).min(),
              let maximumX = points.map(\.x).max(),
              let minimumY = points.map(\.y).min(),
              let maximumY = points.map(\.y).max() else { return 0 }
        return Double(max(maximumX - minimumX, maximumY - minimumY))
    }
}

/// Replaceable, fully local first-pass detector for club-shaft and ball evidence.
/// It deliberately exposes only normalized geometry to the stage solver so a
/// future offline Core ML implementation can replace the contour backend.
final class SwingObjectDetector {
    private var ballTracker: BallPositionTracker

    init(seedBall: BallEvidence? = nil) {
        ballTracker = BallPositionTracker(seed: seedBall)
    }

    var stableBall: BallEvidence? { ballTracker.stableBall }

    func detect(in cgImage: CGImage, pose: PoseEstimationResult?) -> SwingObjectEvidence {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.3
        request.detectsDarkOnLight = true
        request.maximumImageDimension = SwingObjectRegionPolicy.maximumImageDimension
        let visionRegion = SwingObjectRegionPolicy.visionRegion(
            points: pose?.keypoints.values.map(\.position) ?? []
        )
        request.regionOfInterest = visionRegion

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first else {
            let update = ballTracker.update(nil)
            return SwingObjectEvidence(
                shaft: nil,
                ball: nil,
                stableBall: update.stableBall?.center,
                ballLocalChange: update.localChange
            )
        }

        let contours = flattenedContours(observation.topLevelContours)
        let handCenter = pose.flatMap(Self.handCenter)
        let ballCandidate = bestBallCandidate(in: contours, pose: pose, visionRegion: visionRegion)
        let update = ballTracker.update(ballCandidate)
        let shaft = bestShaftCandidate(
            in: contours,
            handCenter: handCenter,
            stableBall: update.stableBall?.center,
            visionRegion: visionRegion
        )
        return SwingObjectEvidence(
            shaft: shaft,
            ball: ballCandidate,
            stableBall: update.stableBall?.center,
            ballLocalChange: update.localChange
        )
    }

    private func flattenedContours(_ contours: [VNContour]) -> [VNContour] {
        contours.flatMap { [$0] + flattenedContours($0.childContours) }
    }

    private func bestBallCandidate(
        in contours: [VNContour],
        pose: PoseEstimationResult?,
        visionRegion: CGRect
    ) -> BallEvidence? {
        let hipY = pose?.hipMid?.y ?? 0.55
        return contours.compactMap { contour -> (BallEvidence, Double)? in
            let points = normalizedPoints(contour, visionRegion: visionRegion)
            guard points.count >= 5, let bounds = bounds(of: points) else { return nil }
            let width = Double(bounds.width)
            let height = Double(bounds.height)
            let maximum = max(width, height)
            let minimum = min(width, height)
            guard minimum >= 0.004,
                  maximum <= 0.055,
                  bounds.midY >= hipY - 0.02 else { return nil }
            let aspect = minimum / max(maximum, .leastNonzeroMagnitude)
            guard aspect >= 0.62 else { return nil }
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let radius = (width + height) / 4
            let groundPreference = min(1, max(0, Double(center.y - hipY) / 0.35))
            let score = aspect * 0.70 + groundPreference * 0.20 + min(1, Double(points.count) / 24) * 0.10
            return (BallEvidence(center: center, radius: radius, confidence: score), score)
        }.max { $0.1 < $1.1 }?.0
    }

    private func bestShaftCandidate(
        in contours: [VNContour],
        handCenter: CGPoint?,
        stableBall: CGPoint?,
        visionRegion: CGRect
    ) -> ClubShaftEvidence? {
        guard let handCenter else { return nil }
        return contours.compactMap { contour -> (ClubShaftEvidence, Double)? in
            let points = normalizedPoints(contour, visionRegion: visionRegion)
            guard points.count >= 2,
                  let pair = farthestPair(in: points) else { return nil }
            let evidence = ClubShaftEvidence(start: pair.0, end: pair.1, confidence: 0)
            guard evidence.length >= 0.08,
                  evidence.isConnected(to: handCenter, tolerance: 0.13) else { return nil }

            let pathLength = zip(points, points.dropFirst()).reduce(0.0) {
                $0 + SwingGeometry.distance($1.0, $1.1)
            }
            let straightness = min(1, evidence.length / max(pathLength, evidence.length))
            guard straightness >= 0.45 else { return nil }
            let ballAlignment = stableBall.map {
                max(0, 1 - evidence.distanceFromExtendedLine(to: $0) / 0.10)
            } ?? 0.35
            let score = min(1, evidence.length * 2.5) * 0.35 + straightness * 0.40 + ballAlignment * 0.25
            return (
                ClubShaftEvidence(start: pair.0, end: pair.1, confidence: score),
                score
            )
        }.max { $0.1 < $1.1 }?.0
    }

    private func normalizedPoints(_ contour: VNContour, visionRegion: CGRect) -> [CGPoint] {
        contour.normalizedPoints.map {
            CGPoint(
                x: visionRegion.minX + CGFloat($0.x) * visionRegion.width,
                y: 1 - (visionRegion.minY + CGFloat($0.y) * visionRegion.height)
            )
        }
    }

    private func bounds(of points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minimumX = first.x
        var maximumX = first.x
        var minimumY = first.y
        var maximumY = first.y
        for point in points.dropFirst() {
            minimumX = min(minimumX, point.x)
            maximumX = max(maximumX, point.x)
            minimumY = min(minimumY, point.y)
            maximumY = max(maximumY, point.y)
        }
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }

    private func farthestPair(in points: [CGPoint]) -> (CGPoint, CGPoint)? {
        guard points.count >= 2 else { return nil }
        let step = max(1, points.count / 32)
        let sampled = stride(from: 0, to: points.count, by: step).map { points[$0] }
        var best: (CGPoint, CGPoint, Double)?
        for firstIndex in sampled.indices {
            for secondIndex in sampled.indices where secondIndex > firstIndex {
                let distance = SwingGeometry.distance(sampled[firstIndex], sampled[secondIndex])
                if best == nil || distance > best!.2 {
                    best = (sampled[firstIndex], sampled[secondIndex], distance)
                }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    nonisolated private static func handCenter(_ pose: PoseEstimationResult) -> CGPoint? {
        SwingGeometry.center(pose.point(for: "leftWrist"), pose.point(for: "rightWrist"))
    }
}

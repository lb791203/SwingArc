import Vision
import SwiftUI
import CoreVideo
import AVFoundation

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

struct PrimaryGolferIdentity: Equatable {
    let center: CGPoint
    let scale: Double
}

enum PrimaryGolferTrackingPolicy {
    static func maximumCenterDistance(for anchorScale: Double) -> Double {
        min(0.34, max(0.24, anchorScale * 0.52))
    }

    static func maximumScaleDelta() -> Double { 0.34 }

    static func matches(
        candidate: PrimaryGolferIdentity,
        anchor: PrimaryGolferIdentity
    ) -> Bool {
        let distance = hypot(
            Double(candidate.center.x - anchor.center.x),
            Double(candidate.center.y - anchor.center.y)
        )
        let scaleDelta = abs(candidate.scale - anchor.scale) / max(anchor.scale, 0.10)
        return distance <= maximumCenterDistance(for: anchor.scale)
            && scaleDelta <= maximumScaleDelta()
    }

    static func shouldRetainAnchor(afterConsecutiveMisses misses: Int) -> Bool {
        misses <= 4
    }
}

struct PrimaryGolferTrackingDiagnostics: Codable, Equatable {
    var acceptedFrames = 0
    var rejectedOutsideAnchor = 0
    var rejectedScaleMismatch = 0
    var noPoseFrames = 0
}

final class PrimaryGolferTracker {
    private var previousCenter: CGPoint?
    private var identityAnchor: PrimaryGolferIdentity?
    private var consecutiveMisses = 0
    private(set) var diagnostics = PrimaryGolferTrackingDiagnostics()

    @discardableResult
    func lockIdentityAnchor(to pose: PoseEstimationResult) -> Bool {
        guard let center = bodyCenter(pose) else { return false }
        let scale = bodyScale(pose)
        guard scale > 0 else { return false }
        identityAnchor = PrimaryGolferIdentity(center: center, scale: scale)
        previousCenter = center
        consecutiveMisses = 0
        return true
    }

    func select(from candidates: [PoseEstimationResult], stableBall: CGPoint?) -> PoseEstimationResult? {
        guard !candidates.isEmpty else {
            registerMissingPose()
            return nil
        }

        let ranked = candidates.compactMap { pose -> (PoseEstimationResult, CGPoint, Double)? in
            guard let center = bodyCenter(pose) else { return nil }
            let scale = bodyScale(pose)
            let anchorPreference: Double
            if let identityAnchor {
                let candidate = PrimaryGolferIdentity(center: center, scale: scale)
                let anchorDistance = SwingGeometry.distance(center, identityAnchor.center)
                let maximumDistance = PrimaryGolferTrackingPolicy.maximumCenterDistance(
                    for: identityAnchor.scale
                )
                guard anchorDistance <= maximumDistance else {
                    diagnostics.rejectedOutsideAnchor += 1
                    return nil
                }
                let scaleMatch = 1 - min(
                    1,
                    abs(scale - identityAnchor.scale) / max(identityAnchor.scale, 0.10)
                )
                guard PrimaryGolferTrackingPolicy.matches(candidate: candidate, anchor: identityAnchor) else {
                    diagnostics.rejectedScaleMismatch += 1
                    return nil
                }
                let centerMatch = 1 - min(1, anchorDistance / maximumDistance)
                anchorPreference = centerMatch * 0.80 + scaleMatch * 0.20
            } else {
                anchorPreference = 0
            }
            let centerPreference = 1 - min(1, abs(Double(center.x - 0.5)) / 0.5)
            let continuity = previousCenter.map {
                1 - min(1, SwingGeometry.distance(center, $0) / 0.35)
            } ?? centerPreference
            let ballPreference = stableBall.map {
                1 - min(1, SwingGeometry.distance(center, $0) / 0.85)
            } ?? centerPreference
            let score: Double
            if identityAnchor != nil {
                score = Double(pose.aggregateConfidence) * 0.25 +
                    min(1, scale / 0.65) * 0.15 +
                    continuity * 0.15 +
                    anchorPreference * 0.35 +
                    ballPreference * 0.05 +
                    centerPreference * 0.05
            } else {
                score = Double(pose.aggregateConfidence) * 0.30 +
                    min(1, scale / 0.65) * 0.25 +
                    continuity * 0.30 +
                    ballPreference * 0.10 +
                    centerPreference * 0.05
            }
            return (pose, center, score)
        }.sorted { $0.2 > $1.2 }

        guard let best = ranked.first else {
            registerMissingPose()
            return nil
        }
        if previousCenter == nil,
           ranked.count > 1,
           ranked[1].2 >= best.2 * 0.97 {
            consecutiveMisses += 1
            return nil
        }
        previousCenter = best.1
        consecutiveMisses = 0
        diagnostics.acceptedFrames += 1
        return best.0
    }

    private func registerMissingPose() {
        diagnostics.noPoseFrames += 1
        consecutiveMisses += 1
        if !PrimaryGolferTrackingPolicy.shouldRetainAnchor(
            afterConsecutiveMisses: consecutiveMisses
        ) {
            previousCenter = nil
        }
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

    func detect(
        in cgImage: CGImage,
        pose: PoseEstimationResult?,
        sourceFrameIndex: Int
    ) -> SwingObjectEvidence {
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
            let update = ballTracker.update(nil, sourceFrameIndex: sourceFrameIndex)
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
        let update = ballTracker.update(
            ballCandidate,
            sourceFrameIndex: sourceFrameIndex
        )
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

struct SwingVideoAnalysisOutput: Equatable {
    let result: SwingAnalysisResult
    /// The exact fine-frame pose inputs used to resolve the P1–P8 path. This
    /// lets downstream, evidence-backed technique checks reuse the completed
    /// Vision pass instead of decoding and detecting the same video twice.
    let poseSamples: [SwingPoseSample]
    let leadArm: LeadArmSide
    let adaptiveWindow: SwingWindow
    let sourceFrameRate: Double
    let elapsedSeconds: Double
    let trackingDiagnostics: PrimaryGolferTrackingDiagnostics
    /// Fine-frame observations after body and available golf-object points
    /// have been merged and temporally tracked. Point state and source remain.
    let observationFrames: [SwingFrameObservation]

    init(
        result: SwingAnalysisResult,
        poseSamples: [SwingPoseSample],
        leadArm: LeadArmSide,
        adaptiveWindow: SwingWindow,
        sourceFrameRate: Double,
        elapsedSeconds: Double,
        trackingDiagnostics: PrimaryGolferTrackingDiagnostics = .init(),
        observationFrames: [SwingFrameObservation] = []
    ) {
        self.result = result
        self.poseSamples = poseSamples
        self.leadArm = leadArm
        self.adaptiveWindow = adaptiveWindow
        self.sourceFrameRate = sourceFrameRate
        self.elapsedSeconds = elapsedSeconds
        self.trackingDiagnostics = trackingDiagnostics
        self.observationFrames = observationFrames
    }
}

enum SwingVideoAnalysisOutcome: Equatable {
    case completed(SwingVideoAnalysisOutput)
    case failed(AnalysisFailure)
    case cancelled
}

struct SwingAnalysisProgressUpdate: Equatable {
    let phase: AnalysisProgressPhase
    let progress: Double
}

enum SourceFrameMatchValidation: Equatable {
    case matched(sourceFrameIndex: Int)
    case failed(AnalysisFailure)
}

/// Run-local accounting guard for adaptive fine-frame AV decoding. Coarse
/// localization is a separate 8 FPS pass; sparse object analysis reuses the
/// fine image cache and performs no AV decode.
final class AdaptiveFineDecodeLedger {
    private var sourceFrames: Set<Int> = []

    @discardableResult
    func registerDecode(sourceFrameIndex: Int) -> Bool {
        guard sourceFrameIndex >= 0,
              sourceFrames.insert(sourceFrameIndex).inserted else { return false }
        return true
    }

    var totalDecodeCount: Int { sourceFrames.count }

    var maximumDecodeCountPerSourceFrame: Int {
        sourceFrames.isEmpty ? 0 : 1
    }
}

enum SourceFrameRequestTimePolicy {
    static func time(
        sourceFrameIndex: Int,
        sourceFrameRate: Double
    ) -> CMTime {
        let roundedFrameRate = sourceFrameRate.rounded()
        if abs(sourceFrameRate - roundedFrameRate) < 1e-9,
           roundedFrameRate > 0,
           roundedFrameRate <= Double(Int32.max) {
            return CMTime(
                value: CMTimeValue(sourceFrameIndex),
                timescale: CMTimeScale(roundedFrameRate)
            )
        }
        return CMTime(
            seconds: Double(sourceFrameIndex) / sourceFrameRate,
            preferredTimescale: 60_000
        )
    }
}

enum SourceFrameMatchPolicy {
    /// A decoded timestamp identifies the requested source frame only inside
    /// its open half-frame interval. The exact half-frame boundary is rejected
    /// because it is ambiguous between adjacent source indices.
    static func validate(
        requestedSourceFrameIndex: Int,
        actualTime: Double,
        sourceFrameRate: Double
    ) -> SourceFrameMatchValidation {
        guard requestedSourceFrameIndex >= 0,
              actualTime.isFinite,
              sourceFrameRate.isFinite,
              sourceFrameRate > 0 else { return .failed(.frameExtractionFailed) }
        let framePosition = actualTime * sourceFrameRate
        let distance = abs(framePosition - Double(requestedSourceFrameIndex))
        guard distance + 1e-9 < 0.5 else { return .failed(.frameExtractionFailed) }
        let observedIndex = Int(framePosition.rounded())
        guard observedIndex == requestedSourceFrameIndex else {
            return .failed(.frameExtractionFailed)
        }
        return .matched(sourceFrameIndex: observedIndex)
    }
}

enum FineFrameImageLoadResult {
    case decoded(CGImage)
    case cached(CGImage)
    case failed
}

/// Run-local ownership of contour inputs. Only <=256-pixel images survive the
/// fine pose call, and the entry count is capped by the adaptive frame budget.
final class FineFrameImageCache {
    static let maximumImageDimension = 256

    private let maximumEntryCount: Int
    private var imagesBySourceFrame: [Int: CGImage] = [:]

    init(maximumEntryCount: Int) {
        self.maximumEntryCount = max(0, maximumEntryCount)
    }

    var count: Int { imagesBySourceFrame.count }

    func load(
        sourceFrameIndex: Int,
        decoder: () -> CGImage?
    ) -> FineFrameImageLoadResult {
        if let cached = imagesBySourceFrame[sourceFrameIndex] {
            return .cached(cached)
        }
        guard imagesBySourceFrame.count < maximumEntryCount,
              let decoded = decoder(),
              let contourImage = Self.downscaledContourImage(decoded) else {
            return .failed
        }
        imagesBySourceFrame[sourceFrameIndex] = contourImage
        return .decoded(decoded)
    }

    func contourImage(sourceFrameIndex: Int) -> CGImage? {
        imagesBySourceFrame[sourceFrameIndex]
    }

    func retainSourceFrames(_ sourceFrameIndices: Set<Int>) {
        imagesBySourceFrame = imagesBySourceFrame.filter {
            sourceFrameIndices.contains($0.key)
        }
    }

    private static func downscaledContourImage(_ image: CGImage) -> CGImage? {
        let sourceMaximum = max(image.width, image.height)
        guard sourceMaximum > 0 else { return nil }
        guard sourceMaximum > maximumImageDimension else { return image }

        let scale = Double(maximumImageDimension) / Double(sourceMaximum)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// Shared AVFoundation/Vision orchestration for UI and command-line analysis.
/// The engine is deliberately stateless: one call owns all detectors, caches,
/// and tracking state, while `AnalysisRunGate` remains the publication authority.
final class SwingVideoAnalysisEngine: @unchecked Sendable {
    typealias ProgressHandler = @Sendable (SwingAnalysisProgressUpdate) -> Void

    private let motionBlurDisposition: SwingMotionBlurDisposition
    private let diagnosticsLock = NSLock()
    private var storedTrackingDiagnostics = PrimaryGolferTrackingDiagnostics()

    init(motionBlurDisposition: SwingMotionBlurDisposition = .warning) {
        self.motionBlurDisposition = motionBlurDisposition
    }

    var latestTrackingDiagnostics: PrimaryGolferTrackingDiagnostics {
        diagnosticsLock.lock()
        defer { diagnosticsLock.unlock() }
        return storedTrackingDiagnostics
    }

    private final class TrackedPoseDetector {
        private struct TimedPose {
            let time: Double
            let pose: PoseEstimationResult
        }

        let vision = VisionPoseDetector()
        let golferTracker = PrimaryGolferTracker()
        private var selectedCoarsePoses: [TimedPose] = []

        var diagnostics: PrimaryGolferTrackingDiagnostics {
            golferTracker.diagnostics
        }

        func selectPose(
            in image: CGImage,
            time: Double,
            recordsCoreAnchorCandidate: Bool
        ) -> PoseEstimationResult? {
            selectPose(
                from: vision.detectPoses(in: image, orientation: .up),
                time: time,
                recordsCoreAnchorCandidate: recordsCoreAnchorCandidate
            )
        }

        private func selectPose(
            from candidates: [PoseEstimationResult],
            time: Double,
            recordsCoreAnchorCandidate: Bool
        ) -> PoseEstimationResult? {
            let selected = golferTracker.select(from: candidates, stableBall: nil)
            if recordsCoreAnchorCandidate, let selected {
                selectedCoarsePoses.append(TimedPose(time: time, pose: selected))
            }
            return selected
        }

        func lockIdentityAnchor(near time: Double) -> Bool {
            guard let nearest = selectedCoarsePoses.min(by: {
                abs($0.time - time) < abs($1.time - time)
            }), abs(nearest.time - time) <= 0.5 else { return false }
            return golferTracker.lockIdentityAnchor(to: nearest.pose)
        }
    }

    private struct PoseFrameExtraction {
        let sample: SwingFrameSample
        let rawPose: PoseEstimationResult?
    }

    func analyze(
        url: URL,
        runID: UUID,
        gate: AnalysisRunGate,
        candidateWindow: SwingWindow? = nil,
        progress: @escaping ProgressHandler
    ) -> SwingVideoAnalysisOutcome {
        let trackedPoseDetector = TrackedPoseDetector()
        var shouldStoreLocalDiagnostics = true
        defer {
            if shouldStoreLocalDiagnostics {
                storeTrackingDiagnostics(trackedPoseDetector.diagnostics)
            }
        }
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard gate.isActive(runID) else { return .cancelled }
        publish(.preparing, progress: 0, runID: runID, gate: gate, handler: progress)

        let asset = AVURLAsset(url: url)
        let duration = asset.duration.seconds
        guard duration.isFinite, duration > 0 else {
            return activeFailure(.invalidDuration, runID: runID, gate: gate)
        }
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            return activeFailure(.frameExtractionFailed, runID: runID, gate: gate)
        }
        let metadataFrameRate = Double(videoTrack.nominalFrameRate)
        guard metadataFrameRate.isFinite, metadataFrameRate > 0 else {
            return activeFailure(.frameExtractionFailed, runID: runID, gate: gate)
        }
        let sourceFrameTimeline: SourceFrameTimeline?
        if metadataFrameRate == metadataFrameRate.rounded(),
           metadataFrameRate <= FineSwingSamplingPlan.maximumSamplesPerSecond {
            sourceFrameTimeline = SourceFrameTimeline(
                duration: duration,
                constantFrameRate: metadataFrameRate
            )
        } else {
            sourceFrameTimeline = try? ExactVideoFrameProvider.load(url: url).timeline
        }
        guard let sourceFrameTimeline else {
            return activeFailure(.frameExtractionFailed, runID: runID, gate: gate)
        }
        let sourceFrameRate = sourceFrameTimeline.averageFrameRate
            ?? metadataFrameRate
        guard let decodeTolerance = FrameExtractionTolerancePolicy.halfFrameTime(
            sourceFrameRate: sourceFrameRate
        ) else {
            return activeFailure(.frameExtractionFailed, runID: runID, gate: gate)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = decodeTolerance
        generator.requestedTimeToleranceAfter = decodeTolerance

        // One tracker is intentionally reused for the complete coarse pass and
        // every adaptive block. Expansion must never create a new golfer identity.
        let coarseScanWindow = candidateWindow ?? SwingWindow(
            startTime: 0,
            endTime: duration
        )
        let coarseTimes = SwingCoreLocator.sampleTimes(
            duration: coarseScanWindow.duration
        ).map {
            min(coarseScanWindow.endTime, coarseScanWindow.startTime + $0)
        }
        var coarseSamples: [CoarseSwingSample] = []
        var coarseQualityFrames: [(time: Double, frame: SwingInputQualityFrame)] = []
        publish(.locating, progress: 0, runID: runID, gate: gate, handler: progress)

        for (index, seconds) in coarseTimes.enumerated() {
            guard gate.isActive(runID) else { return .cancelled }
            guard let requestedSourceFrameIndex = sourceFrameTimeline
                .nearestSourceFrameIndex(at: seconds) else {
                return activeFrameExtractionFailure(runID: runID, gate: gate)
            }
            let extraction: (sample: CoarseSwingSample, quality: SwingInputQualityFrame)? = autoreleasepool {
                guard let requestedTime = FrameExtractionTolerancePolicy.decodeRequestTime(
                    sourceFrameIndex: requestedSourceFrameIndex,
                    sourceFrameTimeline: sourceFrameTimeline
                ) else { return nil }
                var actualTime = CMTime.invalid
                guard let image = try? generator.copyCGImage(
                    at: requestedTime,
                    actualTime: &actualTime
                ),
                actualTime.isValid,
                actualTime.seconds.isFinite,
                sourceFrameTimeline.matches(
                    requestedSourceFrameIndex: requestedSourceFrameIndex,
                    actualTime: actualTime
                ) else { return nil }
                let actualSeconds = actualTime.seconds
                let selectedPose = trackedPoseDetector.selectPose(
                    in: image,
                    time: actualSeconds,
                    recordsCoreAnchorCandidate: true
                )
                let subjectCenter = selectedPose.flatMap { pose -> SwingInputQualityPoint? in
                    let center: CGPoint?
                    if let shoulder = pose.shoulderMid, let hip = pose.hipMid {
                        center = CGPoint(
                            x: (shoulder.x + hip.x) / 2,
                            y: (shoulder.y + hip.y) / 2
                        )
                    } else {
                        center = pose.hipMid ?? pose.shoulderMid
                    }
                    return center.map {
                        SwingInputQualityPoint(x: Double($0.x), y: Double($0.y))
                    }
                }
                let luminance = SwingInputQualityEvaluator.luminanceGrid(from: image)
                let blurScore = luminance.map {
                    SwingInputQualityEvaluator.blurScore(
                        luminance: $0.values,
                        width: $0.width,
                        height: $0.height
                    )
                } ?? 0
                return (
                    sample: CoarseSwingSample(
                        time: actualSeconds,
                        pose: selectedPose.map { SwingPoseSample(time: actualSeconds, pose: $0) }
                    ),
                    quality: SwingInputQualityFrame(
                        poseDetected: selectedPose != nil,
                        fullBodyVisible: selectedPose.map {
                            SwingInputQualityEvaluator.isFullBodyVisible(
                                landmarks: Set($0.keypoints.keys)
                            )
                        } ?? false,
                        subjectCenter: subjectCenter,
                        blurScore: blurScore
                    )
                )
            }
            guard let extraction else {
                return activeFrameExtractionFailure(runID: runID, gate: gate)
            }
            coarseSamples.append(extraction.sample)
            coarseQualityFrames.append((extraction.sample.time, extraction.quality))
            publish(
                .locating,
                progress: Double(index + 1) / Double(max(1, coarseTimes.count)) * 0.20,
                runID: runID,
                gate: gate,
                handler: progress
            )
        }

        guard gate.isActive(runID) else { return .cancelled }
        guard !coarseSamples.isEmpty else {
            return activeFrameExtractionFailure(runID: runID, gate: gate)
        }

        let attempts = SwingAttemptSegmenter.segment(
            samples: coarseSamples,
            sourceDuration: duration
        )
        if candidateWindow == nil {
            let rankedAttempts = SwingAttemptSelectionPolicy.rankedAttempts(
                in: attempts,
                samples: coarseSamples
            )
            if !rankedAttempts.isEmpty {
                shouldStoreLocalDiagnostics = false
                var firstFailure: AnalysisFailure?
                var firstFailureDiagnostics: PrimaryGolferTrackingDiagnostics?
                for attempt in rankedAttempts {
                    guard gate.isActive(runID) else { return .cancelled }
                    let candidateEngine = SwingVideoAnalysisEngine(
                        motionBlurDisposition: motionBlurDisposition
                    )
                    let outcome = candidateEngine.analyze(
                        url: url,
                        runID: runID,
                        gate: gate,
                        candidateWindow: SwingWindow(
                            startTime: attempt.startTime,
                            endTime: attempt.endTime
                        ),
                        progress: progress
                    )
                    switch outcome {
                    case .completed, .cancelled:
                        storeTrackingDiagnostics(candidateEngine.latestTrackingDiagnostics)
                        return outcome
                    case let .failed(failure):
                        if firstFailure == nil {
                            firstFailure = failure
                            firstFailureDiagnostics = candidateEngine.latestTrackingDiagnostics
                        }
                    }
                }
                if let firstFailureDiagnostics {
                    storeTrackingDiagnostics(firstFailureDiagnostics)
                }
                return activeFailure(
                    firstFailure ?? .noSwingMotion,
                    runID: runID,
                    gate: gate
                )
            }
        }
        let coreSamples: [CoarseSwingSample]
        if candidateWindow == nil,
           let preferredAttempt = SwingAttemptSelectionPolicy.preferredAttempt(
            in: attempts,
            samples: coarseSamples
        ) {
            coreSamples = coarseSamples.filter {
                $0.time >= preferredAttempt.startTime && $0.time <= preferredAttempt.endTime
            }
        } else {
            coreSamples = coarseSamples
        }

        let qualityStartTime = coreSamples.first?.time ?? coarseScanWindow.startTime
        let qualityEndTime = coreSamples.last?.time ?? coarseScanWindow.endTime
        let qualityFrames: [SwingInputQualityFrame] = coarseQualityFrames.compactMap {
            sample -> SwingInputQualityFrame? in
            guard sample.time >= qualityStartTime,
                  sample.time <= qualityEndTime else { return nil }
            return sample.frame
        }
        let qualitySignals = SwingInputQualityEvaluator.summarize(
            frames: qualityFrames,
            clubCoverage: nil
        )
        let qualityReport = SwingInputQualityEvaluator.evaluate(
            qualitySignals,
            motionBlurDisposition: motionBlurDisposition
        )
        guard qualityReport.isSupported else {
            return activeFailure(
                .unsupportedInput(qualityReport.blockingIssues),
                runID: runID,
                gate: gate
            )
        }

        let core: SwingCore
        switch SwingCoreLocator.locate(samples: coreSamples) {
        case let .located(locatedCore):
            core = locatedCore
        case let .failed(reason):
            return activeFailure(failure(reason), runID: runID, gate: gate)
        }
        guard trackedPoseDetector.lockIdentityAnchor(near: core.peakTime) else {
            return activeFailure(.noStableGolfer, runID: runID, gate: gate)
        }
        var window = AdaptiveSwingWindowPlanner.initialWindow(core: core, duration: duration)
        var samplesByFrame: [Int: SwingFrameSample] = [:]
        var rawPosesByFrame: [Int: PoseEstimationResult] = [:]
        var rawBodyFramesBySourceFrame: [Int: SwingFrameObservation] = [:]
        var trackedBodyFrames: [SwingFrameObservation] = []
        var finalTimeline: [SwingTemporalFrame] = []
        var windowSearchState = AdaptiveWindowSearchState()
        let fineDecodeLedger = AdaptiveFineDecodeLedger()
        let maximumFrameBudget = adaptiveFrameBudget(sourceFrameRate: sourceFrameRate)
        let fineFrameImageCache = FineFrameImageCache(
            maximumEntryCount: adaptiveFrameCacheBudget(sourceFrameRate: sourceFrameRate)
        )
        publish(.expanding, progress: 0.20, runID: runID, gate: gate, handler: progress)

        adaptiveExtraction: while gate.isActive(runID) {
            let references = FineSwingSamplingPlan.frames(
                window: window,
                sourceFrameTimeline: sourceFrameTimeline
            ).filter { samplesByFrame[$0.sourceFrameIndex] == nil }

            guard !references.isEmpty || !samplesByFrame.isEmpty else {
                return activeFrameExtractionFailure(runID: runID, gate: gate)
            }
            for reference in references {
                guard gate.isActive(runID) else { return .cancelled }
                guard let extraction = extractPoseSample(
                    reference: reference,
                    generator: generator,
                    detector: trackedPoseDetector,
                    sourceFrameTimeline: sourceFrameTimeline,
                    frameImageCache: fineFrameImageCache,
                    decodeLedger: fineDecodeLedger
                ) else {
                    return activeFrameExtractionFailure(runID: runID, gate: gate)
                }
                samplesByFrame[extraction.sample.sourceFrameIndex] = extraction.sample
                if let rawPose = extraction.rawPose {
                    rawPosesByFrame[extraction.sample.sourceFrameIndex] = rawPose
                }
                rawBodyFramesBySourceFrame[extraction.sample.sourceFrameIndex] =
                    SwingPoseObservationAdapter.frame(
                        pose: extraction.rawPose,
                        sourceFrameIndex: extraction.sample.sourceFrameIndex,
                        time: extraction.sample.time
                    )
                publish(
                    .expanding,
                    progress: SwingVideoAnalysisProgressPolicy.expansionProgress(
                        cachedFrameCount: samplesByFrame.count,
                        maximumFrameBudget: maximumFrameBudget
                    ),
                    runID: runID,
                    gate: gate,
                    handler: progress
                )
            }

            trackedBodyFrames = SwingTrajectoryTracker.track(
                Array(rawBodyFramesBySourceFrame.values),
                maximumPredictionFrames: 2
            )
            samplesByFrame = Dictionary(uniqueKeysWithValues: trackedBodyFrames.map { bodyFrame in
                let rawFrame = rawBodyFramesBySourceFrame[bodyFrame.sourceFrameIndex]
                let existingObjects = samplesByFrame[bodyFrame.sourceFrameIndex]?.objectEvidence
                    ?? .empty
                return (
                    bodyFrame.sourceFrameIndex,
                    SwingFrameSample(
                        sourceFrameIndex: bodyFrame.sourceFrameIndex,
                        time: bodyFrame.time,
                        pose: SwingPoseObservationAdapter.poseSample(from: bodyFrame),
                        rawPose: rawFrame.flatMap(SwingPoseObservationAdapter.poseSample(from:)),
                        objectEvidence: existingObjects
                    )
                )
            })
            let frames = samplesByFrame.values.sorted {
                $0.sourceFrameIndex < $1.sourceFrameIndex
            }
            finalTimeline = SwingEvidenceTimeline.build(
                from: SwingFeatureExtractor.extract(frames: frames)
            )
            let currentBoundaryEvidence = finalTimeline.adaptiveBoundaryEvidence
            switch windowSearchState.nextAction(
                current: window,
                duration: duration,
                evidence: currentBoundaryEvidence
            ) {
            case let .expand(next):
                let retainedSourceFrames = Set(FineSwingSamplingPlan.frames(
                    window: next,
                    sourceFrameTimeline: sourceFrameTimeline
                ).map(\.sourceFrameIndex))
                samplesByFrame = samplesByFrame.filter {
                    retainedSourceFrames.contains($0.key)
                }
                rawPosesByFrame = rawPosesByFrame.filter {
                    retainedSourceFrames.contains($0.key)
                }
                rawBodyFramesBySourceFrame = rawBodyFramesBySourceFrame.filter {
                    retainedSourceFrames.contains($0.key)
                }
                trackedBodyFrames = trackedBodyFrames.filter {
                    retainedSourceFrames.contains($0.sourceFrameIndex)
                }
                fineFrameImageCache.retainSourceFrames(retainedSourceFrames)
                window = next
            case let .ready(readyWindow):
                window = readyWindow
                break adaptiveExtraction
            case let .failed(reason):
                return activeFailure(reason, runID: runID, gate: gate)
            }
        }

        guard gate.isActive(runID) else { return .cancelled }
        let fineFrames = samplesByFrame.values.sorted {
            $0.sourceFrameIndex < $1.sourceFrameIndex
        }
        guard !fineFrames.isEmpty else {
            return activeFrameExtractionFailure(runID: runID, gate: gate)
        }
        guard fineFrames.filter({ $0.pose != nil }).count >= SwingStage.allCases.count else {
            return activeFailure(.noStableGolfer, runID: runID, gate: gate)
        }

        // Resolve candidate neighborhoods only from the body timeline. Object
        // evidence is then extracted sparsely and merged before the final solve.
        let bodyHasTopTransition = finalTimeline.contains(where: \.isTopPlateauEnd)
        let bodyImpactCandidates = ImpactCorridorResolver.candidates(in: finalTimeline)
        if let failure = SwingVideoAnalysisValidationPolicy.transitionFailure(
            hasTopTransition: bodyHasTopTransition,
            hasImpactCandidates: !bodyImpactCandidates.isEmpty
        ) {
            return activeFailure(failure, runID: runID, gate: gate)
        }
        let bodyCandidates = bodyImpactCandidates.flatMap { impact in
            let candidates = BidirectionalStageCandidateResolver.objectSamplingCandidates(
                timeline: finalTimeline,
                impact: impact
            )
            return [
                SwingStage.address,
                .takeaway,
                .shaftParallelDownswing,
                .impact,
                .followThrough
            ]
                .flatMap { candidates.candidates(for: $0) }
        }
        guard !bodyCandidates.isEmpty else {
            return activeFailure(.noImpactCorridor, runID: runID, gate: gate)
        }

        let fineReferences = fineFrames.map {
            FineFrameReference(sourceFrameIndex: $0.sourceFrameIndex, time: $0.time)
        }
        let objectReferences = SparseObjectSamplingPlan.frames(
            from: fineReferences,
            candidates: bodyCandidates
        )
        let objectDetector = SwingObjectDetector()
        var objectEvidenceByFrame: [Int: SwingObjectEvidence] = [:]
        var rawGolfObservationByFrame: [Int: GolfObjectObservation] = [:]
        let promotedGolfProvider = Bundle.main.url(
            forResource: "GolfKeypoints",
            withExtension: "mlmodelc"
        ).flatMap { try? CoreMLGolfObjectDetector(modelURL: $0) }
        publish(.evidence, progress: 0.70, runID: runID, gate: gate, handler: progress)

        for (index, reference) in objectReferences.enumerated() {
            guard gate.isActive(runID) else { return .cancelled }
            guard let image = fineFrameImageCache.contourImage(
                sourceFrameIndex: reference.sourceFrameIndex
            ) else {
                return activeFrameExtractionFailure(runID: runID, gate: gate)
            }
            let detected: SwingObjectEvidence = autoreleasepool {
                objectDetector.detect(
                    in: image,
                    pose: rawPosesByFrame[reference.sourceFrameIndex],
                    sourceFrameIndex: reference.sourceFrameIndex
                )
            }
            objectEvidenceByFrame[reference.sourceFrameIndex] = detected
            let contourObservation = ContourGolfObjectObservationAdapter.observation(
                from: detected
            )
            var mergedPoints = contourObservation.points
            if let promotedGolfProvider,
               let promotedObservation = try? promotedGolfProvider.observe(
                    image: image,
                    pose: rawPosesByFrame[reference.sourceFrameIndex]
               ) {
                mergedPoints.merge(promotedObservation.points) { _, promoted in promoted }
            }
            rawGolfObservationByFrame[reference.sourceFrameIndex] =
                GolfObjectObservation(points: mergedPoints)
            publish(
                .evidence,
                progress: SwingVideoAnalysisProgressPolicy.evidenceProgress(
                    processedReferenceCount: index + 1,
                    totalReferenceCount: objectReferences.count
                ),
                runID: runID,
                gate: gate,
                handler: progress
            )
        }

        let stableBall = objectDetector.stableBall?.center
        var golfTracker = GolfObjectTrajectoryTracker(maximumPredictionFrames: 2)
        let trackedGolfFrames = fineFrames.map { frame in
            golfTracker.update(
                observation: rawGolfObservationByFrame[frame.sourceFrameIndex] ?? .empty,
                sourceFrameIndex: frame.sourceFrameIndex,
                time: frame.time
            )
        }
        let trackedGolfByFrame = Dictionary(uniqueKeysWithValues: trackedGolfFrames.map {
            ($0.sourceFrameIndex, $0)
        })
        let mergedFrames = fineFrames.map { frame in
            let detected = objectEvidenceByFrame[frame.sourceFrameIndex] ?? .empty
            let tracked = trackedGolfByFrame[frame.sourceFrameIndex]
                ?? SwingFrameObservation(
                    sourceFrameIndex: frame.sourceFrameIndex,
                    time: frame.time,
                    landmarks: [:]
                )
            let mergedObjects = TrackedGolfObjectEvidenceAdapter.evidence(
                from: tracked,
                stableBall: detected.stableBall ?? stableBall,
                ballLocalChange: detected.ballLocalChange
            )
            return SwingFrameSample(
                sourceFrameIndex: frame.sourceFrameIndex,
                time: frame.time,
                pose: frame.pose,
                rawPose: frame.rawPose,
                objectEvidence: mergedObjects
            )
        }
        trackedBodyFrames = trackedBodyFrames.map { bodyFrame in
            guard let golfFrame = trackedGolfByFrame[bodyFrame.sourceFrameIndex] else {
                return bodyFrame
            }
            let rawGolf = rawGolfObservationByFrame[bodyFrame.sourceFrameIndex]?.points ?? [:]
            var landmarks = bodyFrame.landmarks
            landmarks.merge(golfFrame.landmarks) { _, golf in golf }
            var rawLandmarks = bodyFrame.rawLandmarks
            rawLandmarks.merge(rawGolf) { _, golf in golf }
            return SwingFrameObservation(
                sourceFrameIndex: bodyFrame.sourceFrameIndex,
                time: bodyFrame.time,
                landmarks: landmarks,
                rawLandmarks: rawLandmarks
            )
        }
        finalTimeline = SwingEvidenceTimeline.build(
            from: SwingFeatureExtractor.extract(frames: mergedFrames)
        )

        let impactCandidates = ImpactCorridorResolver.candidates(in: finalTimeline)
        if let failure = SwingVideoAnalysisValidationPolicy.transitionFailure(
            hasTopTransition: finalTimeline.contains(where: \.isTopPlateauEnd),
            hasImpactCandidates: !impactCandidates.isEmpty
        ) {
            return activeFailure(failure, runID: runID, gate: gate)
        }

        publish(.solving, progress: 0.95, runID: runID, gate: gate, handler: progress)
        let candidateSets = impactCandidates.map {
            BidirectionalStageCandidateResolver.candidates(
                timeline: finalTimeline,
                impact: $0
            )
        }
        let result = ConstrainedSwingPathSolver.solve(
            candidateSets: candidateSets,
            timeline: finalTimeline
        )
        guard gate.isActive(runID) else { return .cancelled }
        guard !result.detectedMarkers.isEmpty else {
            return activeFailure(.insufficientStageEvidence, runID: runID, gate: gate)
        }
        publish(.solving, progress: 1, runID: runID, gate: gate, handler: progress)
        guard gate.isActive(runID) else { return .cancelled }
        return .completed(SwingVideoAnalysisOutput(
            result: result,
            poseSamples: mergedFrames.compactMap(\.pose),
            leadArm: finalTimeline
                .map(\.frame.leadArm)
                .first(where: { $0 != .unknown }) ?? .unknown,
            adaptiveWindow: window,
            sourceFrameRate: sourceFrameRate,
            elapsedSeconds: ProcessInfo.processInfo.systemUptime - startedAt,
            trackingDiagnostics: trackedPoseDetector.diagnostics,
            observationFrames: trackedBodyFrames
        ))
    }

    private func extractPoseSample(
        reference: FineFrameReference,
        generator: AVAssetImageGenerator,
        detector: TrackedPoseDetector,
        sourceFrameTimeline: SourceFrameTimeline,
        frameImageCache: FineFrameImageCache,
        decodeLedger: AdaptiveFineDecodeLedger
    ) -> PoseFrameExtraction? {
        autoreleasepool {
            var observedTime: Double?
            var observedSourceFrameIndex: Int?
            let load = frameImageCache.load(sourceFrameIndex: reference.sourceFrameIndex) {
                guard decodeLedger.registerDecode(
                    sourceFrameIndex: reference.sourceFrameIndex
                ) else { return nil }
                guard let requestedTime = FrameExtractionTolerancePolicy.decodeRequestTime(
                    sourceFrameIndex: reference.sourceFrameIndex,
                    sourceFrameTimeline: sourceFrameTimeline
                ) else { return nil }
                var actualTime = CMTime.invalid
                guard let image = try? generator.copyCGImage(
                    at: requestedTime,
                    actualTime: &actualTime
                ),
                actualTime.isValid,
                actualTime.seconds.isFinite,
                sourceFrameTimeline.matches(
                    requestedSourceFrameIndex: reference.sourceFrameIndex,
                    actualTime: actualTime
                ) else { return nil }
                observedTime = actualTime.seconds
                observedSourceFrameIndex = reference.sourceFrameIndex
                return image
            }
            guard case let .decoded(image) = load,
                  let actualSeconds = observedTime,
                  let sourceFrameIndex = observedSourceFrameIndex else { return nil }
            let selected = detector.selectPose(
                in: image,
                time: actualSeconds,
                recordsCoreAnchorCandidate: false
            )
            return PoseFrameExtraction(
                sample: SwingFrameSample(
                    sourceFrameIndex: sourceFrameIndex,
                    time: actualSeconds,
                    pose: selected.map {
                        SwingPoseSample(
                            time: actualSeconds,
                            sourceFrameIndex: sourceFrameIndex,
                            pose: $0
                        )
                    },
                    objectEvidence: .empty
                ),
                rawPose: selected
            )
        }
    }

    private func adaptiveFrameBudget(sourceFrameRate: Double) -> Int {
        let stride = max(
            1,
            Int(ceil(sourceFrameRate / FineSwingSamplingPlan.maximumSamplesPerSecond))
        )
        let effectiveRate = sourceFrameRate / Double(stride)
        return max(1, Int(ceil(AdaptiveSwingWindowPlanner.maximumSpan * effectiveRate)) + 1)
    }

    private func adaptiveFrameCacheBudget(sourceFrameRate: Double) -> Int {
        let stride = max(
            1,
            Int(ceil(sourceFrameRate / FineSwingSamplingPlan.maximumSamplesPerSecond))
        )
        let effectiveRate = sourceFrameRate / Double(stride)
        return max(
            1,
            Int(ceil(AdaptiveSwingWindowPlanner.maximumSpan * effectiveRate)) + 1
        )
    }

    private func failure(_ reason: SwingWindowFailure) -> AnalysisFailure {
        switch reason {
        case .insufficientPoseEvidence: return .noStableGolfer
        case .noSwingMotion: return .noSwingMotion
        case .ambiguousCandidates: return .ambiguousSwingWindows
        case .windowTooLong: return .swingWindowTooLong
        }
    }

    private func activeFailure(
        _ failure: AnalysisFailure,
        runID: UUID,
        gate: AnalysisRunGate
    ) -> SwingVideoAnalysisOutcome {
        gate.isActive(runID) ? .failed(failure) : .cancelled
    }

    private func activeFrameExtractionFailure(
        runID: UUID,
        gate: AnalysisRunGate
    ) -> SwingVideoAnalysisOutcome {
        let failure = SwingVideoAnalysisValidationPolicy.prioritizedFailure(
            frameExtractionFailed: true,
            evidenceFailure: nil
        ) ?? .frameExtractionFailed
        return activeFailure(failure, runID: runID, gate: gate)
    }

    private func publish(
        _ phase: AnalysisProgressPhase,
        progress: Double,
        runID: UUID,
        gate: AnalysisRunGate,
        handler: ProgressHandler
    ) {
        guard gate.isActive(runID) else { return }
        handler(SwingAnalysisProgressUpdate(phase: phase, progress: progress))
    }

    private func storeTrackingDiagnostics(_ diagnostics: PrimaryGolferTrackingDiagnostics) {
        diagnosticsLock.lock()
        storedTrackingDiagnostics = diagnostics
        diagnosticsLock.unlock()
    }

}

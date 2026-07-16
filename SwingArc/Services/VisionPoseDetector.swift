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
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        
        do {
            try requestHandler.perform([poseRequest])
            guard let results = poseRequest.results, let observation = results.first else {
                return nil
            }
            
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
        } catch {
            print("Vision pose detection error on CGImage: \(error)")
            return nil
        }
    }
}

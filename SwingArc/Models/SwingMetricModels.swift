import Foundation

enum SwingMetricID: String, Codable, CaseIterable {
    case backswingTime
    case downswingTime
    case tempoRatio
    case spineTilt2D
    case shoulderLineAngle2D
    case hipLineAngle2D
    case leadElbowAngle
    case trailElbowAngle
    case leadKneeAngle
    case trailKneeAngle
    case headHorizontalDisplacement
    case headVerticalDisplacement
    case hipHorizontalDisplacement
    case hipVerticalDisplacement
    case handPathLength
    case clubheadPathLength
    case clubheadRelativeSpeed2D
    case shaftProjectionAngle
    case swingPlaneProxy2D
    case hipShoulderSeparationProxy2D
    case trueClubheadSpeed
    case attackAngle
    case faceAngle
    case dynamicLoft
    case ballSpeed
    case launchAngle
    case spinRate
    case carryDistance

    var isSupportedBySingleCamera: Bool {
        switch self {
        case .trueClubheadSpeed, .attackAngle, .faceAngle, .dynamicLoft,
             .ballSpeed, .launchAngle, .spinRate, .carryDistance:
            return false
        default:
            return true
        }
    }

    static let motionAnalysisOutputs: Set<SwingMetricID> = [
        .backswingTime,
        .downswingTime,
        .tempoRatio,
        .spineTilt2D,
        .shoulderLineAngle2D,
        .hipLineAngle2D,
        .leadElbowAngle,
        .trailElbowAngle,
        .leadKneeAngle,
        .trailKneeAngle,
        .headHorizontalDisplacement,
        .headVerticalDisplacement,
        .hipHorizontalDisplacement,
        .hipVerticalDisplacement,
        .handPathLength,
        .clubheadPathLength,
        .clubheadRelativeSpeed2D,
        .shaftProjectionAngle,
        .swingPlaneProxy2D,
        .hipShoulderSeparationProxy2D
    ]

    var isMotionAnalysisOutput: Bool {
        Self.motionAnalysisOutputs.contains(self)
    }

    var userFacingTitle: String? {
        switch self {
        case .backswingTime: return "上杆时间"
        case .downswingTime: return "下杆时间"
        case .tempoRatio: return "挥杆节奏"
        case .spineTilt2D: return "脊柱二维倾角"
        case .shoulderLineAngle2D: return "肩线二维角度"
        case .hipLineAngle2D: return "髋线二维角度"
        case .leadElbowAngle: return "前侧手肘角度"
        case .trailElbowAngle: return "后侧手肘角度"
        case .leadKneeAngle: return "前侧膝部角度"
        case .trailKneeAngle: return "后侧膝部角度"
        case .headHorizontalDisplacement: return "头部水平位移"
        case .headVerticalDisplacement: return "头部垂直位移"
        case .hipHorizontalDisplacement: return "髋部水平位移"
        case .hipVerticalDisplacement: return "髋部垂直位移"
        case .handPathLength: return "手部二维路径"
        case .clubheadPathLength: return "杆头二维路径"
        case .clubheadRelativeSpeed2D: return "二维杆头相对速度"
        case .shaftProjectionAngle: return "杆身二维投影角"
        case .swingPlaneProxy2D: return "二维挥杆平面代理"
        case .hipShoulderSeparationProxy2D: return "二维髋肩分离代理"
        case .trueClubheadSpeed, .attackAngle, .faceAngle, .dynamicLoft,
             .ballSpeed, .launchAngle, .spinRate, .carryDistance:
            return nil
        }
    }
}

enum SwingMetricUnavailableReason: String, Codable, Equatable {
    case missingEvidence
    case lowConfidence
    case estimatedInput
    case requiresCalibrated3DOrSensor
}

enum SwingMetricAvailability: Codable, Equatable {
    case measured
    case estimated
    case unavailable(reason: SwingMetricUnavailableReason)
}

struct SwingMetricValue: Codable, Equatable {
    let id: SwingMetricID
    let value: Double?
    let unit: String
    let confidence: Double
    let stage: String?
    let availability: SwingMetricAvailability
}

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

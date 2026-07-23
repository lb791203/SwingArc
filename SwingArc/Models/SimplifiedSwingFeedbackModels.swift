import Foundation

enum SwingFeedbackCategory: String, Codable, CaseIterable, Identifiable {
    case setup
    case bodyStability
    case handPath
    case swingPlane
    case impactAndRelease

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: return "准备姿势"
        case .bodyStability: return "身体稳定"
        case .handPath: return "手部路径"
        case .swingPlane: return "挥杆平面"
        case .impactAndRelease: return "击球与释放"
        }
    }

    var stages: [SwingStage] {
        switch self {
        case .setup:
            return [.address]
        case .bodyStability, .handPath:
            return [
                .takeaway,
                .leadArmParallelBackswing,
                .top,
                .leadArmParallelDownswing,
                .shaftParallelDownswing,
                .impact
            ]
        case .swingPlane:
            return [
                .takeaway,
                .leadArmParallelBackswing,
                .leadArmParallelDownswing,
                .shaftParallelDownswing,
                .followThrough
            ]
        case .impactAndRelease:
            return [
                .shaftParallelDownswing,
                .impact,
                .followThrough
            ]
        }
    }

    var trajectoryLandmarks: [SwingLandmark] {
        switch self {
        case .setup:
            return [
                .head,
                .leftShoulder,
                .rightShoulder,
                .leftHip,
                .rightHip,
                .leftKnee,
                .rightKnee,
                .leftAnkle,
                .rightAnkle,
                .handCenter
            ]
        case .bodyStability:
            return [
                .head,
                .leftShoulder,
                .rightShoulder,
                .leftHip,
                .rightHip
            ]
        case .handPath:
            return [.handCenter]
        case .swingPlane:
            return [.handCenter, .shaftStart, .shaftEnd, .clubhead]
        case .impactAndRelease:
            return [.handCenter, .shaftStart, .shaftEnd, .clubhead, .ball]
        }
    }
}

enum SwingFeedbackStatus: String, Codable, Equatable {
    case good
    case attention
    case insufficientEvidence

    var title: String {
        switch self {
        case .good: return "良好"
        case .attention: return "需注意"
        case .insufficientEvidence: return "证据不足"
        }
    }
}

enum SwingFeedbackEvidenceState: String, Codable, Equatable {
    case measured
    case estimated
    case unavailable

    var title: String {
        switch self {
        case .measured: return "实测"
        case .estimated: return "估算"
        case .unavailable: return "无法识别"
        }
    }
}

struct SwingFeedbackCard: Codable, Equatable, Identifiable {
    var id: String { category.rawValue }

    let category: SwingFeedbackCategory
    let status: SwingFeedbackStatus
    let conclusion: String
    let stages: [SwingStage]
    let metrics: [SwingMetricValue]
    let evidenceState: SwingFeedbackEvidenceState
    let evidenceConfidence: Double
    let attentionSeverity: Int?
}

struct SwingFeedbackSummary: Codable, Equatable {
    let title: String
    let observation: String
    let recommendation: String
    let stages: [SwingStage]
}

struct SimplifiedSwingFeedback: Codable, Equatable {
    let summary: SwingFeedbackSummary
    let cards: [SwingFeedbackCard]

    func card(
        for category: SwingFeedbackCategory
    ) -> SwingFeedbackCard? {
        cards.first(where: { $0.category == category })
    }
}

extension SwingStage {
    var evidenceCode: String {
        switch self {
        case .address: return "P1"
        case .takeaway: return "P2"
        case .leadArmParallelBackswing: return "P3"
        case .top: return "P4"
        case .leadArmParallelDownswing: return "P5"
        case .shaftParallelDownswing: return "P6"
        case .impact: return "P7"
        case .followThrough: return "P8"
        case .finish: return "收杆"
        }
    }
}

import Foundation

enum PracticeHomeAction: Equatable {
    case downTheLine
    case faceOn
    case importVideo
    case history
}

enum PracticeHomePresentation {
    static let modeOrder: [PracticeHomeAction] = [.downTheLine, .faceOn]
    static let secondaryActions: [PracticeHomeAction] = [.importVideo, .history]
}

enum PracticePrimaryControl: Equatable {
    case start
    case pause
    case none
}

enum PriorityFeedback: Equatable {
    case finding(TechniqueFinding)
    case unresolved

    static func select(from findings: [TechniqueFinding]) -> PriorityFeedback {
        guard let first = findings.first else { return .unresolved }
        return .finding(first)
    }
}

struct DrillRecommendation: Equatable {
    let identifier: String
    let title: String

    static func forFinding(_ finding: TechniqueFinding) -> DrillRecommendation {
        switch finding.kind {
        case .postureLoss:
            return DrillRecommendation(identifier: "posture-wall", title: "靠墙起杆练习")
        case .overTheTop:
            return DrillRecommendation(identifier: "path-towel", title: "腋下夹毛巾练习")
        case .chickenWing:
            return DrillRecommendation(identifier: "extension-release", title: "送杆伸展练习")
        }
    }
}

enum PracticeSessionState: Equatable {
    case aligning(view: PracticeCameraView)
    case readyToStart(view: PracticeCameraView)
    case waitingForImpact(view: PracticeCameraView, swingCount: Int)
    case processing(view: PracticeCameraView, swingCount: Int)
    case resultRibbon(view: PracticeCameraView, swingCount: Int, feedback: PriorityFeedback)
    case paused(view: PracticeCameraView, swingCount: Int)
    case degraded(view: PracticeCameraView, message: String)
    case failed(view: PracticeCameraView, message: String)
}

enum PracticeSessionEvent: Equatable {
    case alignmentConfirmed
    case startTapped
    case impactDetected
    case analysisFinished(PriorityFeedback)
    case resultRibbonElapsed
    case pauseTapped
    case resumeTapped
    case degrade(String)
    case fail(String)
}

enum PracticeSessionReducer {
    static func reduce(
        state: PracticeSessionState,
        event: PracticeSessionEvent
    ) -> PracticeSessionState {
        switch (state, event) {
        case let (.aligning(view), .alignmentConfirmed):
            return .readyToStart(view: view)
        case let (.readyToStart(view), .startTapped):
            return .waitingForImpact(view: view, swingCount: 0)
        case let (.waitingForImpact(view, swingCount), .impactDetected):
            return .processing(view: view, swingCount: swingCount + 1)
        case let (.processing(view, swingCount), .analysisFinished(feedback)):
            return .resultRibbon(view: view, swingCount: swingCount, feedback: feedback)
        case let (.resultRibbon(view, swingCount, _), .resultRibbonElapsed):
            return .waitingForImpact(view: view, swingCount: swingCount)
        case let (.waitingForImpact(view, swingCount), .pauseTapped),
             let (.resultRibbon(view, swingCount, _), .pauseTapped):
            return .paused(view: view, swingCount: swingCount)
        case let (.paused(view, swingCount), .resumeTapped):
            return .waitingForImpact(view: view, swingCount: swingCount)
        case let (.aligning(view), .degrade(message)),
             let (.readyToStart(view), .degrade(message)),
             let (.waitingForImpact(view, _), .degrade(message)),
             let (.processing(view, _), .degrade(message)),
             let (.resultRibbon(view, _, _), .degrade(message)),
             let (.paused(view, _), .degrade(message)):
            return .degraded(view: view, message: message)
        case let (.aligning(view), .fail(message)),
             let (.readyToStart(view), .fail(message)),
             let (.waitingForImpact(view, _), .fail(message)),
             let (.processing(view, _), .fail(message)),
             let (.resultRibbon(view, _, _), .fail(message)),
             let (.paused(view, _), .fail(message)):
            return .failed(view: view, message: message)
        default:
            return state
        }
    }
}

enum PracticePresentationPolicy {
    static func primaryControl(for state: PracticeSessionState) -> PracticePrimaryControl {
        switch state {
        case .readyToStart, .paused:
            return .start
        case .waitingForImpact, .resultRibbon:
            return .pause
        case .aligning, .processing, .degraded, .failed:
            return .none
        }
    }

    static func remoteStatus(for state: PracticeSessionState) -> String {
        switch state {
        case .aligning:
            return "ALIGNMENT"
        case .readyToStart:
            return "READY"
        case let .waitingForImpact(_, swingCount):
            return "WAITING · SHOT \(shotNumber(swingCount + 1))"
        case let .processing(_, swingCount):
            return "ANALYSING · SHOT \(shotNumber(swingCount))"
        case let .resultRibbon(_, swingCount, _):
            return "RESULT · SHOT \(shotNumber(swingCount))"
        case let .paused(_, swingCount):
            return "PAUSED · SHOT \(shotNumber(swingCount))"
        case .degraded:
            return "CHECK CAMERA"
        case .failed:
            return "SESSION STOPPED"
        }
    }

    static func remoteDetail(for state: PracticeSessionState) -> String? {
        switch state {
        case .aligning:
            return "全身与球位进入取景框"
        case .readyToStart:
            return "站姿已锁定 · 可开始自动练习"
        case .waitingForImpact:
            return "已监听击球声"
        case .processing:
            return "本机动作解算中"
        case let .resultRibbon(_, _, feedback):
            return feedbackTitle(feedback)
        case .paused:
            return "自动练习已暂停"
        case let .degraded(_, message), let .failed(_, message):
            return message
        }
    }

    private static func shotNumber(_ value: Int) -> String {
        String(format: "%02d", max(value, 0))
    }

    static func feedbackTitle(_ feedback: PriorityFeedback) -> String {
        switch feedback {
        case let .finding(finding):
            switch finding.kind {
            case .postureLoss: return "上杆时身体有起身趋势"
            case .overTheTop: return "下杆略偏外"
            case .chickenWing: return "送杆手臂略收紧"
            }
        case .unresolved:
            return "本球证据不足，暂未判定"
        }
    }

    static func drill(for feedback: PriorityFeedback) -> DrillRecommendation? {
        guard case let .finding(finding) = feedback else { return nil }
        return DrillRecommendation.forFinding(finding)
    }
}

import Foundation

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

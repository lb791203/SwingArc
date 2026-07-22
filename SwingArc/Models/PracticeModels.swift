import Foundation

enum PracticeHomeAction: Equatable {
    case downTheLine
    case faceOn
    case manualCapture
    case importVideo
    case history
}

enum PracticeHomePresentation {
    static let modeOrder: [PracticeHomeAction] = [
        .downTheLine, .faceOn, .manualCapture, .importVideo
    ]
    static let secondaryActions: [PracticeHomeAction] = []
}

/// Keeps simulator-only screenshot launch arguments in one place so they
/// cannot accidentally change the normal practice entry flow.
enum PracticePreviewConfiguration {
    enum SessionPreview: Equatable {
        case waiting
        case paused
    }

    static func view(for arguments: [String]) -> PracticeCameraView? {
        if arguments.contains("-swingarc-preview-face-on") ||
            arguments.contains("-swingarc-preview-face-on-ready") {
            return .faceOn
        }

        if arguments.contains("-swingarc-preview-dtl") ||
            arguments.contains("-swingarc-preview-ready") ||
            arguments.contains("-swingarc-preview-waiting") ||
            arguments.contains("-swingarc-preview-paused") {
            return .downTheLine
        }

        return nil
    }

    static func startsReady(for arguments: [String]) -> Bool {
        arguments.contains("-swingarc-preview-ready") ||
            arguments.contains("-swingarc-preview-face-on-ready")
    }

    static func showsLibrary(for arguments: [String]) -> Bool {
        arguments.contains("-swingarc-preview-library") ||
            arguments.contains("-swingarc-preview-new-project")
    }

    static func showsNewProject(for arguments: [String]) -> Bool {
        arguments.contains("-swingarc-preview-new-project")
    }

    static func showsManualCapture(for arguments: [String]) -> Bool {
        arguments.contains("-swingarc-preview-manual-capture")
    }

    static func importPath(for arguments: [String]) -> String? {
        guard let marker = arguments.firstIndex(of: "-swingarc-preview-import") else {
            return nil
        }

        let pathIndex = arguments.index(after: marker)
        guard pathIndex < arguments.endIndex else { return nil }
        return arguments[pathIndex]
    }

    static func autoAnalyzes(for arguments: [String]) -> Bool {
        arguments.contains("-swingarc-preview-analysis")
    }

    static func sessionPreview(for arguments: [String]) -> SessionPreview? {
        if arguments.contains("-swingarc-preview-paused") {
            return .paused
        }
        if arguments.contains("-swingarc-preview-waiting") {
            return .waiting
        }
        return nil
    }
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
    case searchingForPerson(view: PracticeCameraView, swingCount: Int)
    case readyForSwing(view: PracticeCameraView, swingCount: Int)
    case capturingSwing(view: PracticeCameraView, swingCount: Int)
    case finalizingCapture(view: PracticeCameraView, swingCount: Int)
    case processing(view: PracticeCameraView, swingCount: Int)
    case resultRibbon(view: PracticeCameraView, swingCount: Int, feedback: PriorityFeedback)
    case paused(view: PracticeCameraView, swingCount: Int)
    case degraded(view: PracticeCameraView, message: String)
    case failed(view: PracticeCameraView, message: String)
}

enum PracticeSessionEvent: Equatable {
    case alignmentConfirmed
    case startTapped
    case captureSearching
    case captureReady
    case swingStarted
    case clipFinalizing
    case clipCaptured
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
            return .searchingForPerson(view: view, swingCount: 0)
        case let (.searchingForPerson(view, swingCount), .captureReady),
             let (.capturingSwing(view, swingCount), .captureReady):
            return .readyForSwing(view: view, swingCount: swingCount)
        case let (.searchingForPerson(view, swingCount), .captureSearching),
             let (.readyForSwing(view, swingCount), .captureSearching),
             let (.capturingSwing(view, swingCount), .captureSearching):
            return .searchingForPerson(view: view, swingCount: swingCount)
        case let (.readyForSwing(view, swingCount), .swingStarted):
            return .capturingSwing(view: view, swingCount: swingCount)
        case let (.capturingSwing(view, swingCount), .clipFinalizing):
            return .finalizingCapture(view: view, swingCount: swingCount)
        case let (.searchingForPerson(view, swingCount), .clipCaptured),
             let (.readyForSwing(view, swingCount), .clipCaptured),
             let (.capturingSwing(view, swingCount), .clipCaptured),
             let (.finalizingCapture(view, swingCount), .clipCaptured):
            return .processing(view: view, swingCount: swingCount + 1)
        case let (.processing(view, swingCount), .analysisFinished(feedback)):
            return .resultRibbon(view: view, swingCount: swingCount, feedback: feedback)
        case let (.resultRibbon(view, swingCount, _), .resultRibbonElapsed):
            return .searchingForPerson(view: view, swingCount: swingCount)
        case let (.searchingForPerson(view, swingCount), .pauseTapped),
             let (.readyForSwing(view, swingCount), .pauseTapped),
             let (.capturingSwing(view, swingCount), .pauseTapped),
             let (.finalizingCapture(view, swingCount), .pauseTapped),
             let (.processing(view, swingCount), .pauseTapped),
             let (.resultRibbon(view, swingCount, _), .pauseTapped):
            return .paused(view: view, swingCount: swingCount)
        case let (.paused(view, swingCount), .resumeTapped):
            return .searchingForPerson(view: view, swingCount: swingCount)
        case let (.aligning(view), .degrade(message)),
             let (.readyToStart(view), .degrade(message)),
             let (.searchingForPerson(view, _), .degrade(message)),
             let (.readyForSwing(view, _), .degrade(message)),
             let (.capturingSwing(view, _), .degrade(message)),
             let (.finalizingCapture(view, _), .degrade(message)),
             let (.processing(view, _), .degrade(message)),
             let (.resultRibbon(view, _, _), .degrade(message)),
             let (.paused(view, _), .degrade(message)):
            return .degraded(view: view, message: message)
        case let (.aligning(view), .fail(message)),
             let (.readyToStart(view), .fail(message)),
             let (.searchingForPerson(view, _), .fail(message)),
             let (.readyForSwing(view, _), .fail(message)),
             let (.capturingSwing(view, _), .fail(message)),
             let (.finalizingCapture(view, _), .fail(message)),
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
        case .searchingForPerson, .readyForSwing, .capturingSwing, .resultRibbon:
            return .pause
        case .aligning, .finalizingCapture, .processing, .degraded, .failed:
            return .none
        }
    }

    static func remoteStatus(for state: PracticeSessionState) -> String {
        switch state {
        case .aligning:
            return "ALIGNMENT"
        case .readyToStart:
            return "READY"
        case let .searchingForPerson(_, swingCount):
            return "FINDING PERSON · SHOT \(shotNumber(swingCount + 1))"
        case let .readyForSwing(_, swingCount):
            return "PERSON READY · SHOT \(shotNumber(swingCount + 1))"
        case let .capturingSwing(_, swingCount):
            return "SWING DETECTED · SHOT \(shotNumber(swingCount + 1))"
        case let .finalizingCapture(_, swingCount):
            return "SAVING · SHOT \(shotNumber(swingCount + 1))"
        case let .processing(_, swingCount):
            return "ANALYSING · SHOT \(shotNumber(swingCount))"
        case let .resultRibbon(_, swingCount, _):
            return "RESULT · SHOT \(shotNumber(swingCount))"
        case .paused:
            return "PAUSED"
        case .degraded:
            return "CHECK CAMERA"
        case .failed:
            return "SESSION STOPPED"
        }
    }

    static func remoteDetail(for state: PracticeSessionState) -> String? {
        switch state {
        case .aligning:
            return nil
        case .readyToStart:
            return "站姿已锁定 · 可开始自动练习"
        case .searchingForPerson:
            return "正在寻找人物"
        case .readyForSwing:
            return "人物已入镜，请准备"
        case .capturingSwing:
            return "检测挥杆中"
        case .finalizingCapture:
            return "正在生成视频"
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

enum ManualCapturePresentation {
    static let title = "手动录制"
    static let detail = "点击即录 · 最长 15 秒"
    static let framingPrompt = "全身与球位进入框内"
    static let readyDetail = "点击立即录制"
}

enum ManualCaptureTiming {
    static let maximumDuration: TimeInterval = 15
}

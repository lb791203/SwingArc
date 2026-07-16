import Foundation

enum WorkspaceLayoutMode: Equatable {
    case compact
    case regular

    static func resolve(isRegularWidth: Bool) -> WorkspaceLayoutMode {
        isRegularWidth ? .regular : .compact
    }
}

enum WorkspaceInteractionMode: Equatable {
    case idle
    case drawing
}

enum StageAdjustmentPlacement: Equatable {
    case inline
}

enum WorkspaceAccessoryPolicy {
    static let drawingRailMaximumWidth: CGFloat = 56
    static let stageAdjustmentPlacement: StageAdjustmentPlacement = .inline
}

enum CameraCaptureLayout {
    static func instructionVerticalPosition(containerHeight: CGFloat) -> CGFloat {
        min(containerHeight * 0.72, containerHeight - 180)
    }
}

enum DrawingUndoIntent: Equatable {
    case undoLast
    case confirmClearAll
}

enum DrawingRailPolicy {
    static func undoIntent(isLongPress: Bool) -> DrawingUndoIntent {
        isLongPress ? .confirmClearAll : .undoLast
    }
}

struct WorkspaceModeTransition: Equatable {
    let mode: WorkspaceInteractionMode
    let showsDrawingRail: Bool
    let shouldPausePlayback: Bool

    static func enterDrawing(isPlaying: Bool) -> WorkspaceModeTransition {
        WorkspaceModeTransition(
            mode: .drawing,
            showsDrawingRail: true,
            shouldPausePlayback: isPlaying
        )
    }

    static let beginPlayback = WorkspaceModeTransition(
        mode: .idle,
        showsDrawingRail: false,
        shouldPausePlayback: false
    )

    static let finishDrawing = beginPlayback
}

enum AnalysisProgressPhase: Equatable {
    case preparing
    case locating
    case extracting
    case solving
}

struct AnalysisProgressPresentation: Equatable {
    let phase: AnalysisProgressPhase
    let progress: Double

    var title: String {
        switch phase {
        case .preparing: return "准备视频"
        case .locating: return "定位挥杆段"
        case .extracting: return "逐帧提取"
        case .solving: return "阶段求解"
        }
    }

    var detail: String {
        switch phase {
        case .preparing: return "正在读取视频信息"
        case .locating: return "正在以 8 FPS 粗扫完整视频"
        case .extracting: return "正在提取人体关节证据"
        case .solving: return "正在按时间顺序定位 P1–P8"
        }
    }

    var percentage: Int {
        Int((min(max(progress, 0), 1) * 100).rounded())
    }
}

final class AnalysisRunGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activeID: UUID?

    @discardableResult
    func begin() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        activeID = id
        return id
    }

    func cancel() {
        lock.lock()
        activeID = nil
        lock.unlock()
    }

    func isActive(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeID == id
    }

    func complete(_ id: UUID) {
        lock.lock()
        if activeID == id {
            activeID = nil
        }
        lock.unlock()
    }
}

enum WorkspaceSaveStatus: Equatable {
    case idle
    case saving
    case saved
    case failed

    var label: String {
        switch self {
        case .idle: return ""
        case .saving: return "正在保存"
        case .saved: return "已保存"
        case .failed: return "保存失败"
        }
    }
}

enum StageResultState: Equatable {
    case confirmed
    case review
    case unresolved
    case manual
}

enum StageStripIndicator: String, Equatable {
    case filledCircle = "circle.fill"
    case hollowCircle = "circle"
    case lock = "lock.fill"
}

enum StageStripPolicy {
    static let buttonHeight: CGFloat = 44
    static let maximumTotalHeight: CGFloat = 80

    static func indicator(for state: StageResultState) -> StageStripIndicator {
        switch state {
        case .confirmed, .review: return .filledCircle
        case .unresolved: return .hollowCircle
        case .manual: return .lock
        }
    }
}

struct StageResultSummary: Equatable {
    let confirmed: Int
    let review: Int
    let unresolved: Int

    init(statuses: [StageResultState]) {
        confirmed = statuses.filter { $0 == .confirmed || $0 == .manual }.count
        review = statuses.filter { $0 == .review }.count
        unresolved = statuses.filter { $0 == .unresolved }.count
    }
}

enum VideoFramePolicy {
    static func frameDuration(sourceFrameRate: Double) -> Double {
        sourceFrameRate > 0 ? 1.0 / sourceFrameRate : 1.0 / 60.0
    }
}

enum LocalProjectStatus: String, Codable, Equatable {
    case pending
    case analyzed
    case annotated
}

struct LocalProjectSummary: Identifiable, Codable, Equatable {
    let id: UUID
    let videoURL: URL
    var name: String
    var duration: Double
    var sourceFrameRate: Double
    var modifiedAt: Date
    var status: LocalProjectStatus

    init(
        id: UUID = UUID(),
        videoURL: URL,
        name: String,
        duration: Double,
        sourceFrameRate: Double,
        modifiedAt: Date = Date(),
        status: LocalProjectStatus = .pending
    ) {
        self.id = id
        self.videoURL = videoURL
        self.name = name
        self.duration = duration
        self.sourceFrameRate = sourceFrameRate
        self.modifiedAt = modifiedAt
        self.status = status
    }
}

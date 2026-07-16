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
    case expanding
    case evidence
    case solving
}

struct AnalysisProgressPresentation: Equatable {
    let phase: AnalysisProgressPhase
    let progress: Double

    var title: String {
        switch phase {
        case .preparing: return "准备视频"
        case .locating: return "定位挥杆核心"
        case .expanding: return "扩展挥杆边界"
        case .evidence: return "提取候选证据"
        case .solving: return "全局阶段求解"
        }
    }

    var detail: String {
        switch phase {
        case .preparing: return "正在读取视频信息"
        case .locating: return "正在以 8 FPS 粗扫完整视频"
        case .expanding: return "正在寻找准备位和稳定收杆"
        case .evidence: return "正在检查关节、杆身和球位"
        case .solving: return "正在联合定位 P1–P8"
        }
    }

    var percentage: Int {
        Int((min(max(progress, 0), 1) * 100).rounded())
    }
}

struct AnalysisFailurePresentation: Equatable {
    let failure: AnalysisFailure

    var message: String {
        switch failure {
        case .noVideo:
            return "没有可分析的视频，请重新导入或录制。"
        case .invalidDuration:
            return "视频读取失败，请重新导入。"
        case .insufficientPoseEvidence:
            return "未检测到清晰人体。请选择全身入镜、光线充足的视频；手工标注不会被清除。"
        case .noStableGolfer:
            return "无法持续锁定主球员。请使用固定机位、全身入镜且避免多人遮挡的视频。"
        case .noSwingMotion:
            return "没有找到完整挥杆动作。请确认视频包含从准备到收杆的连续挥杆。"
        case .ambiguousSwingWindows:
            return "检测到多个强度接近的挥杆片段。请裁剪为单次挥杆后重新分析。"
        case .swingWindowTooLong:
            return "挥杆候选片段超过 6 秒。请裁剪无关准备或走动部分后重试。"
        case .frameExtractionFailed:
            return "源视频帧读取不完整，无法进行逐帧定位。请重新导入原始视频。"
        case .missingAddressBoundary:
            return "找不到准备位到起杆的边界"
        case .missingTopTransition:
            return "找不到上杆顶点到下杆的转换"
        case .noImpactCorridor:
            return "找不到可信的击球候选段"
        case .missingFinishBoundary:
            return "找不到稳定收杆位置"
        case .incompleteSwingClip:
            return "视频缺少完整挥杆前段或后段"
        case .analysisCancelled:
            return "分析已取消"
        }
    }
}

enum SwingVideoAnalysisProgressPolicy {
    static func expansionProgress(
        cachedFrameCount: Int,
        maximumFrameBudget: Int
    ) -> Double {
        let denominator = max(1, maximumFrameBudget)
        let ratio = min(1, max(0, Double(cachedFrameCount) / Double(denominator)))
        return 0.20 + ratio * 0.50
    }

    static func evidenceProgress(
        processedReferenceCount: Int,
        totalReferenceCount: Int
    ) -> Double {
        let denominator = max(1, totalReferenceCount)
        let ratio = min(1, max(0, Double(processedReferenceCount) / Double(denominator)))
        return 0.70 + ratio * 0.25
    }
}

enum SwingVideoAnalysisValidationPolicy {
    static func transitionFailure(
        hasTopTransition: Bool,
        hasImpactCandidates: Bool
    ) -> AnalysisFailure? {
        guard hasTopTransition else { return .missingTopTransition }
        guard hasImpactCandidates else { return .noImpactCorridor }
        return nil
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

    @discardableResult
    func cancel(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activeID == id else { return false }
        activeID = nil
        return true
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

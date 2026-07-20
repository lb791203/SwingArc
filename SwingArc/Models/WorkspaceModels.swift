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
            return "挥杆候选片段超过 8 秒。请裁剪无关准备或走动部分后重试。"
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
    static func prioritizedFailure(
        frameExtractionFailed: Bool,
        evidenceFailure: AnalysisFailure?
    ) -> AnalysisFailure? {
        if frameExtractionFailed { return .frameExtractionFailed }
        return evidenceFailure
    }

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
    private let lock = NSRecursiveLock()
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

    @discardableResult
    func mutateIfActive(
        _ id: UUID,
        invalidatingAfterMutation: Bool,
        _ mutation: () -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activeID == id else { return false }
        mutation()
        if invalidatingAfterMutation, activeID == id {
            activeID = nil
        }
        return true
    }
}

/// The single publication boundary used after work has crossed an async queue.
/// Replacement is silent; explicit cancellation publishes while the run is
/// still active and invalidates it atomically after the mutation.
enum AnalysisRunPublicationPolicy {
    static func beginReplacement(gate: AnalysisRunGate) -> UUID {
        gate.begin()
    }

    @discardableResult
    static func publish(
        runID: UUID,
        gate: AnalysisRunGate,
        _ mutation: () -> Void
    ) -> Bool {
        gate.mutateIfActive(
            runID,
            invalidatingAfterMutation: false,
            mutation
        )
    }

    @discardableResult
    static func complete(
        runID: UUID,
        gate: AnalysisRunGate,
        _ mutation: () -> Void
    ) -> Bool {
        gate.mutateIfActive(
            runID,
            invalidatingAfterMutation: true,
            mutation
        )
    }

    @discardableResult
    static func cancel(
        runID: UUID,
        gate: AnalysisRunGate,
        _ publishCancellation: () -> Void
    ) -> Bool {
        gate.mutateIfActive(
            runID,
            invalidatingAfterMutation: true,
            publishCancellation
        )
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

enum MediaLoadState: Equatable {
    case idle
    case ready
    case missing
}

enum MediaLoadPolicy {
    static let missingMessage = "视频文件缺失"

    static func state(fileExists: Bool) -> MediaLoadState {
        fileExists ? .ready : .missing
    }
}

enum FullscreenPlaybackPolicy {
    static let autoHideDelay: TimeInterval = 2.5
    static let minimumTouchTarget: CGFloat = 44
    static let allowsDrawing = false
    static let showsWorkspaceChrome = false
    static let showsTimeLabels = false
    static let showsTransportButtons = false
}

enum FullscreenReplayTap: Equatable {
    case video
    case feedbackPill
    case phase(SwingStage)
    case dismiss
}

enum FullscreenReplayAction: Equatable {
    case togglePlayback
    case openFeedback
    case seek(SwingStage)
    case dismiss
}

enum FullscreenReplayPolicy {
    static func action(for tap: FullscreenReplayTap) -> FullscreenReplayAction {
        switch tap {
        case .video: return .togglePlayback
        case .feedbackPill: return .openFeedback
        case let .phase(stage): return .seek(stage)
        case .dismiss: return .dismiss
        }
    }
}

enum SwingPhaseAppearance: Equatable {
    case confirmed
    case subdued
    case hidden
}

enum SwingPhaseRailPolicy {
    static func appearance(
        for state: StageResultState,
        hasMarker: Bool
    ) -> SwingPhaseAppearance {
        guard hasMarker else { return .hidden }
        switch state {
        case .confirmed, .manual: return .confirmed
        case .review: return .subdued
        case .unresolved: return .hidden
        }
    }
}

enum FeedbackMetric: String, CaseIterable, Codable, Equatable, Identifiable {
    case alignment
    case hipBend
    case hipDepth
    case kneeFlex
    case handPosition
    case swingPlane
    case handPath
    case spineStability
    case headPosition
    case hipPosition
    case chestPosition
    case stanceWidth
    case clubRelease
    case spineTilt
    case leadShoulder
    case leadHip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alignment: return "瞄准"
        case .hipBend: return "髋部前倾"
        case .hipDepth: return "髋部深度"
        case .kneeFlex: return "膝屈"
        case .handPosition: return "手位"
        case .swingPlane: return "挥杆平面"
        case .handPath: return "手部路径"
        case .spineStability: return "脊柱稳定"
        case .headPosition: return "头部位置"
        case .hipPosition: return "髋位"
        case .chestPosition: return "胸位"
        case .stanceWidth: return "站距"
        case .clubRelease: return "释放"
        case .spineTilt: return "脊柱侧倾"
        case .leadShoulder: return "前导肩"
        case .leadHip: return "前导髋"
        }
    }
}

enum FeedbackEvidenceRequirement: Equatable {
    case pose
    case clubAndImpact
}

struct FeedbackMetricDefinition: Equatable {
    let metric: FeedbackMetric
    let stages: [SwingStage]
    let evidence: FeedbackEvidenceRequirement

    var title: String { metric.title }
}

struct FeedbackGroup: Equatable {
    let title: String
    let metrics: [FeedbackMetricDefinition]
}

struct FeedbackProfile: Equatable {
    let view: PracticeCameraView
    let groups: [FeedbackGroup]

    func metric(_ metric: FeedbackMetric) -> FeedbackMetricDefinition? {
        groups.lazy.flatMap(\.metrics).first { $0.metric == metric }
    }

    func contains(_ metric: FeedbackMetric) -> Bool {
        self.metric(metric) != nil
    }
}

struct FeedbackCheckpoint: Codable, Hashable, Equatable {
    let metric: FeedbackMetric
    let stage: SwingStage
}

struct FeedbackConfiguration: Codable, Equatable {
    var activeMetric: FeedbackMetric
    var enabledCheckpoints: Set<FeedbackCheckpoint>

    static func defaultValue(for view: PracticeCameraView) -> FeedbackConfiguration {
        switch view {
        case .downTheLine:
            return FeedbackConfiguration(
                activeMetric: .swingPlane,
                enabledCheckpoints: [
                    FeedbackCheckpoint(metric: .swingPlane, stage: .takeaway),
                    FeedbackCheckpoint(metric: .swingPlane, stage: .leadArmParallelDownswing)
                ]
            )
        case .faceOn:
            return FeedbackConfiguration(
                activeMetric: .spineTilt,
                enabledCheckpoints: [
                    FeedbackCheckpoint(metric: .spineTilt, stage: .top),
                    FeedbackCheckpoint(metric: .spineTilt, stage: .impact)
                ]
            )
        }
    }
}

enum FeedbackAvailability: Equatable {
    case available
    case unavailable(String)

    static func resolve(
        metric: FeedbackMetric,
        analysis: SwingAnalysisState,
        sourceFrameRate: Double
    ) -> FeedbackAvailability {
        guard metric == .clubRelease else {
            guard case let .completed(result) = analysis,
                  result.detections.contains(where: { $0.status == .confirmed }),
                  sourceFrameRate > 0 else {
                return .unavailable("当前画面证据不足")
            }
            return .available
        }

        guard case let .completed(result) = analysis,
              sourceFrameRate >= 120,
              let impact = result.detections.first(where: { $0.stage == .impact }),
              impact.status == .confirmed,
              impact.hasClubEvidence,
              impact.hasBallEvidence || impact.hasBallChangeEvidence else {
            return .unavailable("需要可靠的杆头与击球证据")
        }
        return .available
    }
}

enum SwingFeedbackProfiles {
    private static let setupDTL: [FeedbackMetricDefinition] = [
        .init(metric: .alignment, stages: [.address], evidence: .pose),
        .init(metric: .hipBend, stages: [.address], evidence: .pose),
        .init(metric: .hipDepth, stages: [.address], evidence: .pose),
        .init(metric: .kneeFlex, stages: [.address], evidence: .pose),
        .init(metric: .handPosition, stages: [.address], evidence: .pose)
    ]

    private static let setupFaceOn: [FeedbackMetricDefinition] = [
        .init(metric: .hipPosition, stages: [.address], evidence: .pose),
        .init(metric: .chestPosition, stages: [.address], evidence: .pose),
        .init(metric: .handPosition, stages: [.address], evidence: .pose),
        .init(metric: .stanceWidth, stages: [.address], evidence: .pose)
    ]

    private static let movementStages: [SwingStage] = [
        .takeaway,
        .leadArmParallelBackswing,
        .top,
        .leadArmParallelDownswing,
        .impact,
        .followThrough
    ]

    static func profile(for view: PracticeCameraView) -> FeedbackProfile {
        switch view {
        case .downTheLine:
            return FeedbackProfile(view: view, groups: [
                FeedbackGroup(title: "准备姿势", metrics: setupDTL),
                FeedbackGroup(title: "挥杆平面", metrics: [
                    .init(metric: .swingPlane, stages: [
                        .takeaway,
                        .leadArmParallelBackswing,
                        .leadArmParallelDownswing,
                        .followThrough
                    ], evidence: .pose)
                ]),
                FeedbackGroup(title: "手部路径", metrics: [
                    .init(metric: .handPath, stages: movementStages, evidence: .pose)
                ]),
                FeedbackGroup(title: "脊柱稳定", metrics: [
                    .init(metric: .spineStability, stages: movementStages, evidence: .pose)
                ]),
                FeedbackGroup(title: "头部位置", metrics: [
                    .init(metric: .headPosition, stages: Array(SwingStage.allCases.dropLast()), evidence: .pose)
                ])
            ])
        case .faceOn:
            return FeedbackProfile(view: view, groups: [
                FeedbackGroup(title: "准备姿势", metrics: setupFaceOn),
                FeedbackGroup(title: "释放", metrics: [
                    .init(metric: .clubRelease, stages: [
                        .leadArmParallelDownswing,
                        .impact
                    ], evidence: .clubAndImpact)
                ]),
                FeedbackGroup(title: "脊柱侧倾", metrics: [
                    .init(metric: .spineTilt, stages: movementStages, evidence: .pose)
                ]),
                FeedbackGroup(title: "前导肩", metrics: [
                    .init(metric: .leadShoulder, stages: [.top, .impact], evidence: .pose)
                ]),
                FeedbackGroup(title: "前导髋", metrics: [
                    .init(metric: .leadHip, stages: movementStages, evidence: .pose)
                ]),
                FeedbackGroup(title: "头部位置", metrics: [
                    .init(metric: .headPosition, stages: Array(SwingStage.allCases.dropLast()), evidence: .pose)
                ])
            ])
        }
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

import SwiftUI
import PhotosUI
import Foundation
import UIKit

private enum MediaAction {
    case save
    case share
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var playbackManager = VideoPlaybackManager()

    @State private var projects = LocalProjectStore.projects()
    @State private var activeProject: LocalProjectSummary?
    @State private var currentProjectURL: URL?
    @State private var practiceCameraView: PracticeCameraView?
    @State private var legacyFeedbackConfiguration: FeedbackConfiguration?
    @State private var saveStatus: WorkspaceSaveStatus = .idle

    @State private var drawings: [DrawingElement] = []
    @State private var keyframes: [KeyframeMarker] = []
    @State private var stageCorrections: [StageCorrection] = []
    @State private var isKeyframeMode = false
    @State private var showPoseSkeleton = false
    @State private var showHeadStability = false
    @State private var showSpineAngle = false
    @State private var showGrid = false

    @State private var showProjectLibrary = false
    @State private var showAboutPrivacy = false
    @State private var showVideoPicker = false
    @State private var showManualCapture = false
    @State private var showPPointCorrection = false
    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var showExportActions = false
    @State private var sharePayload: SharePayload?
    @State private var isExporting = false
    @State private var statusMessage: String?
    @State private var showsSettingsAction = false
    @State private var didLoadPreviewImport = false

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if PracticePreviewConfiguration.showsLibrary(for: arguments) {
            _showProjectLibrary = State(initialValue: true)
        }
        if PracticePreviewConfiguration.showsManualCapture(for: arguments) {
            _showManualCapture = State(initialValue: true)
        }
        #endif
    }

    var body: some View {
        Group {
            if let activeProject {
                AnalysisWorkspaceView(
                    project: activeProject,
                    projects: projects,
                    playbackManager: playbackManager,
                    drawings: $drawings,
                    keyframes: $keyframes,
                    isKeyframeMode: $isKeyframeMode,
                    saveStatus: saveStatus,
                    onBack: closeWorkspace,
                    onSelectProject: openProject,
                    onExport: { showExportActions = true },
                    onAnalyze: runAISwingAnalysis,
                    onCancelAnalysis: playbackManager.cancelAnalysis,
                    onSetManualStage: saveManualStage,
                    onCorrectPPoints: {
                        playbackManager.pause()
                        showPPointCorrection = true
                    }
                )
            } else if showProjectLibrary {
                ProjectLibraryView(
                    projects: projects,
                    onOpen: openProject,
                    onRename: renameProject,
                    onDelete: deleteProject,
                    onClose: { showProjectLibrary = false }
                )
            } else {
                PracticeHomeView(
                    onManualCapture: { showManualCapture = true },
                    onImport: { showVideoPicker = true },
                    onOpenLibrary: { showProjectLibrary = true },
                    onOpenAbout: { showAboutPrivacy = true }
                )
            }
        }
        .photosPicker(isPresented: $showVideoPicker, selection: $selectedPickerItem, matching: .videos)
        .onChange(of: selectedPickerItem) { _, item in
            guard let item else { return }
            loadSelectedVideo(from: item)
            selectedPickerItem = nil
        }
        .onAppear {
            #if DEBUG
            guard !didLoadPreviewImport,
                  let path = PracticePreviewConfiguration.importPath(
                    for: ProcessInfo.processInfo.arguments
                  ) else { return }

            didLoadPreviewImport = true
            loadVideoFromURL(
                URL(fileURLWithPath: path),
                practiceView: PracticePreviewConfiguration.view(
                    for: ProcessInfo.processInfo.arguments
                )
            )
            #endif
        }
        .onChange(of: drawings) { _, _ in persistCurrentProject() }
        .onChange(of: keyframes) { _, _ in persistCurrentProject() }
        .onChange(of: stageCorrections) { _, _ in persistCurrentProject() }
        .onChange(of: isKeyframeMode) { _, _ in persistCurrentProject() }
        .onChange(of: showPoseSkeleton) { _, _ in persistCurrentProject() }
        .onChange(of: showHeadStability) { _, _ in persistCurrentProject() }
        .onChange(of: showSpineAngle) { _, _ in persistCurrentProject() }
        .onChange(of: showGrid) { _, _ in persistCurrentProject() }
        .onChange(of: practiceCameraView) { _, _ in persistCurrentProject() }
        .fullScreenCover(isPresented: $showManualCapture) {
            CameraView { temporaryURL in
                persistCapturedVideo(temporaryURL)
            }
        }
        .fullScreenCover(isPresented: $showPPointCorrection) {
            if let currentProjectURL {
                PPointCorrectionWorkspace(
                    videoURL: currentProjectURL,
                    prediction: AnnotationPredictionAdapter.snapshot(
                        detections: playbackManager.analysisOutput?.result.detections ?? [],
                        frames: playbackManager.analysisOutput?.observationFrames ?? []
                    ),
                    markers: keyframes,
                    initialTime: playbackManager.currentTime,
                    onClose: { showPPointCorrection = false },
                    onSave: savePPointCorrection
                )
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.url])
        }
        .sheet(isPresented: $showAboutPrivacy) {
            AboutPrivacyView()
        }
        .confirmationDialog("导出", isPresented: $showExportActions, titleVisibility: .visible) {
            Button("保存当前标注帧") { performMediaAction(.save, kind: .frame) }
            Button("保存标注视频") { performMediaAction(.save, kind: .annotatedVideo) }
            Button("分享当前标注帧") { performMediaAction(.share, kind: .frame) }
            Button("分享标注视频") { performMediaAction(.share, kind: .annotatedVideo) }
            Button("取消", role: .cancel) {}
        }
        .alert("SwingArc", isPresented: Binding(
            get: { statusMessage != nil },
            set: {
                if !$0 {
                    statusMessage = nil
                    showsSettingsAction = false
                }
            }
        )) {
            if showsSettingsAction {
                Button("打开设置") {
                    guard let url = URL(
                        string: UIApplication.openSettingsURLString
                    ) else { return }
                    openURL(url)
                }
            }
            Button("好", role: .cancel) {
                showsSettingsAction = false
            }
        } message: {
            Text(statusMessage ?? "")
        }
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    ProgressView("正在生成媒体…")
                        .tint(.white)
                        .foregroundStyle(.white)
                        .padding(18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func openProject(_ project: LocalProjectSummary) {
        if currentProjectURL != project.videoURL {
            persistCurrentProject()
        }
        loadVideoFromURL(project.videoURL, existingSummary: project, origin: .projectReopened)
    }

    private func closeWorkspace() {
        persistCurrentProject()
        playbackManager.unloadVideo()
        activeProject = nil
        currentProjectURL = nil
        practiceCameraView = nil
        legacyFeedbackConfiguration = nil
        stageCorrections = []
        saveStatus = .idle
        projects = LocalProjectStore.projects()
    }

    private func loadSelectedVideo(from pickerItem: PhotosPickerItem) {
        pickerItem.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data?):
                Task { @MainActor in
                    isExporting = true
                    do {
                        let videoURL = try await ImportedVideoStore(
                            destinationDirectory: LocalProjectStore.videoDirectory()
                        ).persist(data: data)
                        loadVideoFromURL(videoURL, origin: .importCompleted)
                    } catch {
                        showsSettingsAction = false
                        statusMessage = "所选文件不是可播放的视频，请重新选择。"
                    }
                    isExporting = false
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    showsSettingsAction = false
                    statusMessage = "无法读取所选视频：\(error.localizedDescription)"
                }
            default:
                break
            }
        }
    }

    private func persistCapturedVideo(_ temporaryURL: URL) {
        isExporting = true
        Task {
            do {
                let clip = try await CapturedVideoStore(
                    destinationDirectory: LocalProjectStore.videoDirectory()
                ).persist(
                    sourceURL: temporaryURL,
                    prefix: "manual",
                    quality: .complete
                )
                showManualCapture = false
                loadVideoFromURL(clip.url, origin: .capturedClipSaved)
            } catch {
                showsSettingsAction = false
                statusMessage = "录像已经完成，但保存失败。请检查本机储存空间后重试。"
            }
            isExporting = false
        }
    }

    private func loadVideoFromURL(
        _ url: URL,
        existingSummary: LocalProjectSummary? = nil,
        practiceView: PracticeCameraView? = nil,
        origin: VideoLoadOrigin = .importCompleted
    ) {
        playbackManager.unloadVideo()
        currentProjectURL = nil
        drawings = []
        keyframes = []
        stageCorrections = []
        legacyFeedbackConfiguration = nil
        isKeyframeMode = false
        showPoseSkeleton = false
        showHeadStability = false
        showSpineAngle = false
        showGrid = false
        saveStatus = .idle

        let didLoad = playbackManager.loadVideo(url: url)

        if let saved = LocalProjectStore.load(for: url) {
            drawings = saved.drawings
            keyframes = saved.keyframes
            isKeyframeMode = saved.isKeyframeMode
            showPoseSkeleton = saved.showPoseSkeleton
            showHeadStability = saved.showHeadStability
            showSpineAngle = saved.showSpineAngle
            showGrid = saved.showGrid
            self.practiceCameraView = practiceView ?? saved.practiceCameraView
            stageCorrections = saved.stageCorrections
            legacyFeedbackConfiguration = saved.legacyFeedbackConfiguration
        } else {
            self.practiceCameraView = practiceView
        }

        var summary = existingSummary
            ?? projects.first(where: { $0.videoURL == url })
            ?? LocalProjectSummary(
                videoURL: url,
                name: defaultProjectName(),
                duration: playbackManager.duration,
                sourceFrameRate: playbackManager.sourceFrameRate
            )
        if didLoad {
            summary.duration = playbackManager.duration
            summary.sourceFrameRate = playbackManager.sourceFrameRate
        }
        summary.modifiedAt = Date()
        summary.status = projectStatus
        LocalProjectStore.upsertSummary(summary)

        currentProjectURL = url
        activeProject = summary
        projects = LocalProjectStore.projects()
        saveStatus = .saved
        migrateLegacyAnnotationIfNeeded(for: url)

        if didLoad, AutomaticAnalysisPolicy.shouldAnalyze(event: origin) {
            DispatchQueue.main.async {
                guard currentProjectURL == url, playbackManager.analysisState == .idle else { return }
                runAISwingAnalysis()
            }
        }
    }

    private func persistCurrentProject() {
        guard let videoURL = currentProjectURL, var project = activeProject else { return }
        saveStatus = .saving
        let saved = LocalProjectStore.save(
            LocalAnalysisProject(
                drawings: drawings,
                keyframes: keyframes,
                isKeyframeMode: isKeyframeMode,
                showPoseSkeleton: showPoseSkeleton,
                showHeadStability: showHeadStability,
                showSpineAngle: showSpineAngle,
                showGrid: showGrid,
                practiceCameraView: practiceCameraView,
                stageCorrections: stageCorrections,
                legacyFeedbackConfiguration: legacyFeedbackConfiguration
            ),
            for: videoURL
        )

        project.modifiedAt = Date()
        project.duration = playbackManager.duration
        project.sourceFrameRate = playbackManager.sourceFrameRate
        project.status = projectStatus
        LocalProjectStore.upsertSummary(project)
        activeProject = project
        projects = LocalProjectStore.projects()
        saveStatus = saved ? .saved : .failed
    }

    private func migrateLegacyAnnotationIfNeeded(for videoURL: URL) {
        Task {
            do {
                let mediaSHA256 = try await Task.detached(
                    priority: .utility
                ) {
                    try AnnotationStore.mediaSHA256(url: videoURL)
                }.value
                guard currentProjectURL == videoURL,
                      !LegacyAnnotationMigration.isCompleted(
                          mediaSHA256: mediaSHA256
                      ) else {
                    return
                }

                let store = AnnotationStore()
                guard let package = try store.load(
                    mediaSHA256: mediaSHA256
                ) else {
                    LegacyAnnotationMigration.markCompleted(
                        mediaSHA256: mediaSHA256
                    )
                    return
                }

                let frameSession = ExactVideoFrameSession()
                let metadata = try await frameSession.open(url: videoURL)
                guard metadata.timelineSHA256
                    == package.media.timelineSHA256 else {
                    throw AnnotationStoreError.mediaIdentityMismatch
                }
                var frameTimes: [Int: Double] = [:]
                for frame in LegacyAnnotationMigration.sourceFrameIndices(
                    package: package
                ) {
                    if let time = await frameSession.presentationTimeSeconds(
                        at: frame
                    ) {
                        frameTimes[frame] = time
                    }
                }

                guard currentProjectURL == videoURL else { return }
                let migrated = LegacyAnnotationMigration.migrate(
                    package: package,
                    frameTimes: frameTimes,
                    existingMarkers: keyframes
                )

                if migrated.sanitizedPackage != package {
                    try store.save(
                        migrated.sanitizedPackage,
                        expectedMediaSHA256: mediaSHA256
                    )
                }
                if migrated.markers != keyframes {
                    keyframes = migrated.markers
                    persistCurrentProject()
                }
                guard saveStatus != .failed else { return }
                LegacyAnnotationMigration.markCompleted(
                    mediaSHA256: mediaSHA256
                )
            } catch {
                guard currentProjectURL == videoURL else { return }
                showsSettingsAction = false
                statusMessage = "已有 P 点修正未能迁移，原数据仍保留。"
            }
        }
    }

    private var projectStatus: LocalProjectStatus {
        if !drawings.isEmpty { return .annotated }
        if !keyframes.isEmpty { return .analyzed }
        return .pending
    }

    private func renameProject(_ project: LocalProjectSummary, to name: String) {
        LocalProjectStore.rename(project.id, to: name)
        projects = LocalProjectStore.projects()
        if activeProject?.id == project.id {
            activeProject = projects.first(where: { $0.id == project.id })
        }
    }

    private func deleteProject(_ project: LocalProjectSummary) {
        LocalProjectStore.remove(project.id)
        let directory = LocalProjectStore.videoDirectory()
        if project.videoURL.isFileURL && project.videoURL.path.hasPrefix(directory.path) {
            try? FileManager.default.removeItem(at: project.videoURL)
        }
        projects = LocalProjectStore.projects()
    }

    private func runAISwingAnalysis() {
        playbackManager.pause()
        playbackManager.analyzeSwing { result in
            keyframes = StageMarkerMerger.merge(existing: keyframes, automatic: result.detectedMarkers)
            guard let currentProjectURL else { return }
            playbackManager.refineManualPPoints(
                videoURL: currentProjectURL,
                manualMarkers: keyframes
            )
        }
    }

    private func saveManualStage(_ stage: SwingStage) {
        let sourceFrameIndex: Int?
        if playbackManager.sourceFrameRate > 0 {
            sourceFrameIndex = Int(
                (playbackManager.currentTime * playbackManager.sourceFrameRate).rounded()
            )
        } else {
            sourceFrameIndex = nil
        }
        saveManualStage(
            stage,
            time: playbackManager.currentTime,
            sourceFrameIndex: sourceFrameIndex
        )
    }

    private func savePPointCorrection(
        code: PPointCode,
        sourceFrameIndex: Int,
        time: Double,
        image: CGImage
    ) {
        guard SwingStage.pStages.indices.contains(code.ordinal) else { return }
        let stage = SwingStage.pStages[code.ordinal]
        saveManualStage(
            stage,
            time: time,
            sourceFrameIndex: sourceFrameIndex
        )
        if let marker = keyframes.first(where: { $0.stage == stage.rawValue }) {
            playbackManager.seek(to: marker)
        }
        playbackManager.refineManualPPoint(
            image: image,
            sourceFrameIndex: sourceFrameIndex,
            time: time
        )
    }

    private func saveManualStage(
        _ stage: SwingStage,
        time: Double,
        sourceFrameIndex: Int?
    ) {
        let marker = KeyframeMarker(
            time: time,
            stage: stage,
            source: .manual,
            sourceFrameIndex: sourceFrameIndex
        )
        keyframes.removeAll { $0.stage == stage.rawValue }
        keyframes.append(marker)
        keyframes.sort { $0.time < $1.time }
        guard let view = practiceCameraView,
              let automaticFrame = playbackManager.analysisOutput?.result.detections
                .first(where: { $0.stage == stage })?.sourceFrameIndex,
              let sourceFrameIndex else { return }
        stageCorrections.removeAll { $0.stage == stage && $0.view == view }
        stageCorrections.append(StageCorrection(
            stage: stage,
            view: view,
            automaticFrameIndex: automaticFrame,
            manualFrameIndex: sourceFrameIndex
        ))
    }

    private func performMediaAction(_ action: MediaAction, kind: MediaExportKind) {
        guard let asset = playbackManager.currentAsset else {
            showsSettingsAction = false
            statusMessage = "没有可导出的视频。"
            return
        }

        let time = playbackManager.currentTime
        let drawingsForFrame = drawings.filter {
            DrawingDisplayPolicy.shouldShow($0, at: time, isKeyframeMode: isKeyframeMode)
        }
        isExporting = true

        Task {
            do {
                let exportURL = try await MediaExportService.export(
                    kind: kind,
                    asset: asset,
                    time: time,
                    drawings: kind == .frame ? drawingsForFrame : drawings
                )
                switch action {
                case .save:
                    try await MediaExportService.saveToPhotoLibrary(exportURL, kind: kind)
                    showsSettingsAction = false
                    statusMessage = kind == .frame ? "当前帧已保存到相册。" : "标注视频已保存到相册。"
                case .share:
                    sharePayload = SharePayload(url: exportURL)
                }
            } catch {
                if case MediaExportError.photoPermissionDenied = error {
                    showsSettingsAction = true
                } else {
                    showsSettingsAction = false
                }
                statusMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func defaultProjectName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return "视频分析 \(formatter.string(from: Date()))"
    }
}

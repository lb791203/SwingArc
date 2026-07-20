import SwiftUI
import PhotosUI

private enum MediaAction {
    case save
    case share
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @StateObject private var playbackManager = VideoPlaybackManager()

    @State private var projects = LocalProjectStore.projects()
    @State private var activeProject: LocalProjectSummary?
    @State private var currentProjectURL: URL?
    @State private var saveStatus: WorkspaceSaveStatus = .idle

    @State private var drawings: [DrawingElement] = []
    @State private var keyframes: [KeyframeMarker] = []
    @State private var isKeyframeMode = false
    @State private var showPoseSkeleton = false
    @State private var showHeadStability = false
    @State private var showSpineAngle = false
    @State private var showGrid = false

    @State private var showCameraView = false
    @State private var selectedPracticeView: PracticeCameraView?
    @State private var showProjectLibrary = false
    @State private var showVideoPicker = false
    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var showExportActions = false
    @State private var sharePayload: SharePayload?
    @State private var isExporting = false
    @State private var statusMessage: String?

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
                    showPoseSkeleton: $showPoseSkeleton,
                    showHeadStability: $showHeadStability,
                    showSpineAngle: $showSpineAngle,
                    showGrid: $showGrid,
                    saveStatus: saveStatus,
                    onBack: closeWorkspace,
                    onSelectProject: openProject,
                    onExport: { showExportActions = true },
                    onAnalyze: runAISwingAnalysis,
                    onCancelAnalysis: playbackManager.cancelAnalysis,
                    onSetManualStage: saveManualStage
                )
            } else if showProjectLibrary {
                ProjectLibraryView(
                    projects: projects,
                    onOpen: openProject,
                    onImport: { showVideoPicker = true },
                    onRecord: { showCameraView = true },
                    onRename: renameProject,
                    onDelete: deleteProject,
                    onClose: { showProjectLibrary = false }
                )
            } else {
                PracticeHomeView(
                    onStartPractice: { selectedPracticeView = $0 },
                    onImport: { showVideoPicker = true },
                    onOpenLibrary: { showProjectLibrary = true }
                )
            }
        }
        .photosPicker(isPresented: $showVideoPicker, selection: $selectedPickerItem, matching: .videos)
        .onChange(of: selectedPickerItem) { _, item in
            guard let item else { return }
            loadSelectedVideo(from: item)
            selectedPickerItem = nil
        }
        .onChange(of: drawings) { _, _ in persistCurrentProject() }
        .onChange(of: keyframes) { _, _ in persistCurrentProject() }
        .onChange(of: isKeyframeMode) { _, _ in persistCurrentProject() }
        .onChange(of: showPoseSkeleton) { _, _ in persistCurrentProject() }
        .onChange(of: showHeadStability) { _, _ in persistCurrentProject() }
        .onChange(of: showSpineAngle) { _, _ in persistCurrentProject() }
        .onChange(of: showGrid) { _, _ in persistCurrentProject() }
        .fullScreenCover(isPresented: $showCameraView) {
            CameraView { recordedURL in
                showCameraView = false
                loadVideoFromURL(persistVideoIfNeeded(recordedURL))
            }
        }
        .fullScreenCover(item: $selectedPracticeView) { practiceView in
            PracticeSessionView(
                view: practiceView,
                onClose: {
                    selectedPracticeView = nil
                    projects = LocalProjectStore.projects()
                },
                onOpenLastClip: { clipURL in
                    selectedPracticeView = nil
                    loadVideoFromURL(clipURL)
                }
            )
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.url])
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
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
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
        loadVideoFromURL(project.videoURL, existingSummary: project)
    }

    private func closeWorkspace() {
        persistCurrentProject()
        playbackManager.unloadVideo()
        activeProject = nil
        currentProjectURL = nil
        saveStatus = .idle
        projects = LocalProjectStore.projects()
    }

    private func loadSelectedVideo(from pickerItem: PhotosPickerItem) {
        pickerItem.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data?):
                let videoURL = LocalProjectStore.videoDirectory()
                    .appendingPathComponent("imported-\(UUID().uuidString).mp4")
                do {
                    try data.write(to: videoURL, options: .atomic)
                    DispatchQueue.main.async { loadVideoFromURL(videoURL) }
                } catch {
                    DispatchQueue.main.async { statusMessage = "视频导入失败：\(error.localizedDescription)" }
                }
            case .failure(let error):
                DispatchQueue.main.async { statusMessage = "无法读取所选视频：\(error.localizedDescription)" }
            default:
                break
            }
        }
    }

    private func loadVideoFromURL(_ url: URL, existingSummary: LocalProjectSummary? = nil) {
        playbackManager.unloadVideo()
        currentProjectURL = nil
        drawings = []
        keyframes = []
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
                showGrid: showGrid
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
        }
    }

    private func saveManualStage(_ stage: SwingStage) {
        let marker = KeyframeMarker(time: playbackManager.currentTime, stage: stage, source: .manual)
        keyframes.removeAll { $0.stage == stage.rawValue }
        keyframes.append(marker)
        keyframes.sort { $0.time < $1.time }
    }

    private func performMediaAction(_ action: MediaAction, kind: MediaExportKind) {
        guard let asset = playbackManager.currentAsset else {
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
                    statusMessage = kind == .frame ? "当前帧已保存到相册。" : "标注视频已保存到相册。"
                case .share:
                    sharePayload = SharePayload(url: exportURL)
                }
            } catch {
                statusMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func persistVideoIfNeeded(_ sourceURL: URL) -> URL {
        guard sourceURL.isFileURL else { return sourceURL }
        let directory = LocalProjectStore.videoDirectory()
        guard !sourceURL.path.hasPrefix(directory.path) else { return sourceURL }
        let pathExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destination = directory.appendingPathComponent("recorded-\(UUID().uuidString).\(pathExtension)")
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            statusMessage = "录制视频保存失败：\(error.localizedDescription)"
            return sourceURL
        }
    }

    private func defaultProjectName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return "视频分析 \(formatter.string(from: Date()))"
    }
}

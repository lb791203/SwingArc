import SwiftUI
import Combine
import CoreGraphics

@MainActor
public struct DatasetSubjectAnchorSheet: View {
    @ObservedObject var anchorController: DatasetSubjectAnchorController
    @ObservedObject var runGenerator: DatasetPredictionRunGenerator
    let clip: GolfClipIdentity
    let store: GolfDatasetStore
    let videoURL: URL
    let onDismiss: () -> Void

    @State private var currentFrameIndex: Int = 0
    @State private var selectedCandidateIndex: Int? = nil
    @State private var lastClickPoint: GolfNormalizedPoint? = nil
    @State private var annotatorIDInput: String = "annotator-mac"
    @State private var message: String? = nil
    @State private var generationTask: Task<Void, Never>?

    public init(
        anchorController: DatasetSubjectAnchorController,
        runGenerator: DatasetPredictionRunGenerator,
        clip: GolfClipIdentity,
        store: GolfDatasetStore,
        videoURL: URL,
        onDismiss: @escaping () -> Void
    ) {
        self.anchorController = anchorController
        self.runGenerator = runGenerator
        self.clip = clip
        self.store = store
        self.videoURL = videoURL
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("主体锚点 — \(clip.clipID)")
                    .font(.title3).bold()
                Spacer()
                Button("关闭") {
                    generationTask?.cancel()
                    anchorController.resetState()
                    onDismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal)

            HStack(alignment: .top, spacing: 20) {
                // Left pane: Video Frame & Vision Candidate Selection
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("帧索引: \(currentFrameIndex) / \(clip.media.frameCount - 1)")
                            .font(.headline)
                        Spacer()
                        Button("−5") { changeFrame(by: -5) }
                        Button("−1") { changeFrame(by: -1) }
                        Button("+1") { changeFrame(by: 1) }
                        Button("+5") { changeFrame(by: 5) }
                    }

                    GeometryReader { geo in
                        let imageSize = anchorController.currentFrameImage.map {
                            CGSize(width: $0.width, height: $0.height)
                        } ?? CGSize(
                            width: clip.media.orientedWidth,
                            height: clip.media.orientedHeight
                        )
                        let imageRect = DatasetSubjectAnchorGeometry.aspectFitRect(
                            imageSize: imageSize,
                            containerSize: geo.size
                        )
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(Color.black.opacity(0.9))

                            if let cgImage = anchorController.currentFrameImage {
                                #if os(macOS)
                                Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                                    .resizable()
                                    .frame(width: imageRect.width, height: imageRect.height)
                                    .position(x: imageRect.midX, y: imageRect.midY)
                                #endif
                            } else {
                                ProgressView("加载真实视频帧...")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }

                            // Overlay candidate bounding boxes
                            ForEach(anchorController.currentFrameCandidates, id: \.candidateIndex) { candidate in
                                let b = candidate.bodyBounds
                                let candidateRect = DatasetSubjectAnchorGeometry.screenRect(
                                    for: b,
                                    in: imageRect
                                )
                                let isSelected = selectedCandidateIndex == candidate.candidateIndex
                                Rectangle()
                                    .stroke(isSelected ? Color.green : Color.yellow, lineWidth: isSelected ? 3 : 2)
                                    .background(isSelected ? Color.green.opacity(0.15) : Color.yellow.opacity(0.05))
                                    .frame(
                                        width: candidateRect.width,
                                        height: candidateRect.height
                                    )
                                    .offset(
                                        x: candidateRect.minX,
                                        y: candidateRect.minY
                                    )
                                    .overlay(
                                        Text("Candidate #\(candidate.candidateIndex)")
                                            .font(.caption2).bold()
                                            .padding(2)
                                            .background(Color.black.opacity(0.75))
                                            .foregroundColor(isSelected ? .green : .yellow),
                                        alignment: .topLeading
                                    )
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    guard let pt = DatasetSubjectAnchorGeometry.normalizedImagePoint(
                                        at: value.location,
                                        imageRect: imageRect
                                    ) else {
                                        self.lastClickPoint = nil
                                        self.selectedCandidateIndex = nil
                                        self.message = "点击位于视频画面之外，请在实际画面内选择候选人"
                                        return
                                    }
                                    self.lastClickPoint = pt
                                    if let hit = anchorController.findCandidate(at: pt, in: anchorController.currentFrameCandidates) {
                                        self.selectedCandidateIndex = hit.candidateIndex
                                        self.message = "选中 Candidate #\(hit.candidateIndex) at (\(String(format: "%.3f", pt.x)), \(String(format: "%.3f", pt.y)))"
                                    } else {
                                        self.selectedCandidateIndex = nil
                                        self.message = "未命中或存在多重候选人，请精准点击候选框"
                                    }
                                }
                        )
                    }
                    .frame(width: 400, height: 350)
                    .cornerRadius(8)

                    if let status = anchorController.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let selected = selectedCandidateIndex, let pt = lastClickPoint {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("选中候选人细节:")
                                .font(.caption).bold()
                            Text("Frame: \(currentFrameIndex), Candidate: #\(selected)")
                                .font(.caption)
                            Text("点击位置: (\(String(format: "%.4f", pt.x)), \(String(format: "%.4f", pt.y)))")
                                .font(.caption)

                            Button("保存此锚点") {
                                saveAnchor(candidateIndex: selected, clickPoint: pt)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                }

                Divider()

                // Right pane: Saved Anchors & Generator
                VStack(alignment: .leading, spacing: 12) {
                    Text("已保存锚点 (\(anchorController.loadedAnchors.count))")
                        .font(.headline)

                    List {
                        ForEach(anchorController.loadedAnchors, id: \.anchorID) { anchor in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { anchorController.selectedAnchorIDs.contains(anchor.anchorID) },
                                    set: { isSelected in
                                        if isSelected {
                                            anchorController.selectedAnchorIDs.insert(anchor.anchorID)
                                        } else {
                                            anchorController.selectedAnchorIDs.remove(anchor.anchorID)
                                        }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Anchor \(anchor.anchorID.prefix(20))...")
                                            .font(.caption).bold()
                                        Text("Frame \(anchor.sourceFrameIndex), Candidate #\(anchor.candidateIndex)")
                                            .font(.caption2)
                                        Text("Click: (\(String(format: "%.3f", anchor.normalizedClickPoint.x)), \(String(format: "%.3f", anchor.normalizedClickPoint.y)))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 240)

                    if let msg = message {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }

                    if runGenerator.isGenerating {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView()
                            Text(runGenerator.progressText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let err = runGenerator.lastErrorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button("生成全视频 manual-bootstrap Run") {
                        generateFullClipRun()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(runGenerator.isGenerating || anchorController.selectedAnchorIDs.isEmpty)
                }
                .frame(width: 300)
            }
            .padding()
        }
        .frame(width: 760, height: 520)
        .onAppear {
            loadAnchors()
            anchorController.loadFrameCandidates(videoURL: videoURL, sourceFrameIndex: currentFrameIndex)
        }
        .onChange(of: currentFrameIndex) { _, newIndex in
            selectedCandidateIndex = nil
            anchorController.loadFrameCandidates(videoURL: videoURL, sourceFrameIndex: newIndex)
        }
        .onDisappear {
            generationTask?.cancel()
            generationTask = nil
        }
    }

    private func changeFrame(by delta: Int) {
        currentFrameIndex = max(0, min(clip.media.frameCount - 1, currentFrameIndex + delta))
    }

    private func loadAnchors(selectingAnchorID: String? = nil) {
        if let anchors = try? store.loadSubjectAnchors(clipID: clip.clipID) {
            anchorController.replaceLoadedAnchors(
                anchors,
                selectingAnchorID: selectingAnchorID
            )
        }
    }

    private func saveAnchor(candidateIndex: Int, clickPoint: GolfNormalizedPoint) {
        let anchor = anchorController.makeAnchor(
            clipID: clip.clipID,
            mediaSHA256: clip.media.sha256,
            timelineSHA256: clip.media.timelineSHA256,
            sourceFrameIndex: currentFrameIndex,
            candidateIndex: candidateIndex,
            clickPoint: clickPoint
        )
        do {
            try store.appendSubjectAnchor(anchor, clipID: clip.clipID)
            loadAnchors(selectingAnchorID: anchor.anchorID)
            message = "已成功保存锚点 (Frame \(currentFrameIndex), Candidate #\(candidateIndex))"
        } catch {
            message = "保存锚点失败: \(error.localizedDescription)"
        }
    }

    private func generateFullClipRun() {
        generationTask?.cancel()
        generationTask = Task {
            let selectedAnchors = anchorController.loadedAnchors.filter {
                anchorController.selectedAnchorIDs.contains($0.anchorID)
            }
            let result = await runGenerator.generateManualBootstrapRun(
                clip: clip,
                store: store,
                anchors: selectedAnchors,
                videoURL: videoURL
            )
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let run):
                message = "成功生成并写入 Run: \(run.predictionRunID.prefix(16))..."
            case .failure(let err):
                message = "生成失败: \(err.description)"
            }
            generationTask = nil
        }
    }
}

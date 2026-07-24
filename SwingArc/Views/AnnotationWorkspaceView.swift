import SwiftUI
import Combine
import CoreMedia

@MainActor
final class AnnotationFrameController: ObservableObject {
    @Published private(set) var frameCount = 0
    @Published private(set) var timelineSHA256 = ""
    @Published private(set) var orientedWidth = 0
    @Published private(set) var orientedHeight = 0
    @Published private(set) var currentFrame: ExactVideoFrame?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let session = ExactVideoFrameSession()
    private var requestToken = 0

    func open(url: URL) async {
        requestToken += 1
        let token = requestToken
        isLoading = true
        defer {
            if token == requestToken {
                isLoading = false
            }
        }
        do {
            let metadata = try await session.open(url: url)
            let first = try await session.frame(at: 0)
            guard token == requestToken else { return }
            frameCount = metadata.frameCount
            timelineSHA256 = metadata.timelineSHA256
            orientedWidth = metadata.orientedWidth
            orientedHeight = metadata.orientedHeight
            currentFrame = first
        } catch {
            guard token == requestToken else { return }
            errorMessage = "无法建立原片逐帧时间线：\(error.localizedDescription)"
        }
    }

    func show(index: Int) async -> Bool {
        requestToken += 1
        let token = requestToken
        isLoading = true
        defer {
            if token == requestToken {
                isLoading = false
            }
        }
        do {
            let frame = try await session.frame(at: index)
            guard token == requestToken else { return false }
            currentFrame = frame
            return true
        } catch {
            guard token == requestToken else { return false }
            errorMessage = "无法读取源帧 \(index + 1)"
            return false
        }
    }

    func nearestSourceFrameIndex(at time: Double) async -> Int? {
        await session.nearestSourceFrameIndex(at: time)
    }
}

struct AnnotationWorkspaceView: View {
    let videoURL: URL
    let prediction: AnnotationPredictionSnapshot
    let onClose: () -> Void
    let onExport: (URL) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var frameController = AnnotationFrameController()
    @State private var state = AnnotationWorkspaceState.empty
    @State private var package: AnnotationPackage?
    @State private var mediaSHA256 = ""
    @State private var isPreparing = true
    @State private var workspaceError: String?
    @State private var saveTask: Task<Void, Never>?

    @State private var selectedAnnotatorID = "annotator-a"
    @State private var reviewerID = "reviewer"
    @State private var golferID = "golfer-local"
    @State private var selectedView = AnnotationView.downTheLine
    @State private var selectedHandedness = AnnotationHandedness.right
    @State private var selectedAuthorization =
        AnnotationAuthorization.internalReview
    @State private var selectedSplit = AnnotationSplit.development

    @State private var selectedStage = "P1"
    @State private var selectedLandmark = "clubhead"
    @State private var landmarkCategory = AnnotationLandmarkCategory.golf
    @State private var selectedVisibility = AnnotationVisibility.visible
    @State private var selectedAdjudicationStage: String?

    private var store: AnnotationStore { AnnotationStore() }

    var body: some View {
        NavigationStack {
            Group {
                if isPreparing {
                    preparationView
                } else if horizontalSizeClass == .regular {
                    HStack(spacing: 0) {
                        videoPane
                        Divider().overlay(AnalysisTheme.proTourRaisedSurface)
                        editorPane
                            .frame(width: 360)
                    }
                } else {
                    VStack(spacing: 0) {
                        videoPane
                        Divider().overlay(AnalysisTheme.proTourRaisedSurface)
                        editorPane
                            .frame(maxHeight: 330)
                    }
                }
            }
            .background(AnalysisTheme.proTourBackground.ignoresSafeArea())
            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        persistNow()
                        onClose()
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(
                            AnnotationStepPresentation.title(for: state.step)
                        )
                        .font(.headline)
                        Text("真值标注")
                            .font(.caption2)
                            .foregroundStyle(
                                AnalysisTheme.proTourSecondaryText
                            )
                    }
                }
            }
            .toolbarBackground(
                AnalysisTheme.proTourBackground,
                for: .navigationBar
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            await initializeWorkspace()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                persistNow()
            }
        }
        .alert(
            "标注无法继续",
            isPresented: Binding(
                get: { workspaceError != nil },
                set: { if !$0 { workspaceError = nil } }
            )
        ) {
            Button("好") { workspaceError = nil }
        } message: {
            Text(workspaceError ?? "")
        }
    }

    private var preparationView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(AnalysisTheme.proTourSignal)
            Text("正在核对原片与真实源帧")
                .font(.headline)
            Text("视频不会上传")
                .font(.caption)
                .foregroundStyle(AnalysisTheme.proTourSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var videoPane: some View {
        VStack(spacing: 0) {
            AnnotationFrameCanvas(
                image: frameController.currentFrame?.image,
                points: activePoints,
                selectedLandmark: state.activePass == nil
                    ? nil
                    : selectedLandmark,
                onMovePoint: setPoint
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                Text(
                    "帧 \(state.currentSourceFrameIndex + 1) / " +
                        "\(frameController.frameCount)"
                )
                .monospacedDigit()
                Spacer()
                Text(
                    frameController.currentFrame?.presentationTime.seconds
                        .formatted(
                            .number.precision(.fractionLength(3))
                        ) ?? "0.000"
                )
                .monospacedDigit()
                Text("秒")
                    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .frame(height: 32)

            HStack(spacing: 10) {
                frameStepButton(-5, title: "−5")
                frameStepButton(-1, title: "−1")
                frameStepButton(1, title: "+1")
                frameStepButton(5, title: "+5")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .overlay(alignment: .topTrailing) {
            if frameController.isLoading {
                ProgressView()
                    .tint(AnalysisTheme.proTourSignal)
                    .padding(12)
            }
        }
    }

    private var editorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusHeader
                switch state.step {
                case .setup:
                    setupControls
                case .stages:
                    stageControls
                case .landmarks:
                    landmarkControls
                case .adjudication:
                    adjudicationControls
                case .export:
                    exportControls
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .background(AnalysisTheme.proTourSurface)
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(
                    package?.frozenAt == nil
                        ? AnalysisTheme.proTourSignal
                        : AnalysisTheme.proTourSecondaryText
                )
                .frame(width: 8, height: 8)
            Text(package?.frozenAt == nil ? "可编辑" : "已冻结")
                .font(.caption.weight(.semibold))
            Spacer()
            Text(videoURL.lastPathComponent)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(AnalysisTheme.proTourSecondaryText)
        }
    }

    private var setupControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if package == nil {
                metadataControls
            } else if let package {
                metadataSummary(package.metadata)
            }

            Text("标注者")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AnalysisTheme.proTourSecondaryText)

            Picker("标注者", selection: $selectedAnnotatorID) {
                Text("标注者 A").tag("annotator-a")
                Text("标注者 B").tag("annotator-b")
            }
            .pickerStyle(.segmented)

            if let active = state.activePass {
                Text(
                    "\(displayAnnotator(active.annotatorID)) · " +
                        "修订 \(active.revision) 尚未提交"
                )
                .font(.callout)
                primaryButton("继续当前标注") {
                    state.step = .stages
                }
            } else {
                let submitted = state.submittedPasses.first {
                    $0.annotatorID == selectedAnnotatorID
                }
                primaryButton(
                    submitted == nil ? "开始独立标注" : "创建新修订"
                ) {
                    beginSelectedPass(existing: submitted != nil)
                }
                .disabled(package?.frozenAt != nil)
            }

            submittedPassSummary

            if state.submittedPasses.count >= 2 {
                secondaryButton("比较并裁定") {
                    state.step = .adjudication
                    selectFirstAdjudication()
                }
            }
        }
    }

    private var metadataControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("球员编号", text: $golferID)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(
                    AnalysisTheme.proTourRaisedSurface,
                    in: RoundedRectangle(cornerRadius: 10)
                )

            menuPicker("机位", selection: $selectedView) {
                Text("正后方 DTL").tag(AnnotationView.downTheLine)
                Text("正面 Face-on").tag(AnnotationView.faceOn)
            }
            menuPicker("惯用手", selection: $selectedHandedness) {
                Text("右手").tag(AnnotationHandedness.right)
                Text("左手").tag(AnnotationHandedness.left)
            }
            menuPicker("用途授权", selection: $selectedAuthorization) {
                Text("仅内部复核")
                    .tag(AnnotationAuthorization.internalReview)
                Text("允许训练")
                    .tag(AnnotationAuthorization.trainingAllowed)
            }
            menuPicker("数据分组", selection: $selectedSplit) {
                ForEach(AnnotationSplit.allCases, id: \.rawValue) {
                    Text(splitLabel($0)).tag($0)
                }
            }
        }
    }

    private var submittedPassSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(["annotator-a", "annotator-b"], id: \.self) { id in
                let pass = state.submittedPasses.first {
                    $0.annotatorID == id
                }
                HStack {
                    Image(
                        systemName: pass == nil
                            ? "circle"
                            : "checkmark.circle.fill"
                    )
                    .foregroundStyle(
                        pass == nil
                            ? AnalysisTheme.proTourSecondaryText
                            : AnalysisTheme.proTourSignal
                    )
                    Text(displayAnnotator(id))
                    Spacer()
                    Text(pass.map { "修订 \($0.revision)" } ?? "未提交")
                        .font(.caption)
                        .foregroundStyle(
                            AnalysisTheme.proTourSecondaryText
                        )
                }
            }
        }
    }

    private var stageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(
                        AnnotationPackageValidator.stageCodes,
                        id: \.self
                    ) { stage in
                        Button(stage) {
                            selectedStage = stage
                            jumpToStageSuggestion(stage)
                        }
                        .buttonStyle(.plain)
                        .font(.callout.monospaced().weight(.bold))
                        .foregroundStyle(
                            selectedStage == stage
                                ? AnalysisTheme.proTourBackground
                                : AnalysisTheme.proTourPrimaryText
                        )
                        .frame(width: 48, height: 44)
                        .background(
                            selectedStage == stage
                                ? AnalysisTheme.proTourSignal
                                : AnalysisTheme.proTourRaisedSurface,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .accessibilityLabel(stage)
                    }
                }
            }
            .scrollIndicators(.hidden)

            stageEvidenceSummary

            primaryButton("当前帧设为 \(selectedStage)") {
                reduce(.setStage(
                    stage: selectedStage,
                    sourceFrameIndex: state.currentSourceFrameIndex
                ))
            }
            secondaryButton("标记为无法确定") {
                reduce(.setStage(
                    stage: selectedStage,
                    sourceFrameIndex: nil
                ))
            }
            secondaryButton("下一步：关键点") {
                state.step = .landmarks
                moveToFirstQueueFrame()
            }
        }
    }

    private var stageEvidenceSummary: some View {
        let manual = state.activePass?.stages.first {
            $0.stage == selectedStage
        }
        let suggested = state.prediction.stages.first {
            $0.stage == selectedStage
        }
        return VStack(alignment: .leading, spacing: 5) {
            Text(
                manual?.sourceFrameIndex.map {
                    "人工帧 \($0 + 1)"
                } ?? "尚未人工确定"
            )
            .font(.headline)
            if let candidate = suggested?.suggestedSourceFrameIndex
                ?? suggested?.sourceFrameIndex {
                Text("Vision/球杆建议：帧 \(candidate + 1)")
                    .font(.caption)
                    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            }
            if let note = suggested?.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            AnalysisTheme.proTourRaisedSurface,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var landmarkControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("关键点类别", selection: $landmarkCategory) {
                Text("人体").tag(AnnotationLandmarkCategory.body)
                Text("球杆").tag(AnnotationLandmarkCategory.golf)
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(activeLandmarkCatalog, id: \.self) { landmark in
                        Button(landmarkLabel(landmark)) {
                            selectedLandmark = landmark
                            syncVisibilityFromSelectedPoint()
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            selectedLandmark == landmark
                                ? AnalysisTheme.proTourBackground
                                : AnalysisTheme.proTourPrimaryText
                        )
                        .padding(.horizontal, 11)
                        .frame(height: 44)
                        .background(
                            selectedLandmark == landmark
                                ? AnalysisTheme.proTourSignal
                                : AnalysisTheme.proTourRaisedSurface,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)

            Picker("可见性", selection: $selectedVisibility) {
                ForEach(AnnotationVisibility.allCases, id: \.rawValue) {
                    Text(visibilityLabel($0)).tag($0)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedVisibility) { _, value in
                setSelectedVisibility(value)
            }

            HStack(spacing: 10) {
                secondaryButton("上一队列帧") {
                    moveWithinQueue(delta: -1)
                }
                secondaryButton("下一队列帧") {
                    moveWithinQueue(delta: 1)
                }
            }

            HStack(spacing: 10) {
                secondaryButton("添加当前帧") {
                    reduce(.addFrameToQueue(state.currentSourceFrameIndex))
                }
                secondaryButton("移除当前帧") {
                    reduce(.removeFrameFromQueue(
                        state.currentSourceFrameIndex
                    ))
                }
                .disabled(
                    state.protectedFrameIndices.contains(
                        state.currentSourceFrameIndex
                    )
                )
            }

            TextField("复核者", text: $reviewerID)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(
                    AnalysisTheme.proTourRaisedSurface,
                    in: RoundedRectangle(cornerRadius: 10)
                )

            primaryButton("复核本帧") {
                guard !reviewerID.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty else {
                    workspaceError = "请输入复核者编号"
                    return
                }
                reduce(.reviewFrame(
                    sourceFrameIndex: state.currentSourceFrameIndex,
                    reviewerID: reviewerID
                ))
            }

            secondaryButton("返回 P1–P8") {
                state.step = .stages
            }

            primaryButton("提交当前标注者") {
                reduce(.submitActivePass)
                if state.submittedPasses.count >= 2 {
                    selectFirstAdjudication()
                }
            }
        }
    }

    private var adjudicationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.adjudicationQueue.isEmpty {
                Label("没有待裁定分歧", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AnalysisTheme.proTourSignal)
                primaryButton("进入冻结与导出") {
                    state.step = .export
                }
            } else {
                Picker(
                    "待裁定阶段",
                    selection: Binding(
                        get: {
                            selectedAdjudicationStage
                                ?? state.adjudicationQueue.first
                                ?? "P1"
                        },
                        set: {
                            selectedAdjudicationStage = $0
                            jumpToFirstOriginal(stage: $0)
                        }
                    )
                ) {
                    ForEach(state.adjudicationQueue, id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .pickerStyle(.segmented)

                adjudicationOriginals

                primaryButton("采用当前帧") {
                    adjudicateCurrentFrame()
                }
                secondaryButton("仍无法确定") {
                    adjudicateUnresolved()
                }
            }

            secondaryButton("返回任务资料") {
                state.step = .setup
            }
        }
    }

    private var adjudicationOriginals: some View {
        let stage = selectedAdjudicationStage
            ?? state.adjudicationQueue.first
            ?? "P1"
        let originals = state.visibleComparison(for: stage) ?? []
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(stage) 原始选择")
                .font(.headline)
            ForEach(Array(originals.enumerated()), id: \.offset) { index, item in
                Button {
                    if let frame = item.sourceFrameIndex {
                        loadFrame(frame)
                    }
                } label: {
                    HStack {
                        Text(index == 0 ? "标注者 A" : "标注者 B")
                        Spacer()
                        Text(
                            item.sourceFrameIndex.map {
                                "帧 \($0 + 1)"
                            } ?? "无法确定"
                        )
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            AnalysisTheme.proTourRaisedSurface,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var exportControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let package {
                metadataSummary(package.metadata)
                let validation = validationErrorsForExport(package)
                if validation.isEmpty {
                    Label(
                        "授权、双人标注和关键点复核均已通过",
                        systemImage: "checkmark.shield.fill"
                    )
                    .foregroundStyle(AnalysisTheme.proTourSignal)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("尚不能导出训练数据")
                            .font(.headline)
                        ForEach(
                            Array(validation.enumerated()),
                            id: \.offset
                        ) { _, error in
                            Text("• \(validationMessage(error))")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                }

                primaryButton("冻结并导出 JSON") {
                    freezeAndExport()
                }
                .disabled(!validation.isEmpty || package.frozenAt != nil)
            }

            secondaryButton("返回分歧裁定") {
                state.step = .adjudication
                selectFirstAdjudication()
            }
        }
    }

    private var activePoints: [String: AnnotationPoint] {
        state.activePass?.frameLabels.first {
            $0.sourceFrameIndex == state.currentSourceFrameIndex
        }?.landmarks ?? state.prediction.frameLabels.first {
            $0.sourceFrameIndex == state.currentSourceFrameIndex
        }?.landmarks ?? [:]
    }

    private var activeLandmarkCatalog: [String] {
        landmarkCategory == .body
            ? AnnotationLandmarkCatalog.body
            : AnnotationLandmarkCatalog.golf
    }

    private func frameStepButton(
        _ delta: Int,
        title: String
    ) -> some View {
        Button(title) {
            let target = AnnotationFrameStepPolicy.target(
                current: state.currentSourceFrameIndex,
                delta: delta,
                frameCount: frameController.frameCount
            )
            loadFrame(target)
        }
        .buttonStyle(.plain)
        .font(.headline.monospaced())
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            AnalysisTheme.proTourRaisedSurface,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .accessibilityLabel("移动 \(title) 帧")
    }

    private func primaryButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AnalysisTheme.proTourBackground)
        .background(
            AnalysisTheme.proTourSignal,
            in: RoundedRectangle(cornerRadius: 11)
        )
        .accessibilityLabel(title)
    }

    private func secondaryButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
        .background(
            AnalysisTheme.proTourRaisedSurface,
            in: RoundedRectangle(cornerRadius: 11)
        )
        .accessibilityLabel(title)
    }

    private func menuPicker<Value, Content>(
        _ title: String,
        selection: Binding<Value>,
        @ViewBuilder content: () -> Content
    ) -> some View where Value: Hashable, Content: View {
        HStack {
            Text(title)
                .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            Spacer()
            Picker(title, selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
        }
        .frame(minHeight: 44)
    }

    private func metadataSummary(
        _ metadata: AnnotationClipMetadata
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metadata.clipID)
                .font(.caption.monospaced())
                .lineLimit(1)
            Text(
                "\(viewLabel(metadata.view)) · " +
                    "\(handednessLabel(metadata.handedness)) · " +
                    "\(authorizationLabel(metadata.authorization)) · " +
                    splitLabel(metadata.split)
            )
            .font(.caption)
            .foregroundStyle(AnalysisTheme.proTourSecondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AnalysisTheme.proTourRaisedSurface,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func initializeWorkspace() async {
        isPreparing = true
        state.prediction = prediction
        let hashTask = Task.detached(priority: .utility) {
            try AnnotationStore.mediaSHA256(url: videoURL)
        }
        await frameController.open(url: videoURL)
        do {
            mediaSHA256 = try await hashTask.value
            if let frameError = frameController.errorMessage {
                throw AnnotationWorkspaceLoadError.message(frameError)
            }
            if let existing = try store.load(mediaSHA256: mediaSHA256) {
                guard existing.media.timelineSHA256
                    == frameController.timelineSHA256 else {
                    throw AnnotationWorkspaceLoadError.message(
                        "标注包与当前原片时间线不一致"
                    )
                }
                package = existing
                restore(existing)
            } else {
                rebuildQueueFromPrediction()
            }
        } catch {
            workspaceError = error.localizedDescription
        }
        isPreparing = false
    }

    private func ensurePackage() -> Bool {
        if package != nil { return true }
        guard !mediaSHA256.isEmpty,
              !frameController.timelineSHA256.isEmpty,
              frameController.frameCount > 0 else {
            workspaceError = "原片身份尚未准备完成"
            return false
        }
        let trimmedGolferID = golferID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedGolferID.isEmpty else {
            workspaceError = "请输入球员编号"
            return false
        }
        if selectedSplit != .development,
           selectedAuthorization != .trainingAllowed {
            workspaceError = "训练、验证或留出数据必须取得训练授权"
            return false
        }
        let metadata = AnnotationClipMetadata(
            clipID: String(mediaSHA256.prefix(16)),
            golferID: trimmedGolferID,
            view: selectedView,
            handedness: selectedHandedness,
            authorization: selectedAuthorization,
            split: selectedSplit
        )
        package = AnnotationPackage(
            schemaVersion: 1,
            stageSystem: "p-system-v1",
            media: AnnotationMediaIdentity(
                fileName: videoURL.lastPathComponent,
                sha256: mediaSHA256,
                timelineSHA256: frameController.timelineSHA256,
                frameCount: frameController.frameCount,
                width: frameController.orientedWidth,
                height: frameController.orientedHeight
            ),
            metadata: metadata,
            frameQueue: state.frameQueue,
            passes: [],
            adjudications: [],
            frozenAt: nil
        )
        persistNow()
        return true
    }

    private func beginSelectedPass(existing: Bool) {
        guard ensurePackage() else { return }
        reduce(
            existing
                ? .beginRevision(annotatorID: selectedAnnotatorID)
                : .beginPass(annotatorID: selectedAnnotatorID)
        )
    }

    private func reduce(_ action: AnnotationWorkflowAction) {
        AnnotationWorkflowReducer.reduce(state: &state, action: action)
        refreshProtectedFrames()
        scheduleSave()
    }

    private func setPoint(
        _ landmark: String,
        _ point: AnnotationPoint
    ) {
        guard state.activePass != nil else { return }
        reduce(.setPoint(
            landmark: landmark,
            sourceFrameIndex: state.currentSourceFrameIndex,
            point: point
        ))
        selectedVisibility = point.visibility
    }

    private func setSelectedVisibility(_ visibility: AnnotationVisibility) {
        guard state.activePass != nil else { return }
        var point = activePoints[selectedLandmark] ?? AnnotationPoint(
            x: nil,
            y: nil,
            visibility: visibility,
            source: .manual,
            confidence: nil
        )
        point.visibility = visibility
        point.source = .manual
        if visibility != .visible {
            point.x = nil
            point.y = nil
        }
        setPoint(selectedLandmark, point)
    }

    private func syncVisibilityFromSelectedPoint() {
        selectedVisibility = activePoints[selectedLandmark]?.visibility
            ?? .unresolved
    }

    private func jumpToStageSuggestion(_ stage: String) {
        let manual = state.activePass?.stages.first {
            $0.stage == stage
        }?.sourceFrameIndex
        let predicted = state.prediction.stages.first {
            $0.stage == stage
        }
        if let target = manual
            ?? predicted?.sourceFrameIndex
            ?? predicted?.suggestedSourceFrameIndex {
            loadFrame(target)
        }
    }

    private func loadFrame(_ index: Int) {
        let target = AnnotationFrameStepPolicy.target(
            current: index,
            delta: 0,
            frameCount: frameController.frameCount
        )
        Task {
            if await frameController.show(index: target) {
                state.currentSourceFrameIndex = target
                scheduleSave()
            } else {
                workspaceError = frameController.errorMessage
            }
        }
    }

    private func rebuildQueueFromPrediction() {
        let stagePairs: [(String, Int)] = state.prediction.stages.compactMap {
            selection -> (String, Int)? in
                guard let frame = selection.sourceFrameIndex
                    ?? selection.suggestedSourceFrameIndex else {
                    return nil
                }
                return (selection.stage, frame)
            }
        let stageFrames = Dictionary(uniqueKeysWithValues: stagePairs)
        let flagged = Set(
            state.prediction.frameLabels.compactMap { label in
                let golfPoints = AnnotationLandmarkCatalog.golf.compactMap {
                    label.landmarks[$0]
                }
                return golfPoints.contains(where: {
                    $0.visibility != .visible
                }) ? label.sourceFrameIndex : nil
            }
        )
        let queue = AnnotationFrameQueueBuilder.build(
            stageFrames: stageFrames,
            flaggedFrames: flagged,
            userAddedFrames: [],
            protectedFrames: [],
            frameCount: frameController.frameCount,
            policy: .v1
        )
        reduce(.replaceFrameQueue(queue, protectedFrames: []))
    }

    private func moveToFirstQueueFrame() {
        if state.frameQueue.isEmpty {
            rebuildQueueFromPrediction()
        }
        if let first = state.frameQueue.first {
            loadFrame(first)
        }
    }

    private func moveWithinQueue(delta: Int) {
        let queue = state.frameQueue
        guard !queue.isEmpty else { return }
        let current = queue.firstIndex(
            of: state.currentSourceFrameIndex
        ) ?? 0
        let targetIndex = min(
            queue.count - 1,
            max(0, current + delta)
        )
        loadFrame(queue[targetIndex])
    }

    private func selectFirstAdjudication() {
        state.step = state.adjudicationQueue.isEmpty
            ? .export
            : .adjudication
        selectedAdjudicationStage = state.adjudicationQueue.first
        if let stage = selectedAdjudicationStage {
            jumpToFirstOriginal(stage: stage)
        }
    }

    private func jumpToFirstOriginal(stage: String) {
        if let frame = state.visibleComparison(for: stage)?
            .compactMap(\.sourceFrameIndex).first {
            loadFrame(frame)
        }
    }

    private func adjudicateCurrentFrame() {
        let stage = selectedAdjudicationStage
            ?? state.adjudicationQueue.first
        guard let stage else { return }
        reduce(.adjudicate(
            stage: stage,
            sourceFrameIndex: state.currentSourceFrameIndex,
            adjudicatorID: reviewerID,
            note: "逐帧人工裁定"
        ))
        selectFirstAdjudication()
    }

    private func adjudicateUnresolved() {
        let stage = selectedAdjudicationStage
            ?? state.adjudicationQueue.first
        guard let stage else { return }
        reduce(.adjudicate(
            stage: stage,
            sourceFrameIndex: nil,
            adjudicatorID: reviewerID,
            note: "逐帧复核后仍无法确定"
        ))
        selectFirstAdjudication()
    }

    private func validationErrorsForExport(
        _ source: AnnotationPackage
    ) -> [AnnotationValidationError] {
        var candidate = synchronized(source)
        candidate.frozenAt = Date()
        return AnnotationPackageValidator.validate(candidate)
    }

    private func freezeAndExport() {
        guard var candidate = package else { return }
        candidate = synchronized(candidate)
        let exports = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "SwingArcAnnotationExports",
            isDirectory: true
        )
        do {
            let receipt = try AnnotationExportService.freezeAndExport(
                package: &candidate,
                destinationDirectory: exports,
                now: Date()
            )
            package = candidate
            try store.save(
                candidate,
                expectedMediaSHA256: mediaSHA256
            )
            onExport(receipt.url)
        } catch AnnotationExportError.validationFailed(let errors) {
            workspaceError = errors
                .map(validationMessage)
                .joined(separator: "\n")
        } catch {
            workspaceError = "导出失败：\(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        guard package != nil else { return }
        synchronizePackage()
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            persistNow()
        }
    }

    private func persistNow() {
        saveTask?.cancel()
        synchronizePackage()
        guard let package else { return }
        do {
            try store.save(
                package,
                expectedMediaSHA256: mediaSHA256.isEmpty
                    ? nil
                    : mediaSHA256
            )
        } catch {
            workspaceError = "标注保存失败：\(error.localizedDescription)"
        }
    }

    private func synchronizePackage() {
        guard let current = package else { return }
        package = synchronized(current)
    }

    private func synchronized(
        _ source: AnnotationPackage
    ) -> AnnotationPackage {
        var copy = source
        copy.activeDraft = state.activePass
        copy.currentSourceFrameIndex = state.currentSourceFrameIndex
        copy.frameQueue = state.frameQueue
        copy.passes = state.submittedPasses
        copy.archivedPassRevisions = state.archivedPassRevisions
        copy.adjudications = state.adjudications
        return copy
    }

    private func restore(_ source: AnnotationPackage) {
        selectedView = source.metadata.view
        selectedHandedness = source.metadata.handedness
        selectedAuthorization = source.metadata.authorization
        selectedSplit = source.metadata.split
        golferID = source.metadata.golferID
        state = AnnotationWorkspaceState(
            step: source.activeDraft == nil ? .setup : .stages,
            currentSourceFrameIndex: source.currentSourceFrameIndex,
            activePass: source.activeDraft,
            submittedPasses: source.passes,
            archivedPassRevisions: source.archivedPassRevisions,
            adjudications: source.adjudications,
            frameQueue: source.frameQueue,
            protectedFrameIndices: [],
            prediction: prediction
        )
        refreshProtectedFrames()
        loadFrame(source.currentSourceFrameIndex)
    }

    private func refreshProtectedFrames() {
        let submitted = state.submittedPasses.flatMap {
            $0.stages.compactMap(\.sourceFrameIndex)
                + $0.frameLabels.map(\.sourceFrameIndex)
        }
        let adjudicated = state.adjudications.compactMap(
            \.sourceFrameIndex
        )
        state.protectedFrameIndices = Set(submitted + adjudicated)
    }

    private func validationMessage(
        _ error: AnnotationValidationError
    ) -> String {
        switch error {
        case .unsupportedSchema: return "标注格式版本不支持"
        case .invalidStageSystem: return "P-System 版本不正确"
        case .invalidMediaIdentity: return "原片身份不完整"
        case .invalidSubmittedPassCount: return "需要 A/B 两个已提交会话"
        case .duplicateAnnotator: return "A/B 必须是两个独立通道"
        case .invalidStageSet: return "P1–P8 阶段不完整"
        case .invalidStageOrder: return "P1–P8 帧顺序错误"
        case .trainingWithoutAuthorization: return "没有训练用途授权"
        case .missingReviewedFrames: return "每位标注者至少复核一个关键点帧"
        case .unreviewedTrainingFrame: return "存在未复核关键点帧"
        case .unresolvedTrainingStage: return "训练数据仍有无法确定的 P 点"
        case .activeDraftPresent: return "仍有未提交的活动草稿"
        case .invalidFrameQueue: return "标注帧队列无效"
        case .missingAdjudication: return "存在尚未裁定的阶段"
        case .incompleteAdjudication: return "裁定缺少两个原始选择"
        }
    }

    private func viewLabel(_ value: AnnotationView) -> String {
        value == .downTheLine ? "DTL" : "Face-on"
    }

    private func handednessLabel(
        _ value: AnnotationHandedness
    ) -> String {
        value == .right ? "右手" : "左手"
    }

    private func authorizationLabel(
        _ value: AnnotationAuthorization
    ) -> String {
        value == .trainingAllowed ? "允许训练" : "仅内部复核"
    }

    private func splitLabel(_ value: AnnotationSplit) -> String {
        switch value {
        case .development: return "开发"
        case .training: return "训练"
        case .validation: return "验证"
        case .heldOut: return "留出"
        }
    }

    private func visibilityLabel(
        _ value: AnnotationVisibility
    ) -> String {
        switch value {
        case .visible: return "可见"
        case .occluded: return "遮挡"
        case .outOfFrame: return "出画"
        case .unresolved: return "无法确定"
        }
    }

    private func displayAnnotator(_ id: String) -> String {
        id == "annotator-a" ? "标注者 A" : "标注者 B"
    }

    private func landmarkLabel(_ value: String) -> String {
        let labels: [String: String] = [
            "head": "头",
            "leftShoulder": "左肩",
            "rightShoulder": "右肩",
            "leftElbow": "左肘",
            "rightElbow": "右肘",
            "leftWrist": "左腕",
            "rightWrist": "右腕",
            "handCenter": "双手",
            "leftHip": "左髋",
            "rightHip": "右髋",
            "leftKnee": "左膝",
            "rightKnee": "右膝",
            "leftAnkle": "左踝",
            "rightAnkle": "右踝",
            "grip": "握把",
            "shaftStart": "杆身起点",
            "shaftEnd": "杆身末端",
            "clubhead": "杆头",
            "ball": "球"
        ]
        return labels[value] ?? value
    }
}

private enum AnnotationLandmarkCategory: String {
    case body
    case golf
}

private enum AnnotationWorkspaceLoadError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}

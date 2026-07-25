import SwiftUI
import UniformTypeIdentifiers

struct DatasetImportSheet: View {
    let store: GolfDatasetStore
    let onImported: (DatasetImportReceipt) -> Void

    @State private var state = DatasetImportState.empty
    @State private var clipID = ""
    @State private var golferID = ""
    @State private var proposedSplit = GolfDatasetSplit.training
    @State private var videoURL: URL?
    @State private var pPointTruthURL: URL?
    @State private var showsVideoPicker = false
    @State private var showsTruthPicker = false
    @State private var isVerifying = false
    @State private var status = "正在读取数据集注册表…"

    init(
        store: GolfDatasetStore,
        onImported: @escaping (DatasetImportReceipt) -> Void = { _ in }
    ) {
        self.store = store
        self.onImported = onImported
    }

    var body: some View {
        Form {
            Section("1. 数据集与匿名球员") {
                HStack {
                    TextField("匿名 golferID", text: $golferID)
                        .onChange(of: golferID) { _, value in
                            state = DatasetImportReducer.reduce(
                                state,
                                .assignGolfer(value)
                            )
                        }
                    Picker("首次锁定拆分", selection: $proposedSplit) {
                        ForEach(GolfDatasetSplit.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Button("锁定新球员") {
                        state = DatasetImportReducer.reduce(
                            state,
                            .registerGolfer(
                                golferID: golferID,
                                split: proposedSplit,
                                at: Date()
                            )
                        )
                    }
                    .disabled(golferID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let split = state.split {
                    LabeledContent("已锁定拆分", value: split.rawValue)
                }
                Text("同一 golferID 的拆分一旦锁定，不允许覆盖。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("2. 视频与 P1–P8 真值") {
                fileRow(
                    title: "原始视频",
                    url: videoURL,
                    buttonTitle: "选择视频"
                ) { showsVideoPicker = true }
                fileRow(
                    title: "P 点真值 JSON",
                    url: pPointTruthURL,
                    buttonTitle: "选择真值"
                ) { showsTruthPicker = true }
                Button(isVerifying ? "正在核验…" : "核验媒体与源帧时间线") {
                    verifySelection()
                }
                .disabled(videoURL == nil || pPointTruthURL == nil || isVerifying)
            }

            Section("3. 片段身份") {
                TextField("clipID", text: $clipID)
                Picker("机位", selection: viewBinding) {
                    Text("请选择").tag(GolfDatasetView?.none)
                    Text("DTL").tag(GolfDatasetView?.some(.downTheLine))
                    Text("Face-on").tag(GolfDatasetView?.some(.faceOn))
                }
                Picker("持杆", selection: handednessBinding) {
                    Text("请选择").tag(GolfDatasetHandedness?.none)
                    Text("右手").tag(GolfDatasetHandedness?.some(.right))
                    Text("左手").tag(GolfDatasetHandedness?.some(.left))
                }
                Picker("授权", selection: authorizationBinding) {
                    Text("请选择").tag(GolfDatasetAuthorization?.none)
                    Text("允许训练").tag(GolfDatasetAuthorization?.some(.trainingAllowed))
                    Text("仅内部复核").tag(GolfDatasetAuthorization?.some(.internalReview))
                }
            }

            Section {
                Button("导入到本地数据集") {
                    importClip()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!state.canImport || clipID.isEmpty)
                Text(status)
                    .font(.callout)
                    .foregroundStyle(statusColor)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { loadRegistry() }
        .fileImporter(
            isPresented: $showsVideoPicker,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            videoURL = try? result.get().first
            state = DatasetImportReducer.reduce(state, .resetMedia)
        }
        .fileImporter(
            isPresented: $showsTruthPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            pPointTruthURL = try? result.get().first
            state = DatasetImportReducer.reduce(state, .resetMedia)
        }
    }

    private var viewBinding: Binding<GolfDatasetView?> {
        Binding(
            get: { state.view },
            set: { value in
                guard let value else { return }
                state = DatasetImportReducer.reduce(state, .setView(value))
            }
        )
    }

    private var handednessBinding: Binding<GolfDatasetHandedness?> {
        Binding(
            get: { state.handedness },
            set: { value in
                guard let value else { return }
                state = DatasetImportReducer.reduce(state, .setHandedness(value))
            }
        )
    }

    private var authorizationBinding: Binding<GolfDatasetAuthorization?> {
        Binding(
            get: { state.authorization },
            set: { value in
                guard let value else { return }
                state = DatasetImportReducer.reduce(state, .setAuthorization(value))
            }
        )
    }

    private var statusColor: Color {
        state.issue == nil ? .secondary : .red
    }

    @ViewBuilder
    private func fileRow(
        title: String,
        url: URL?,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text(url?.lastPathComponent ?? "尚未选择")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(buttonTitle, action: action)
        }
    }

    private func loadRegistry() {
        do {
            state = try DatasetImportController.initialState(store: store)
            status = "注册表已加载。请选择或首次锁定匿名 golferID。"
        } catch DatasetImportControllerError.missingRegistry {
            let registry = GolferRegistry(datasetID: "swingarc-golf-keypoints-v1")
            do {
                try store.saveRegistry(registry)
                state = DatasetImportReducer.reduce(.empty, .loadRegistry(registry))
                status = "已创建本地注册表。请锁定第一个匿名 golferID。"
            } catch {
                status = error.localizedDescription
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func verifySelection() {
        guard let videoURL, let pPointTruthURL else { return }
        isVerifying = true
        status = "正在计算媒体哈希并打开精确源帧时间线…"
        Task {
            let videoAccess = videoURL.startAccessingSecurityScopedResource()
            let truthAccess = pPointTruthURL.startAccessingSecurityScopedResource()
            defer {
                if videoAccess { videoURL.stopAccessingSecurityScopedResource() }
                if truthAccess { pPointTruthURL.stopAccessingSecurityScopedResource() }
            }
            do {
                let verified = try await DatasetImportController.verify(
                    videoURL: videoURL,
                    pPointTruthURL: pPointTruthURL
                )
                state = DatasetImportReducer.reduce(
                    state,
                    .mediaVerified(
                        media: verified.media,
                        securityScopedBookmark: verified.bookmark
                    )
                )
                status = "媒体哈希、时间线和 P1–P8 真值已匹配。"
            } catch {
                state = DatasetImportReducer.reduce(state, .resetMedia)
                status = error.localizedDescription
            }
            isVerifying = false
        }
    }

    private func importClip() {
        do {
            let receipt = try DatasetImportController.importClip(
                state: state,
                clipID: clipID,
                store: store
            )
            status = "已导入 \(receipt.clip.clipID)，拆分：\(receipt.split.rawValue)。"
            onImported(receipt)
        } catch {
            status = error.localizedDescription
        }
    }
}

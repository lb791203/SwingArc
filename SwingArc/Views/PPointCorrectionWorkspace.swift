import CoreMedia
import SwiftUI

struct PPointCorrectionWorkspace: View {
    let videoURL: URL
    let prediction: AnnotationPredictionSnapshot
    let manualMarkers: [KeyframeMarker]
    let initialTime: Double
    let onClose: () -> Void
    let onSave: (PPointCode, Int, Double) -> Void

    @StateObject private var frameController = AnnotationFrameController()
    @State private var correctionState: PPointCorrectionState?
    @State private var preparationError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let state = correctionState {
                    correctionContent(state)
                } else {
                    preparationView
                }
            }
            .background(AnalysisTheme.proTourBackground.ignoresSafeArea())
            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", action: onClose)
                        .accessibilityLabel("关闭 P 点修正")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("P 点修正")
                            .font(.headline)
                        Text("当前视频")
                            .font(.caption2)
                            .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                    }
                }
            }
            .toolbarBackground(
                AnalysisTheme.proTourBackground,
                for: .navigationBar
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task(id: videoURL) {
            await prepare()
        }
        .alert(
            "无法修正 P 点",
            isPresented: Binding(
                get: { preparationError != nil },
                set: { if !$0 { preparationError = nil } }
            )
        ) {
            Button("好") { preparationError = nil }
        } message: {
            Text(preparationError ?? "")
        }
        .preferredColorScheme(.dark)
    }

    private var preparationView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(AnalysisTheme.proTourSignal)
            Text("正在建立精确源帧")
                .font(.headline)
            Text("保留自动结果，只修正错误的 P 点")
                .font(.caption)
                .foregroundStyle(AnalysisTheme.proTourSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func correctionContent(_ state: PPointCorrectionState) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            if let image = frameController.currentFrame?.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(AnalysisTheme.proTourSignal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if frameController.isLoading {
                ProgressView()
                    .tint(AnalysisTheme.proTourSignal)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("当前 P 点源帧")
        .overlay(alignment: .top) {
            stageSelector(state)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.78), .black.opacity(0.30), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .padding(.bottom, -24)
                )
        }
        .overlay(alignment: .bottom) {
            correctionControls(state)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.64), .black.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .padding(.top, -34)
                )
        }
    }

    private func stageSelector(_ state: PPointCorrectionState) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PPointCode.allCases) { code in
                    let selection = state.selection(for: code)
                    Button {
                        select(code)
                    } label: {
                        VStack(spacing: 3) {
                            Text(code.rawValue)
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                            Circle()
                                .fill(statusColor(selection.source))
                                .frame(width: 5, height: 5)
                        }
                        .frame(width: 38, height: 42)
                        .foregroundStyle(
                            state.selectedCode == code
                                ? AnalysisTheme.proTourBackground
                                : AnalysisTheme.proTourPrimaryText
                        )
                        .background(
                            state.selectedCode == code
                                ? AnalysisTheme.proTourSignal
                                : AnalysisTheme.proTourSurface,
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(code.rawValue)，\(statusLabel(selection.source))"
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func correctionControls(_ state: PPointCorrectionState) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(
                    "帧 \(state.currentSourceFrameIndex + 1) / " +
                        "\(frameController.frameCount)"
                )
                .monospacedDigit()

                Spacer()

                let selection = state.selection(for: state.selectedCode)
                Label(
                    statusLabel(selection.source),
                    systemImage: selection.source == .manual
                        ? "lock.fill"
                        : "sparkles"
                )
                .foregroundStyle(statusColor(selection.source))
            }
            .font(.caption)

            HStack(spacing: 9) {
                stepButton(-5, title: "−5")
                stepButton(-1, title: "−1")
                stepButton(1, title: "+1")
                stepButton(5, title: "+5")
            }

            Button {
                saveSelectedStage()
            } label: {
                Text("设为 \(state.selectedCode.rawValue)")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(AnalysisTheme.proTourBackground)
                    .background(
                        AnalysisTheme.proTourSignal,
                        in: RoundedRectangle(cornerRadius: 15)
                    )
            }
            .buttonStyle(.plain)
            .disabled(frameController.currentFrame == nil)
            .accessibilityLabel("将当前帧设为 \(state.selectedCode.rawValue)")
        }
        .padding(10)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    private func stepButton(_ amount: Int, title: String) -> some View {
        Button {
            step(amount)
        } label: {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    AnalysisTheme.proTourSurface,
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("移动 \(title) 帧")
    }

    @MainActor
    private func prepare() async {
        await frameController.open(url: videoURL)
        guard frameController.frameCount > 0 else {
            preparationError = frameController.errorMessage ?? "无法读取视频源帧。"
            return
        }

        let predicted: [PPointCode: Int] = Dictionary(
            uniqueKeysWithValues: prediction.stages.compactMap { selection in
                guard let code = PPointCode(rawValue: selection.stage),
                      let frame = selection.sourceFrameIndex else {
                    return nil
                }
                return (code, frame)
            }
        )
        let suggested: [PPointCode: Int] = Dictionary(
            uniqueKeysWithValues: prediction.stages.compactMap { selection in
                guard let code = PPointCode(rawValue: selection.stage),
                      let frame = selection.suggestedSourceFrameIndex else {
                    return nil
                }
                return (code, frame)
            }
        )
        var manual: [PPointCode: Int] = [:]
        for marker in manualMarkers where marker.source == .manual {
            guard let code = Self.code(for: marker.stage),
                  let frame = await frameController.nearestSourceFrameIndex(
                      at: marker.time
                  ) else {
                continue
            }
            manual[code] = frame
        }

        var initial = PPointCorrectionState(
            frameCount: frameController.frameCount,
            predictedFrames: predicted,
            suggestedFrames: suggested,
            manualFrames: manual
        )
        if predicted.isEmpty,
           suggested.isEmpty,
           manual.isEmpty,
           let initialFrame = await frameController.nearestSourceFrameIndex(
               at: initialTime
           ) {
            PPointCorrectionReducer.reduce(
                state: &initial,
                action: .step(initialFrame)
            )
        }
        correctionState = initial
        _ = await frameController.show(
            index: initial.currentSourceFrameIndex
        )
    }

    private func select(_ code: PPointCode) {
        guard var state = correctionState else { return }
        PPointCorrectionReducer.reduce(state: &state, action: .select(code))
        correctionState = state
        show(frame: state.currentSourceFrameIndex)
    }

    private func step(_ amount: Int) {
        guard var state = correctionState else { return }
        PPointCorrectionReducer.reduce(state: &state, action: .step(amount))
        correctionState = state
        show(frame: state.currentSourceFrameIndex)
    }

    private func show(frame: Int) {
        Task {
            _ = await frameController.show(index: frame)
        }
    }

    private func saveSelectedStage() {
        guard var state = correctionState,
              let frame = frameController.currentFrame,
              frame.sourceFrameIndex == state.currentSourceFrameIndex else {
            return
        }
        PPointCorrectionReducer.reduce(
            state: &state,
            action: .setSelectedStage
        )
        correctionState = state
        onSave(
            state.selectedCode,
            state.currentSourceFrameIndex,
            frame.presentationTime.seconds
        )
        onClose()
    }

    private func statusColor(
        _ source: PPointSelectionSource
    ) -> Color {
        switch source {
        case .manual:
            return AnalysisTheme.proTourSignal
        case .automatic:
            return AnalysisTheme.proTourPrimaryText
        case .unresolved:
            return AnalysisTheme.proTourPaused
        }
    }

    private func statusLabel(
        _ source: PPointSelectionSource
    ) -> String {
        switch source {
        case .manual: return "人工修正"
        case .automatic: return "自动识别"
        case .unresolved: return "待修正"
        }
    }

    private static func code(for stageRawValue: String) -> PPointCode? {
        guard let stage = SwingStage(rawValue: stageRawValue),
              let index = SwingStage.pStages.firstIndex(of: stage) else {
            return nil
        }
        return PPointCode.allCases[index]
    }
}

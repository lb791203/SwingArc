import CoreMedia
import SwiftUI

struct PPointCorrectionWorkspace: View {
    let videoURL: URL
    let prediction: AnnotationPredictionSnapshot
    let markers: [KeyframeMarker]
    let initialTime: Double
    /// The stage the user tapped; the workspace opens on it.
    var initialStage: SwingStage? = nil
    let onClose: () -> Void
    let onSave: (PPointCode, Int, Double, CGImage) -> Void

    @StateObject private var frameController = AnnotationFrameController()
    @State private var correctionState: PPointCorrectionState?
    @State private var preparationError: String?
    @State private var scrubFrame: Double = 0
    @State private var savedMessage: String?
    /// Latest frame the user asked for while a decode was running. Slider
    /// drags overwrite it, so only the newest request is decoded next instead
    /// of a backlog of one decode per slider tick.
    @State private var pendingFrame: Int?
    @State private var isDecodingFrame = false
    @State private var frameReadFailed = false

    var body: some View {
        Group {
            if let state = correctionState {
                correctionContent(state)
            } else {
                preparationView
            }
        }
        .background(AnalysisTheme.proTourBackground.ignoresSafeArea())
        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            topChrome
                .safeAreaPadding(.top, 4)
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
        .tint(AnalysisTheme.proTourSignal)
        .preferredColorScheme(.dark)
    }

    private var topChrome: some View {
        VStack(spacing: 2) {
            HStack {
                Button("关闭", action: onClose)
                    .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                    .scaledFont(size: 15, weight: .semibold)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 38)
                    .background(
                        .black.opacity(0.30),
                        in: Capsule()
                    )
                    .accessibilityLabel("关闭 P 点修正")

                Spacer()

                VStack(spacing: 0) {
                    Text("P 点修正")
                        .scaledFont(size: 17, weight: .bold)
                    Text("当前视频")
                        .font(.caption2)
                        .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                }

                Spacer()

                Color.clear
                    .frame(width: 54, height: 38)
            }
            .padding(.horizontal, 12)

            if let state = correctionState {
                stageSelector(state)
            }
        }
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.54), .black.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.bottom, -18)
        )
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
        .overlay(alignment: .bottom) {
            correctionControls(state)
                .padding(.horizontal, 12)
                .safeAreaPadding(.bottom, 24)
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
                                .scaledFont(size: 14, weight: .black, design: .monospaced)
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
                                ? AnalysisTheme.proTourSignal.opacity(0.86)
                                : .black.opacity(0.28),
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(.white.opacity(0.16), lineWidth: 1)
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
        VStack(spacing: 8) {
            HStack {
                Text(
                    "帧 \(state.currentSourceFrameIndex + 1) / " +
                        "\(frameController.frameCount)"
                )
                .scaledFont(size: 20, weight: .bold, design: .rounded)
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
            .shadow(color: .black.opacity(0.9), radius: 3)

            frameScrubber(state)

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
                    .scaledFont(size: 16, weight: .bold)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(AnalysisTheme.proTourBackground)
                    .background(
                        AnalysisTheme.proTourSignal.opacity(0.84),
                        in: RoundedRectangle(cornerRadius: 13)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isShowingCurrentFrame(state))
            .opacity(isShowingCurrentFrame(state) ? 1 : 0.5)

            if frameReadFailed {
                Text(
                    "无法读取第 \(state.currentSourceFrameIndex + 1) 帧，请用 ±1 换一帧"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .shadow(color: .black.opacity(0.9), radius: 3)
            }
            .accessibilityLabel(
                "将当前帧设为 \(state.selectedCode.rawValue)"
            )

            if let savedMessage {
                Text(savedMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AnalysisTheme.proTourSignal)
                    .shadow(color: .black.opacity(0.9), radius: 3)
                    .transition(.opacity)
            }
        }
    }

    /// Drag to move through every source frame the selected stage may use,
    /// instead of stepping ±1/±5 frames at a time.
    @ViewBuilder
    private func frameScrubber(_ state: PPointCorrectionState) -> some View {
        let range = state.selectableFrameRange
        if range.upperBound > range.lowerBound {
            HStack(spacing: 8) {
                Text("\(range.lowerBound + 1)")
                Slider(
                    value: Binding(
                        get: { scrubFrame },
                        set: { value in
                            scrubFrame = value
                            jump(to: Int(value.rounded()))
                        }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                .tint(AnalysisTheme.proTourSignal)
                .accessibilityLabel("拖动选择 \(state.selectedCode.rawValue) 帧")
                .accessibilityValue("帧 \(state.currentSourceFrameIndex + 1)")
                Text("\(range.upperBound + 1)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            .shadow(color: .black.opacity(0.9), radius: 3)
            .padding(.horizontal, 4)
        }
    }

    private func stepButton(_ amount: Int, title: String) -> some View {
        Button {
            step(amount)
        } label: {
            Text(title)
                .scaledFont(size: 18, weight: .bold, design: .monospaced)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    .black.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
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

        var predicted: [PPointCode: Int] = Dictionary(
            uniqueKeysWithValues: prediction.stages.compactMap { selection in
                guard let code = PPointCode(rawValue: selection.stage),
                      let frame = selection.sourceFrameIndex else {
                    return nil
                }
                return (code, frame)
            }
        )
        var suggested: [PPointCode: Int] = Dictionary(
            uniqueKeysWithValues: prediction.stages.compactMap { selection in
                guard let code = PPointCode(rawValue: selection.stage),
                      let frame = selection.suggestedSourceFrameIndex else {
                    return nil
                }
                return (code, frame)
            }
        )
        var manual: [PPointCode: Int] = [:]
        for marker in markers {
            guard let code = Self.code(for: marker.stage) else {
                continue
            }
            let frame: Int?
            if let exactFrame = marker.sourceFrameIndex,
               (0..<frameController.frameCount).contains(exactFrame) {
                frame = exactFrame
            } else {
                frame = await frameController.nearestSourceFrameIndex(
                    at: marker.time
                )
            }
            guard let frame else { continue }
            PPointCorrectionMarkerPolicy.apply(
                code: code,
                frame: frame,
                kind: PPointCorrectionMarkerPolicy.kind(
                    isManual: marker.source == .manual,
                    automaticIsConfirmed:
                        marker.automaticStatus == .confirmed
                ),
                predictedFrames: &predicted,
                suggestedFrames: &suggested,
                manualFrames: &manual
            )
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
        if let initialStage,
           let code = Self.code(for: initialStage.rawValue) {
            PPointCorrectionReducer.reduce(
                state: &initial,
                action: .select(code)
            )
        }
        correctionState = initial
        scrubFrame = Double(initial.currentSourceFrameIndex)
        _ = await frameController.show(
            index: initial.currentSourceFrameIndex
        )
    }

    private func select(_ code: PPointCode) {
        guard var state = correctionState else { return }
        PPointCorrectionReducer.reduce(state: &state, action: .select(code))
        correctionState = state
        scrubFrame = Double(state.currentSourceFrameIndex)
        show(frame: state.currentSourceFrameIndex)
    }

    private func step(_ amount: Int) {
        guard var state = correctionState else { return }
        PPointCorrectionReducer.reduce(state: &state, action: .step(amount))
        correctionState = state
        scrubFrame = Double(state.currentSourceFrameIndex)
        show(frame: state.currentSourceFrameIndex)
    }

    private func jump(to frame: Int) {
        guard var state = correctionState,
              frame != state.currentSourceFrameIndex else { return }
        PPointCorrectionReducer.reduce(state: &state, action: .jump(frame))
        correctionState = state
        show(frame: state.currentSourceFrameIndex)
    }

    private func show(frame: Int) {
        pendingFrame = frame
        guard !isDecodingFrame else { return }
        isDecodingFrame = true
        Task { @MainActor in
            while let next = pendingFrame {
                pendingFrame = nil
                let loaded = await frameController.show(index: next)
                if pendingFrame == nil {
                    frameReadFailed = !loaded
                    if loaded { frameController.errorMessage = nil }
                }
            }
            isDecodingFrame = false
        }
    }

    /// True once the frame on screen is the frame the selected stage would be
    /// set to; "设为" stays disabled until then.
    private func isShowingCurrentFrame(_ state: PPointCorrectionState) -> Bool {
        frameController.currentFrame?.sourceFrameIndex == state.currentSourceFrameIndex
    }

    private func saveSelectedStage() {
        guard var state = correctionState,
              let frame = frameController.currentFrame,
              frame.sourceFrameIndex == state.currentSourceFrameIndex else {
            flashSaved(
                frameReadFailed
                    ? "无法读取第 \(((correctionState?.currentSourceFrameIndex ?? 0) + 1)) 帧，请换一帧"
                    : "画面还在加载，请稍候"
            )
            return
        }
        PPointCorrectionReducer.reduce(
            state: &state,
            action: .setSelectedStage
        )
        correctionState = state
        let savedCode = state.selectedCode
        onSave(
            savedCode,
            state.currentSourceFrameIndex,
            frame.presentationTime.seconds,
            frame.image
        )
        // Move straight on to the next stage so P1→P8 can be set in one pass.
        if let next = state.nextCode {
            PPointCorrectionReducer.reduce(state: &state, action: .select(next))
            correctionState = state
            scrubFrame = Double(state.currentSourceFrameIndex)
            show(frame: state.currentSourceFrameIndex)
            flashSaved("已设 \(savedCode.rawValue)，下一个 \(next.rawValue)")
        } else {
            flashSaved("已设 \(savedCode.rawValue)")
        }
    }

    private func flashSaved(_ message: String) {
        withAnimation { savedMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if savedMessage == message {
                withAnimation { savedMessage = nil }
            }
        }
    }

    private func statusColor(
        _ source: PPointSelectionSource
    ) -> Color {
        switch source {
        case .manual:
            return AnalysisTheme.proTourSignal
        case .automatic:
            return AnalysisTheme.proTourPrimaryText
        case .review:
            return AnalysisTheme.current
        case .unresolved:
            return AnalysisTheme.proTourPaused
        }
    }

    private func statusLabel(
        _ source: PPointSelectionSource
    ) -> String {
        PPointSelectionPresentation.label(for: source)
    }

    private static func code(for stageRawValue: String) -> PPointCode? {
        guard let stage = SwingStage(rawValue: stageRawValue),
              let index = SwingStage.pStages.firstIndex(of: stage) else {
            return nil
        }
        return PPointCode.allCases[index]
    }
}

import SwiftUI
import AVFoundation

/// Full-screen, two-metre-readable practice surface. The phone remains on the
/// tripod; one oversized control is the only required interaction after setup.
struct PracticeSessionView: View {
    let view: PracticeCameraView
    let onClose: () -> Void
    let onOpenLastClip: (URL) -> Void

    @StateObject private var cameraState: CameraStateModel
    @StateObject private var sessionEngine: PracticeSessionEngine
    @State private var persistedLastClipURL: URL?

    init(
        view: PracticeCameraView,
        onClose: @escaping () -> Void,
        onOpenLastClip: @escaping (URL) -> Void
    ) {
        self.view = view
        self.onClose = onClose
        self.onOpenLastClip = onOpenLastClip
        let cameraState = CameraStateModel()
        _cameraState = StateObject(wrappedValue: cameraState)
        _sessionEngine = StateObject(
            wrappedValue: PracticeSessionEngine(
                recorder: cameraState,
                analyzer: OnDevicePracticeAnalyzer()
            )
        )
    }

    var body: some View {
        ZStack {
            CameraPreviewRepresentable(cameraState: cameraState, useFrontCamera: false)
                .ignoresSafeArea()

            if case .aligning = sessionEngine.state {
                alignmentGuide
            }

            LinearGradient(
                colors: [.black.opacity(0.65), .clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 16) {
                header
                Spacer()
                remoteStatus
                if case let .resultRibbon(_, _, feedback) = sessionEngine.state {
                    feedbackRibbon(feedback)
                }
                if let persistedLastClipURL {
                    Button("查看上一球慢动作") {
                        onOpenLastClip(persistedLastClipURL)
                    }
                    .font(.headline)
                    .frame(minHeight: 52)
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .foregroundStyle(.white)
                }
                Spacer()
                primaryControl
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .onAppear {
            cameraState.setupSession()
            sessionEngine.begin(view: view)
        }
        .onDisappear {
            sessionEngine.pause()
            cameraState.stopSession()
        }
        .onChange(of: sessionEngine.lastClipURL) { _, clipURL in
            guard let clipURL else { return }
            persistedLastClipURL = persistPracticeClip(clipURL)
        }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.bold))
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.42), in: Circle())
            }
            .foregroundStyle(.white)
            Spacer()
            Text(view == .downTheLine ? "正后方 · DTL" : "正面 · Face-on")
                .font(.headline.weight(.bold))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(.black.opacity(0.42), in: Capsule())
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 52, height: 52)
        }
    }

    private var alignmentGuide: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(AnalysisTheme.confirmed, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .frame(width: geometry.size.width * 0.56, height: geometry.size.height * 0.60)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.46)
                Text("让全身与球位进入框内")
                    .font(.headline.weight(.bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.62), in: Capsule())
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.79)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var remoteStatus: some View {
        Text(PracticePresentationPolicy.remoteStatus(for: sessionEngine.state))
            .font(.system(size: 27, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .frame(maxWidth: 520)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private func feedbackRibbon(_ feedback: PriorityFeedback) -> some View {
        VStack(spacing: 5) {
            Text(PracticePresentationPolicy.feedbackTitle(feedback))
                .font(.headline.weight(.bold))
            if let drill = PracticePresentationPolicy.drill(for: feedback) {
                Text("建议：\(drill.title)")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(AnalysisTheme.primaryText.opacity(0.90), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var primaryControl: some View {
        switch sessionEngine.state {
        case .aligning:
            Button("我已站好") {
                sessionEngine.confirmAlignment()
            }
            .buttonStyle(PracticePrimaryButtonStyle(tint: AnalysisTheme.confirmed))
        default:
            switch PracticePresentationPolicy.primaryControl(for: sessionEngine.state) {
            case .start:
                Button(startTitle) {
                    if case .paused = sessionEngine.state {
                        sessionEngine.resume()
                    } else {
                        sessionEngine.start()
                    }
                    sessionEngine.armNextCapture()
                }
                .buttonStyle(PracticePrimaryButtonStyle(tint: AnalysisTheme.confirmed))
            case .pause:
                Button("暂停自动练习") {
                    sessionEngine.pause()
                }
                .buttonStyle(PracticePrimaryButtonStyle(tint: .orange))
            case .none:
                Color.clear.frame(height: 80)
            }
        }
    }

    private var startTitle: String {
        if case .paused = sessionEngine.state { return "继续自动练习" }
        return "开始自动练习"
    }

    private func persistPracticeClip(_ sourceURL: URL) -> URL? {
        let destination = LocalProjectStore.videoDirectory()
            .appendingPathComponent("practice-\(UUID().uuidString).mp4")
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

private struct PracticePrimaryButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.bold))
            .foregroundStyle(.black)
            .frame(maxWidth: 420, minHeight: 76)
            .padding(.horizontal, 20)
            .background(tint.opacity(configuration.isPressed ? 0.74 : 1), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.60), lineWidth: 2))
    }
}

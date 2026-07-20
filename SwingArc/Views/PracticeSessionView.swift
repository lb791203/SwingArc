import SwiftUI
import AVFoundation

/// A camera-first practice surface for a golfer standing beside a tripod. It
/// deliberately exposes one large action at a time and keeps every state
/// readable from the ball position.
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

            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            LinearGradient(
                colors: [
                    AnalysisTheme.proTourBackground.opacity(0.94),
                    .clear,
                    AnalysisTheme.proTourBackground.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if case .aligning = sessionEngine.state {
                alignmentGuide
            }

            VStack(spacing: 0) {
                header
                Spacer(minLength: 30)
                statusCluster
                Spacer(minLength: 24)
                bottomControls
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            cameraState.setupSession()
            sessionEngine.begin(view: view)
            #if DEBUG
            if PracticePreviewConfiguration.startsReady(for: ProcessInfo.processInfo.arguments) {
                sessionEngine.confirmAlignment()
            }
            #endif
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
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(AnalysisTheme.proTourSurface.opacity(0.88), in: Circle())
                    .overlay(Circle().stroke(AnalysisTheme.proTourRaisedSurface, lineWidth: 1))
            }
            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
            .accessibilityLabel("结束练习")

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(AnalysisTheme.proTourGreen)
                    .frame(width: 8, height: 8)
                Text(view == .downTheLine ? "DTL" : "FACE-ON")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1.1)
            }
            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .background(AnalysisTheme.proTourSurface.opacity(0.88), in: Capsule())
            .overlay(Capsule().stroke(AnalysisTheme.proTourRaisedSurface, lineWidth: 1))

            Spacer()

            Color.clear.frame(width: 48, height: 48)
        }
    }

    private var alignmentGuide: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(
                        AnalysisTheme.proTourSignal,
                        style: StrokeStyle(lineWidth: 3, dash: [12, 10])
                    )
                    .frame(width: geometry.size.width * 0.62, height: geometry.size.height * 0.54)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.47)

                VStack(spacing: 8) {
                    Text("FRAME CHECK")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                    Text("全身与球位进入框内")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(AnalysisTheme.proTourBackground.opacity(0.92), in: Capsule())
                .overlay(Capsule().stroke(AnalysisTheme.proTourRaisedSurface, lineWidth: 1))
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.77)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var statusCluster: some View {
        VStack(spacing: 14) {
            HStack(spacing: 9) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 10, height: 10)
                Text(stateLabel)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(statusTint)
            }

            Text(PracticePresentationPolicy.remoteStatus(for: sessionEngine.state))
                .font(.system(size: 31, weight: .heavy, design: .monospaced))
                .tracking(-0.7)
                .multilineTextAlignment(.center)
                .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                .minimumScaleFactor(0.72)

            if let detail = PracticePresentationPolicy.remoteDetail(for: sessionEngine.state) {
                Text(detail)
                    .font(.system(size: 16, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .background(AnalysisTheme.proTourBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AnalysisTheme.proTourRaisedSurface.opacity(0.92), lineWidth: 1)
        )
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            if case let .resultRibbon(_, _, feedback) = sessionEngine.state {
                feedbackRibbon(feedback)
            }

            if let persistedLastClipURL {
                Button {
                    onOpenLastClip(persistedLastClipURL)
                } label: {
                    Label("查看上一球慢动作", systemImage: "play.rectangle")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                .background(AnalysisTheme.proTourSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AnalysisTheme.proTourRaisedSurface, lineWidth: 1)
                )
            }

            primaryControl
        }
    }

    private func feedbackRibbon(_ feedback: PriorityFeedback) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feedbackIcon(for: feedback))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(feedbackTint(for: feedback))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(PracticePresentationPolicy.feedbackTitle(feedback))
                    .font(.system(size: 16, weight: .bold))
                if let drill = PracticePresentationPolicy.drill(for: feedback) {
                    Text("DRILL · \(drill.title)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(AnalysisTheme.proTourSurface.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(feedbackTint(for: feedback).opacity(0.42), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var primaryControl: some View {
        switch sessionEngine.state {
        case .aligning:
            PracticePrimaryControlButton(
                title: "我已站好",
                systemImage: "viewfinder",
                tint: AnalysisTheme.proTourSignal,
                action: sessionEngine.confirmAlignment
            )
        default:
            switch PracticePresentationPolicy.primaryControl(for: sessionEngine.state) {
            case .start:
                PracticePrimaryControlButton(
                    title: startTitle,
                    systemImage: "play.fill",
                    tint: AnalysisTheme.proTourSignal,
                    action: startOrResume
                )
            case .pause:
                PracticePrimaryControlButton(
                    title: "暂停自动练习",
                    systemImage: "pause.fill",
                    tint: AnalysisTheme.proTourPaused,
                    action: sessionEngine.pause
                )
            case .none:
                Color.clear.frame(height: 76)
            }
        }
    }

    private var stateLabel: String {
        switch sessionEngine.state {
        case .aligning: return "CAMERA ALIGNMENT"
        case .readyToStart: return "STANCE LOCKED"
        case .waitingForImpact: return "AUTO CAPTURE ARMED"
        case .processing: return "ON-DEVICE ANALYSIS"
        case .resultRibbon: return "PRIORITY FEEDBACK"
        case .paused: return "PRACTICE PAUSED"
        case .degraded, .failed: return "ATTENTION"
        }
    }

    private var statusTint: Color {
        switch sessionEngine.state {
        case .aligning, .readyToStart, .resultRibbon:
            return AnalysisTheme.proTourSignal
        case .paused, .degraded, .failed:
            return AnalysisTheme.proTourPaused
        case .waitingForImpact, .processing:
            return AnalysisTheme.proTourPrimaryText
        }
    }

    private var startTitle: String {
        if case .paused = sessionEngine.state { return "继续自动练习" }
        return "开始自动练习"
    }

    private func startOrResume() {
        if case .paused = sessionEngine.state {
            sessionEngine.resume()
        } else {
            sessionEngine.start()
        }
        sessionEngine.armNextCapture()
    }

    private func feedbackIcon(for feedback: PriorityFeedback) -> String {
        switch feedback {
        case .finding: return "scope"
        case .unresolved: return "questionmark.circle"
        }
    }

    private func feedbackTint(for feedback: PriorityFeedback) -> Color {
        switch feedback {
        case .finding: return AnalysisTheme.proTourSignal
        case .unresolved: return AnalysisTheme.proTourSecondaryText
        }
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

private struct PracticePrimaryControlButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 78)
        }
        .buttonStyle(ProTourPracticeButtonStyle(tint: tint))
    }
}

private struct ProTourPracticeButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AnalysisTheme.proTourBackground)
            .background(tint.opacity(configuration.isPressed ? 0.76 : 1), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AnalysisTheme.proTourPrimaryText.opacity(0.25), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

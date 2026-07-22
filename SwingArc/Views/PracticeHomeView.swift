import SwiftUI

/// The start screen is deliberately a mode selector rather than a project
/// library: when the phone is on a tripod, the golfer should only have to
/// recognise an angle and make one large tap.
struct PracticeHomeView: View {
    let onStartPractice: (PracticeCameraView) -> Void
    let onManualCapture: () -> Void
    let onImport: () -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AnalysisTheme.proTourBackground
                    .ignoresSafeArea()

                GeometryReader { proxy in
                    let metrics = PracticeHomeMetrics(height: proxy.size.height)

                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.top, metrics.headerTopPadding)

                        Text("TRAINING MODE")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(AnalysisTheme.proTourSignal)
                            .padding(.top, metrics.trainingTopPadding)

                        Text("选择机位")
                            .font(
                                .system(
                                    size: metrics.mainTitleSize,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                            .padding(.top, 6)

                        Text("单机位自动练习 · 架好手机后再开始")
                            .font(.system(size: metrics.cardDetailSize + 2, weight: .medium))
                            .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                            .padding(.top, 4)

                        Spacer(minLength: metrics.cardsTopPadding)

                        VStack(spacing: metrics.cardSpacing) {
                            ForEach(Array(PracticeHomePresentation.modeOrder.enumerated()), id: \.offset) { _, action in
                                modeSelector(for: action, metrics: metrics)
                            }
                        }

                        Spacer(minLength: metrics.bottomPadding)
                    }
                    .padding(.horizontal, 20)
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .top
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(AnalysisTheme.proTourSignal)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center) {
            BrandMarkView(size: 30, showsWordmark: true)

            Spacer()

            Button(action: onOpenLibrary) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AnalysisTheme.proTourSignal)
                    Text("记录")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                }
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("打开挥杆记录")
        }
    }

    @ViewBuilder
    private func modeSelector(
        for action: PracticeHomeAction,
        metrics: PracticeHomeMetrics
    ) -> some View {
        switch action {
        case .downTheLine:
            PracticeModeSelector(
                index: "01",
                eyebrow: "DOWN THE LINE",
                title: "正后方 · DTL",
                detail: "下杆路径 · 脊柱稳定",
                systemImage: "figure.golf",
                surfaceOpacity: 0.85,
                metrics: metrics,
                action: { onStartPractice(.downTheLine) }
            )
        case .faceOn:
            PracticeModeSelector(
                index: "02",
                eyebrow: "FACE-ON",
                title: "正面 · FACE-ON",
                detail: "送杆动作 · 重心移动",
                systemImage: "viewfinder",
                surfaceOpacity: 0.70,
                metrics: metrics,
                action: { onStartPractice(.faceOn) }
            )
        case .importVideo:
            PracticeModeSelector(
                index: "04",
                eyebrow: "IMPORT VIDEO",
                title: "导入视频",
                detail: "从相册选择 · 自动 AI 分析",
                systemImage: "photo.on.rectangle",
                surfaceOpacity: 0.40,
                metrics: metrics,
                action: onImport
            )
        case .manualCapture:
            PracticeModeSelector(
                index: "03",
                eyebrow: "MANUAL CAPTURE",
                title: "手动录像",
                detail: "点击即录 · 最长 15 秒",
                systemImage: "record.circle",
                surfaceOpacity: 0.55,
                metrics: metrics,
                action: onManualCapture
            )
        case .history:
            EmptyView()
        }
    }

}

private struct PracticeHomeMetrics {
    let cardHeight: CGFloat
    let cardSpacing: CGFloat
    let mainTitleSize: CGFloat
    let cardTitleSize: CGFloat
    let cardDetailSize: CGFloat
    let trainingTopPadding: CGFloat
    let cardsTopPadding: CGFloat
    let headerTopPadding: CGFloat
    let bottomPadding: CGFloat

    init(height: CGFloat) {
        if height >= 820 {
            cardHeight = 126
            cardSpacing = 12
            mainTitleSize = 38
            cardTitleSize = 24
            cardDetailSize = 14
            trainingTopPadding = 34
            cardsTopPadding = 24
            headerTopPadding = 12
            bottomPadding = 8
        } else if height >= 700 {
            cardHeight = 108
            cardSpacing = 10
            mainTitleSize = 34
            cardTitleSize = 22
            cardDetailSize = 13
            trainingTopPadding = 24
            cardsTopPadding = 18
            headerTopPadding = 8
            bottomPadding = 6
        } else {
            cardHeight = 92
            cardSpacing = 8
            mainTitleSize = 30
            cardTitleSize = 20
            cardDetailSize = 12
            trainingTopPadding = 16
            cardsTopPadding = 12
            headerTopPadding = 4
            bottomPadding = 4
        }
    }
}

private struct PracticeModeSelector: View {
    let index: String
    let eyebrow: String
    let title: String
    let detail: String
    let systemImage: String
    let surfaceOpacity: Double
    let metrics: PracticeHomeMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(index)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(AnalysisTheme.proTourBackground)
                    .frame(width: 38, height: 38)
                    .background(
                        modeAccent,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                    Text(title)
                        .font(
                            .system(
                                size: metrics.cardTitleSize,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                    Text(detail)
                        .font(.system(size: metrics.cardDetailSize, weight: .medium))
                        .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                }

                Spacer(minLength: 8)

                VStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 25, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(modeAccent)
                .frame(width: 42)
            }
            .padding(.horizontal, 20)
            .frame(height: metrics.cardHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AnalysisTheme.proTourSurface.opacity(surfaceOpacity),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(modeAccent.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(ProTourPressStyle())
        .accessibilityLabel("开始\(title)练习")
    }

    private var modeAccent: Color {
        AnalysisTheme.proTourSignal
    }
}

private struct ProTourPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.80 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

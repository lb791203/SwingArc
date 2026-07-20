import SwiftUI

/// The start screen is deliberately a mode selector rather than a project
/// library: when the phone is on a tripod, the golfer should only have to
/// recognise an angle and make one large tap.
struct PracticeHomeView: View {
    let onStartPractice: (PracticeCameraView) -> Void
    let onImport: () -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AnalysisTheme.proTourBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.top, 12)

                        Text("TRAINING MODE")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(AnalysisTheme.proTourSignal)
                            .padding(.top, 42)

                        Text("选择机位")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                            .padding(.top, 8)

                        Text("单机位自动练习 · 架好手机后再开始")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                            .padding(.top, 6)

                        VStack(spacing: 14) {
                            ForEach(Array(PracticeHomePresentation.modeOrder.enumerated()), id: \.offset) { _, action in
                                modeSelector(for: action)
                            }
                        }
                        .padding(.top, 30)

                        Rectangle()
                            .fill(AnalysisTheme.proTourRaisedSurface)
                            .frame(height: 1)
                            .padding(.vertical, 30)

                        Text("TOOLS")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(AnalysisTheme.proTourSecondaryText)

                        HStack(spacing: 12) {
                            ForEach(Array(PracticeHomePresentation.secondaryActions.enumerated()), id: \.offset) { _, action in
                                utilityButton(for: action)
                            }
                        }
                        .padding(.top, 14)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 38)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(AnalysisTheme.proTourSignal)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Image(systemName: "figure.golf")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AnalysisTheme.proTourSignal)
                Text("SWINGARC")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(AnalysisTheme.proTourPrimaryText)
            }

            Spacer()

            Text("LOCAL AI")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AnalysisTheme.proTourSurface, in: Capsule())
                .overlay(Capsule().stroke(AnalysisTheme.proTourRaisedSurface, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func modeSelector(for action: PracticeHomeAction) -> some View {
        switch action {
        case .downTheLine:
            PracticeModeSelector(
                index: "01",
                eyebrow: "DOWN THE LINE",
                title: "正后方 · DTL",
                detail: "下杆路径 · 脊柱稳定",
                systemImage: "figure.golf",
                usesBrandSurface: true,
                action: { onStartPractice(.downTheLine) }
            )
        case .faceOn:
            PracticeModeSelector(
                index: "02",
                eyebrow: "FACE-ON",
                title: "正面 · FACE-ON",
                detail: "送杆动作 · 重心移动",
                systemImage: "viewfinder",
                usesBrandSurface: false,
                action: { onStartPractice(.faceOn) }
            )
        case .importVideo, .history:
            EmptyView()
        }
    }

    @ViewBuilder
    private func utilityButton(for action: PracticeHomeAction) -> some View {
        switch action {
        case .importVideo:
            PracticeUtilityButton(
                title: "导入影片",
                detail: "慢动作 · P1–P8",
                systemImage: "square.and.arrow.down",
                action: onImport
            )
        case .history:
            PracticeUtilityButton(
                title: "历史分析",
                detail: "已保存的练习",
                systemImage: "clock.arrow.circlepath",
                action: onOpenLibrary
            )
        case .downTheLine, .faceOn:
            EmptyView()
        }
    }
}

private struct PracticeModeSelector: View {
    let index: String
    let eyebrow: String
    let title: String
    let detail: String
    let systemImage: String
    let usesBrandSurface: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(index)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(usesBrandSurface ? AnalysisTheme.proTourSignal : AnalysisTheme.proTourSecondaryText)
                    .frame(width: 30, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(usesBrandSurface ? AnalysisTheme.proTourPrimaryText.opacity(0.72) : AnalysisTheme.proTourSecondaryText)
                    Text(title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                    Text(detail)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(usesBrandSurface ? AnalysisTheme.proTourPrimaryText.opacity(0.72) : AnalysisTheme.proTourSecondaryText)
                }

                Spacer(minLength: 8)

                VStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 25, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(usesBrandSurface ? AnalysisTheme.proTourSignal : AnalysisTheme.proTourPrimaryText)
                .frame(width: 42)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .background(usesBrandSurface ? AnalysisTheme.proTourGreen : AnalysisTheme.proTourSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(usesBrandSurface ? AnalysisTheme.proTourSignal.opacity(0.36) : AnalysisTheme.proTourRaisedSurface, lineWidth: 1)
            )
        }
        .buttonStyle(ProTourPressStyle())
        .accessibilityLabel("开始\(title)练习")
    }
}

private struct PracticeUtilityButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AnalysisTheme.proTourSignal)
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .padding(16)
            .background(AnalysisTheme.proTourSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AnalysisTheme.proTourRaisedSurface, lineWidth: 1)
            )
        }
        .buttonStyle(ProTourPressStyle())
        .accessibilityLabel(title)
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

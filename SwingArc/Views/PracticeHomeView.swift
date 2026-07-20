import SwiftUI

/// The default entry screen keeps all three confirmed workflows equally
/// discoverable: rear-view practice, face-on practice, and legacy import.
struct PracticeHomeView: View {
    let onStartPractice: (PracticeCameraView) -> Void
    let onImport: () -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SwingArc")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("架好手机，专注挥杆。每一球只给有证据的反馈。")
                            .font(.body)
                            .foregroundStyle(AnalysisTheme.secondaryText)
                    }
                    .padding(.bottom, 4)

                    PracticeEntryCard(
                        title: "正后方练习",
                        subtitle: "DTL · 观察下杆路径与脊柱稳定",
                        systemImage: "figure.golf",
                        tint: .blue,
                        action: { onStartPractice(.downTheLine) }
                    )
                    PracticeEntryCard(
                        title: "正面练习",
                        subtitle: "Face-on · 观察送杆与重心动作",
                        systemImage: "viewfinder",
                        tint: .orange,
                        action: { onStartPractice(.faceOn) }
                    )
                    PracticeEntryCard(
                        title: "导入已有挥杆影片",
                        subtitle: "保留原有慢动作、P1–P8 与手动标注工具",
                        systemImage: "photo.on.rectangle.angled",
                        tint: .teal,
                        action: onImport
                    )

                    Button(action: onOpenLibrary) {
                        Label("查看历史分析", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.bordered)
                    .tint(AnalysisTheme.primaryText)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(AnalysisTheme.libraryBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(AnalysisTheme.primaryText)
    }
}

private struct PracticeEntryCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 68, height: 68)
                    .foregroundStyle(.white)
                    .background(tint, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AnalysisTheme.primaryText)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AnalysisTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(AnalysisTheme.secondaryText)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
            .background(AnalysisTheme.libraryCard, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.black.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .accessibilityHint("开始\(title)")
    }
}

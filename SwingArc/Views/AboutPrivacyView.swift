import SwiftUI

struct AboutPrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("SwingArc") {
                    LabeledContent("版本", value: AppInformation.currentVersion)
                    Text(AppInformation.analysisDisclaimer)
                        .foregroundStyle(.secondary)
                }

                Section("隐私与支持") {
                    Link(destination: AppInformation.privacyURL) {
                        Label("隐私政策", systemImage: "hand.raised")
                    }
                    Link(destination: AppInformation.supportURL) {
                        Label("支持与联系", systemImage: "questionmark.circle")
                    }
                }

                Section {
                    Text("视频、P 点、画线和项目均保存在此设备；SwingArc 不要求账号，也不会上传您的挥杆视频。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("关于与隐私")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

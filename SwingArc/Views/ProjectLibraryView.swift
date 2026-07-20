import SwiftUI
import AVFoundation
import UIKit

struct ProjectLibraryView: View {
    let projects: [LocalProjectSummary]
    let onOpen: (LocalProjectSummary) -> Void
    let onImport: () -> Void
    let onRecord: () -> Void
    let onRename: (LocalProjectSummary, String) -> Void
    let onDelete: (LocalProjectSummary) -> Void
    var onClose: (() -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showsNewProjectSheet = false
    @State private var projectToRename: LocalProjectSummary?
    @State private var projectToDelete: LocalProjectSummary?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    projectCollection
                }
            }
            .background(AnalysisTheme.libraryBackground.ignoresSafeArea())
            .navigationTitle("分析项目")
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("练习") { onClose() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsNewProjectSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.white)
                            .background(AnalysisTheme.primaryText, in: Circle())
                    }
                    .accessibilityLabel("新建分析项目")
                }
            }
        }
        .tint(AnalysisTheme.primaryText)
        .sheet(isPresented: $showsNewProjectSheet) {
            NewProjectSheet(
                onImport: {
                    showsNewProjectSheet = false
                    onImport()
                },
                onRecord: {
                    showsNewProjectSheet = false
                    onRecord()
                }
            )
            .presentationDetents([.height(250)])
            .presentationDragIndicator(.visible)
        }
        .alert("重命名项目", isPresented: Binding(
            get: { projectToRename != nil },
            set: { if !$0 { projectToRename = nil } }
        )) {
            TextField("项目名称", text: $renameText)
            Button("取消", role: .cancel) { projectToRename = nil }
            Button("保存") {
                if let project = projectToRename {
                    onRename(project, renameText)
                }
                projectToRename = nil
            }
        }
        .confirmationDialog(
            "删除这个分析项目？",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除项目", role: .destructive) {
                if let project = projectToDelete {
                    onDelete(project)
                }
                projectToDelete = nil
            }
            Button("取消", role: .cancel) { projectToDelete = nil }
        } message: {
            Text("项目记录和本地视频将被移除，此操作无法撤销。")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(AnalysisTheme.secondaryText)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("开始第一次视频分析")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AnalysisTheme.primaryText)
                Text("导入或录制一段挥杆视频开始分析")
                    .font(.subheadline)
                    .foregroundStyle(AnalysisTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button(action: onImport) {
                    Label("导入视频", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(AnalysisTheme.primaryText)

                Button(action: onRecord) {
                    Label("录制视频", systemImage: "video")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 360)
            Spacer()
        }
        .padding(24)
    }

    private var projectCollection: some View {
        ScrollView {
            LazyVGrid(
                columns: horizontalSizeClass == .regular
                    ? [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 16)]
                    : [GridItem(.flexible())],
                spacing: 14
            ) {
                ForEach(projects) { project in
                    ProjectCard(project: project) {
                        onOpen(project)
                    } onRename: {
                        renameText = project.name
                        projectToRename = project
                    } onDelete: {
                        projectToDelete = project
                    }
                }
            }
            .padding(16)
        }
    }
}

struct NewProjectSheet: View {
    let onImport: () -> Void
    let onRecord: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Button(action: onImport) {
                    NewProjectActionLabel(
                        title: "导入视频",
                        subtitle: "从照片选择已有视频",
                        systemImage: "photo.on.rectangle"
                    )
                }
                .buttonStyle(.plain)

                Button(action: onRecord) {
                    NewProjectActionLabel(
                        title: "录制视频",
                        subtitle: "使用高速相机录制",
                        systemImage: "video"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .navigationTitle("新建项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct NewProjectActionLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(AnalysisTheme.libraryBackground, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(AnalysisTheme.primaryText)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black.opacity(0.07)))
    }
}

private struct ProjectCard: View {
    let project: LocalProjectSummary
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    VideoThumbnailView(url: project.videoURL)
                        .frame(width: 118, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 7) {
                        Text(project.name)
                            .font(.headline)
                            .foregroundStyle(AnalysisTheme.primaryText)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(formatDuration(project.duration)) · \(formatFrameRate(project.sourceFrameRate))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(AnalysisTheme.secondaryText)

                        HStack(spacing: 6) {
                            Image(systemName: project.status.systemImage)
                            Text(project.status.label)
                            Text("·")
                            Text(project.modifiedAt, format: .relative(presentation: .named))
                        }
                        .font(.caption)
                        .foregroundStyle(AnalysisTheme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开项目")

            Menu {
                Button("重命名", systemImage: "pencil", action: onRename)
                Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(AnalysisTheme.secondaryText)
        }
        .padding(12)
        .background(AnalysisTheme.libraryCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.07)))
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func formatFrameRate(_ rate: Double) -> String {
        rate > 0 ? "\(Int(rate.rounded())) fps" : "帧率未知"
    }
}

private struct VideoThumbnailView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            AnalysisTheme.chrome
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "play.rectangle")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .clipped()
        .task(id: url) {
            image = await generateThumbnail()
        }
        .accessibilityHidden(true)
    }

    private func generateThumbnail() async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 320)
        guard let result = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: result.image)
    }
}

private extension LocalProjectStatus {
    var label: String {
        switch self {
        case .pending: return "待分析"
        case .analyzed: return "已分析"
        case .annotated: return "已标注"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "clock"
        case .analyzed: return "checkmark.circle"
        case .annotated: return "pencil.and.outline"
        }
    }
}

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
            .background(AnalysisTheme.proTourBackground.ignoresSafeArea())
            .navigationTitle("挥杆档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("练习") { onClose() }
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsNewProjectSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                            .frame(width: 42, height: 42)
                            .foregroundStyle(AnalysisTheme.proTourBackground)
                            .background(AnalysisTheme.proTourSignal, in: Circle())
                    }
                    .accessibilityLabel("新建分析项目")
                }
            }
        }
        .tint(AnalysisTheme.proTourSignal)
        .preferredColorScheme(.dark)
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
            .presentationDetents([.height(280)])
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
        VStack(alignment: .leading, spacing: 0) {
            Text("SWING LIBRARY")
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(AnalysisTheme.proTourSignal)
                .padding(.top, 22)

            Text("挥杆档案")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                .padding(.top, 10)

            Text("导入一段影片，逐帧定位你的 P1–P8。")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                .padding(.top, 8)

            Spacer(minLength: 36)

            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "film.stack")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(AnalysisTheme.proTourSignal)
                    .frame(width: 76, height: 76)
                    .background(AnalysisTheme.proTourSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                Text("还没有分析影片")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AnalysisTheme.proTourPrimaryText)

                Text("所有影片与标注仅保存在这台设备。")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            }

            Spacer()

            VStack(spacing: 12) {
                LibraryActionButton(
                    title: "导入影片分析",
                    detail: "慢动作 · P1–P8 · 手动画线",
                    systemImage: "arrow.down.to.line.compact",
                    isPrimary: true,
                    action: onImport
                )
                LibraryActionButton(
                    title: "录制新影片",
                    detail: "使用本机高速相机",
                    systemImage: "video",
                    isPrimary: false,
                    action: onRecord
                )
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
    }

    private var projectCollection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("ANALYSIS ARCHIVE")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(AnalysisTheme.proTourSignal)
                    Text("已保存影片")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                    Text("\(projects.count) 段本地挥杆记录")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                }

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
            }
            .padding(24)
            .padding(.top, 22)
        }
    }
}

private struct LibraryActionButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 48, height: 48)
                    .foregroundStyle(isPrimary ? AnalysisTheme.proTourBackground : AnalysisTheme.proTourSignal)
                    .background(
                        isPrimary ? AnalysisTheme.proTourSignal : AnalysisTheme.proTourRaisedSurface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                    Text(detail)
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.7)
                }

                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(isPrimary ? AnalysisTheme.proTourBackground : AnalysisTheme.proTourPrimaryText)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                isPrimary ? AnalysisTheme.proTourSignal : AnalysisTheme.proTourSurface,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AnalysisTheme.proTourRaisedSurface)
                }
            }
        }
        .buttonStyle(.plain)
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
            .background(AnalysisTheme.proTourBackground.ignoresSafeArea())
            .navigationTitle("新建项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
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
                .foregroundStyle(AnalysisTheme.proTourSignal)
                .background(AnalysisTheme.proTourRaisedSurface, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(AnalysisTheme.proTourSecondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(AnalysisTheme.proTourSecondaryText)
        }
        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(AnalysisTheme.proTourSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AnalysisTheme.proTourRaisedSurface))
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
                        Text("VIDEO ANALYSIS")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                        Text(project.name)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(formatDuration(project.duration)) · \(formatFrameRate(project.sourceFrameRate))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(AnalysisTheme.proTourSecondaryText)

                        HStack(spacing: 6) {
                            Image(systemName: project.status.systemImage)
                            Text(project.status.label)
                        }
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(project.status.proTourColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(project.status.proTourColor.opacity(0.12), in: Capsule())
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
            .foregroundStyle(AnalysisTheme.proTourSecondaryText)
        }
        .padding(12)
        .background(AnalysisTheme.proTourSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AnalysisTheme.proTourRaisedSurface))
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

    var proTourColor: Color {
        switch self {
        case .pending: return AnalysisTheme.proTourSecondaryText
        case .analyzed, .annotated: return AnalysisTheme.proTourSignal
        }
    }
}

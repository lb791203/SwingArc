import SwiftUI

/// Row model representing one clip in the sidebar.
struct DatasetClipRowModel: Identifiable {
    let id: String
    let golferID: String
    let view: String
    let split: String
    let completionProgress: Double // 0...1
    let pendingReviewCount: Int
    let hasP6P8Issues: Bool
    let hasTrackingBreaks: Bool
    let hasLowConfidence: Bool
    let hasROIOOB: Bool
}

/// Filter categories for the clip list.
public enum DatasetSidebarFilter: String, CaseIterable, Hashable, Codable, Sendable {
    case allClips = "全部"
    case pendingReview = "待复核"
    case p6p8 = "P6/P8"
    case trackingBreaks = "跟踪断点"
    case lowConfidence = "低置信"
    case roiOutOfBounds = "ROI 越界"
}

// MARK: - DatasetClipSidebar

struct DatasetClipSidebar: View {
    let clips: [DatasetClipRowModel]
    let selectedClipID: String?
    let selectedFilter: DatasetSidebarFilter
    let onSelectClip: (String) -> Void
    let onSelectFilter: (DatasetSidebarFilter) -> Void

    var body: some View {
        List(selection: Binding(
            get: { selectedClipID },
            set: { if let id = $0 { onSelectClip(id) } }
        )) {
            Section("筛选") {
                ForEach(DatasetSidebarFilter.allCases, id: \.self) { filter in
                    Button {
                        onSelectFilter(filter)
                    } label: {
                        HStack {
                            Text(filter.rawValue)
                                .foregroundColor(.primary)
                            Spacer()
                            if filter == selectedFilter {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("视频库") {
                ForEach(clips) { clip in
                    clipRow(clip)
                        .tag(clip.id)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private func clipRow(_ clip: DatasetClipRowModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clip.id)
                .font(.headline)

            HStack(spacing: 6) {
                Text(clip.golferID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(clip.view)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(clip.split)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ProgressView(value: clip.completionProgress)
                .tint(.accentColor)

            HStack(spacing: 8) {
                if clip.pendingReviewCount > 0 {
                    Label("\(clip.pendingReviewCount)", systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                if clip.hasP6P8Issues {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                if clip.hasTrackingBreaks {
                    Image(systemName: "link.badge.minus")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if clip.hasLowConfidence {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if clip.hasROIOOB {
                    Image(systemName: "rectangle.dashed.badge.record")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview {
    DatasetClipSidebar(
        clips: [
            DatasetClipRowModel(
                id: "clip-001",
                golferID: "golfer-001",
                view: "DTL",
                split: "training",
                completionProgress: 0.85,
                pendingReviewCount: 12,
                hasP6P8Issues: true,
                hasTrackingBreaks: false,
                hasLowConfidence: true,
                hasROIOOB: false
            )
        ],
        selectedClipID: "clip-001",
        selectedFilter: .allClips,
        onSelectClip: { _ in },
        onSelectFilter: { _ in }
    )
    .frame(width: 260)
}

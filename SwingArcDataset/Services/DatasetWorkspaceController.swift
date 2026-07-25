import Combine
import CoreGraphics
import Foundation

public enum DatasetReviewMode: String, Codable, Equatable, Sendable {
    case blindIndependentPass
    case predictionFirst
}

/// Mode-level overlay policy. A blind pass never receives prediction data at the
/// presentation boundary, even if a parent run ID is retained for provenance.
public struct DatasetAnnotationPresentation: Equatable, Sendable {
    public let split: GolfDatasetSplit
    public let reviewMode: DatasetReviewMode
    public let prediction: GolfPredictionRun?

    public init(split: GolfDatasetSplit, reviewMode: DatasetReviewMode, prediction: GolfPredictionRun?) {
        self.split = split
        self.reviewMode = reviewMode
        self.prediction = prediction
    }

    public var visiblePredictionPoints: [GolfLandmark: GolfPredictionPoint] {
        guard reviewMode == .predictionFirst, split != .heldOut else { return [:] }
        return prediction?.frames.first?.points ?? [:]
    }
    public var showsConfidence: Bool { reviewMode == .predictionFirst && split != .heldOut && prediction != nil }
    public var allowsAcceptPrediction: Bool { !visiblePredictionPoints.isEmpty }
}

public enum DatasetWorkspaceAccess: Equatable, Sendable {
    case editable
    case readOnly(reason: String)
}

public struct DatasetWorkspaceSessionRecord: Codable, Equatable, Sendable {
    public let clipID: String
    public let currentSourceFrameIndex: Int
    public let filter: DatasetSidebarFilter
    public let activeRevisionID: String?
    public let securityScopedBookmark: Data

    public init(clipID: String, currentSourceFrameIndex: Int, filter: DatasetSidebarFilter,
                activeRevisionID: String?, securityScopedBookmark: Data) {
        self.clipID = clipID; self.currentSourceFrameIndex = currentSourceFrameIndex
        self.filter = filter; self.activeRevisionID = activeRevisionID
        self.securityScopedBookmark = securityScopedBookmark
    }
}

public protocol DatasetWorkspaceSessionPersisting: AnyObject {
    func load() -> DatasetWorkspaceSessionRecord?
    func save(_ record: DatasetWorkspaceSessionRecord)
}

public final class UserDefaultsDatasetWorkspaceSessionPersistence: DatasetWorkspaceSessionPersisting {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "SwingArcDataset.workspaceSession.v1") {
        self.defaults = defaults; self.key = key
    }
    public func load() -> DatasetWorkspaceSessionRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DatasetWorkspaceSessionRecord.self, from: data)
    }
    public func save(_ record: DatasetWorkspaceSessionRecord) {
        defaults.set(try? JSONEncoder().encode(record), forKey: key)
    }
}

public final class InMemoryDatasetWorkspaceSessionPersistence: DatasetWorkspaceSessionPersisting {
    private var record: DatasetWorkspaceSessionRecord?
    public init() {}
    public func load() -> DatasetWorkspaceSessionRecord? { record }
    public func save(_ record: DatasetWorkspaceSessionRecord) { self.record = record }
}

public protocol DatasetWorkspaceStore: AnyObject {
    func loadSnapshot() throws -> GolfDatasetSnapshot
    func loadPrediction(clipID: String, predictionRunID: String) throws -> GolfPredictionRun
    func saveRevision(_ revision: GolfAnnotationRevision) throws
}

extension GolfDatasetStore: DatasetWorkspaceStore {}

public struct DatasetWorkspaceMediaMetadata: Equatable, Sendable {
    public let frameCount: Int
    public let timelineSHA256: String
    public init(frameCount: Int, timelineSHA256: String) {
        self.frameCount = frameCount; self.timelineSHA256 = timelineSHA256
    }
}

@MainActor
public final class DatasetWorkspaceController: ObservableObject {
    private let store: DatasetWorkspaceStore
    private let sessionPersistence: DatasetWorkspaceSessionPersisting
    private let annotatorID: String
    private let frameSession = ExactVideoFrameSession()

    @Published public private(set) var clips: [GolfClipIdentity] = []
    @Published public private(set) var selectedClipID: String?
    @Published public private(set) var selectedFilter: DatasetSidebarFilter = .allClips
    @Published public private(set) var annotationState: DatasetAnnotationState?
    @Published public private(set) var access: DatasetWorkspaceAccess = .readOnly(reason: "尚未选择 clip")
    @Published public private(set) var activeRevisionID: String?
    @Published public private(set) var fullFrameImage: CGImage?
    @Published public private(set) var currentSourceTime: Double?
    @Published public private(set) var isFrameLoading = false

    private var bookmark = Data()
    private var activeSplit: GolfDatasetSplit?

    public init(store: DatasetWorkspaceStore, sessionPersistence: DatasetWorkspaceSessionPersisting,
                annotatorID: String) {
        self.store = store; self.sessionPersistence = sessionPersistence; self.annotatorID = annotatorID
        reloadClipList()
    }

    public func reloadClipList() {
        clips = (try? store.loadSnapshot().clips) ?? []
    }

    public func restore() async {
        reloadClipList()
        guard let record = sessionPersistence.load(), let clip = clips.first(where: { $0.clipID == record.clipID }) else { return }
        selectedFilter = record.filter
        do {
            guard !record.securityScopedBookmark.isEmpty else { throw CocoaError(.fileNoSuchFile) }
            var stale = false
            let url = try URL(resolvingBookmarkData: record.securityScopedBookmark, options: .withSecurityScope,
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale, url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
            defer { url.stopAccessingSecurityScopedResource() }
            let metadata = try await frameSession.open(url: url)
            try openVerifiedClip(clip: clip, split: split(for: clip), parentPredictionRunID: record.activeRevisionID.flatMap { id in
                latestRevision(for: clip.clipID, preferredID: id)?.parentPredictionRunID
            } ?? latestRevision(for: clip.clipID, preferredID: nil)?.parentPredictionRunID ?? "",
            metadata: .init(frameCount: metadata.frameCount, timelineSHA256: metadata.timelineSHA256), queue: [],
            securityScopedBookmark: record.securityScopedBookmark, preferredRevisionID: record.activeRevisionID,
            preferredFrame: record.currentSourceFrameIndex)
            await loadExactCurrentFrame()
        } catch {
            selectedClipID = clip.clipID
            access = .readOnly(reason: "视频书签不可用或已撤销。")
        }
    }

    public func openVerifiedClip(clip: GolfClipIdentity, split: GolfDatasetSplit, parentPredictionRunID: String,
                                 metadata: DatasetWorkspaceMediaMetadata, queue: [GolfAnnotationQueueItem],
                                 securityScopedBookmark: Data, preferredRevisionID: String? = nil,
                                 preferredFrame: Int? = nil) throws {
        selectedClipID = clip.clipID; activeSplit = split; bookmark = securityScopedBookmark
        guard clip.media.frameCount == metadata.frameCount, clip.media.timelineSHA256 == metadata.timelineSHA256 else {
            annotationState = nil; access = .readOnly(reason: "媒体或源帧时间线与 clip 身份不匹配。"); persistSession(); return
        }
        guard !securityScopedBookmark.isEmpty else {
            annotationState = nil; access = .readOnly(reason: "视频书签不可用或已撤销。"); persistSession(); return
        }
        let revision = latestRevision(for: clip.clipID, preferredID: preferredRevisionID)
        let parentID = revision?.parentPredictionRunID ?? parentPredictionRunID
        guard !parentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            annotationState = nil; access = .readOnly(reason: "缺少可追溯的预测运行 ID。"); persistSession(); return
        }
        // This branch is the blind-mode boundary: it does not call loadPrediction.
        let prediction: GolfPredictionRun?
        if split == .heldOut {
            prediction = nil
        } else {
            prediction = try? store.loadPrediction(clipID: clip.clipID, predictionRunID: parentID)
        }
        // Training/validation can still collect manual decisions when the caller
        // has an explicit provenance ID but no stored run is available. The UI
        // receives nil prediction data, so it cannot imply an overlay exists.
        let decisions = Self.decisionMap(from: revision)
        annotationState = DatasetAnnotationState(predictionRun: prediction, parentPredictionRunID: parentID,
                                                 mediaFrameCount: metadata.frameCount, annotationQueue: queue,
                                                 currentSourceFrameIndex: preferredFrame ?? 0, decisions: decisions,
                                                 annotatorID: annotatorID, revisionID: revision?.revisionID ?? "")
        activeRevisionID = revision?.revisionID
        access = .editable
        persistSession()
    }

    public func selectFilter(_ filter: DatasetSidebarFilter) { selectedFilter = filter; persistSession() }
    public func dispatch(_ action: DatasetAnnotationAction) {
        guard case .editable = access, let state = annotationState else { return }
        if case .acceptUnresolvedFrame(let at) = action {
            // Each accepted point becomes an independent append-only snapshot.
            for landmark in GolfLandmark.allCases where state.decisions[AnnotationDecisionKey(frameIndex: state.currentSourceFrameIndex, landmark: landmark)] == nil {
                dispatch(.acceptPrediction(landmark, decidedAt: at))
            }
            return
        }
        annotationState = DatasetAnnotationReducer.reduce(state, action)
        if case .step = action {
            persistSession()
            Task { await self.loadExactCurrentFrame() }
            return
        }
        guard let next = annotationState, next != state else { return }
        saveRevisionSnapshot(from: next)
        persistSession()
    }

    /// Uses the exact source-frame session rather than AVPlayer seek snapshots.
    public func loadExactCurrentFrame() async {
        guard case .editable = access, let frameIndex = annotationState?.currentSourceFrameIndex else { return }
        isFrameLoading = true
        defer { isFrameLoading = false }
        do {
            let frame = try await frameSession.frame(at: frameIndex)
            fullFrameImage = frame.image
            currentSourceTime = frame.presentationTime.seconds
        } catch {
            access = .readOnly(reason: "无法解码精确源帧 \(frameIndex)。")
        }
    }

    private func saveRevisionSnapshot(from state: DatasetAnnotationState) {
        let revisionID = UUID().uuidString.lowercased()
        let grouped = Dictionary(grouping: state.decisions, by: { $0.key.frameIndex })
        let frames = grouped.keys.sorted().map { frame in
            GolfFrameRevision(sourceFrameIndex: frame, decisions: (grouped[frame] ?? []).map(\.value).sorted {
                $0.landmark.rawValue < $1.landmark.rawValue
            })
        }
        let revision = GolfAnnotationRevision(revisionID: revisionID, clipID: selectedClipID ?? "",
                                              parentPredictionRunID: state.parentPredictionRunID, annotatorID: annotatorID,
                                              createdAt: Date(), frameRevisions: frames)
        do {
            try store.saveRevision(revision)
            activeRevisionID = revisionID
            annotationState = DatasetAnnotationState(predictionRun: state.predictionRun, parentPredictionRunID: state.parentPredictionRunID,
                                                     mediaFrameCount: state.mediaFrameCount, annotationQueue: state.annotationQueue,
                                                     currentSourceFrameIndex: state.currentSourceFrameIndex, decisions: state.decisions,
                                                     annotatorID: state.annotatorID, revisionID: revisionID)
        } catch { access = .readOnly(reason: "无法原子保存标注修订：\(error.localizedDescription)") }
    }

    func split(for clip: GolfClipIdentity) -> GolfDatasetSplit { (try? store.loadSnapshot().registry?.split(for: clip.golferID)) ?? .heldOut }
    private func latestRevision(for clipID: String, preferredID: String?) -> GolfAnnotationRevision? {
        let revisions = ((try? store.loadSnapshot().revisions) ?? []).filter { $0.clipID == clipID }
        if let preferredID, let revision = revisions.first(where: { $0.revisionID == preferredID }) { return revision }
        return revisions.max { ($0.createdAt, $0.revisionID) < ($1.createdAt, $1.revisionID) }
    }
    private func persistSession() {
        guard let clipID = selectedClipID else { return }
        sessionPersistence.save(.init(clipID: clipID, currentSourceFrameIndex: annotationState?.currentSourceFrameIndex ?? 0,
                                      filter: selectedFilter, activeRevisionID: activeRevisionID, securityScopedBookmark: bookmark))
    }
    private static func decisionMap(from revision: GolfAnnotationRevision?) -> [AnnotationDecisionKey: GolfAnnotationDecision] {
        Dictionary(uniqueKeysWithValues: (revision?.frameRevisions ?? []).flatMap { frame in
            frame.decisions.map { (AnnotationDecisionKey(frameIndex: frame.sourceFrameIndex, landmark: $0.landmark), $0) }
        })
    }
}

import Combine
import CoreGraphics
import CoreMedia
import Foundation

public enum DatasetReviewMode: String, Codable, Equatable, Sendable {
    case blindIndependentPass
    case predictionFirst
}

/// Mode-level overlay policy. A blind pass never receives prediction data at
/// the presentation boundary, even when a parent run ID is kept for provenance.
public struct DatasetAnnotationPresentation: Equatable, Sendable {
    public let split: GolfDatasetSplit
    public let reviewMode: DatasetReviewMode
    public let prediction: GolfPredictionRun?

    public init(
        split: GolfDatasetSplit,
        reviewMode: DatasetReviewMode,
        prediction: GolfPredictionRun?
    ) {
        self.split = split
        self.reviewMode = reviewMode
        self.prediction = prediction
    }

    public var visiblePredictionPoints: [GolfLandmark: GolfPredictionPoint] {
        guard reviewMode == .predictionFirst, split != .heldOut else { return [:] }
        return prediction?.frames.first?.points ?? [:]
    }

    public var showsConfidence: Bool {
        reviewMode == .predictionFirst && split != .heldOut && prediction != nil
    }

    public var allowsAcceptPrediction: Bool {
        !visiblePredictionPoints.isEmpty
    }
}

public enum DatasetWorkspaceAccess: Equatable, Sendable {
    case editable
    case readOnly(reason: String)
}

private enum DatasetWorkspaceControllerError: LocalizedError {
    case missingRevision(String)
    case unreadableRevisionHistory(String)

    var errorDescription: String? {
        switch self {
        case .missingRevision(let revisionID):
            return "上次活动修订 \(revisionID) 已不存在，已停止恢复。"
        case .unreadableRevisionHistory(let reason):
            return "无法读取标注修订历史：\(reason)"
        }
    }
}

/// Cursor state is intentionally separate from immutable annotation revisions
/// and from the per-clip bookmark repository.
public struct DatasetWorkspaceSessionRecord: Codable, Equatable, Sendable {
    public let clipID: String
    public let currentSourceFrameIndex: Int
    public let filter: DatasetSidebarFilter
    public let activeRevisionID: String?
    public let activePredictionRunID: String?

    public init(
        clipID: String,
        currentSourceFrameIndex: Int,
        filter: DatasetSidebarFilter,
        activeRevisionID: String?,
        activePredictionRunID: String? = nil
    ) {
        self.clipID = clipID
        self.currentSourceFrameIndex = currentSourceFrameIndex
        self.filter = filter
        self.activeRevisionID = activeRevisionID
        self.activePredictionRunID = activePredictionRunID
    }
}

public protocol DatasetWorkspaceSessionPersisting: AnyObject {
    func load() -> DatasetWorkspaceSessionRecord?
    func save(_ record: DatasetWorkspaceSessionRecord)
}

public final class UserDefaultsDatasetWorkspaceSessionPersistence:
    DatasetWorkspaceSessionPersisting
{
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "SwingArcDataset.workspaceSession.v2"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> DatasetWorkspaceSessionRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DatasetWorkspaceSessionRecord.self, from: data)
    }

    public func save(_ record: DatasetWorkspaceSessionRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }
}

public final class InMemoryDatasetWorkspaceSessionPersistence:
    DatasetWorkspaceSessionPersisting
{
    private var record: DatasetWorkspaceSessionRecord?

    public init() {}
    public func load() -> DatasetWorkspaceSessionRecord? { record }
    public func save(_ record: DatasetWorkspaceSessionRecord) { self.record = record }
}

public protocol DatasetWorkspaceBookmarkPersisting: AnyObject {
    func loadBookmark(for clipID: String) -> Data?
    func saveBookmark(_ bookmark: Data, for clipID: String)
}

public final class UserDefaultsDatasetWorkspaceBookmarkPersistence:
    DatasetWorkspaceBookmarkPersisting
{
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "SwingArcDataset.videoBookmarks.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func loadBookmark(for clipID: String) -> Data? {
        loadAll()[clipID]
    }

    public func saveBookmark(_ bookmark: Data, for clipID: String) {
        var bookmarks = loadAll()
        bookmarks[clipID] = bookmark
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: key)
    }

    private func loadAll() -> [String: Data] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Data].self, from: data)) ?? [:]
    }
}

public final class InMemoryDatasetWorkspaceBookmarkPersistence:
    DatasetWorkspaceBookmarkPersisting
{
    private var bookmarks: [String: Data] = [:]

    public init() {}
    public func loadBookmark(for clipID: String) -> Data? { bookmarks[clipID] }
    public func saveBookmark(_ bookmark: Data, for clipID: String) {
        bookmarks[clipID] = bookmark
    }
}

/// These narrow reads prevent the annotation controller from using
/// `loadSnapshot()`, which eagerly decodes every prediction payload.
public protocol DatasetWorkspaceStore: AnyObject {
    func loadClips() throws -> [GolfClipIdentity]
    func loadRegistry() throws -> GolferRegistry
    func loadRevisions(clipID: String) throws -> [GolfAnnotationRevision]
    func listPredictionRunIDs(clipID: String) throws -> [String]
    func loadPrediction(
        clipID: String,
        predictionRunID: String
    ) throws -> GolfPredictionRun
    func saveRevision(_ revision: GolfAnnotationRevision) throws
}

extension GolfDatasetStore: DatasetWorkspaceStore {}

public struct DatasetWorkspaceMediaMetadata: Equatable, Sendable {
    public let mediaSHA256: String
    public let frameCount: Int
    public let timelineSHA256: String
    public let orientedWidth: Int
    public let orientedHeight: Int

    public init(
        mediaSHA256: String,
        frameCount: Int,
        timelineSHA256: String,
        orientedWidth: Int = 0,
        orientedHeight: Int = 0
    ) {
        self.mediaSHA256 = mediaSHA256
        self.frameCount = frameCount
        self.timelineSHA256 = timelineSHA256
        self.orientedWidth = orientedWidth
        self.orientedHeight = orientedHeight
    }
}

public struct DatasetWorkspaceDecodedFrame: @unchecked Sendable {
    public let image: CGImage
    public let sourceTime: Double
}

@MainActor
public protocol DatasetWorkspaceMediaAccessing: AnyObject {
    var activeURL: URL? { get }
    func open(bookmark: Data) async throws -> DatasetWorkspaceMediaMetadata
    func frame(at sourceFrameIndex: Int) async throws -> DatasetWorkspaceDecodedFrame
    func close()
}

@MainActor
public protocol DatasetWorkspaceMediaAccessFactory: AnyObject {
    /// Every call must return a new independently owned media session.
    func makeMediaAccess() -> DatasetWorkspaceMediaAccessing
}

@MainActor
public final class SecurityScopedExactVideoMediaAccessFactory:
    DatasetWorkspaceMediaAccessFactory
{
    public init() {}

    public func makeMediaAccess() -> DatasetWorkspaceMediaAccessing {
        SecurityScopedExactVideoMediaAccess()
    }
}

@MainActor
public final class SecurityScopedExactVideoMediaAccess:
    DatasetWorkspaceMediaAccessing
{
    private let frameSession = ExactVideoFrameSession()
    public private(set) var activeURL: URL?

    public init() {}

    deinit {
        activeURL?.stopAccessingSecurityScopedResource()
    }

    public func open(bookmark: Data) async throws -> DatasetWorkspaceMediaMetadata {
        close()
        guard !bookmark.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard !stale, url.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }
        do {
            let metadata = try await frameSession.open(url: url)
            let mediaSHA256 = try await Task.detached(priority: .utility) {
                try AnnotationStore.mediaSHA256(url: url)
            }.value
            activeURL = url
            return DatasetWorkspaceMediaMetadata(
                mediaSHA256: mediaSHA256,
                frameCount: metadata.frameCount,
                timelineSHA256: metadata.timelineSHA256,
                orientedWidth: metadata.orientedWidth,
                orientedHeight: metadata.orientedHeight
            )
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    public func frame(
        at sourceFrameIndex: Int
    ) async throws -> DatasetWorkspaceDecodedFrame {
        let frame = try await frameSession.frame(at: sourceFrameIndex)
        return DatasetWorkspaceDecodedFrame(
            image: frame.image,
            sourceTime: CMTimeGetSeconds(frame.presentationTime)
        )
    }

    public func close() {
        activeURL?.stopAccessingSecurityScopedResource()
        activeURL = nil
    }
}

@MainActor
public final class DatasetWorkspaceController: ObservableObject {
    private let store: DatasetWorkspaceStore
    private let sessionPersistence: DatasetWorkspaceSessionPersisting
    private let bookmarkPersistence: DatasetWorkspaceBookmarkPersisting
    private let mediaAccessFactory: DatasetWorkspaceMediaAccessFactory
    private let annotatorID: String
    private var activeMediaAccess: DatasetWorkspaceMediaAccessing?
    private var selectionGeneration = 0
    private var frameLoadGeneration = 0

    @Published public private(set) var clips: [GolfClipIdentity] = []
    @Published public private(set) var selectedClipID: String?
    @Published public private(set) var selectedFilter: DatasetSidebarFilter = .allClips
    @Published public private(set) var annotationState: DatasetAnnotationState?
    @Published public private(set) var access: DatasetWorkspaceAccess =
        .readOnly(reason: "尚未选择 clip")
    @Published public private(set) var activeRevisionID: String?
    @Published public private(set) var activePredictionRunID: String?
    @Published public private(set) var fullFrameImage: CGImage?
    @Published public private(set) var currentSourceTime: Double?
    @Published public private(set) var isFrameLoading = false
    @Published public private(set) var selectedVideoURL: URL?

    public init(
        store: DatasetWorkspaceStore,
        sessionPersistence: DatasetWorkspaceSessionPersisting,
        bookmarkPersistence: DatasetWorkspaceBookmarkPersisting =
            UserDefaultsDatasetWorkspaceBookmarkPersistence(),
        mediaAccessFactory: DatasetWorkspaceMediaAccessFactory? = nil,
        annotatorID: String
    ) {
        self.store = store
        self.sessionPersistence = sessionPersistence
        self.bookmarkPersistence = bookmarkPersistence
        self.mediaAccessFactory = mediaAccessFactory
            ?? SecurityScopedExactVideoMediaAccessFactory()
        self.annotatorID = annotatorID
        reloadClipList()
    }

    public var selectedClip: GolfClipIdentity? {
        guard let selectedClipID else { return nil }
        return clips.first { $0.clipID == selectedClipID }
    }

    public var fullFrameImageSize: CGSize {
        if let fullFrameImage {
            return CGSize(width: fullFrameImage.width, height: fullFrameImage.height)
        }
        guard let selectedClip else { return .zero }
        return CGSize(
            width: selectedClip.media.orientedWidth,
            height: selectedClip.media.orientedHeight
        )
    }

    public func reloadClipList() {
        clips = (try? store.loadClips()) ?? []
    }

    public func rememberBookmark(_ bookmark: Data, for clipID: String) {
        guard !bookmark.isEmpty else { return }
        bookmarkPersistence.saveBookmark(bookmark, for: clipID)
    }

    public func registerImportedClip(
        clipID: String,
        securityScopedBookmark: Data
    ) async {
        rememberBookmark(securityScopedBookmark, for: clipID)
        reloadClipList()
        await selectClip(clipID)
    }

    public func restore() async {
        reloadClipList()
        guard let record = sessionPersistence.load() else { return }
        selectedFilter = record.filter
        await selectClip(
            record.clipID,
            preferredRevisionID: record.activeRevisionID,
            preferredPredictionRunID: record.activePredictionRunID,
            preferredFrame: record.currentSourceFrameIndex
        )
    }

    public func selectClip(
        _ clipID: String,
        predictionRunID: String? = nil
    ) async {
        await selectClip(
            clipID,
            preferredRevisionID: nil,
            preferredPredictionRunID: predictionRunID,
            preferredFrame: nil
        )
    }

    private func selectClip(
        _ clipID: String,
        preferredRevisionID: String?,
        preferredPredictionRunID: String?,
        preferredFrame: Int?
    ) async {
        selectionGeneration += 1
        frameLoadGeneration += 1
        let generation = selectionGeneration
        guard let clip = clips.first(where: { $0.clipID == clipID }) else {
            clearSelection(reason: "找不到所选 clip。")
            return
        }
        selectedClipID = clipID
        annotationState = nil
        activeRevisionID = nil
        activePredictionRunID = nil
        fullFrameImage = nil
        currentSourceTime = nil
        isFrameLoading = false
        activeMediaAccess?.close()
        activeMediaAccess = nil
        selectedVideoURL = nil

        guard let bookmark = bookmarkPersistence.loadBookmark(for: clipID),
              !bookmark.isEmpty else {
            access = .readOnly(reason: "视频书签不可用或已撤销。")
            persistSession()
            return
        }

        let candidateMediaAccess = mediaAccessFactory.makeMediaAccess()
        do {
            let metadata = try await candidateMediaAccess.open(
                bookmark: bookmark
            )
            guard generation == selectionGeneration else {
                candidateMediaAccess.close()
                return
            }
            let revision = try latestRevision(
                for: clipID,
                preferredID: preferredRevisionID
            )
            let predictionRunIDs = try store.listPredictionRunIDs(
                clipID: clipID
            )
            let parentPredictionRunID: String
            if let revision {
                parentPredictionRunID = revision.parentPredictionRunID
            } else if let preferredPredictionRunID {
                guard predictionRunIDs.contains(preferredPredictionRunID) else {
                    candidateMediaAccess.close()
                    access = .readOnly(reason: "指定的预测运行不存在。")
                    persistSession()
                    return
                }
                parentPredictionRunID = preferredPredictionRunID
            } else if predictionRunIDs.count == 1 {
                parentPredictionRunID = predictionRunIDs[0]
            } else if predictionRunIDs.count > 1 {
                candidateMediaAccess.close()
                access = .readOnly(reason: "存在多个预测运行，必须明确选择一个运行。")
                persistSession()
                return
            } else {
                parentPredictionRunID = ""
            }
            try openVerifiedClip(
                clip: clip,
                split: split(for: clip),
                parentPredictionRunID: parentPredictionRunID,
                metadata: metadata,
                queue: [],
                preferredRevisionID: revision?.revisionID,
                preferredFrame: preferredFrame
            )
            guard case .editable = access else {
                if parentPredictionRunID.isEmpty,
                   Self.mediaIdentityMatches(clip: clip, metadata: metadata) {
                    activeMediaAccess = candidateMediaAccess
                    selectedVideoURL = candidateMediaAccess.activeURL
                    return
                }
                candidateMediaAccess.close()
                return
            }
            activeMediaAccess = candidateMediaAccess
            selectedVideoURL = candidateMediaAccess.activeURL
            await loadExactCurrentFrame()
        } catch let error as DatasetWorkspaceControllerError {
            candidateMediaAccess.close()
            guard generation == selectionGeneration else { return }
            activeMediaAccess?.close()
            activeMediaAccess = nil
            selectedVideoURL = nil
            access = .readOnly(reason: error.localizedDescription)
        } catch {
            candidateMediaAccess.close()
            guard generation == selectionGeneration else { return }
            activeMediaAccess?.close()
            activeMediaAccess = nil
            selectedVideoURL = nil
            access = .readOnly(
                reason: "无法打开或核验视频书签：\(error.localizedDescription)"
            )
            persistSession()
        }
    }

    /// Pure verified-open boundary used by behavior tests and the live media
    /// selection path. It never resolves a bookmark or decodes a frame.
    public func openVerifiedClip(
        clip: GolfClipIdentity,
        split: GolfDatasetSplit,
        parentPredictionRunID: String,
        metadata: DatasetWorkspaceMediaMetadata,
        queue: [GolfAnnotationQueueItem],
        preferredRevisionID: String? = nil,
        preferredFrame: Int? = nil
    ) throws {
        selectedClipID = clip.clipID
        guard Self.mediaIdentityMatches(clip: clip, metadata: metadata) else {
            annotationState = nil
            access = .readOnly(reason: "媒体、帧数或源帧时间线与 clip 身份不匹配。")
            persistSession()
            return
        }

        let revision = try latestRevision(
            for: clip.clipID,
            preferredID: preferredRevisionID
        )
        let parentID = revision?.parentPredictionRunID
            ?? parentPredictionRunID
        guard !parentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            annotationState = nil
            access = .readOnly(reason: "缺少可追溯的预测运行 ID。")
            persistSession()
            return
        }

        // Blind boundary: held-out paths never call loadPrediction.
        let prediction: GolfPredictionRun?
        if split == .heldOut {
            prediction = nil
        } else {
            prediction = try? store.loadPrediction(
                clipID: clip.clipID,
                predictionRunID: parentID
            )
        }

        annotationState = DatasetAnnotationState(
            predictionRun: prediction,
            parentPredictionRunID: parentID,
            mediaFrameCount: metadata.frameCount,
            annotationQueue: queue,
            currentSourceFrameIndex: preferredFrame ?? 0,
            decisions: Self.decisionMap(from: revision),
            annotatorID: annotatorID,
            revisionID: revision?.revisionID ?? ""
        )
        activeRevisionID = revision?.revisionID
        activePredictionRunID = parentID
        access = .editable
        persistSession()
    }

    private static func mediaIdentityMatches(
        clip: GolfClipIdentity,
        metadata: DatasetWorkspaceMediaMetadata
    ) -> Bool {
        clip.media.sha256 == metadata.mediaSHA256
            && clip.media.frameCount == metadata.frameCount
            && clip.media.timelineSHA256 == metadata.timelineSHA256
    }

    public func selectFilter(_ filter: DatasetSidebarFilter) {
        selectedFilter = filter
        persistSession()
    }

    public func dispatch(_ action: DatasetAnnotationAction) {
        guard case .editable = access, let state = annotationState else { return }
        if case .acceptUnresolvedFrame(let decidedAt) = action {
            for landmark in GolfLandmark.allCases where state.decisions[
                AnnotationDecisionKey(
                    frameIndex: state.currentSourceFrameIndex,
                    landmark: landmark
                )
            ] == nil {
                dispatch(.acceptPrediction(landmark, decidedAt: decidedAt))
            }
            return
        }

        let next = DatasetAnnotationReducer.reduce(state, action)
        if case .step = action {
            annotationState = next
            persistSession()
            if activeMediaAccess != nil {
                Task { await self.loadExactCurrentFrame() }
            }
            return
        }
        guard next != state else { return }
        saveRevisionSnapshot(from: next)
        persistSession()
    }

    public func loadExactCurrentFrame() async {
        guard case .editable = access,
              let frameIndex = annotationState?.currentSourceFrameIndex else {
            return
        }
        frameLoadGeneration += 1
        let generation = frameLoadGeneration
        isFrameLoading = true
        defer {
            if generation == frameLoadGeneration {
                isFrameLoading = false
            }
        }
        do {
            guard let mediaAccess = activeMediaAccess else {
                throw CocoaError(.fileNoSuchFile)
            }
            let frame = try await mediaAccess.frame(at: frameIndex)
            guard generation == frameLoadGeneration,
                  frameIndex == annotationState?.currentSourceFrameIndex else {
                return
            }
            fullFrameImage = frame.image
            currentSourceTime = frame.sourceTime
        } catch {
            guard generation == frameLoadGeneration else { return }
            access = .readOnly(reason: "无法解码精确源帧 \(frameIndex)。")
        }
    }

    public func closeMedia() {
        frameLoadGeneration += 1
        isFrameLoading = false
        activeMediaAccess?.close()
        activeMediaAccess = nil
    }

    func split(for clip: GolfClipIdentity) -> GolfDatasetSplit {
        (try? store.loadRegistry().split(for: clip.golferID)) ?? .heldOut
    }

    private func saveRevisionSnapshot(from state: DatasetAnnotationState) {
        let revisionID = UUID().uuidString.lowercased()
        let grouped = Dictionary(grouping: state.decisions) { $0.key.frameIndex }
        let frames = grouped.keys.sorted().map { frameIndex in
            GolfFrameRevision(
                sourceFrameIndex: frameIndex,
                decisions: (grouped[frameIndex] ?? [])
                    .map(\.value)
                    .sorted { $0.landmark.rawValue < $1.landmark.rawValue }
            )
        }
        let revision = GolfAnnotationRevision(
            revisionID: revisionID,
            clipID: selectedClipID ?? "",
            parentPredictionRunID: state.parentPredictionRunID,
            annotatorID: annotatorID,
            createdAt: Date(),
            frameRevisions: frames
        )
        do {
            try store.saveRevision(revision)
            activeRevisionID = revisionID
            annotationState = DatasetAnnotationState(
                predictionRun: state.predictionRun,
                parentPredictionRunID: state.parentPredictionRunID,
                mediaFrameCount: state.mediaFrameCount,
                annotationQueue: state.annotationQueue,
                currentSourceFrameIndex: state.currentSourceFrameIndex,
                decisions: state.decisions,
                annotatorID: state.annotatorID,
                revisionID: revisionID
            )
        } catch {
            access = .readOnly(
                reason: "无法原子保存标注修订：\(error.localizedDescription)"
            )
        }
    }

    private func latestRevision(
        for clipID: String,
        preferredID: String?
    ) throws -> GolfAnnotationRevision? {
        let revisions: [GolfAnnotationRevision]
        do {
            revisions = try store.loadRevisions(clipID: clipID)
        } catch {
            throw DatasetWorkspaceControllerError.unreadableRevisionHistory(
                error.localizedDescription
            )
        }
        if let preferredID {
            guard let preferred = revisions.first(where: {
                $0.revisionID == preferredID
            }) else {
                throw DatasetWorkspaceControllerError.missingRevision(
                    preferredID
                )
            }
            return preferred
        }
        return revisions.max {
            ($0.createdAt, $0.revisionID) < ($1.createdAt, $1.revisionID)
        }
    }

    private func persistSession() {
        guard let clipID = selectedClipID else { return }
        sessionPersistence.save(
            DatasetWorkspaceSessionRecord(
                clipID: clipID,
                currentSourceFrameIndex:
                    annotationState?.currentSourceFrameIndex ?? 0,
                filter: selectedFilter,
                activeRevisionID: activeRevisionID,
                activePredictionRunID: activePredictionRunID
            )
        )
    }

    private func clearSelection(reason: String) {
        selectionGeneration += 1
        frameLoadGeneration += 1
        activeMediaAccess?.close()
        activeMediaAccess = nil
        selectedClipID = nil
        annotationState = nil
        activeRevisionID = nil
        activePredictionRunID = nil
        fullFrameImage = nil
        currentSourceTime = nil
        isFrameLoading = false
        selectedVideoURL = nil
        access = .readOnly(reason: reason)
    }

    private static func decisionMap(
        from revision: GolfAnnotationRevision?
    ) -> [AnnotationDecisionKey: GolfAnnotationDecision] {
        Dictionary(
            uniqueKeysWithValues: (revision?.frameRevisions ?? []).flatMap {
                frame in
                frame.decisions.map {
                    (
                        AnnotationDecisionKey(
                            frameIndex: frame.sourceFrameIndex,
                            landmark: $0.landmark
                        ),
                        $0
                    )
                }
            }
        )
    }
}

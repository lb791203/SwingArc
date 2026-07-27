import Foundation

struct DatasetVerifiedMedia: Equatable, Sendable {
    let media: GolfMediaIdentity
    let pPointTruthSHA256: String
    let pPointTruthView: GolfDatasetView
    let pPointTruthData: Data

    init(
        media: GolfMediaIdentity,
        pPointTruthSHA256: String,
        pPointTruthView: GolfDatasetView,
        pPointTruthData: Data
    ) {
        self.media = media
        self.pPointTruthSHA256 = pPointTruthSHA256
        self.pPointTruthView = pPointTruthView
        self.pPointTruthData = pPointTruthData
    }
}

enum DatasetImportIssue: Error, Equatable, Sendable {
    case golferNotRegistered(String)
    case golferRegistrationFailed(String)
    case pPointTruthViewMismatch(
        expected: GolfDatasetView,
        selected: GolfDatasetView
    )
    case splitLocked(
        golferID: String,
        locked: GolfDatasetSplit,
        requested: GolfDatasetSplit
    )
    case incompleteIdentity
    case invalidClipID
}

struct DatasetImportState: Equatable, Sendable {
    var registry: GolferRegistry?
    var verifiedMedia: DatasetVerifiedMedia?
    var securityScopedBookmark: Data?
    var golferID: String?
    var view: GolfDatasetView?
    var handedness: GolfDatasetHandedness?
    var authorization: GolfDatasetAuthorization?
    var issue: DatasetImportIssue?

    static let empty = DatasetImportState(
        registry: nil,
        verifiedMedia: nil,
        securityScopedBookmark: nil,
        golferID: nil,
        view: nil,
        handedness: nil,
        authorization: nil,
        issue: nil
    )

    var split: GolfDatasetSplit? {
        guard let golferID else { return nil }
        return registry?.split(for: golferID)
    }

    var canImport: Bool {
        registry != nil
            && verifiedMedia != nil
            && verifiedMedia?.pPointTruthData.isEmpty == false
            && securityScopedBookmark?.isEmpty == false
            && golferID != nil
            && split != nil
            && view != nil
            && handedness != nil
            && authorization != nil
            && issue == nil
    }

    func makeClip(clipID rawClipID: String) throws -> GolfClipIdentity {
        let clipID = rawClipID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clipID.isEmpty, clipID == rawClipID,
              !clipID.contains("/"), !clipID.contains("..") else {
            throw DatasetImportIssue.invalidClipID
        }
        guard canImport,
              let verifiedMedia,
              let golferID,
              let view,
              let handedness,
              let authorization else {
            throw DatasetImportIssue.incompleteIdentity
        }
        return GolfClipIdentity(
            clipID: clipID,
            golferID: golferID,
            media: verifiedMedia.media,
            view: view,
            handedness: handedness,
            authorization: authorization,
            pPointTruthSHA256: verifiedMedia.pPointTruthSHA256
        )
    }
}

enum DatasetImportAction: Equatable, Sendable {
    case loadRegistry(GolferRegistry)
    case mediaVerified(
        media: DatasetVerifiedMedia,
        securityScopedBookmark: Data
    )
    case assignGolfer(String)
    case registerGolfer(
        golferID: String,
        split: GolfDatasetSplit,
        at: Date
    )
    case setView(GolfDatasetView)
    case setHandedness(GolfDatasetHandedness)
    case setAuthorization(GolfDatasetAuthorization)
    case requestSplitOverride(GolfDatasetSplit)
    case resetMedia
}

enum DatasetImportReducer {
    static func reduce(
        _ state: DatasetImportState,
        _ action: DatasetImportAction
    ) -> DatasetImportState {
        var next = state
        switch action {
        case .loadRegistry(let registry):
            next.registry = registry
            next.issue = identityIssue(in: next)

        case .mediaVerified(let media, let bookmark):
            next.verifiedMedia = media
            next.securityScopedBookmark = bookmark
            next.issue = identityIssue(in: next)

        case .assignGolfer(let rawGolferID):
            let golferID = rawGolferID.trimmingCharacters(in: .whitespacesAndNewlines)
            next.golferID = golferID.isEmpty ? nil : golferID
            next.issue = identityIssue(in: next)

        case .registerGolfer(let golferID, let split, let date):
            guard let registry = next.registry else {
                next.issue = .golferRegistrationFailed(golferID)
                break
            }
            do {
                next.registry = try registry.assign(
                    golferID: golferID,
                    split: split,
                    at: date
                )
                next.golferID = golferID
                next.issue = identityIssue(in: next)
            } catch {
                next.issue = .golferRegistrationFailed(golferID)
            }

        case .setView(let view):
            next.view = view
            next.issue = identityIssue(in: next)

        case .setHandedness(let handedness):
            next.handedness = handedness
            next.issue = identityIssue(in: next)

        case .setAuthorization(let authorization):
            next.authorization = authorization
            next.issue = identityIssue(in: next)

        case .requestSplitOverride(let requested):
            guard let golferID = next.golferID,
                  let locked = next.registry?.split(for: golferID) else {
                next.issue = identityIssue(in: next)
                break
            }
            next.issue = locked == requested
                ? nil
                : .splitLocked(
                    golferID: golferID,
                    locked: locked,
                    requested: requested
                )

        case .resetMedia:
            next.verifiedMedia = nil
            next.securityScopedBookmark = nil
            next.issue = identityIssue(in: next)
        }
        return next
    }

    private static func identityIssue(
        in state: DatasetImportState
    ) -> DatasetImportIssue? {
        if let golferID = state.golferID,
           state.registry?.split(for: golferID) == nil {
            return .golferNotRegistered(golferID)
        }
        if let expected = state.verifiedMedia?.pPointTruthView,
           let selected = state.view,
           expected != selected {
            return .pPointTruthViewMismatch(
                expected: expected,
                selected: selected
            )
        }
        return nil
    }
}

extension DatasetImportIssue: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .golferNotRegistered(let golferID):
            return "匿名球员 \(golferID) 尚未锁定数据集拆分。"
        case .golferRegistrationFailed(let golferID):
            return "无法注册匿名球员 \(golferID)。"
        case .pPointTruthViewMismatch(let expected, let selected):
            return "P 点真值机位为 \(expected.rawValue)，不能标记为 \(selected.rawValue)。"
        case .splitLocked(let golferID, let locked, let requested):
            return "\(golferID) 已锁定为 \(locked.rawValue)，不能改为 \(requested.rawValue)。"
        case .incompleteIdentity:
            return "请完成媒体核验、golferID、机位、持杆和授权。"
        case .invalidClipID:
            return "clipID 不能为空，也不能包含路径字符。"
        }
    }
}

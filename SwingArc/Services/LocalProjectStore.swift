import Foundation

struct LocalAnalysisProject: Codable, Equatable {
    var drawings: [DrawingElement]
    var keyframes: [KeyframeMarker]
    var isKeyframeMode: Bool
    var showPoseSkeleton: Bool
    var showHeadStability: Bool
    var showSpineAngle: Bool
    var showGrid: Bool
    /// The selected camera angle is explicit evidence context. Imported
    /// projects may leave it nil, which intentionally withholds view-specific
    /// technique findings until the user has recorded through a practice mode.
    var practiceCameraView: PracticeCameraView?
    /// Per-video user corrections are retained as truth for this project.
    /// They are optional in stored payloads so projects saved before this
    /// feature continue to decode unchanged.
    var stageCorrections: [StageCorrection]

    init(
        drawings: [DrawingElement],
        keyframes: [KeyframeMarker],
        isKeyframeMode: Bool,
        showPoseSkeleton: Bool,
        showHeadStability: Bool,
        showSpineAngle: Bool,
        showGrid: Bool,
        practiceCameraView: PracticeCameraView? = nil,
        stageCorrections: [StageCorrection] = []
    ) {
        self.drawings = drawings
        self.keyframes = keyframes
        self.isKeyframeMode = isKeyframeMode
        self.showPoseSkeleton = showPoseSkeleton
        self.showHeadStability = showHeadStability
        self.showSpineAngle = showSpineAngle
        self.showGrid = showGrid
        self.practiceCameraView = practiceCameraView
        self.stageCorrections = stageCorrections
    }

    private enum CodingKeys: String, CodingKey {
        case drawings
        case keyframes
        case isKeyframeMode
        case showPoseSkeleton
        case showHeadStability
        case showSpineAngle
        case showGrid
        case practiceCameraView
        case stageCorrections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            drawings: try container.decode([DrawingElement].self, forKey: .drawings),
            keyframes: try container.decode([KeyframeMarker].self, forKey: .keyframes),
            isKeyframeMode: try container.decode(Bool.self, forKey: .isKeyframeMode),
            showPoseSkeleton: try container.decode(Bool.self, forKey: .showPoseSkeleton),
            showHeadStability: try container.decode(Bool.self, forKey: .showHeadStability),
            showSpineAngle: try container.decode(Bool.self, forKey: .showSpineAngle),
            showGrid: try container.decode(Bool.self, forKey: .showGrid),
            practiceCameraView: try container.decodeIfPresent(PracticeCameraView.self, forKey: .practiceCameraView),
            stageCorrections: try container.decodeIfPresent(
                [StageCorrection].self,
                forKey: .stageCorrections
            ) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(drawings, forKey: .drawings)
        try container.encode(keyframes, forKey: .keyframes)
        try container.encode(isKeyframeMode, forKey: .isKeyframeMode)
        try container.encode(showPoseSkeleton, forKey: .showPoseSkeleton)
        try container.encode(showHeadStability, forKey: .showHeadStability)
        try container.encode(showSpineAngle, forKey: .showSpineAngle)
        try container.encode(showGrid, forKey: .showGrid)
        try container.encodeIfPresent(practiceCameraView, forKey: .practiceCameraView)
        try container.encode(stageCorrections, forKey: .stageCorrections)
    }
}

private struct StoredProjectSummary: Codable, Equatable {
    let id: UUID
    let videoFileName: String
    var name: String
    var duration: Double
    var sourceFrameRate: Double
    var modifiedAt: Date
    var status: LocalProjectStatus

    init(_ summary: LocalProjectSummary) {
        id = summary.id
        videoFileName = summary.videoURL.lastPathComponent
        name = summary.name
        duration = summary.duration
        sourceFrameRate = summary.sourceFrameRate
        modifiedAt = summary.modifiedAt
        status = summary.status
    }

    func resolved(in directory: URL) -> LocalProjectSummary {
        LocalProjectSummary(
            id: id,
            videoURL: directory.appendingPathComponent(videoFileName),
            name: name,
            duration: duration,
            sourceFrameRate: sourceFrameRate,
            modifiedAt: modifiedAt,
            status: status
        )
    }
}

enum LocalProjectStore {
    private static let projectPrefix = "com.liangbo.swingarc.project."
    private static let lastVideoURLKey = "com.liangbo.swingarc.last-video-url"
    private static let projectIndexKey = "com.liangbo.swingarc.project-index"

    static func videoDirectory(fileManager: FileManager = .default) -> URL {
        let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("SwingArcVideos", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func load(for videoURL: URL, defaults: UserDefaults = .standard) -> LocalAnalysisProject? {
        guard let data = defaults.data(forKey: projectKey(for: videoURL)) else { return nil }
        return try? JSONDecoder().decode(LocalAnalysisProject.self, from: data)
    }

    @discardableResult
    static func save(
        _ project: LocalAnalysisProject,
        for videoURL: URL,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(project) else { return false }
        defaults.set(data, forKey: projectKey(for: videoURL))
        defaults.set(videoURL.lastPathComponent, forKey: lastVideoURLKey)
        return true
    }

    static func lastVideoURL(
        defaults: UserDefaults = .standard,
        videoDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let value = defaults.string(forKey: lastVideoURLKey) else { return nil }
        let directory = videoDirectory ?? self.videoDirectory(fileManager: fileManager)
        let legacyURL = URL(string: value)
        let fileName = legacyURL?.lastPathComponent.isEmpty == false
            ? legacyURL!.lastPathComponent
            : value
        let resolvedURL = directory.appendingPathComponent(fileName)

        if let legacyURL, legacyURL.isFileURL, legacyURL != resolvedURL {
            migratePayload(from: legacyURL, to: resolvedURL, defaults: defaults)
            defaults.set(fileName, forKey: lastVideoURLKey)
        }
        return resolvedURL
    }

    static func projects(
        defaults: UserDefaults = .standard,
        videoDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [LocalProjectSummary] {
        let directory = videoDirectory ?? self.videoDirectory(fileManager: fileManager)

        if let data = defaults.data(forKey: projectIndexKey),
           let stored = try? JSONDecoder().decode([StoredProjectSummary].self, from: data) {
            return stored
                .map { $0.resolved(in: directory) }
                .sorted { $0.modifiedAt > $1.modifiedAt }
        }

        if let data = defaults.data(forKey: projectIndexKey),
           let legacy = try? JSONDecoder().decode([LocalProjectSummary].self, from: data) {
            let migrated = legacy.map {
                migrateLegacySummary($0, to: directory, defaults: defaults)
            }
            saveIndex(migrated, defaults: defaults)
            return migrated.sorted { $0.modifiedAt > $1.modifiedAt }
        }

        guard let videoURL = lastVideoURL(
            defaults: defaults,
            videoDirectory: directory,
            fileManager: fileManager
        ) else {
            return []
        }
        let savedProject = load(for: videoURL, defaults: defaults)
        let status: LocalProjectStatus
        if savedProject?.drawings.isEmpty == false {
            status = .annotated
        } else if savedProject?.keyframes.isEmpty == false {
            status = .analyzed
        } else {
            status = .pending
        }
        let resourceValues = try? videoURL.resourceValues(forKeys: [.contentModificationDateKey])
        let modifiedAt = resourceValues?.contentModificationDate ?? Date()
        let migrated = LocalProjectSummary(
            videoURL: videoURL,
            name: "上次分析",
            duration: 0,
            sourceFrameRate: 0,
            modifiedAt: modifiedAt,
            status: status
        )
        saveIndex([migrated], defaults: defaults)
        return [migrated]
    }

    static func upsertSummary(
        _ summary: LocalProjectSummary,
        defaults: UserDefaults = .standard,
        videoDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        var items = projects(
            defaults: defaults,
            videoDirectory: videoDirectory,
            fileManager: fileManager
        )
        items.removeAll {
            $0.id == summary.id || $0.videoURL.lastPathComponent == summary.videoURL.lastPathComponent
        }
        items.append(summary)
        saveIndex(items, defaults: defaults)
    }

    static func rename(
        _ id: UUID,
        to name: String,
        defaults: UserDefaults = .standard,
        videoDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = projects(
            defaults: defaults,
            videoDirectory: videoDirectory,
            fileManager: fileManager
        )
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = trimmed
        items[index].modifiedAt = Date()
        saveIndex(items, defaults: defaults)
    }

    static func remove(
        _ id: UUID,
        defaults: UserDefaults = .standard,
        videoDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        var items = projects(
            defaults: defaults,
            videoDirectory: videoDirectory,
            fileManager: fileManager
        )
        guard let project = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        defaults.removeObject(forKey: projectKey(for: project.videoURL))
        saveIndex(items, defaults: defaults)
    }

    static func seedLegacyProjectForTesting(
        _ project: LocalAnalysisProject,
        summary: LocalProjectSummary,
        defaults: UserDefaults
    ) {
        guard let projectData = try? JSONEncoder().encode(project),
              let indexData = try? JSONEncoder().encode([summary]) else {
            return
        }
        defaults.set(projectData, forKey: legacyProjectKey(for: summary.videoURL))
        defaults.set(indexData, forKey: projectIndexKey)
        defaults.set(summary.videoURL.absoluteString, forKey: lastVideoURLKey)
    }

    private static func migrateLegacySummary(
        _ summary: LocalProjectSummary,
        to directory: URL,
        defaults: UserDefaults
    ) -> LocalProjectSummary {
        let resolvedURL = directory.appendingPathComponent(summary.videoURL.lastPathComponent)
        migratePayload(from: summary.videoURL, to: resolvedURL, defaults: defaults)
        if defaults.string(forKey: lastVideoURLKey) == summary.videoURL.absoluteString {
            defaults.set(resolvedURL.lastPathComponent, forKey: lastVideoURLKey)
        }
        return LocalProjectSummary(
            id: summary.id,
            videoURL: resolvedURL,
            name: summary.name,
            duration: summary.duration,
            sourceFrameRate: summary.sourceFrameRate,
            modifiedAt: summary.modifiedAt,
            status: summary.status
        )
    }

    private static func migratePayload(
        from legacyURL: URL,
        to resolvedURL: URL,
        defaults: UserDefaults
    ) {
        let oldKey = legacyProjectKey(for: legacyURL)
        let newKey = projectKey(for: resolvedURL)
        guard oldKey != newKey,
              defaults.data(forKey: newKey) == nil,
              let data = defaults.data(forKey: oldKey) else {
            return
        }
        defaults.set(data, forKey: newKey)
        defaults.removeObject(forKey: oldKey)
    }

    private static func saveIndex(_ projects: [LocalProjectSummary], defaults: UserDefaults) {
        let stored = projects.map(StoredProjectSummary.init)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: projectIndexKey)
    }

    private static func projectKey(for videoURL: URL) -> String {
        let identifier = Data(videoURL.lastPathComponent.utf8).base64EncodedString()
        return projectPrefix + identifier
    }

    private static func legacyProjectKey(for videoURL: URL) -> String {
        let identifier = Data(videoURL.absoluteString.utf8).base64EncodedString()
        return projectPrefix + identifier
    }
}

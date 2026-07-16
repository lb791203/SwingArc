import Foundation

struct LocalAnalysisProject: Codable, Equatable {
    var drawings: [DrawingElement]
    var keyframes: [KeyframeMarker]
    var isKeyframeMode: Bool
    var showPoseSkeleton: Bool
    var showHeadStability: Bool
    var showSpineAngle: Bool
    var showGrid: Bool
}

enum LocalProjectStore {
    private static let projectPrefix = "com.liangbo.swingarc.project."
    private static let lastVideoURLKey = "com.liangbo.swingarc.last-video-url"
    private static let projectIndexKey = "com.liangbo.swingarc.project-index"

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
        defaults.set(videoURL.absoluteString, forKey: lastVideoURLKey)
        return true
    }

    static func lastVideoURL(defaults: UserDefaults = .standard) -> URL? {
        guard let value = defaults.string(forKey: lastVideoURLKey) else { return nil }
        return URL(string: value)
    }

    static func projects(defaults: UserDefaults = .standard) -> [LocalProjectSummary] {
        if let data = defaults.data(forKey: projectIndexKey),
           let projects = try? JSONDecoder().decode([LocalProjectSummary].self, from: data) {
            return projects.sorted { $0.modifiedAt > $1.modifiedAt }
        }

        guard let videoURL = lastVideoURL(defaults: defaults),
              !videoURL.isFileURL || FileManager.default.fileExists(atPath: videoURL.path) else {
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

    static func upsertSummary(_ summary: LocalProjectSummary, defaults: UserDefaults = .standard) {
        var items = projects(defaults: defaults)
        items.removeAll { $0.id == summary.id || $0.videoURL == summary.videoURL }
        items.append(summary)
        saveIndex(items, defaults: defaults)
    }

    static func rename(_ id: UUID, to name: String, defaults: UserDefaults = .standard) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = projects(defaults: defaults)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = trimmed
        items[index].modifiedAt = Date()
        saveIndex(items, defaults: defaults)
    }

    static func remove(_ id: UUID, defaults: UserDefaults = .standard) {
        var items = projects(defaults: defaults)
        guard let project = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        defaults.removeObject(forKey: projectKey(for: project.videoURL))
        saveIndex(items, defaults: defaults)
    }

    private static func saveIndex(_ projects: [LocalProjectSummary], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        defaults.set(data, forKey: projectIndexKey)
    }

    private static func projectKey(for videoURL: URL) -> String {
        let identifier = Data(videoURL.absoluteString.utf8).base64EncodedString()
        return projectPrefix + identifier
    }
}

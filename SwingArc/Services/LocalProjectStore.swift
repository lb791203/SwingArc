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

    static func load(for videoURL: URL) -> LocalAnalysisProject? {
        guard let data = UserDefaults.standard.data(forKey: projectKey(for: videoURL)) else { return nil }
        return try? JSONDecoder().decode(LocalAnalysisProject.self, from: data)
    }

    static func save(_ project: LocalAnalysisProject, for videoURL: URL) {
        guard let data = try? JSONEncoder().encode(project) else { return }
        UserDefaults.standard.set(data, forKey: projectKey(for: videoURL))
        UserDefaults.standard.set(videoURL.absoluteString, forKey: lastVideoURLKey)
    }

    static func lastVideoURL() -> URL? {
        guard let value = UserDefaults.standard.string(forKey: lastVideoURLKey) else { return nil }
        return URL(string: value)
    }

    private static func projectKey(for videoURL: URL) -> String {
        let identifier = Data(videoURL.absoluteString.utf8).base64EncodedString()
        return projectPrefix + identifier
    }
}

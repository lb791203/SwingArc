import Foundation

@main
struct InvalidVideoImportSourceSmoke {
    static func main() throws {
        let content = try String(
            contentsOfFile: "SwingArc/Views/ContentView.swift",
            encoding: .utf8
        )
        let store = try String(
            contentsOfFile: "SwingArc/Services/CapturedVideoStore.swift",
            encoding: .utf8
        )
        let importFlow = try section(
            of: content,
            from: "private func loadSelectedVideo",
            to: "private func persistCapturedVideo"
        )
        guard let validation = importFlow.range(of: "try await ImportedVideoStore"),
              let activation = importFlow.range(of: "loadVideoFromURL") else {
            preconditionFailure("Import must validate before activation")
        }
        precondition(validation.lowerBound < activation.lowerBound)
        precondition(importFlow.contains("所选文件不是可播放的视频，请重新选择。"))
        precondition(store.contains("asset.load(.isPlayable)"))
        precondition(store.contains("asset.loadTracks(withMediaType: .video)"))
        precondition(store.contains("duration.isNumeric"))
        precondition(store.contains("seconds.isFinite"))
        precondition(store.contains("defer { try? fileManager.removeItem(at: partialURL) }"))
    }

    private static func section(
        of source: String,
        from start: String,
        to end: String
    ) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(
                  of: end,
                  range: startRange.upperBound..<source.endIndex
              ) else {
            throw SourceContractError.missing(start)
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
}

private enum SourceContractError: Error {
    case missing(String)
}

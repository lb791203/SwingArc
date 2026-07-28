import Foundation

@main
struct CoreReleaseHomeSurfaceSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let models = try read(root, "SwingArc/Models/PracticeModels.swift")
        let home = try read(root, "SwingArc/Views/PracticeHomeView.swift")
        let content = try read(root, "SwingArc/Views/ContentView.swift")

        let orderStart = models.range(
            of: "static let modeOrder: [PracticeHomeAction] = ["
        )!.upperBound
        let orderTail = models[orderStart...]
        let orderEnd = orderTail.range(of: "]")!.lowerBound
        let order = String(orderTail[..<orderEnd])

        precondition(order.contains(".manualCapture"))
        precondition(order.contains(".importVideo"))
        precondition(!order.contains(".downTheLine"))
        precondition(!order.contains(".faceOn"))

        precondition(home.contains("Text(\"挥杆视频分析\")"))
        precondition(home.contains("title: \"手动录像\""))
        precondition(home.contains("title: \"导入视频\""))
        precondition(!home.contains("正后方 · DTL"))
        precondition(!home.contains("正面 · FACE-ON"))
        precondition(!home.contains("选择机位"))

        precondition(!content.contains("onStartPractice:"))
        precondition(!content.contains("PracticeSessionView("))
        precondition(content.contains("showManualCapture = true"))
        precondition(content.contains("showVideoPicker = true"))
        precondition(content.contains("showProjectLibrary = true"))
    }

    private static func read(_ root: URL, _ path: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}

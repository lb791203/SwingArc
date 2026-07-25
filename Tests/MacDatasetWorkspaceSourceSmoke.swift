import Foundation

private func requireToken(_ source: String, _ token: String, _ index: Int) throws {
    precondition(source.contains(token), "Source file \(index) missing required token: '\(token)'")
}

@main
struct MacDatasetWorkspaceSourceSmoke {
    static func main() throws {
        print("Checkpoint B: Three-column workspace source contract smoke tests")
        print()

        let filePaths = [
            "SwingArcDataset/Views/DatasetWorkspaceView.swift",
            "SwingArcDataset/Views/DatasetClipSidebar.swift",
            "SwingArcDataset/Views/DatasetFrameCanvas.swift",
            "SwingArcDataset/Views/DatasetKeypointInspector.swift",
            "SwingArcDataset/Views/DatasetTimelineView.swift"
        ]

        print("Reading \(filePaths.count) source files...")
        let sources = try filePaths.map { path in
            try String(contentsOfFile: path, encoding: .utf8)
        }

        // Combine all sources into one for broad token search
        let combined = sources.joined(separator: "\n")

        let requiredTokens = [
            "NavigationSplitView",
            "DatasetClipSidebar",
            "DatasetFrameCanvas",
            "DatasetKeypointInspector",
            "DatasetTimelineView",
            "接受当前帧",
            "−5",
            "−1",
            "+1",
            "+5",
            "grip",
            "shaftStart",
            "shaftEnd",
            "clubhead",
            "ball"
        ]

        print("Verifying \(requiredTokens.count) required tokens across all view files...")
        for (i, token) in requiredTokens.enumerated() {
            precondition(combined.contains(token), "Missing required token #\(i): '\(token)'")
        }

        print()
        print("All required tokens present across workspace view sources.")
        print("Checkpoint B passed.")
    }
}

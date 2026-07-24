import Foundation

@main
struct PPointCorrectionPresentationSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "SwingArc/Views/PPointCorrectionWorkspace.swift"
            ),
            encoding: .utf8
        )

        for required in [
            "P 点修正",
            "当前视频",
            "−5",
            "−1",
            "+1",
            "+5",
            "设为 \\(state.selectedCode.rawValue)"
        ] {
            precondition(source.contains(required), "Missing phone correction control: \(required)")
        }

        for forbidden in [
            "annotator-a",
            "annotator-b",
            "reviewer",
            "裁定",
            "真值标注",
            "selectedLandmark",
            "landmarkCategory"
        ] {
            precondition(!source.contains(forbidden), "Phone correction leaked training UI: \(forbidden)")
        }
    }
}

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
            ".safeAreaPadding(.top",
            ".overlay(alignment: .top)",
            ".overlay(alignment: .bottom)",
            ".safeAreaPadding(.bottom, 24)",
            "−5",
            "−1",
            "+1",
            "+5",
            "minHeight: 42",
            "minHeight: 46",
            "marker.sourceFrameIndex",
            "设为 \\(state.selectedCode.rawValue)"
        ] {
            precondition(source.contains(required), "Missing phone correction control: \(required)")
        }

        for forbidden in [
            "NavigationStack",
            ".ultraThinMaterial",
            "ScrollView(.vertical",
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

        guard let saveStart = source.range(
            of: "private func saveSelectedStage()"
        ), let statusStart = source.range(
            of: "private func statusColor",
            range: saveStart.upperBound..<source.endIndex
        ) else {
            preconditionFailure("Missing saveSelectedStage implementation")
        }
        let saveImplementation = source[
            saveStart.lowerBound..<statusStart.lowerBound
        ]
        precondition(
            !saveImplementation.contains("onClose()"),
            "Saving one P point must keep the correction workspace open"
        )
    }
}

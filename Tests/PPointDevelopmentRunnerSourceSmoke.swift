import Foundation

@main
struct PPointDevelopmentRunnerSourceSmoke {
    static func main() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath
        )
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "Tools/PrecisionDataset/RunPPointDevelopmentEvaluation.swift"
            ),
            encoding: .utf8
        )

        precondition(source.contains("view: analysisView"))
        precondition(source.contains("view: output.view =="))
        precondition(!source.contains("view: truth.view"))
        precondition(
            source.contains(
                "try PPointDevelopmentCoveragePolicy.validate(truths)"
            )
        )
    }
}

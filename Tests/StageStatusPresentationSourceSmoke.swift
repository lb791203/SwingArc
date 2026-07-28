import Foundation

@main
struct StageStatusPresentationSourceSmoke {
    static func main() throws {
        let workspace = try String(
            contentsOfFile: "SwingArc/Views/AnalysisWorkspaceView.swift",
            encoding: .utf8
        )
        let components = try String(
            contentsOfFile: "SwingArc/Views/WorkspaceComponents.swift",
            encoding: .utf8
        )

        let adjustmentCall = try section(
            of: workspace,
            from: "StageAdjustmentBar(",
            to: "onCancel:"
        )
        precondition(
            adjustmentCall.contains("marker: keyframes.first"),
            "Reopened stage adjustment must receive the persisted marker"
        )

        let adjustment = try section(
            of: components,
            from: "struct StageAdjustmentBar",
            to: "struct WorkspaceProjectSidebar"
        )
        precondition(adjustment.contains("let marker: KeyframeMarker?"))
        precondition(adjustment.contains("StageResultPolicy.state(for: marker)"))
        precondition(adjustment.contains("StageResultPresentation.label"))

        for deprecatedLabel in ["已确认", "未确定", "尚未识别"] {
            precondition(
                !components.contains(deprecatedLabel),
                "Stage status labels must use the central release vocabulary"
            )
        }
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

import Foundation

@main
struct SimplifiedSwingFeedbackPresentationSmoke {
    static func main() {
        let measured = SwingMetricValue(
            id: .spineTilt2D,
            value: 31,
            unit: "°",
            confidence: 0.9,
            stage: "P1",
            availability: .measured
        )
        let estimated = SwingMetricValue(
            id: .handPathLength,
            value: 0.8,
            unit: "身高",
            confidence: 0.6,
            stage: "P3",
            availability: .estimated
        )
        let unsupported = SwingMetricValue(
            id: .attackAngle,
            value: -3,
            unit: "°",
            confidence: 0.9,
            stage: "P7",
            availability: .measured
        )
        let extras = (0..<4).map { index in
            SwingMetricValue(
                id: .leadElbowAngle,
                value: Double(150 + index),
                unit: "°",
                confidence: 0.9,
                stage: "P\(index + 2)",
                availability: .measured
            )
        }

        let visible = SimplifiedFeedbackDisplayPolicy.visibleMetrics(
            [measured, estimated, unsupported] + extras
        )
        precondition(visible.count == 3)
        precondition(visible.first?.id == .spineTilt2D)
        precondition(!visible.contains(where: { $0.id == .attackAngle }))
        precondition(
            SimplifiedFeedbackDisplayPolicy.stageCodes(
                [.address, .top, .impact]
            ) == ["P1", "P4", "P7"]
        )
    }
}

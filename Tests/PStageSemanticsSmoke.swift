import Foundation

@main
struct PStageSemanticsSmoke {
    static func main() throws {
        let pStages: [SwingStage] = [
            .address,
            .takeaway,
            .leadArmParallelBackswing,
            .top,
            .leadArmParallelDownswing,
            .shaftParallelDownswing,
            .impact,
            .followThrough
        ]

        precondition(SwingStage.allCases == pStages)
        precondition(SwingStage.pStages == pStages)
        precondition(!SwingStage.allCases.contains(.finish))
        precondition(SwingStage.impact.rawValue == "击球瞬间 (Impact)")
        precondition(SwingStage.followThrough.rawValue == "送杆 (Follow-Through)")

        let legacyFinish = try JSONDecoder().decode(
            SwingStage.self,
            from: Data("\"收杆 (Finish)\"".utf8)
        )
        precondition(legacyFinish == .finish)
    }
}

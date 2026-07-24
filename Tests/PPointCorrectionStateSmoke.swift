import Foundation

@main
struct PPointCorrectionStateSmoke {
    static func main() {
        var state = PPointCorrectionState(
            frameCount: 100,
            predictedFrames: [.p1: 10, .p2: 20, .p3: 30, .p4: 40],
            suggestedFrames: [.p5: 50],
            manualFrames: [.p2: 22]
        )

        precondition(state.selection(for: .p1).source == .automatic)
        precondition(state.selection(for: .p2).source == .manual)
        precondition(state.selection(for: .p2).sourceFrameIndex == 22)
        precondition(state.selection(for: .p5).source == .unresolved)
        precondition(state.selection(for: .p5).suggestedSourceFrameIndex == 50)

        PPointCorrectionReducer.reduce(state: &state, action: .select(.p2))
        precondition(state.currentSourceFrameIndex == 22)

        PPointCorrectionReducer.reduce(state: &state, action: .step(-50))
        precondition(
            state.currentSourceFrameIndex == 11,
            "P2 must not cross the resolved P1 frame"
        )
        PPointCorrectionReducer.reduce(state: &state, action: .step(1))
        precondition(state.currentSourceFrameIndex == 12)
        PPointCorrectionReducer.reduce(state: &state, action: .setSelectedStage)
        precondition(state.selection(for: .p2).sourceFrameIndex == 12)
        precondition(state.selection(for: .p2).source == .manual)

        PPointCorrectionReducer.reduce(state: &state, action: .select(.p5))
        precondition(state.currentSourceFrameIndex == 50)
        PPointCorrectionReducer.reduce(state: &state, action: .step(500))
        precondition(state.currentSourceFrameIndex == 99)
        PPointCorrectionReducer.reduce(state: &state, action: .setSelectedStage)
        precondition(state.selection(for: .p5).sourceFrameIndex == 99)
        precondition(state.orderedManualSelections.map(\.code) == [.p2, .p5])

        var empty = PPointCorrectionState(
            frameCount: 0,
            predictedFrames: [:],
            suggestedFrames: [:],
            manualFrames: [:]
        )
        PPointCorrectionReducer.reduce(state: &empty, action: .step(5))
        precondition(empty.currentSourceFrameIndex == 0)
    }
}

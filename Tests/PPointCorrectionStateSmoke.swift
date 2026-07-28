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
        precondition(state.selection(for: .p5).source == .review)
        precondition(state.selection(for: .p5).suggestedSourceFrameIndex == 50)
        precondition(
            PPointSelectionPresentation.label(for: .review) == "待核对"
        )
        precondition(state.selection(for: .p6).source == .unresolved)
        precondition(
            PPointSelectionPresentation.label(for: .unresolved) == "待修正"
        )

        var persistedPredicted: [PPointCode: Int] = [.p1: 11, .p2: 21]
        var persistedSuggested: [PPointCode: Int] = [:]
        var persistedManual: [PPointCode: Int] = [:]
        PPointCorrectionMarkerPolicy.apply(
            code: .p1,
            frame: 12,
            kind: .automaticConfirmed,
            predictedFrames: &persistedPredicted,
            suggestedFrames: &persistedSuggested,
            manualFrames: &persistedManual
        )
        PPointCorrectionMarkerPolicy.apply(
            code: .p2,
            frame: 22,
            kind: .automaticReview,
            predictedFrames: &persistedPredicted,
            suggestedFrames: &persistedSuggested,
            manualFrames: &persistedManual
        )
        PPointCorrectionMarkerPolicy.apply(
            code: .p3,
            frame: 32,
            kind: .manual,
            predictedFrames: &persistedPredicted,
            suggestedFrames: &persistedSuggested,
            manualFrames: &persistedManual
        )
        let persistedState = PPointCorrectionState(
            frameCount: 100,
            predictedFrames: persistedPredicted,
            suggestedFrames: persistedSuggested,
            manualFrames: persistedManual
        )
        precondition(persistedState.selection(for: .p1).source == .automatic)
        precondition(persistedState.selection(for: .p1).sourceFrameIndex == 12)
        precondition(persistedState.selection(for: .p2).source == .review)
        precondition(persistedState.selection(for: .p2).sourceFrameIndex == nil)
        precondition(
            persistedState.selection(for: .p2).suggestedSourceFrameIndex == 22
        )
        precondition(persistedState.selection(for: .p3).source == .manual)
        precondition(persistedState.selection(for: .p3).sourceFrameIndex == 32)

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

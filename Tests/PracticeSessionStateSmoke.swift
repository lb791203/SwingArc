import Foundation

@main
struct PracticeSessionStateSmoke {
    static func main() {
        var state = PracticeSessionState.aligning(view: .downTheLine)
        state = PracticeSessionReducer.reduce(state: state, event: .alignmentConfirmed)
        precondition(state == .readyToStart(view: .downTheLine))
        state = PracticeSessionReducer.reduce(state: state, event: .startTapped)
        precondition(state == .searchingForPerson(view: .downTheLine, swingCount: 0))
        state = PracticeSessionReducer.reduce(state: state, event: .captureReady)
        state = PracticeSessionReducer.reduce(state: state, event: .swingStarted)
        state = PracticeSessionReducer.reduce(state: state, event: .clipFinalizing)
        state = PracticeSessionReducer.reduce(state: state, event: .clipCaptured)
        precondition(state == .processing(view: .downTheLine, swingCount: 1))
        state = PracticeSessionReducer.reduce(
            state: state,
            event: .analysisFinished(.unresolved)
        )
        precondition(state == .resultRibbon(
            view: .downTheLine,
            swingCount: 1,
            feedback: .unresolved
        ))
        state = PracticeSessionReducer.reduce(state: state, event: .resultRibbonElapsed)
        precondition(state == .searchingForPerson(view: .downTheLine, swingCount: 1))
        state = PracticeSessionReducer.reduce(state: state, event: .pauseTapped)
        precondition(state == .paused(view: .downTheLine, swingCount: 1))
        state = PracticeSessionReducer.reduce(state: state, event: .resumeTapped)
        precondition(state == .searchingForPerson(view: .downTheLine, swingCount: 1))
    }
}

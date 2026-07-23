import Foundation

@main
struct AnnotationWorkspaceStateSmoke {
    static func main() {
        var state = AnnotationWorkspaceState.empty
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .beginPass(annotatorID: "annotator-a")
        )
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .setStage(
                stage: "P1",
                sourceFrameIndex: 100
            )
        )
        precondition(state.activePass?.stages.first {
            $0.stage == "P1"
        }?.sourceFrameIndex == 100)
        precondition(state.activePass?.stages.first {
            $0.stage == "P1"
        }?.status == .manual)

        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .updatePrediction(.init(
                stages: [
                    .init(
                        stage: "P1",
                        sourceFrameIndex: 200,
                        status: .predicted,
                        note: nil
                    )
                ],
                frameLabels: []
            ))
        )
        precondition(state.activePass?.stages.first {
            $0.stage == "P1"
        }?.sourceFrameIndex == 100)

        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .submitActivePass
        )
        precondition(state.submittedPasses.count == 1)

        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .beginRevision(annotatorID: "annotator-a")
        )
        precondition(state.activePass?.revision == 2)
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .setStage(stage: "P1", sourceFrameIndex: 101)
        )
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .submitActivePass
        )
        precondition(state.submittedPasses.count == 1)
        precondition(state.archivedPassRevisions.count == 1)

        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .beginPass(annotatorID: "annotator-b")
        )
        precondition(state.visibleComparison(for: "P1") == nil)
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .setStage(stage: "P1", sourceFrameIndex: 104)
        )
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .submitActivePass
        )
        precondition(state.adjudicationQueue.contains("P1"))

        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .adjudicate(
                stage: "P1",
                sourceFrameIndex: 102,
                adjudicatorID: "reviewer",
                note: "逐帧确认"
            )
        )
        precondition(!state.adjudicationQueue.contains("P1"))
        precondition(state.adjudications.first?.sourceFrameIndex == 102)
        precondition(state.adjudications.first?.originalSelections.count == 2)

        let queue = AnnotationFrameQueueBuilder.build(
            stageFrames: ["P1": 0, "P5": 16, "P8": 24],
            flaggedFrames: [7],
            userAddedFrames: [9],
            protectedFrames: [11],
            frameCount: 25,
            policy: .v1
        )
        precondition(
            Set([0, 4, 7, 8, 9, 11, 12, 16, 18, 20, 22, 24])
                .isSubset(of: Set(queue))
        )
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .replaceFrameQueue(queue, protectedFrames: [11])
        )
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .removeFrameFromQueue(11)
        )
        precondition(state.frameQueue.contains(11))
        AnnotationWorkflowReducer.reduce(
            state: &state,
            action: .removeFrameFromQueue(9)
        )
        precondition(!state.frameQueue.contains(9))
    }
}

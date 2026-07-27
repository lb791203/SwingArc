import Foundation

private func makeTruth(
    frameCount: Int = 300,
    frames: [Int] = [100, 110, 120, 130, 140, 150, 160, 170]
) -> GolfPPointTruthDocument {
    GolfPPointTruthDocument(
        media: GolfPPointTruthMedia(
            sha256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            frameCount: frameCount
        ),
        view: .downTheLine,
        stages: zip(GolfPPointStageCode.allCases, frames).map {
            GolfPPointTruthStage(code: $0.0, sourceFrameIndex: $0.1)
        }
    )
}

private func testFirstPassContainsOnlyP1ThroughP8() {
    let queue = DatasetAnnotationQueueFactory.make(
        mode: .pPointFirstPass,
        truth: makeTruth(),
        split: .training,
        totalFrames: 300
    )

    precondition(
        queue.map(\.sourceFrameIndex)
            == [100, 110, 120, 130, 140, 150, 160, 170]
    )
    precondition(queue.allSatisfy(\.isProtected))
    precondition(queue.count == GolfPPointStageCode.allCases.count)
}

private func testExpandedModePreservesExistingBuilderContract() {
    let truth = makeTruth()
    let queue = DatasetAnnotationQueueFactory.make(
        mode: .expandedTraining,
        truth: truth,
        split: .training,
        totalFrames: 300
    )
    let authoritative = GolfAnnotationFrameQueueBuilder.build(
        input: GolfAnnotationQueueInput(
            split: .training,
            p1: 100,
            p5: 140,
            p6: 150,
            p8: 170,
            totalFrames: 300,
            anomalyFrames: [],
            preSwingNegativeSamples: [],
            postSwingNegativeSamples: []
        )
    )

    precondition(queue == authoritative)
    precondition(queue.count > GolfPPointStageCode.allCases.count)
}

private func testFirstPassDefensivelyRejectsIncompleteTruth() {
    let queue = DatasetAnnotationQueueFactory.make(
        mode: .pPointFirstPass,
        truth: makeTruth(frames: [100, 110, 120, 130, 140, 150, 160]),
        split: .training,
        totalFrames: 300
    )

    precondition(queue.isEmpty)
}

@main
private enum MacDatasetAnnotationQueueModeSmoke {
    static func main() {
        testFirstPassContainsOnlyP1ThroughP8()
        testExpandedModePreservesExistingBuilderContract()
        testFirstPassDefensivelyRejectsIncompleteTruth()
        print("All dataset annotation queue-mode tests passed.")
    }
}

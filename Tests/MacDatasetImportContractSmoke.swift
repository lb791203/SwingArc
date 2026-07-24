import Foundation

private func fixtureMedia() -> DatasetVerifiedMedia {
    DatasetVerifiedMedia(
        media: GolfMediaIdentity(
            fileName: "fixture.mov",
            sha256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            frameCount: 757,
            orientedWidth: 1920,
            orientedHeight: 1080,
            sourceTimescale: 600
        ),
        pPointTruthSHA256: String(repeating: "c", count: 64),
        pPointTruthView: .downTheLine
    )
}

private func fixtureRegistry() throws -> GolferRegistry {
    try GolferRegistry(datasetID: "swingarc-golf-keypoints-v1")
        .assign(
            golferID: "golfer-001",
            split: .training,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
}

private func testImportStateRequiresExplicitIdentity() throws {
    var state = DatasetImportState.empty
    state = DatasetImportReducer.reduce(
        state,
        .loadRegistry(try fixtureRegistry())
    )
    state = DatasetImportReducer.reduce(
        state,
        .mediaVerified(
            media: fixtureMedia(),
            securityScopedBookmark: Data([1, 2, 3])
        )
    )
    state = DatasetImportReducer.reduce(state, .assignGolfer("golfer-001"))
    state = DatasetImportReducer.reduce(state, .setView(.downTheLine))
    state = DatasetImportReducer.reduce(state, .setHandedness(.right))
    state = DatasetImportReducer.reduce(
        state,
        .setAuthorization(.trainingAllowed)
    )

    precondition(state.canImport)
    precondition(state.split == .training)
    precondition(state.securityScopedBookmark == Data([1, 2, 3]))

    let clip = try state.makeClip(clipID: "clip-001")
    precondition(clip.golferID == "golfer-001")
    precondition(clip.media == fixtureMedia().media)
    precondition(clip.pPointTruthSHA256 == fixtureMedia().pPointTruthSHA256)
}

private func testSplitOverrideIsRejected() throws {
    var state = DatasetImportState.empty
    state = DatasetImportReducer.reduce(
        state,
        .loadRegistry(try fixtureRegistry())
    )
    state = DatasetImportReducer.reduce(state, .assignGolfer("golfer-001"))
    state = DatasetImportReducer.reduce(state, .requestSplitOverride(.heldOut))

    precondition(state.split == .training)
    precondition(
        state.issue == .splitLocked(
            golferID: "golfer-001",
            locked: .training,
            requested: .heldOut
        )
    )
}

private func testUnknownGolferCannotImport() throws {
    var state = DatasetImportState.empty
    state = DatasetImportReducer.reduce(
        state,
        .loadRegistry(try fixtureRegistry())
    )
    state = DatasetImportReducer.reduce(
        state,
        .mediaVerified(
            media: fixtureMedia(),
            securityScopedBookmark: Data([4, 5, 6])
        )
    )
    state = DatasetImportReducer.reduce(state, .assignGolfer("golfer-999"))
    state = DatasetImportReducer.reduce(state, .setView(.faceOn))
    state = DatasetImportReducer.reduce(state, .setHandedness(.left))
    state = DatasetImportReducer.reduce(
        state,
        .setAuthorization(.trainingAllowed)
    )

    precondition(!state.canImport)
    precondition(state.issue == .golferNotRegistered("golfer-999"))
}

private func testPPointTruthViewCannotBeRelabeled() throws {
    var state = DatasetImportState.empty
    state = DatasetImportReducer.reduce(
        state,
        .loadRegistry(try fixtureRegistry())
    )
    state = DatasetImportReducer.reduce(
        state,
        .mediaVerified(
            media: fixtureMedia(),
            securityScopedBookmark: Data([7, 8, 9])
        )
    )
    state = DatasetImportReducer.reduce(state, .assignGolfer("golfer-001"))
    state = DatasetImportReducer.reduce(state, .setView(.faceOn))
    precondition(
        state.issue == .pPointTruthViewMismatch(
            expected: .downTheLine,
            selected: .faceOn
        )
    )
    precondition(!state.canImport)
}

private func testNewGolferSplitBecomesLocked() {
    var state = DatasetImportState.empty
    state = DatasetImportReducer.reduce(
        state,
        .loadRegistry(GolferRegistry(datasetID: "swingarc-golf-keypoints-v1"))
    )
    state = DatasetImportReducer.reduce(
        state,
        .registerGolfer(
            golferID: "golfer-002",
            split: .validation,
            at: Date(timeIntervalSince1970: 1_700_000_100)
        )
    )
    precondition(state.golferID == "golfer-002")
    precondition(state.split == .validation)

    state = DatasetImportReducer.reduce(state, .requestSplitOverride(.training))
    precondition(
        state.issue == .splitLocked(
            golferID: "golfer-002",
            locked: .validation,
            requested: .training
        )
    )
}

@main
struct MacDatasetImportContractSmoke {
    static func main() throws {
        try testImportStateRequiresExplicitIdentity()
        try testSplitOverrideIsRejected()
        try testUnknownGolferCannotImport()
        try testPPointTruthViewCannotBeRelabeled()
        testNewGolferSplitBecomesLocked()
        print("All Mac dataset import contract tests passed.")
    }
}

import Foundation

@main
struct AnnotationModelsSmoke {
    static func main() throws {
        let media = AnnotationMediaIdentity(
            fileName: "IMG_4692.MOV",
            sha256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            frameCount: 1526,
            width: 1080,
            height: 1920
        )
        let metadata = AnnotationClipMetadata(
            clipID: "clip-4692",
            golferID: "golfer-001",
            view: .faceOn,
            handedness: .right,
            authorization: .trainingAllowed,
            split: .development
        )
        let stages = (1...8).map {
            AnnotationStageSelection(
                stage: "P\($0)",
                sourceFrameIndex: 100 + $0 * 10,
                status: .manual,
                note: nil
            )
        }
        let passA = AnnotationPass(
            id: UUID(),
            annotatorID: "annotator-a",
            revision: 1,
            submittedAt: Date(timeIntervalSince1970: 1),
            stages: stages,
            frameLabels: []
        )
        let passB = AnnotationPass(
            id: UUID(),
            annotatorID: "annotator-b",
            revision: 1,
            submittedAt: Date(timeIntervalSince1970: 2),
            stages: stages,
            frameLabels: []
        )
        let package = AnnotationPackage(
            schemaVersion: 1,
            stageSystem: "p-system-v1",
            media: media,
            metadata: metadata,
            passes: [passA, passB],
            adjudications: [],
            frozenAt: nil
        )

        precondition(AnnotationPackageValidator.validate(package).isEmpty)
        let roundTrip = try JSONDecoder().decode(
            AnnotationPackage.self,
            from: JSONEncoder().encode(package)
        )
        precondition(roundTrip == package)

        let duplicate = package.replacingPasses([passA, passA])
        precondition(
            AnnotationPackageValidator.validate(duplicate)
                .contains(.duplicateAnnotator("annotator-a"))
        )

        var wrongStages = stages
        wrongStages[0] = .init(
            stage: "P1",
            sourceFrameIndex: 120,
            status: .manual,
            note: nil
        )
        wrongStages[1] = .init(
            stage: "P2",
            sourceFrameIndex: 110,
            status: .manual,
            note: nil
        )
        let wrongOrder = passB.replacingStages(wrongStages)
        precondition(
            AnnotationPackageValidator.validate(
                package.replacingPasses([passA, wrongOrder])
            ).contains(.invalidStageOrder(annotatorID: "annotator-b"))
        )

        let point = AnnotationPoint(
            x: 0.5,
            y: 0.6,
            visibility: .visible,
            source: .manual,
            confidence: nil
        )
        precondition(point.isEligibleForCoordinateTraining)
        precondition(
            AnnotationPoint(
                x: 0.5,
                y: 0.6,
                visibility: .occluded,
                source: .manual,
                confidence: nil
            ).isEligibleForCoordinateTraining == false
        )

        var closeStages = stages
        closeStages[0].sourceFrameIndex = stages[0].sourceFrameIndex.map { $0 + 1 }
        let closePass = passB.replacingStages(closeStages)
        let consensus = AnnotationConsensusResolver.resolve(
            package.replacingPasses([passA, closePass])
        )
        precondition(
            consensus.first { $0.stage == "P1" }?.sourceFrameIndex == 111
        )
    }
}

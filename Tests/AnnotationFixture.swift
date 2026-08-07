import Foundation

enum AnnotationFixture {
    static func package(
        mediaSHA256: String = String(repeating: "a", count: 64),
        timelineSHA256: String = String(repeating: "b", count: 64),
        reviewed: Bool = true
    ) -> AnnotationPackage {
        let media = AnnotationMediaIdentity(
            fileName: "fixture.mov",
            sha256: mediaSHA256,
            timelineSHA256: timelineSHA256,
            frameCount: 400,
            width: 1080,
            height: 1920
        )
        let metadata = AnnotationClipMetadata(
            clipID: "fixture-clip",
            golferID: "fixture-golfer",
            view: .faceOn,
            handedness: .right,
            authorization: .trainingAllowed,
            split: .training
        )
        let points = Dictionary(uniqueKeysWithValues:
            ["grip", "shaftStart", "shaftEnd", "clubhead", "ball"].map {
                ($0, AnnotationPoint(
                    x: 0.5,
                    y: 0.5,
                    visibility: .visible,
                    source: .manual,
                    confidence: nil
                ))
            }
        )
        func pass(
            _ annotator: String,
            submittedAt: TimeInterval
        ) -> AnnotationPass {
            AnnotationPass(
                id: UUID(),
                annotatorID: annotator,
                revision: 1,
                submittedAt: Date(timeIntervalSince1970: submittedAt),
                stages: (1...8).map {
                    AnnotationStageSelection(
                        stage: "P\($0)",
                        sourceFrameIndex: $0 * 40,
                        status: .manual,
                        note: nil
                    )
                },
                frameLabels: [
                    AnnotationFrameLabel(
                        sourceFrameIndex: 280,
                        landmarks: points,
                        reviewerID: reviewed ? "reviewer" : nil,
                        reviewed: reviewed
                    )
                ]
            )
        }
        return AnnotationPackage(
            schemaVersion: 1,
            stageSystem: "p-system-v1",
            media: media,
            metadata: metadata,
            frameQueue: (1...8).map { $0 * 40 },
            passes: [
                pass("annotator-a", submittedAt: 1),
                pass("annotator-b", submittedAt: 2)
            ],
            adjudications: [],
            frozenAt: nil
        )
    }

    static func completeReviewedPackage() -> AnnotationPackage {
        package(reviewed: true)
    }
}

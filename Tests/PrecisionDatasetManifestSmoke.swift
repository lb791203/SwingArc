import Foundation

@main
struct PrecisionDatasetManifestSmoke {
    static func main() {
        verifyDoublePassIsRequired()
        verifyClipIDsAreUnique()
        verifyGolferCannotCrossSplits()
        verifyTrainingRequiresAuthorization()
        verifyEveryStageNeedsTwoAnnotators()
        verifyLargeStageDisagreementNeedsAdjudication()
        verifyResolvedStagesMustBeOrdered()
        verifyTrainingLabelsMustBeReviewed()
        verifyNonDevelopmentClipsRequireIdentityAndViewMetadata()
    }

    private static func verifyDoublePassIsRequired() {
        let clip = makeClip(annotationPasses: 0)
        precondition(
            PrecisionManifestValidator.errors(in: [clip])
                == [.missingDoublePass("golfer-001-dtl-001")]
        )
    }

    private static func verifyClipIDsAreUnique() {
        let first = makeClip()
        let second = makeClip(fileName: "IMG_4695.MOV")
        precondition(
            PrecisionManifestValidator.errors(in: [first, second])
                == [.duplicateClipID("golfer-001-dtl-001")]
        )
    }

    private static func verifyGolferCannotCrossSplits() {
        let training = makeClip(split: .training)
        let validation = makeClip(
            clipID: "golfer-001-face-on-001",
            fileName: "IMG_4695.MOV",
            view: .faceOn,
            split: .validation
        )
        precondition(
            PrecisionManifestValidator.errors(in: [training, validation])
                == [.golferSplitLeak("golfer-001")]
        )
    }

    private static func verifyTrainingRequiresAuthorization() {
        let clip = makeClip(
            split: .training,
            authorization: .internalReview
        )
        precondition(
            PrecisionManifestValidator.errors(in: [clip])
                == [.trainingNotAuthorized("golfer-001-dtl-001")]
        )
    }

    private static func verifyEveryStageNeedsTwoAnnotators() {
        let stage = PrecisionStageLabel(
            stage: "P1",
            annotatorFrames: ["annotator-a": 20],
            adjudicatedSourceFrameIndex: nil
        )
        let clip = makeClip(stages: [stage])
        precondition(
            PrecisionManifestValidator.errors(in: [clip])
                == [.stageMissingDoublePass(clipID: clip.clipID, stage: "P1")]
        )
    }

    private static func verifyLargeStageDisagreementNeedsAdjudication() {
        let stage = PrecisionStageLabel(
            stage: "P1",
            annotatorFrames: ["annotator-a": 20, "annotator-b": 23],
            adjudicatedSourceFrameIndex: nil
        )
        let clip = makeClip(stages: [stage])
        precondition(
            PrecisionManifestValidator.errors(in: [clip])
                == [.stageNeedsAdjudication(clipID: clip.clipID, stage: "P1")]
        )
    }

    private static func verifyResolvedStagesMustBeOrdered() {
        let p1 = PrecisionStageLabel(
            stage: "P1",
            annotatorFrames: ["annotator-a": 30, "annotator-b": 31],
            adjudicatedSourceFrameIndex: nil
        )
        let p2 = PrecisionStageLabel(
            stage: "P2",
            annotatorFrames: ["annotator-a": 29, "annotator-b": 30],
            adjudicatedSourceFrameIndex: nil
        )
        let clip = makeClip(stages: [p1, p2])
        precondition(
            PrecisionManifestValidator.errors(in: [clip])
                == [.invalidStageOrder(clip.clipID)]
        )
    }

    private static func verifyTrainingLabelsMustBeReviewed() {
        let frame = PrecisionFrameLabel(
            sourceFrameIndex: 42,
            landmarks: [
                "clubhead": NormalizedLabelPoint(x: 0.7, y: 0.8, visibility: "visible")
            ],
            reviewer: "",
            reviewed: false
        )
        let clip = makeClip(split: .training, frameLabels: [frame])
        precondition(
            PrecisionManifestValidator.errors(in: [clip])
                == [.unreviewedTrainingLabel(clipID: clip.clipID, sourceFrameIndex: 42)]
        )
    }

    private static func verifyNonDevelopmentClipsRequireIdentityAndViewMetadata() {
        let clip = PrecisionClipManifest(
            clipID: "unassigned-img-4694",
            golferID: nil,
            fileName: "IMG_4694.MOV",
            view: nil,
            handedness: nil,
            split: .training,
            authorization: .trainingAllowed,
            sourceFrameRate: 30,
            duration: 45.5,
            annotationPasses: 2,
            stages: [],
            frameLabels: []
        )
        precondition(
            PrecisionManifestValidator.errors(in: [clip]) == [
                .missingRequiredMetadata(clipID: clip.clipID, field: "golferID"),
                .missingRequiredMetadata(clipID: clip.clipID, field: "view"),
                .missingRequiredMetadata(clipID: clip.clipID, field: "handedness")
            ]
        )
    }

    private static func makeClip(
        clipID: String = "golfer-001-dtl-001",
        fileName: String = "IMG_4694.MOV",
        view: DatasetView = .downTheLine,
        split: DatasetSplit = .development,
        authorization: VideoAuthorization = .trainingAllowed,
        annotationPasses: Int = 2,
        stages: [PrecisionStageLabel] = [],
        frameLabels: [PrecisionFrameLabel] = []
    ) -> PrecisionClipManifest {
        PrecisionClipManifest(
            clipID: clipID,
            golferID: "golfer-001",
            fileName: fileName,
            view: view,
            handedness: .right,
            split: split,
            authorization: authorization,
            sourceFrameRate: 30,
            duration: 45.5,
            annotationPasses: annotationPasses,
            stages: stages,
            frameLabels: frameLabels
        )
    }
}

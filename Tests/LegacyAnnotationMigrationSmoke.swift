import Foundation

@main
struct LegacyAnnotationMigrationSmoke {
    static func main() {
        let stages = PPointCode.allCases.enumerated().map { index, code in
            AnnotationStageSelection(
                stage: code.rawValue,
                sourceFrameIndex: 10 + index * 10,
                status: .manual,
                note: nil
            )
        }
        let accidentalPoint = AnnotationPoint(
            x: 0.5,
            y: 0.5,
            visibility: .visible,
            source: .manual,
            confidence: nil
        )
        let draft = AnnotationPass(
            id: UUID(),
            annotatorID: "annotator-a",
            revision: 1,
            submittedAt: nil,
            stages: stages,
            frameLabels: [
                .init(
                    sourceFrameIndex: 62,
                    landmarks: ["clubhead": accidentalPoint],
                    reviewerID: nil,
                    reviewed: false
                ),
                .init(
                    sourceFrameIndex: 80,
                    landmarks: ["clubhead": accidentalPoint],
                    reviewerID: "reviewer",
                    reviewed: true
                )
            ]
        )
        let package = AnnotationPackage(
            schemaVersion: 1,
            stageSystem: "p-system-v1",
            media: .init(
                fileName: "fixture.mov",
                sha256: String(repeating: "a", count: 64),
                timelineSHA256: String(repeating: "b", count: 64),
                frameCount: 100,
                width: 1080,
                height: 1920
            ),
            metadata: .init(
                clipID: "fixture",
                golferID: "golfer-local",
                view: .faceOn,
                handedness: .right,
                authorization: .internalReview,
                split: .development
            ),
            activeDraft: draft,
            passes: [],
            adjudications: [],
            frozenAt: nil
        )
        let existingP4 = KeyframeMarker(
            time: 1.45,
            stage: .top,
            source: .manual
        )
        let frameTimes = Dictionary(
            uniqueKeysWithValues: (0..<100).map {
                ($0, Double($0) / 30)
            }
        )

        let migrated = LegacyAnnotationMigration.migrate(
            package: package,
            frameTimes: frameTimes,
            existingMarkers: [existingP4]
        )
        precondition(migrated.markers.count == 8)
        precondition(
            migrated.markers.first(where: {
                $0.stage == SwingStage.top.rawValue
            }) == existingP4,
            "A newer project-level manual P point must win"
        )
        precondition(migrated.discardedUnreviewedFrameLabelCount == 1)
        precondition(migrated.sanitizedPackage.activeDraft?.frameLabels.count == 1)
        precondition(
            migrated.sanitizedPackage.activeDraft?.frameLabels.first?.reviewed == true
        )

        let second = LegacyAnnotationMigration.migrate(
            package: migrated.sanitizedPackage,
            frameTimes: frameTimes,
            existingMarkers: migrated.markers
        )
        precondition(second.markers == migrated.markers)

        let suite = "LegacyAnnotationMigrationSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(
            !LegacyAnnotationMigration.isCompleted(
                mediaSHA256: package.media.sha256,
                defaults: defaults
            )
        )
        LegacyAnnotationMigration.markCompleted(
            mediaSHA256: package.media.sha256,
            defaults: defaults
        )
        precondition(
            LegacyAnnotationMigration.isCompleted(
                mediaSHA256: package.media.sha256,
                defaults: defaults
            )
        )
    }
}

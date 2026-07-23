import Foundation

@main
struct P1P8AcceptanceEvaluationSmoke {
    static func main() throws {
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let legacyManifest = try JSONDecoder().decode(
            GroundTruthManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        precondition(legacyManifest.stageSystem == .legacyNamedKeyframes)
        try GroundTruthManifestValidator.validate(
            legacyManifest,
            videoName: "IMG_4500.mov",
            sourceFrameRate: 30.009,
            duration: 25.279
        )

        let legacyStages: [SwingStage] = [
            .address,
            .takeaway,
            .leadArmParallelBackswing,
            .top,
            .leadArmParallelDownswing,
            .impact,
            .followThrough,
            .finish
        ]
        let legacyDetections = zip(legacyStages, legacyManifest.stages).map { pair in
            detection(
                stage: pair.0,
                frame: pair.1.sourceFrameIndex,
                frameRate: legacyManifest.sourceFrameRate,
                hasClubEvidence: pair.0 != .finish,
                hasBallEvidence: pair.0 == .impact
            )
        }
        let legacyResult = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: legacyDetections
        )
        precondition(
            RealVideoAcceptance.evaluate(manifest: legacyManifest, result: legacyResult)
                .allSatisfy(\.passed)
        )

        let duplicateImpact = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: legacyDetections + [legacyDetections.first { $0.stage == .impact }!]
        )
        precondition(
            RealVideoAcceptance.evaluate(manifest: legacyManifest, result: duplicateImpact)
                .first { $0.stage == "impact" }?.passed == false,
            "Legacy verification still requires exactly one named impact anchor"
        )
        let unsupportedImpact = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: legacyDetections.map { item in
                item.stage == .impact
                    ? detection(
                        stage: .impact,
                        frame: item.sourceFrameIndex!,
                        frameRate: legacyManifest.sourceFrameRate,
                        hasClubEvidence: false,
                        hasBallEvidence: false
                    )
                    : item
            }
        )
        precondition(
            RealVideoAcceptance.evaluate(manifest: legacyManifest, result: unsupportedImpact)
                .first { $0.stage == "impact" }?.passed == false,
            "Confirmed impact requires honest object evidence in every manifest version"
        )

        let canonicalManifest = canonicalManifest()
        try GroundTruthManifestValidator.validate(
            canonicalManifest,
            videoName: canonicalManifest.video,
            sourceFrameRate: canonicalManifest.sourceFrameRate,
            duration: canonicalManifest.duration
        )
        let canonicalDetections = zip(SwingStage.pStages, canonicalManifest.stages).map { pair in
            let stage = pair.0
            return detection(
                stage: stage,
                frame: pair.1.sourceFrameIndex,
                frameRate: canonicalManifest.sourceFrameRate,
                hasClubEvidence: stage == .shaftParallelDownswing
                    || stage == .impact
                    || stage == .followThrough,
                hasBallEvidence: stage == .impact
            )
        }
        let canonicalResult = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: canonicalDetections
        )
        precondition(
            RealVideoAcceptance.evaluate(manifest: canonicalManifest, result: canonicalResult)
                .allSatisfy(\.passed)
        )

        let unsupportedP6 = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: canonicalDetections.map { item in
                item.stage == .shaftParallelDownswing
                    ? detection(
                        stage: item.stage,
                        frame: item.sourceFrameIndex!,
                        frameRate: canonicalManifest.sourceFrameRate,
                        hasClubEvidence: false,
                        hasBallEvidence: false
                    )
                    : item
            }
        )
        precondition(
            RealVideoAcceptance.evaluate(manifest: canonicalManifest, result: unsupportedP6)
                .first { $0.stage == "P6" }?.passed == false,
            "Canonical P6 requires observed shaft evidence"
        )
        let unsupportedP8 = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: canonicalDetections.map { item in
                item.stage == .followThrough
                    ? detection(
                        stage: item.stage,
                        frame: item.sourceFrameIndex!,
                        frameRate: canonicalManifest.sourceFrameRate,
                        hasClubEvidence: false,
                        hasBallEvidence: false
                    )
                    : item
            }
        )
        precondition(
            RealVideoAcceptance.evaluate(manifest: canonicalManifest, result: unsupportedP8)
                .first { $0.stage == "P8" }?.passed == false,
            "Canonical P8 cannot substitute arm evidence for a missing shaft"
        )

        let p4Truth = canonicalManifest.stages.first { $0.stage == "P4" }!
        let wrongP4Frame = p4Truth.sourceFrameIndex + 2
        let wrongP4 = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: canonicalDetections.map { item in
                item.stage == .top
                    ? detection(
                        stage: .top,
                        frame: wrongP4Frame,
                        frameRate: canonicalManifest.sourceFrameRate,
                        hasClubEvidence: false,
                        hasBallEvidence: false
                    )
                    : item
            }
        )
        let failures = RealVideoAcceptance.evaluate(manifest: canonicalManifest, result: wrongP4)
            .filter { !$0.passed }
        precondition(failures.count == 1)
        precondition(failures[0].stage == "P4")
        precondition(failures[0].absoluteFrameError == 2)

        try verifyManifestValidation(manifestURL: manifestURL)
    }

    private static func canonicalManifest() -> GroundTruthManifest {
        let definitions = GroundTruthStageSystem.canonicalP1P8.requiredDefinitions
        return GroundTruthManifest(
            stageSystem: .canonicalP1P8,
            video: "synthetic-p-system.mov",
            sourceFrameRate: 30,
            duration: 4,
            annotationPasses: 2,
            maximumAcceptedFrameError: 1,
            stages: zip((1...8).map { "P\($0)" }, definitions).enumerated().map { offset, pair in
                StageGroundTruth(
                    stage: pair.0,
                    sourceFrameIndex: 10 + offset * 10,
                    definition: pair.1
                )
            }
        )
    }

    private static func detection(
        stage: SwingStage,
        frame: Int,
        frameRate: Double,
        hasClubEvidence: Bool,
        hasBallEvidence: Bool
    ) -> SwingStageDetection {
        SwingStageDetection(
            stage: stage,
            time: Double(frame) / frameRate,
            sourceFrameIndex: frame,
            confidence: 0.9,
            status: .confirmed,
            hasClubEvidence: hasClubEvidence,
            hasBallEvidence: hasBallEvidence
        )
    }

    private static func verifyManifestValidation(manifestURL: URL) throws {
        let validData = try Data(contentsOf: manifestURL)
        try expectRejected(validData) { $0["video"] = "different.mov" }
        try expectRejected(validData) { $0["sourceFrameRate"] = 29.0 }
        try expectRejected(validData) { $0["duration"] = 24.0 }
        try expectRejected(validData) { $0["annotationPasses"] = 1 }
        try expectRejected(validData) { $0["maximumAcceptedFrameError"] = 2 }
        try expectRejected(validData) { $0["stageSystem"] = "p-system-v1" }
        try expectRejected(validData) { json in
            var stages = json["stages"] as! [[String: Any]]
            stages[7]["stage"] = "followThrough"
            json["stages"] = stages
        }
        try expectRejected(validData) { json in
            var stages = json["stages"] as! [[String: Any]]
            stages[0]["sourceFrameIndex"] = -1
            json["stages"] = stages
        }
        try expectRejected(validData) { json in
            var stages = json["stages"] as! [[String: Any]]
            stages[7]["sourceFrameIndex"] = 999_999
            json["stages"] = stages
        }
        try expectRejected(validData) { json in
            var stages = json["stages"] as! [[String: Any]]
            stages[2]["sourceFrameIndex"] = stages[1]["sourceFrameIndex"]
            json["stages"] = stages
        }
        try expectRejected(validData) { json in
            var stages = json["stages"] as! [[String: Any]]
            stages[5]["definition"] = "changed definition"
            json["stages"] = stages
        }
    }

    private static func expectRejected(
        _ validData: Data,
        mutation: (inout [String: Any]) -> Void
    ) throws {
        var json = try JSONSerialization.jsonObject(with: validData) as! [String: Any]
        mutation(&json)
        let manifest = try JSONDecoder().decode(
            GroundTruthManifest.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        do {
            try GroundTruthManifestValidator.validate(
                manifest,
                videoName: "IMG_4500.mov",
                sourceFrameRate: 30.0,
                duration: 25.23
            )
            preconditionFailure("Malformed manifest must be rejected")
        } catch is GroundTruthManifestValidationError {
            // Expected.
        }
    }
}

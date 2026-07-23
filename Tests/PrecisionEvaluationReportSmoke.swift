import Foundation

@main
struct PrecisionEvaluationReportSmoke {
    static func main() throws {
        let passingInput = makePassingInput()
        let passingReport = PrecisionEvaluationReportBuilder.makeReport(from: passingInput)

        precondition(passingReport.datasetHash == "sha256:fixture-dataset")
        precondition(passingReport.artifactVersion == "artifact-schema-1")
        precondition(passingReport.modelVersion == "pose-1+clubhead-1")
        precondition(passingReport.heldOutGolferCount == 10)
        precondition(passingReport.golferCounts.count == 8)
        precondition(
            passingReport.views.allSatisfy {
                $0.hasHeldOutCoverage && $0.heldOutGolferCount == 5
            }
        )
        precondition(passingReport.stageRates.count == 16)
        precondition(passingReport.stageRates.allSatisfy { $0.hitRate == 1 })
        precondition(passingReport.stageRates.allSatisfy { $0.unresolvedRate == 0 })
        precondition(passingReport.stageRates.allSatisfy { $0.falseConfirmationRate == 0 })
        precondition(passingReport.bodyLandmarks.count == 26)
        precondition(passingReport.bodyLandmarks.allSatisfy { $0.medianError == 0.02 })
        precondition(passingReport.bodyLandmarks.allSatisfy { $0.p90Error == 0.02 })
        precondition(passingReport.bodyLandmarks.allSatisfy { $0.missRate == 0 })
        precondition(passingReport.bodyLandmarkMedianError == 0.02)
        precondition(passingReport.clubhead.visibleFrameHitRate == 1)
        precondition(passingReport.clubhead.medianError == 0.01)
        precondition(passingReport.clubhead.p90Error == 0.01)
        precondition(passingReport.clubhead.maximumAcceptedError == 0.02)
        precondition(passingReport.clubhead.gapCount == 0)
        precondition(passingReport.clubhead.missingVisibleFrameCount == 0)
        precondition(passingReport.inputRejections.count == 1)
        precondition(passingReport.inputRejections[0].passed)
        precondition(passingReport.device.device == "iPhone fixture")
        precondition(passingReport.device.elapsedSeconds == 2.5)
        precondition(passingReport.device.peakMemoryMB == 384)
        precondition(passingReport.unsupportedMetricsHaveNoMeasuredValues)
        precondition(passingReport.dataIntegrityPassed)
        precondition(passingReport.dataIntegrityIssues.isEmpty)
        precondition(passingReport.releasePassed)
        precondition(passingReport.failedThresholds.isEmpty)

        verifyFewerThanTenHeldOutGolfersFails(passingInput)
        verifyEmptyViewFails(passingInput)
        verifyMissingStageFails(passingInput)
        verifyDuplicateStageFails(passingInput)
        verifyUnresolvedAndFalseConfirmationFail(passingInput)
        verifyGolferIdentifiersCannotInflateCount(passingInput)
        verifySparseAndViewlessEvidenceFails(passingInput)
        verifyMeasuredUnsupportedMetricFails(passingInput)
        try verifyDeterministicMachineAndHumanOutput(passingInput)
        try verifyMarkdownEscapesFreeFormValues(passingInput)
    }

    private static func verifyFewerThanTenHeldOutGolfersFails(
        _ passingInput: PrecisionEvaluationInput
    ) {
        let input = replacingClips(
            in: passingInput,
            with: Array(passingInput.clips.prefix(8))
        )
        let report = PrecisionEvaluationReportBuilder.makeReport(from: input)
        precondition(report.heldOutGolferCount == 8)
        precondition(!report.releasePassed)
        precondition(report.failedThresholds.contains("heldOutGolferCount >= 10"))
    }

    private static func verifyEmptyViewFails(_ passingInput: PrecisionEvaluationInput) {
        let dtlOnly = (0..<10).map {
            makeClip(golferID: "dtl-only-\($0)", view: .downTheLine)
        }
        let report = PrecisionEvaluationReportBuilder.makeReport(
            from: replacingClips(in: passingInput, with: dtlOnly)
        )
        let faceOn = report.views.first { $0.view == .faceOn }
        precondition(report.heldOutGolferCount == 10)
        precondition(faceOn?.hasHeldOutCoverage == false)
        precondition(
            report.stageRates
                .filter { $0.view == .faceOn }
                .allSatisfy { $0.hitRate == 0 }
        )
        precondition(!report.releasePassed)
        precondition(report.failedThresholds.contains("held-out coverage for dtl and face-on"))
    }

    private static func verifyMissingStageFails(_ passingInput: PrecisionEvaluationInput) {
        var clips = passingInput.clips
        clips[0] = replacing(
            clips[0],
            stages: clips[0].stages.filter { $0.stage != "P8" }
        )
        let report = PrecisionEvaluationReportBuilder.makeReport(
            from: replacingClips(in: passingInput, with: clips)
        )
        let p8DTL = report.stageRates.first {
            $0.view == .downTheLine && $0.stage == "P8"
        }
        precondition(p8DTL?.hitRate == 0.8)
        precondition(!report.dataIntegrityPassed)
        precondition(report.dataIntegrityIssues.contains("held-out clips have exactly one P1-P8 record"))
        precondition(!report.releasePassed)
    }

    private static func verifyUnresolvedAndFalseConfirmationFail(
        _ passingInput: PrecisionEvaluationInput
    ) {
        var clips = passingInput.clips
        clips[0] = replacing(
            clips[0],
            stages: clips[0].stages.map { stage in
                guard stage.stage == "P7" else { return stage }
                return PrecisionStageEvaluation(
                    stage: stage.stage,
                    referenceFrame: stage.referenceFrame,
                    predictedFrame: nil,
                    status: "unresolved"
                )
            }
        )
        clips[1] = replacing(
            clips[1],
            stages: clips[1].stages.map { stage in
                guard stage.stage == "P6" else { return stage }
                return PrecisionStageEvaluation(
                    stage: stage.stage,
                    referenceFrame: stage.referenceFrame,
                    predictedFrame: 600,
                    status: "confirmed"
                )
            }
        )
        let report = PrecisionEvaluationReportBuilder.makeReport(
            from: replacingClips(in: passingInput, with: clips)
        )
        let p7DTL = report.stageRates.first {
            $0.view == .downTheLine && $0.stage == "P7"
        }
        let p6DTL = report.stageRates.first {
            $0.view == .downTheLine && $0.stage == "P6"
        }
        precondition(p7DTL?.hitRate == 0.8)
        precondition(p7DTL?.unresolvedRate == 0.2)
        precondition(p6DTL?.hitRate == 0.8)
        precondition(p6DTL?.falseConfirmationRate == 0.2)
        precondition(!report.releasePassed)
    }

    private static func verifyDuplicateStageFails(
        _ passingInput: PrecisionEvaluationInput
    ) {
        var clips = passingInput.clips
        clips[0] = replacing(
            clips[0],
            stages: clips[0].stages + [clips[0].stages[0]]
        )
        let report = PrecisionEvaluationReportBuilder.makeReport(
            from: replacingClips(in: passingInput, with: clips)
        )
        precondition(!report.dataIntegrityPassed)
        precondition(report.dataIntegrityIssues.contains("held-out clips have exactly one P1-P8 record"))
        precondition(!report.releasePassed)
    }

    private static func verifyGolferIdentifiersCannotInflateCount(
        _ passingInput: PrecisionEvaluationInput
    ) {
        var clips = passingInput.clips
        clips[0] = replacing(clips[0], golferID: " golfer-001 ")
        let report = PrecisionEvaluationReportBuilder.makeReport(
            from: replacingClips(in: passingInput, with: clips)
        )
        precondition(report.heldOutGolferCount == 9)
        precondition(!report.dataIntegrityPassed)
        precondition(report.dataIntegrityIssues.contains("held-out golfer IDs are canonical nonblank identifiers"))
        precondition(!report.releasePassed)
    }

    private static func verifySparseAndViewlessEvidenceFails(
        _ passingInput: PrecisionEvaluationInput
    ) {
        var clips = passingInput.clips
        clips[0] = replacing(
            clips[0],
            bodyLandmarks: Array(clips[0].bodyLandmarks.prefix(1))
        )
        clips[1] = replacing(clips[1], clubheadFrames: [])
        clips[2] = replacing(clips[2], removeView: true)
        let report = PrecisionEvaluationReportBuilder.makeReport(
            from: replacingClips(in: passingInput, with: clips)
        )
        precondition(!report.dataIntegrityPassed)
        precondition(report.dataIntegrityIssues.contains("held-out clips have classified views"))
        precondition(report.dataIntegrityIssues.contains("held-out body observations are complete and unique"))
        precondition(report.dataIntegrityIssues.contains("held-out clubhead visibility observations are complete and unique"))
        precondition(!report.releasePassed)
    }

    private static func verifyMeasuredUnsupportedMetricFails(
        _ passingInput: PrecisionEvaluationInput
    ) {
        var clips = passingInput.clips
        let first = clips[0]
        clips[0] = replacing(
            first,
            metrics: [
                SwingMetricValue(
                    id: .trueClubheadSpeed,
                    value: 112,
                    unit: "mph",
                    confidence: 0.99,
                    stage: "P7",
                    availability: .measured
                )
            ]
        )
        let report = PrecisionEvaluationReportBuilder.makeReport(
            from: replacingClips(in: passingInput, with: clips)
        )
        precondition(!report.unsupportedMetricsHaveNoMeasuredValues)
        precondition(!report.releasePassed)
        precondition(
            report.failedThresholds.contains("unsupported metrics have no measured values")
        )
    }

    private static func verifyDeterministicMachineAndHumanOutput(
        _ input: PrecisionEvaluationInput
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let inputData = try encoder.encode(input)

        let jsonA = try PrecisionEvaluationCLI.render(
            arguments: ["precision-evaluation", "--input", "fixture.json", "--format", "json"],
            readFile: { path in
                precondition(path == "fixture.json")
                return inputData
            }
        )
        let jsonB = try PrecisionEvaluationCLI.render(
            arguments: ["precision-evaluation", "--input", "fixture.json", "--format", "json"],
            readFile: { _ in inputData }
        )
        precondition(jsonA == jsonB)
        precondition(
            String(decoding: jsonA, as: UTF8.self).contains("\"passed\""),
            "Machine-readable input rejection results must include their decision"
        )
        let decoded = try JSONDecoder().decode(PrecisionEvaluationReport.self, from: jsonA)
        precondition(decoded.releasePassed)

        let markdownA = try PrecisionEvaluationCLI.render(
            arguments: [
                "precision-evaluation",
                "--input", "fixture.json",
                "--format", "markdown"
            ],
            readFile: { _ in inputData }
        )
        let markdownB = try PrecisionEvaluationCLI.render(
            arguments: [
                "precision-evaluation",
                "--input", "fixture.json",
                "--format", "markdown"
            ],
            readFile: { _ in inputData }
        )
        precondition(markdownA == markdownB)
        let markdown = String(decoding: markdownA, as: UTF8.self)
        precondition(markdown.contains("# Precision Swing Evaluation"))
        precondition(markdown.contains("sha256:fixture-dataset"))
        precondition(markdown.contains("| dtl | P1 |"))
        precondition(markdown.contains("| face-on | P8 |"))
        precondition(markdown.contains("| dtl | leftWrist |"))
        precondition(markdown.contains("Release passed: **true**"))

        let emptyInputData = try encoder.encode(
            replacingClips(in: input, with: [])
        )
        let emptyJSON = try PrecisionEvaluationCLI.render(
            inputData: emptyInputData,
            format: .json
        )
        let object = try JSONSerialization.jsonObject(with: emptyJSON)
        let dictionary = try requireDictionary(object)
        precondition(
            dictionary.keys.contains("bodyLandmarkMedianError")
                && dictionary["bodyLandmarkMedianError"] is NSNull,
            "Unavailable aggregate errors must be explicit nulls, not absent fields"
        )
        let clubhead = try requireDictionary(dictionary["clubhead"] as Any)
        precondition(clubhead.keys.contains("medianError") && clubhead["medianError"] is NSNull)
        precondition(clubhead.keys.contains("p90Error") && clubhead["p90Error"] is NSNull)
    }

    private static func verifyMarkdownEscapesFreeFormValues(
        _ input: PrecisionEvaluationInput
    ) throws {
        let hostile = PrecisionEvaluationInput(
            datasetHash: "sha|tick`\nline",
            artifactVersion: input.artifactVersion,
            modelVersion: input.modelVersion,
            clips: input.clips,
            inputRejections: [
                PrecisionInputRejectionResult(
                    caseID: "case|one",
                    expectedRejected: true,
                    actualRejected: true,
                    reason: "line one\nline | two"
                )
            ],
            device: PrecisionDeviceMeasurement(
                device: "phone|fixture",
                operatingSystem: "iOS\nfixture",
                elapsedSeconds: input.device.elapsedSeconds,
                peakMemoryMB: input.device.peakMemoryMB
            )
        )
        let markdown = PrecisionEvaluationCLI.markdown(
            for: PrecisionEvaluationReportBuilder.makeReport(from: hostile)
        )
        precondition(markdown.contains("sha&#124;tick&#96;<br>line"))
        precondition(markdown.contains("case&#124;one"))
        precondition(markdown.contains("line one<br>line &#124; two"))
        precondition(markdown.contains("phone&#124;fixture"))
        precondition(markdown.contains("iOS<br>fixture"))
    }

    private static func makePassingInput() -> PrecisionEvaluationInput {
        let clips = (0..<10).map { index in
            makeClip(
                golferID: "golfer-\(String(format: "%03d", index))",
                view: index < 5 ? .downTheLine : .faceOn
            )
        }
        return PrecisionEvaluationInput(
            datasetHash: "sha256:fixture-dataset",
            artifactVersion: "artifact-schema-1",
            modelVersion: "pose-1+clubhead-1",
            clips: clips,
            inputRejections: [
                PrecisionInputRejectionResult(
                    caseID: "missing-address",
                    expectedRejected: true,
                    actualRejected: true,
                    reason: "missing stable address"
                )
            ],
            device: PrecisionDeviceMeasurement(
                device: "iPhone fixture",
                operatingSystem: "iOS fixture",
                elapsedSeconds: 2.5,
                peakMemoryMB: 384
            )
        )
    }

    private static func makeClip(
        golferID: String,
        view: DatasetView
    ) -> PrecisionClipEvaluation {
        let stages = (1...8).map { stage in
            PrecisionStageEvaluation(
                stage: "P\(stage)",
                referenceFrame: stage * 10,
                predictedFrame: stage * 10,
                status: "confirmed"
            )
        }
        let bodyLandmarkNames = [
            "head",
            "leftShoulder", "rightShoulder",
            "leftElbow", "rightElbow",
            "leftWrist", "rightWrist",
            "leftHip", "rightHip",
            "leftKnee", "rightKnee",
            "leftAnkle", "rightAnkle"
        ]
        let bodyLandmarks = (1...8).flatMap { stage in
            bodyLandmarkNames.map { landmark in
                PrecisionBodyLandmarkEvaluation(
                    sourceFrameIndex: stage * 10,
                    landmark: landmark,
                    normalizedError: 0.02
                )
            }
        }
        return PrecisionClipEvaluation(
            clipID: "\(golferID)-\(view.rawValue)",
            golferID: golferID,
            split: .heldOut,
            view: view,
            stages: stages,
            expectedBodyLandmarkCount: bodyLandmarks.count,
            bodyLandmarks: bodyLandmarks,
            expectedClubheadFrameCount: 2,
            clubheadFrames: [
                PrecisionClubheadFrameEvaluation(
                    sourceFrameIndex: 70,
                    visibleInReference: true,
                    normalizedError: 0.01
                ),
                PrecisionClubheadFrameEvaluation(
                    sourceFrameIndex: 71,
                    visibleInReference: true,
                    normalizedError: 0.01
                )
            ],
            metrics: [
                SwingMetricValue(
                    id: .trueClubheadSpeed,
                    value: nil,
                    unit: "mph",
                    confidence: 0,
                    stage: nil,
                    availability: .unavailable(
                        reason: .requiresCalibrated3DOrSensor
                    )
                )
            ]
        )
    }

    private static func replacing(
        _ clip: PrecisionClipEvaluation,
        golferID: String? = nil,
        removeView: Bool = false,
        stages: [PrecisionStageEvaluation]? = nil,
        bodyLandmarks: [PrecisionBodyLandmarkEvaluation]? = nil,
        clubheadFrames: [PrecisionClubheadFrameEvaluation]? = nil,
        metrics: [SwingMetricValue]? = nil
    ) -> PrecisionClipEvaluation {
        PrecisionClipEvaluation(
            clipID: clip.clipID,
            golferID: golferID ?? clip.golferID,
            split: clip.split,
            view: removeView ? nil : clip.view,
            stages: stages ?? clip.stages,
            expectedBodyLandmarkCount: clip.expectedBodyLandmarkCount,
            bodyLandmarks: bodyLandmarks ?? clip.bodyLandmarks,
            expectedClubheadFrameCount: clip.expectedClubheadFrameCount,
            clubheadFrames: clubheadFrames ?? clip.clubheadFrames,
            metrics: metrics ?? clip.metrics
        )
    }

    private static func replacingClips(
        in input: PrecisionEvaluationInput,
        with clips: [PrecisionClipEvaluation]
    ) -> PrecisionEvaluationInput {
        PrecisionEvaluationInput(
            datasetHash: input.datasetHash,
            artifactVersion: input.artifactVersion,
            modelVersion: input.modelVersion,
            clips: clips,
            inputRejections: input.inputRejections,
            device: input.device
        )
    }

    private static func requireDictionary(_ value: Any) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw PrecisionEvaluationReportSmokeError.expectedDictionary
        }
        return dictionary
    }
}

private enum PrecisionEvaluationReportSmokeError: Error {
    case expectedDictionary
}

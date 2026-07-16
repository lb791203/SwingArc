import Foundation

@main
struct P1P8AcceptanceEvaluationSmoke {
    static func main() throws {
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let manifest = try JSONDecoder().decode(
            GroundTruthManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let stages = SwingStage.allCases
        let correctDetections = zip(stages, manifest.stages).map { pair in
            let stage = pair.0
            let truth = pair.1
            return SwingStageDetection(
                stage: stage,
                time: Double(truth.sourceFrameIndex) / manifest.sourceFrameRate,
                sourceFrameIndex: truth.sourceFrameIndex,
                confidence: 0.9,
                status: .confirmed,
                hasClubEvidence: true,
                hasBallEvidence: stage == .impact
            )
        }
        let correctResult = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: correctDetections
        )
        precondition(RealVideoAcceptance.evaluate(manifest: manifest, result: correctResult).allSatisfy(\.passed))

        let p4Truth = manifest.stages.first { $0.stage == "P4" }!
        let wrongP4Frame = p4Truth.sourceFrameIndex + 2
        let wrongDetections = correctDetections.map { detection in
            detection.stage == .top
                ? SwingStageDetection(
                    stage: .top,
                    time: Double(wrongP4Frame) / manifest.sourceFrameRate,
                    sourceFrameIndex: wrongP4Frame,
                    confidence: 0.9,
                    status: .confirmed
                )
                : detection
        }
        let wrongResult = SwingAnalysisResult(
            detectedMarkers: [],
            unresolvedStages: [],
            detections: wrongDetections
        )
        let failures = RealVideoAcceptance.evaluate(manifest: manifest, result: wrongResult).filter { !$0.passed }
        precondition(failures.count == 1)
        precondition(failures[0].stage == "P4")
        precondition(failures[0].absoluteFrameError == 2)
    }
}

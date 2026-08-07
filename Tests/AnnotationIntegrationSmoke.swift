import Foundation

@main
struct AnnotationIntegrationSmoke {
    static func main() {
        let prediction = AnnotationPredictionAdapter.snapshot(
            detections: [
                .init(
                    stage: .address,
                    time: 1,
                    sourceFrameIndex: 100,
                    confidence: 0.9,
                    status: .confirmed,
                    hasClubEvidence: false,
                    hasBallEvidence: false,
                    hasBallChangeEvidence: false
                ),
                .init(
                    stage: .takeaway,
                    time: 2,
                    sourceFrameIndex: 200,
                    confidence: 0.8,
                    status: .confirmed,
                    hasClubEvidence: false,
                    hasBallEvidence: false,
                    hasBallChangeEvidence: false
                ),
                .init(
                    stage: .leadArmParallelBackswing,
                    time: 3,
                    sourceFrameIndex: 300,
                    confidence: 0.72,
                    status: .lowConfidence,
                    hasClubEvidence: true,
                    hasBallEvidence: false,
                    hasBallChangeEvidence: false
                )
            ],
            frames: []
        )
        precondition(
            prediction.stages.first {
                $0.stage == "P1"
            }?.status == .predicted
        )
        precondition(
            prediction.stages.first {
                $0.stage == "P2"
            }?.status == .unresolved,
            "P2 cannot be confirmed without shaft evidence"
        )
        precondition(
            prediction.stages.first {
                $0.stage == "P2"
            }?.suggestedSourceFrameIndex == 200
        )
        precondition(
            prediction.stages.first {
                $0.stage == "P3"
            }?.status == .unresolved,
            "Low-confidence automatic output must remain a review candidate"
        )
        precondition(
            prediction.stages.first {
                $0.stage == "P3"
            }?.sourceFrameIndex == nil
        )
        precondition(
            prediction.stages.first {
                $0.stage == "P3"
            }?.suggestedSourceFrameIndex == 300
        )

        let arguments = CommandLine.arguments
        if arguments.count == 4 {
            let contentView = try! String(contentsOfFile: arguments[1], encoding: .utf8)
            let workspace = try! String(contentsOfFile: arguments[2], encoding: .utf8)
            let components = try! String(contentsOfFile: arguments[3], encoding: .utf8)

            precondition(contentView.contains("showPPointCorrection"))
            precondition(contentView.contains("PPointCorrectionWorkspace("))
            precondition(!contentView.contains("AnnotationWorkspaceView("))
            precondition(workspace.contains("let onCorrectPPoints: () -> Void"))
            precondition(components.contains("let onCorrectPPoints: () -> Void"))
            precondition(workspace.contains(".accessibilityLabel(\"修正 P 点\")"))
            precondition(workspace.contains("Text(\"画线\")"))
            precondition(components.contains("Text(\"修正 P 点\")"))
        }
    }
}

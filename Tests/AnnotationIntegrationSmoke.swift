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

        let arguments = CommandLine.arguments
        if arguments.count == 4 {
            let contentView = try! String(contentsOfFile: arguments[1], encoding: .utf8)
            let workspace = try! String(contentsOfFile: arguments[2], encoding: .utf8)
            let components = try! String(contentsOfFile: arguments[3], encoding: .utf8)

            precondition(contentView.contains("showAnnotationWorkspace"))
            precondition(contentView.contains("AnnotationWorkspaceView("))
            precondition(contentView.contains(".fullScreenCover(isPresented: $showAnnotationWorkspace)"))
            precondition(workspace.contains("let onAnnotate: () -> Void"))
            precondition(components.contains("let onAnnotate: () -> Void"))
            precondition(components.contains("Text(\"标注\")"))
        }
    }
}

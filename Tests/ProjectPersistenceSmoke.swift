import Foundation
import SwiftUI

@main
struct ProjectPersistenceSmoke {
    static func main() throws {
        let original = LocalAnalysisProject(
            drawings: [
                DrawingElement(
                    tool: .line,
                    points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.7, y: 0.8)],
                    color: .green,
                    lineWidth: 3,
                    isKeyframeSpecific: true,
                    videoTime: 1.25
                ),
                DrawingElement(
                    tool: .arrow,
                    points: [CGPoint(x: 0.2, y: 0.7), CGPoint(x: 0.8, y: 0.3)],
                    color: .red,
                    lineWidth: 3,
                    isKeyframeSpecific: false,
                    videoTime: 2.0
                )
            ],
            keyframes: [
                KeyframeMarker(
                    time: 1.25,
                    stage: .impact,
                    source: .manual,
                    sourceFrameIndex: 301
                )
            ],
            isKeyframeMode: true,
            showPoseSkeleton: true,
            showHeadStability: false,
            showSpineAngle: true,
            showGrid: false,
            stageCorrections: [
                StageCorrection(
                    stage: .top,
                    view: .downTheLine,
                    automaticFrameIndex: 40,
                    manualFrameIndex: 43
                )
            ]
        )

        let restored = try JSONDecoder().decode(LocalAnalysisProject.self, from: JSONEncoder().encode(original))
        precondition(restored.drawings.count == 2)
        precondition(restored.drawings[0].points == original.drawings[0].points)
        precondition(restored.drawings[1].tool == .arrow)
        precondition(restored.keyframes == original.keyframes)
        precondition(restored.keyframes[0].isLocked)
        precondition(restored.keyframes[0].sourceFrameIndex == 301)
        precondition(restored.stageCorrections == original.stageCorrections)
        precondition(restored.showPoseSkeleton)
        precondition(restored.showSpineAngle)
        precondition(restored.legacyFeedbackConfiguration == nil)

        let encodedObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(original)
        ) as! [String: Any]
        precondition(encodedObject["feedbackConfiguration"] == nil)
    }
}

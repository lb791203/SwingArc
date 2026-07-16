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
                )
            ],
            keyframes: [KeyframeMarker(time: 1.25, stage: .impact)],
            isKeyframeMode: true,
            showPoseSkeleton: true,
            showHeadStability: false,
            showSpineAngle: true,
            showGrid: false
        )

        let restored = try JSONDecoder().decode(LocalAnalysisProject.self, from: JSONEncoder().encode(original))
        precondition(restored.drawings.count == 1)
        precondition(restored.drawings[0].points == original.drawings[0].points)
        precondition(restored.keyframes == original.keyframes)
        precondition(restored.showPoseSkeleton)
        precondition(restored.showSpineAngle)
    }
}

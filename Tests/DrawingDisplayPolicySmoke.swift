import Foundation
import SwiftUI

@main
struct DrawingDisplayPolicySmoke {
    static func main() {
        let drawing = DrawingElement(
            tool: .line,
            points: [.zero, CGPoint(x: 1, y: 1)],
            isKeyframeSpecific: true,
            videoTime: 1.0
        )

        precondition(DrawingDisplayPolicy.shouldShow(drawing, at: 5.0, isKeyframeMode: false))
        precondition(!DrawingDisplayPolicy.shouldShow(drawing, at: 5.0, isKeyframeMode: true))

        precondition(DrawingTool.line.revealsColorPalette)
        precondition(DrawingTool.arrow.revealsColorPalette)
        precondition(!DrawingTool.circle.revealsColorPalette)

        let arrowHead = ArrowGeometry.headPoints(
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 10, y: 0),
            length: 4
        )
        precondition(arrowHead != nil)
        precondition((arrowHead?.left.x ?? 10) < 10)
        precondition((arrowHead?.right.x ?? 10) < 10)
    }
}

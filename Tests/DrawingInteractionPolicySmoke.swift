import Foundation
import SwiftUI

@main
struct DrawingInteractionPolicySmoke {
    static func main() {
        let fallbackRect = DrawingCanvasGeometry.interactionRect(
            videoRect: .zero,
            canvasSize: CGSize(width: 390, height: 280)
        )
        precondition(fallbackRect == .zero)

        let portraitVideoRect = DrawingCanvasGeometry.aspectFitRect(
            contentSize: CGSize(width: 1920, height: 1080),
            containerSize: CGSize(width: 390, height: 844)
        )
        precondition(abs(portraitVideoRect.width - 390) < 0.001)
        precondition(abs(portraitVideoRect.height - 219.375) < 0.001)
        precondition(abs(portraitVideoRect.minY - 312.3125) < 0.001)
        precondition(DrawingMagnifierPolicy.shouldShow(for: .select, isAdjustingControlPoint: true))
        precondition(!DrawingMagnifierPolicy.shouldShow(for: .select, isAdjustingControlPoint: false))
        precondition(!DrawingMagnifierPolicy.shouldShow(for: .line, isAdjustingControlPoint: true))
        precondition(!DrawingInteractionPolicy.allowsPointEditing(for: .circle))
        precondition(!DrawingInteractionPolicy.allowsPointEditing(for: .angle))
        precondition(DrawingInteractionPolicy.allowsPointEditing(for: .line))

        let line = DrawingElement(
            tool: .line,
            points: [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.6, y: 0.7)]
        )
        let movedLine = DrawingInteractionPolicy.translated(line, by: CGPoint(x: 0.1, y: -0.2))
        precondition(pointsAreEqual(movedLine.points, [CGPoint(x: 0.3, y: 0.1), CGPoint(x: 0.7, y: 0.5)]))

        let circle = DrawingElement(
            tool: .circle,
            points: [CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.6, y: 0.4)]
        )
        let movedCircle = DrawingInteractionPolicy.translated(circle, by: CGPoint(x: 0.5, y: 0.5))
        precondition(pointsAreEqual(movedCircle.points, [CGPoint(x: 0.8, y: 0.9), CGPoint(x: 1.0, y: 0.9)]))

        precondition(DrawingInteractionPolicy.isHit(
            line,
            at: CGPoint(x: 0.4, y: 0.5),
            tolerance: 0.03
        ))
        precondition(DrawingInteractionPolicy.isHit(
            circle,
            at: CGPoint(x: 0.6, y: 0.4),
            tolerance: 0.03
        ))
        precondition(DrawingInteractionPolicy.isHit(
            circle,
            at: CGPoint(x: 0.4, y: 0.4),
            tolerance: 0.03
        ))

        // The export canvas is non-square.  A center plus circumference point
        // must remain a circle, centred at the original point, after scaling.
        let exportCenter = CGPoint(x: 960, y: 810)
        let exportEdge = CGPoint(x: 1_056, y: 756)
        let exportCircle = DrawingCircleGeometry.bounds(center: exportCenter, edge: exportEdge)
        precondition(abs(exportCircle.midX - exportCenter.x) < 0.0001)
        precondition(abs(exportCircle.midY - exportCenter.y) < 0.0001)
        precondition(abs(exportCircle.width - exportCircle.height) < 0.0001)
        precondition(exportCircle.width > 200)
    }

    private static func pointsAreEqual(_ actual: [CGPoint], _ expected: [CGPoint], tolerance: CGFloat = 0.0001) -> Bool {
        actual.count == expected.count && zip(actual, expected).allSatisfy {
            abs($0.x - $1.x) <= tolerance && abs($0.y - $1.y) <= tolerance
        }
    }
}

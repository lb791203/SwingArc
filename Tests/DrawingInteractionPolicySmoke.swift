import Foundation
import SwiftUI

@main
struct DrawingInteractionPolicySmoke {
    static func main() {
        let fallbackRect = DrawingCanvasGeometry.interactionRect(
            videoRect: .zero,
            canvasSize: CGSize(width: 390, height: 280)
        )
        precondition(fallbackRect == CGRect(x: 0, y: 0, width: 390, height: 280))
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
    }

    private static func pointsAreEqual(_ actual: [CGPoint], _ expected: [CGPoint], tolerance: CGFloat = 0.0001) -> Bool {
        actual.count == expected.count && zip(actual, expected).allSatisfy {
            abs($0.x - $1.x) <= tolerance && abs($0.y - $1.y) <= tolerance
        }
    }
}

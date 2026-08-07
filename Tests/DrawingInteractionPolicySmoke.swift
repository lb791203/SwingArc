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
        let asymmetricCanvasPoint = DrawingCanvasGeometry.denormalizedPoint(
            CGPoint(x: 0.2, y: 0.3),
            in: CGRect(x: 10, y: 20, width: 200, height: 100)
        )
        precondition(asymmetricCanvasPoint == CGPoint(x: 50, y: 50))
        precondition(DrawingMagnifierPolicy.shouldShow(for: .select, isAdjustingControlPoint: true))
        precondition(!DrawingMagnifierPolicy.shouldShow(for: .select, isAdjustingControlPoint: false))
        precondition(!DrawingMagnifierPolicy.shouldShow(for: .line, isAdjustingControlPoint: true))
        precondition(!DrawingInteractionPolicy.allowsPointEditing(for: .circle))
        precondition(DrawingInteractionPolicy.allowsPointEditing(for: .angle))
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

        // The export canvas is non-square. A center plus circumference point
        // must remain a circle, centred at the original point, after scaling.
        let exportCenter = CGPoint(x: 960, y: 810)
        let exportEdge = CGPoint(x: 1_056, y: 756)
        let exportCircle = DrawingCircleGeometry.bounds(center: exportCenter, edge: exportEdge)
        precondition(abs(exportCircle.midX - exportCenter.x) < 0.0001)
        precondition(abs(exportCircle.midY - exportCenter.y) < 0.0001)
        precondition(abs(exportCircle.width - exportCircle.height) < 0.0001)
        precondition(exportCircle.width > 200)

        var angleDraft = DrawingAngleDraft()
        angleDraft.update(with: CGPoint(x: 0.5, y: 0.5))
        angleDraft.update(with: CGPoint(x: 0.8, y: 0.5))
        precondition(angleDraft.phase == .definingFirstArm)
        precondition(angleDraft.endGesture(canvasSize: CGSize(width: 390, height: 220)) == nil)
        precondition(angleDraft.phase == .awaitingSecondArm)
        precondition(angleDraft.points == [
            CGPoint(x: 0.8, y: 0.5),
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.5, y: 0.5)
        ])

        angleDraft.update(with: CGPoint(x: 0.5, y: 0.2))
        let completedAngle = angleDraft.endGesture(
            canvasSize: CGSize(width: 390, height: 220)
        )
        precondition(completedAngle?.count == 3)
        precondition(angleDraft.phase == .idle)
        precondition(angleDraft.points.isEmpty)

        let rightAngle = DrawingAngleGeometry.layout(points: [
            CGPoint(x: 80, y: 100),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 100, y: 70)
        ])
        precondition(abs((rightAngle?.degrees ?? 0) - 90) < 0.0001)

        let wrappedAcuteAngle = DrawingAngleGeometry.layout(points: [
            point(center: CGPoint(x: 100, y: 100), radius: 50, degrees: -170),
            CGPoint(x: 100, y: 100),
            point(center: CGPoint(x: 100, y: 100), radius: 50, degrees: 170)
        ])
        precondition(abs((wrappedAcuteAngle?.degrees ?? 0) - 20) < 0.0001)
        precondition(abs(wrappedAcuteAngle?.signedSweepRadians ?? 0) < .pi / 2)

        let incompleteAngle = DrawingAngleGeometry.layout(points: [
            CGPoint(x: 80, y: 100),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 100, y: 100)
        ])
        precondition(incompleteAngle == nil)

        var rejectedAngleDraft = DrawingAngleDraft()
        rejectedAngleDraft.update(with: CGPoint(x: 0.5, y: 0.5))
        rejectedAngleDraft.update(with: CGPoint(x: 0.501, y: 0.5))
        precondition(rejectedAngleDraft.endGesture(
            canvasSize: CGSize(width: 390, height: 220)
        ) == nil)
        precondition(rejectedAngleDraft.phase == .idle)

        var retryAngleDraft = DrawingAngleDraft()
        retryAngleDraft.update(with: CGPoint(x: 0.5, y: 0.5))
        retryAngleDraft.update(with: CGPoint(x: 0.8, y: 0.5))
        precondition(retryAngleDraft.endGesture(
            canvasSize: CGSize(width: 390, height: 220)
        ) == nil)
        retryAngleDraft.update(with: CGPoint(x: 0.501, y: 0.5))
        precondition(retryAngleDraft.endGesture(
            canvasSize: CGSize(width: 390, height: 220)
        ) == nil)
        precondition(retryAngleDraft.phase == .awaitingSecondArm)
        retryAngleDraft.update(with: CGPoint(x: 0.5, y: 0.2))
        precondition(retryAngleDraft.endGesture(
            canvasSize: CGSize(width: 390, height: 220)
        )?.count == 3)
    }

    private static func point(center: CGPoint, radius: CGFloat, degrees: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }

    private static func pointsAreEqual(_ actual: [CGPoint], _ expected: [CGPoint], tolerance: CGFloat = 0.0001) -> Bool {
        actual.count == expected.count && zip(actual, expected).allSatisfy {
            abs($0.x - $1.x) <= tolerance && abs($0.y - $1.y) <= tolerance
        }
    }
}

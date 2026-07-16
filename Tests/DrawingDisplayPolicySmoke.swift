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
    }
}

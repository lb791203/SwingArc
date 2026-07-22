import SwiftUI

/// The reusable SwingArc identity for non-video surfaces.
/// Geometry mirrors `BrandAssets/SwingArcMark.svg` so the app icon and UI
/// retain the same silhouette at every display size.
struct BrandMarkView: View {
    let size: CGFloat
    var showsWordmark: Bool = false

    var body: some View {
        HStack(spacing: max(7, size * 0.22)) {
            ZStack {
                SwingArcRibbonShape()
                    .fill(AnalysisTheme.proTourPrimaryText)

                Circle()
                    .fill(AnalysisTheme.proTourSignal)
                    .frame(width: size * 0.082, height: size * 0.082)
                    .position(x: size * 0.180, y: size * 0.846)
            }
            .frame(width: size, height: size)

            if showsWordmark {
                Text("SWINGARC")
                    .font(.system(size: size * 0.53, weight: .black, design: .rounded))
                    .tracking(size * 0.035)
                    .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SwingArc")
    }
}

struct SwingArcRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 1024
        let sy = rect.height / 1024
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        var path = Path()
        path.move(to: point(751, 230))
        path.addCurve(to: point(292, 262), control1: point(626, 149), control2: point(408, 154))
        path.addCurve(to: point(350, 471), control1: point(207, 341), control2: point(240, 432))
        path.addCurve(to: point(681, 557), control1: point(456, 509), control2: point(608, 483))
        path.addCurve(to: point(605, 776), control1: point(747, 624), control2: point(700, 721))
        path.addCurve(to: point(279, 762), control1: point(503, 835), control2: point(361, 830))
        path.addLine(to: point(235, 817))
        path.addCurve(to: point(696, 831), control1: point(355, 920), control2: point(555, 919))
        path.addCurve(to: point(783, 488), control1: point(843, 739), control2: point(884, 591))
        path.addCurve(to: point(413, 388), control1: point(685, 387), control2: point(520, 423))
        path.addCurve(to: point(378, 301), control1: point(353, 368), control2: point(341, 333))
        path.addCurve(to: point(704, 297), control1: point(451, 238), control2: point(610, 238))
        path.closeSubpath()
        return path
    }
}

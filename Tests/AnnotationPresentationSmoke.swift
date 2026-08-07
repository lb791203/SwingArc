import Foundation
import CoreGraphics

@main
struct AnnotationPresentationSmoke {
    static func main() {
        precondition(
            AnnotationStepPresentation.title(for: .setup) == "任务资料"
        )
        precondition(
            AnnotationStepPresentation.title(for: .stages) == "P1–P8"
        )
        precondition(
            AnnotationStepPresentation.title(for: .landmarks) == "关键点"
        )
        precondition(
            AnnotationStepPresentation.title(for: .adjudication) == "分歧裁定"
        )
        precondition(
            AnnotationStepPresentation.title(for: .export) == "冻结与导出"
        )
        precondition(
            AnnotationLandmarkCatalog.golf
                == ["grip", "shaftStart", "shaftEnd", "clubhead", "ball"]
        )
        precondition(
            AnnotationFrameStepPolicy.target(
                current: 100,
                delta: -5,
                frameCount: 1526
            ) == 95
        )
        precondition(
            AnnotationFrameStepPolicy.target(
                current: 1525,
                delta: 5,
                frameCount: 1526
            ) == 1525
        )

        let fit = AnnotationCanvasGeometry.aspectFitRect(
            imageSize: CGSize(width: 1920, height: 1080),
            containerSize: CGSize(width: 300, height: 400)
        )
        precondition(abs(fit.minX) < 0.001)
        precondition(abs(fit.minY - 115.625) < 0.001)
        precondition(abs(fit.width - 300) < 0.001)
        precondition(abs(fit.height - 168.75) < 0.001)
        let normalized = AnnotationCanvasGeometry.normalizedPoint(
            location: CGPoint(x: 150, y: 200),
            imageRect: fit
        )
        precondition(abs(normalized.x - 0.5) < 0.001)
        precondition(abs(normalized.y - 0.5) < 0.001)

        if CommandLine.arguments.count > 1 {
            let source = try! String(
                contentsOfFile: CommandLine.arguments[1],
                encoding: .utf8
            )
            for required in [
                "ExactVideoFrameSession",
                "AnnotationStore",
                "beginPass",
                "beginRevision",
                "freezeAndExport",
                "scenePhase",
                "horizontalSizeClass"
            ] {
                precondition(
                    source.contains(required),
                    "Annotation workspace is missing \(required)"
                )
            }
        }
    }
}

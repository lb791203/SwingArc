import Foundation

@main
struct HomeManualStylingSmoke {
    static func main() throws {
        let home = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )
        let camera = try String(
            contentsOfFile: CommandLine.arguments[2],
            encoding: .utf8
        )
        let theme = try String(
            contentsOfFile: CommandLine.arguments[3],
            encoding: .utf8
        )

        precondition(
            home.contains(
                ".font(.system(size: 13, weight: .bold, design: .monospaced))"
            )
        )
        precondition(home.contains(".font(.system(size: 14, weight: .bold))"))
        precondition(home.contains(".frame(minWidth: 44, minHeight: 44)"))
        precondition(!home.contains("Capsule()"))
        precondition(home.contains(".frame(width: 38, height: 38)"))
        precondition(home.contains("RoundedRectangle(cornerRadius: 12"))
        precondition(home.contains("modeAccent"))

        let opacityArguments = [
            "surfaceOpacity: 0.70",
            "surfaceOpacity: 0.50"
        ]

        for argument in opacityArguments {
            precondition(home.contains(argument))
        }

        precondition(home.contains("Text(\"挥杆视频分析\")"))
        precondition(home.contains("录制或导入视频，开始 P1–P8 识别与画线"))
        precondition(!home.contains("选择机位"))
        precondition(!home.contains("正后方 · DTL"))
        precondition(!home.contains("正面 · FACE-ON"))

        precondition(home.contains("let surfaceOpacity: Double"))
        precondition(
            home.contains(
                "AnalysisTheme.proTourSurface.opacity(surfaceOpacity)"
            )
        )
        precondition(home.contains("modeAccent.opacity(0.14)"))
        precondition(!home.contains("usesBrandSurface"))

        let removedSurfaceTokens = [
            "practiceDTLSurface",
            "practiceFaceOnSurface",
            "practiceManualSurface",
            "practiceImportSurface"
        ]

        for token in removedSurfaceTokens {
            precondition(!theme.contains(token))
            precondition(!home.contains(token))
        }

        precondition(home.contains("GeometryReader"))
        precondition(!home.contains("ScrollView"))
        precondition(home.contains("private struct PracticeHomeMetrics"))
        precondition(home.contains("if height >= 820"))
        precondition(home.contains("if height >= 700"))
        precondition(home.contains("cardHeight = 126"))
        precondition(home.contains("cardHeight = 108"))
        precondition(home.contains("cardHeight = 92"))
        precondition(home.contains("cardSpacing = 12"))
        precondition(home.contains("cardSpacing = 10"))
        precondition(home.contains("cardSpacing = 8"))

        guard let controlStart = camera.range(of: "private var captureControl") else {
            preconditionFailure("Manual capture control missing")
        }
        let control = camera[controlStart.lowerBound...]
        precondition(control.contains("VStack(spacing: 4)"))
        precondition(control.contains(".multilineTextAlignment(.center)"))
        precondition(!control.prefix(1_800).contains("Spacer()"))
    }
}

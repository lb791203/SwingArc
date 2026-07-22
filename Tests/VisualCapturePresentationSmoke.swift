import Foundation

@main
struct VisualCapturePresentationSmoke {
    static func main() throws {
        let models = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let engine = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let sessionView = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)

        for state in [
            "searchingForPerson",
            "readyForSwing",
            "capturingSwing",
            "finalizingCapture"
        ] {
            precondition(models.contains(state), "Missing truthful visual state: \(state)")
        }
        for copy in [
            "正在寻找人物",
            "人物已入镜，请准备",
            "检测挥杆中",
            "正在生成视频"
        ] {
            precondition(
                models.contains(copy) || sessionView.contains(copy),
                "Missing visual capture copy: \(copy)"
            )
        }

        precondition(
            engine.contains("@Published private(set) var lastClip: RecordedPracticeClip?"),
            "The engine handoff must retain capture quality with the URL"
        )
        precondition(
            engine.contains("status: @escaping (PracticeCaptureStatus) -> Void"),
            "The recorder must publish visual capture progress"
        )
        precondition(!engine.contains("func ingestImpact"))
        precondition(!models.contains("waitingForImpact"))
        precondition(!models.contains("已监听击球声"))
    }
}

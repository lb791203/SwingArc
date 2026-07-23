import Foundation

@main
struct TwoStageAnalysisPolicySmoke {
    static func main() {
        precondition(AnalysisProgressPresentation(phase: .locating, progress: 0.20).detail.contains("8 FPS"))
        precondition(AnalysisProgressPresentation(phase: .expanding, progress: 0.50).title == "扩展挥杆边界")
        precondition(AnalysisProgressPresentation(phase: .expanding, progress: 0.50).detail.contains("击球后动作"))
        precondition(AnalysisProgressPresentation(phase: .evidence, progress: 0.80).title == "提取候选证据")
        precondition(AnalysisProgressPresentation(phase: .solving, progress: 0.96).title == "全局阶段求解")

        let explicitFailures: [AnalysisFailure] = [
            .missingAddressBoundary,
            .missingTopTransition,
            .noImpactCorridor,
            .missingPostImpactBoundary,
            .incompleteSwingClip,
            .analysisCancelled
        ]
        precondition(explicitFailures.count == 6)

        let expectedCopy: [(AnalysisFailure, String)] = [
            (.missingAddressBoundary, "找不到准备位到起杆的边界"),
            (.missingTopTransition, "找不到上杆顶点到下杆的转换"),
            (.noImpactCorridor, "找不到可信的击球候选段"),
            (.missingPostImpactBoundary, "找不到击球后动作边界"),
            (.incompleteSwingClip, "视频缺少完整挥杆前段或后段"),
            (.analysisCancelled, "分析已取消")
        ]
        for (failure, message) in expectedCopy {
            precondition(AnalysisFailurePresentation(failure: failure).message == message)
        }

        let unsupported = AnalysisFailure.unsupportedInput([
            .fullBodyNotVisible,
            .motionBlur
        ])
        precondition(
            AnalysisFailurePresentation(failure: unsupported).message
                == "当前视频不适合自动分析：请确保人物全身入镜；画面运动模糊，请提高光线或帧率。视频仍可播放和手工标注。"
        )
    }
}

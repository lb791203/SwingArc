# SwingArc 真实 AI 分析与保存分享修复计划

> **供执行代理使用：** 必须使用 `superpowers:executing-plans` 按任务逐项执行。每项任务使用复选框记录状态。

**目标：** 让 AI 分析只展示有视频与体态证据支持的 P1–P8 和体态结果，并完成已确认的“保存 / 分享”功能；不再出现固定时间点、随机评分或假报告。

**架构：** 将挥杆阶段识别抽离为纯 Swift 计算模块，输入是带时间戳的体态样本，输出是已识别阶段和未确定阶段。`VideoPlaybackManager` 负责一次分析会话，并串行调用 Vision，避免实时播放和扫描互相竞争。`ContentView` 只消费已完成的分析结果；媒体导出服务负责生成帧图片或带标注视频，系统分享面板只接收生成后的本地文件。

**技术栈：** Swift 5、SwiftUI、AVFoundation、Vision、PhotosUI、Photos、UIKit；纯逻辑使用 `swiftc` 烟雾测试。

## 全局约束

- 最低支持 iOS 17；继续使用 AVPlayer 与 AVPlayerItemVideoOutput 回放视频。
- P1 至 P8 必须是八个不同阶段，补充当前缺失的 P3。
- 人体证据不足时不得按视频时长百分比生成 P 点。
- 不显示随机分数、优秀/良好评级、诊断结论或挥杆建议。
- AI 未完成前，时间轴不展示自动 P 点，体态叠层也不能开启。
- 工作台右上菜单只有“保存”和“分享”。
- 编辑自动保存本地项目；重命名、替换、删除只放项目列表。

---

### 任务 1：建立真实 P1–P8 阶段模型与纯识别器

**文件：**

- 新建：`SwingArc/Services/SwingStageDetector.swift`
- 修改：`SwingArc/Models/DrawingModels.swift`
- 测试：`Tests/SwingStageDetectorSmoke.swift`

**接口：**

- 输入：`PoseEstimationResult`、`KeyframeMarker`。
- 输出：包含八个 case 的 `SwingStage`、`SwingAnalysisResult.detectedMarkers` 与 `SwingAnalysisResult.unresolvedStages`。

- [x] **步骤 1：先写失败测试**

```swift
import Foundation

@main
struct SwingStageDetectorSmoke {
    static func main() {
        let samples = [
            SwingPoseSample(time: 0.0, wristY: 0.82), // P1
            SwingPoseSample(time: 0.1, wristY: 0.70), // P2
            SwingPoseSample(time: 0.2, wristY: 0.54), // P3
            SwingPoseSample(time: 0.3, wristY: 0.25), // P4
            SwingPoseSample(time: 0.45, wristY: 0.48), // P5
            SwingPoseSample(time: 0.55, wristY: 0.83), // P6
            SwingPoseSample(time: 0.7, wristY: 0.56), // P7
            SwingPoseSample(time: 0.8, wristY: 0.47),
            SwingPoseSample(time: 0.9, wristY: 0.46) // P8 stable
        ]
        let result = SwingStageDetector.detect(samples: samples)
        precondition(result.detectedMarkers.map(\.stage) == SwingStage.allCases.map(\.rawValue))
        precondition(result.unresolvedStages.isEmpty)
        precondition(SwingStage.allCases.count == 8)
        precondition(SwingStage.allCases.contains(.leadArmParallelBackswing))
    }
}
```

- [x] **步骤 2：确认测试按预期失败**

运行：

```bash
swiftc SwingArc/Models/DrawingModels.swift Tests/SwingStageDetectorSmoke.swift -o /tmp/swing-stage-test && /tmp/swing-stage-test
```

预期：因 `SwingPoseSample`、`SwingStageDetector` 和 P3 尚未存在而失败。

- [x] **步骤 3：写“无证据不能补点”测试**

```swift
let empty = SwingStageDetector.detect(samples: [])
precondition(empty.detectedMarkers.isEmpty)
precondition(empty.unresolvedStages == Set(SwingStage.allCases))
```

- [x] **步骤 4：实现最小纯识别器**

```swift
struct SwingAnalysisResult: Equatable {
    let detectedMarkers: [KeyframeMarker]
    let unresolvedStages: Set<SwingStage>
}

struct SwingPoseSample: Equatable {
    let time: Double
    let wristY: CGFloat
}

enum SwingStageDetector {
    static func detect(samples: [SwingPoseSample]) -> SwingAnalysisResult {
        guard samples.count >= 9 else {
            return .init(detectedMarkers: [], unresolvedStages: Set(SwingStage.allCases))
        }
        // 仅从样本的极值与有序插值推导阶段；没有依据即标记为未确定。
    }
}
```

具体规则：P1 取初段手部最低样本；P2/P3 取 P4 前有序上升样本；P4 取手部最高样本；P5/P6 取 P4 后有序下降样本；P7 取 P6 后再次上升样本；P8 只有在结束前至少两帧手部位置变化不超过 0.04 时才取最后稳定样本。顺序、样本数或稳定条件不满足时，不生成该 P 点，而是加入 `unresolvedStages`。

- [x] **步骤 5：验证测试通过**

```bash
swiftc SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/SwingStageDetectorSmoke.swift -o /tmp/swing-stage-test && /tmp/swing-stage-test
```

预期：退出码为 0。

- [x] **步骤 6：提交本任务**

```bash
git add SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/SwingStageDetectorSmoke.swift
git commit -m "feat: add evidence-backed P1-P8 stage detector"
```

### 任务 2：串行运行 Vision，并输出完整分析会话

**文件：**

- 修改：`SwingArc/Services/VisionPoseDetector.swift`
- 修改：`SwingArc/Views/CustomVideoPlayer.swift`
- 测试：`Tests/SwingAnalysisSessionSmoke.swift`

**接口：**

- 输入：任务 1 的 `SwingStageDetector.detect(samples:)` 和 AVAsset 视频帧。
- 输出：`@Published var analysisResult: SwingAnalysisResult?`、`@Published var analysisFailure: AnalysisFailure?`、`@Published var scanProgress: Double`。

- [ ] **步骤 1：写会话空结果测试**

```swift
let emptyResult = SwingStageDetector.detect(samples: [])
precondition(emptyResult.detectedMarkers.isEmpty)
precondition(emptyResult.unresolvedStages.count == 8)
```

- [ ] **步骤 2：先确认测试失败**

```bash
swiftc SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/SwingAnalysisSessionSmoke.swift -o /tmp/analysis-session-test && /tmp/analysis-session-test
```

预期：任务 1 尚未完成前失败。

- [ ] **步骤 3：实现串行 Vision 边界**

```swift
private let poseQueue = DispatchQueue(label: "com.liangbo.swingarc.pose", qos: .userInitiated)

private func detectPoseSerially(_ image: CGImage, completion: @escaping (PoseEstimationResult?) -> Void) {
    poseQueue.async { [poseDetector] in
        let pose = poseDetector.detectPose(in: image)
        DispatchQueue.main.async { completion(pose) }
    }
}
```

当前帧识别与 AI 扫描都经过该边界。扫描期间停止 display link 再投递实时识别；扫描只收集 `(time, pose)` 样本，交给任务 1 的识别器。删除 `autoDetectSwingStages` 中按 0.08、0.22、0.45 等比例补点的分支；没有可靠体态则设置 `.insufficientPoseEvidence`。

- [ ] **步骤 4：验证会话状态**

```bash
swiftc SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/SwingAnalysisSessionSmoke.swift -o /tmp/analysis-session-test && /tmp/analysis-session-test
```

预期：退出码为 0，测试不包含任何默认时长比例。

- [ ] **步骤 5：编译真机架构**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj -scheme SwingArcProject -destination 'id=ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3' build CODE_SIGNING_ALLOWED=NO
```

预期：`BUILD SUCCEEDED`。

- [ ] **步骤 6：提交本任务**

```bash
git add SwingArc/Services/VisionPoseDetector.swift SwingArc/Views/CustomVideoPlayer.swift Tests/SwingAnalysisSessionSmoke.swift
git commit -m "fix: serialize pose analysis and remove fabricated markers"
```

### 任务 3：让工作台只显示真实 AI 分析状态

**文件：**

- 修改：`SwingArc/Views/ContentView.swift`
- 修改：`SwingArc/Views/DrawingOverlay.swift`
- 测试：`Tests/AnalysisWorkspaceStateSmoke.swift`

**接口：**

- 输入：`VideoPlaybackManager.analysisResult`、`.analysisFailure`、`.isScanning`。
- 输出：AI 底部结果面板、仅分析后可见的 P 点、仅分析后可用的体态叠层。

- [ ] **步骤 1：写 UI 状态失败测试**

```swift
let idleMarkers: [KeyframeMarker] = []
precondition(idleMarkers.isEmpty, "AI 未完成时，时间轴不能显示自动阶段")
let failed = SwingAnalysisResult(detectedMarkers: [], unresolvedStages: Set(SwingStage.allCases))
precondition(failed.detectedMarkers.isEmpty)
```

- [ ] **步骤 2：确认测试在新类型出现前失败**

```bash
swiftc SwingArc/Models/DrawingModels.swift Tests/AnalysisWorkspaceStateSmoke.swift -o /tmp/workspace-state-test && /tmp/workspace-state-test
```

预期：因尚无 `SwingAnalysisResult` 而失败。

- [ ] **步骤 3：替换现有 AI 展示逻辑**

```swift
private func runAISwingAnalysis() {
    playbackManager.analyzeSwing { result in
        keyframes = result.detectedMarkers
        showAnalysisSheet = true
    }
}

private var visibleStageMarkers: [KeyframeMarker] {
    playbackManager.analysisResult?.detectedMarkers ?? []
}
```

删除 `swingScore`、`headSwayScore`、`spineAngleDelta`、固定诊断文字、`Int.random` 与 `Double.random`。阶段标签只从 `visibleStageMarkers` 生成；未确定阶段显示禁用的“未确定”，同时提供逐帧手动设置。只有 `analysisResult != nil` 时，骨架、头部轨迹、身体倾斜三个开关才能出现；AI 入口放在底部面板，不保留顶部霓虹按钮。

- [ ] **步骤 4：验证通过并编译**

```bash
swiftc SwingArc/Models/DrawingModels.swift SwingArc/Services/SwingStageDetector.swift Tests/AnalysisWorkspaceStateSmoke.swift -o /tmp/workspace-state-test && /tmp/workspace-state-test
```

预期：退出码为 0。

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj -scheme SwingArcProject -destination 'id=ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3' build CODE_SIGNING_ALLOWED=NO
```

预期：`BUILD SUCCEEDED`。

- [ ] **步骤 5：提交本任务**

```bash
git add SwingArc/Views/ContentView.swift SwingArc/Views/DrawingOverlay.swift Tests/AnalysisWorkspaceStateSmoke.swift
git commit -m "fix: show only completed AI analysis in workspace"
```

### 任务 4：增加已确认的保存和分享动作

**文件：**

- 新建：`SwingArc/Services/MediaExportService.swift`
- 新建：`SwingArc/Views/ShareSheet.swift`
- 修改：`SwingArc/Views/ContentView.swift`
- 修改：`SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj`（同步可运行工程时）
- 测试：`Tests/MediaExportFormatSmoke.swift`

**接口：**

- 输入：当前 `AVAsset`、当前时间、输出类型（`frame` 或 `annotatedVideo`）。
- 输出：可保存到相册或传给 `UIActivityViewController` 的临时文件 `URL`。

- [ ] **步骤 1：写输出类型失败测试**

```swift
precondition(MediaExportKind.frame.fileExtension == "jpg")
precondition(MediaExportKind.annotatedVideo.fileExtension == "mov")
```

- [ ] **步骤 2：确认失败**

```bash
swiftc Tests/MediaExportFormatSmoke.swift -o /tmp/media-export-test && /tmp/media-export-test
```

预期：因 `MediaExportKind` 不存在而失败。

- [ ] **步骤 3：实现最小导出类型与服务边界**

```swift
enum MediaExportKind: CaseIterable {
    case frame
    case annotatedVideo

    var fileExtension: String { self == .frame ? "jpg" : "mov" }
}
```

`MediaExportService.saveFrame` 通过 `AVAssetImageGenerator` 在当前时间生成 JPEG 临时文件。`MediaExportService.exportAnnotatedVideo` 通过 `AVAssetExportSession` 和 `AVVideoCompositionCoreAnimationTool` 输出带手工标注和已选体态叠层的 MOV 文件。`ShareSheet` 使用 `UIActivityViewController(activityItems: [url], applicationActivities: nil)`。

- [ ] **步骤 4：实现只有两项的菜单**

```swift
Menu {
    Button("保存") { selectedMediaAction = .save }
    Button("分享") { selectedMediaAction = .share }
} label: {
    Image(systemName: "ellipsis")
}
```

用户选择“保存”或“分享”后，才出现第二层“当前帧 / 标注视频”。禁止把重命名、替换、删除、直接导出或手动项目保存加回此菜单。

- [ ] **步骤 5：验证导出并签名安装真机**

```bash
swiftc SwingArc/Services/MediaExportService.swift Tests/MediaExportFormatSmoke.swift -o /tmp/media-export-test && /tmp/media-export-test
```

预期：退出码为 0。

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj -scheme SwingArcProject -destination 'id=ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3' -allowProvisioningUpdates build
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun devicectl device install app --device ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3 /Users/liangbo/Library/Developer/Xcode/DerivedData/SwingArcProject-cjywvgtlyaohnehjlifcszambmdr/Build/Products/Debug-iphoneos/SwingArcProject.app
```

真机验收：点击“保存”后可选择类型并产生文件；点击“分享”后对所选文件打开 iPhone 原生分享面板。

- [ ] **步骤 6：提交本任务**

```bash
git add SwingArc/Services/MediaExportService.swift SwingArc/Views/ShareSheet.swift SwingArc/Views/ContentView.swift Tests/MediaExportFormatSmoke.swift
git commit -m "feat: add save and share media actions"
```

## 自检结论

- 规格覆盖：任务 1 处理 P1–P8 与不伪造时间；任务 2 处理真实 Vision 采样与串行化；任务 3 处理真实 UI/体态显示；任务 4 处理仅含保存和分享的导出流程。
- 占位检查：没有遗留待定任务；每项均包含文件、测试、命令、预期结果、实现边界与提交命令。
- 类型一致性：任务 2、3 使用任务 1 的 `SwingAnalysisResult`；任务 4 只依赖当前视频、绘制和叠层，不耦合阶段识别内部实现。

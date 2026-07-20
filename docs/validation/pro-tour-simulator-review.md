# Pro Tour UI 模拟器验收记录

日期：2026-07-20  
设备：iPhone 17 Simulator（Xcode 27 beta）  
范围：专业巡回赛视觉与单机位自动练习入口；不包含真机相机、麦克风或户外性能验证。

| 项目 | 结果 | 验收依据 |
| --- | --- | --- |
| 练习首页 | 已确认 | 实际 SwiftUI 模拟器画面；DTL、正面、导入影片与挥杆记录入口均可见。 |
| DTL 相机对齐 | 已确认 | 实际 SwiftUI 模拟器画面；大尺寸 `ALIGNMENT`、取景框与单一确认操作在 2 米阅读场景下保持清晰。 |
| 站姿锁定 READY | 已确认 | 实际 SwiftUI 模拟器画面；大尺寸 `READY`、状态文案与单一开始按钮已确认。 |
| 主色与操作层级 | 已确认 | 石墨黑为基底，荧光黄绿仅用于主操作/已确认状态，橙色保留给暂停/中断。 |
| 正面视角 | 已确认 | 实际 SwiftUI 模拟器画面已覆盖 `FACE-ON` 的 `ALIGNMENT` 与 `READY`；与 DTL 保持同一单一主操作流程。 |
| 导入影片 | 入口保留，待媒体流程验证 | 首页入口已确认；尚未在模拟器导入实拍素材。 |
| 自动等待、暂停、结果、回看片段 | 待交互验证 | 已完成视觉/状态策略，仍需以可触发的相机与音讯流程逐项验证。 |
| AI 证据卡与 P 点标注 | 逻辑验证，待实拍素材验证 | 无可信姿态/P 点证据时不显示诊断与处方；已通过 smoke test，待用真实导入影片复核。 |
| 真机安装、相机、麦克风、阳光/热控 | 未执行 | 按当前决定，模拟器验收完成后再安排。 |

## 本次执行证据

- 实际工程：[SwingArcProject.xcodeproj](/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj)
- 实际 App bundle：`com.liangbo.swingarc`
- 本轮截图：`/tmp/swingarc-pro-tour-home.png`、`/tmp/swingarc-pro-tour-alignment-2.png`、`/tmp/swingarc-pro-tour-ready-2.png`、`/tmp/swingarc-pro-tour-face-on-alignment.png`、`/tmp/swingarc-pro-tour-face-on-ready.png`
- 已放入模拟器相册的导入流程测试媒体：`/tmp/swingarc-import-fixture.mp4`；尚待从系统影片选择器完成一次端到端选择。
- 仅用于开发构建的预览参数：`-swingarc-preview-dtl`、`-swingarc-preview-ready`、`-swingarc-preview-face-on`、`-swingarc-preview-face-on-ready`；实现均在 `#if DEBUG` 中，发布构建不受影响。

## 进入真机阶段前的检查顺序

1. 安装并启动，不把“可编译”当作真机通过。
2. 确认相机预览、相机/麦克风权限与 120/240 FPS 可用格式。
3. 在练习场验证击球声触发、前后裁切与自动重新就绪。
4. 在阳光下连续使用 30 分钟，记录发热、帧率、音讯误触发及语音可听性。
5. 导入已标注视频，复核 P 点、稳定性置信度、人工标注优先级与诊断证据卡。

# SwingArc 手机 P 点修正验证记录

日期：2026-07-24  
分支：`codex/precision-swing-analysis`

## 真实视频回归

输入：

- `/tmp/swingarc-phone-evidence-20260724-1/imported.mp4`
- 1364 源帧，约 45.47 秒

使用当前源码重新编译 `RealVideoTrackingDiagnostics` 后运行，结果：

```json
{
  "diagnostics": {
    "acceptedFrames": 177,
    "noPoseFrames": 1,
    "rejectedOutsideAnchor": 0,
    "rejectedScaleMismatch": 1
  },
  "outcome": "failed: insufficientStageEvidence",
  "video": "imported.mp4"
}
```

结论：

- Apple Vision 已稳定识别人体；不能把该视频归因为“未识别到清晰人体”。
- P1–P8 求解无有效路径时，当前代码返回
  `insufficientStageEvidence`。
- 用户文案为：
  “人体已识别，但未能自动确定完整 P1–P8。你可以手动设置 P 点。”

## 手机流程回归

已通过：

- `AnalysisFailureSourceContractSmoke`
- `PPointCorrectionStateSmoke`
- `PPointCorrectionPresentationSmoke`
- `PhoneCorrectionIntegrationSourceSmoke`
- `ManualStageLockSmoke`
- `LegacyAnnotationMigrationSmoke`
- `BrandAssetSmoke`
- `AppStoreReleaseReadinessSmoke`
- iOS Debug unsigned device build
- iOS Release physical-device signed build
- Release physical-device install and launch

行为确认：

- 手机分析页不再打开 `AnnotationWorkspaceView`。
- 精确入口显示“修正 P 点”。
- 绘图入口显示“画线”。
- P 点修正页面以视频全屏铺底，P1–P8、逐帧和保存控件使用浮层。
- 顶部不再使用系统导航栏，P1–P8 紧接标题区域，原有空白让给视频。
- 底部恢复清晰的两层操作：逐帧按钮一排，“设为 P 点”单独一排。
- 底部无材质底板和黑色渐变；逐帧按钮高 42pt，保存按钮高 46pt。
- 底部控件额外避让系统手势区 24pt，不贴近 Home 指示条。
- 自动 P 点先显示；现有人工 P 点覆盖自动结果。
- 重新分析保留人工锁定。
- 旧活动 A 草稿只迁移人工 P1–P8。
- 未复核的旧关键点从活动草稿清除，不进入新流程或训练数据。

## Release 与设备

- 设备：iPhone 16 Pro，iOS 27.0，无线连接
- UDID：`00008140-001C20102493C01C`
- Bundle ID：`com.liangbo.swingarc`
- 配置：Release
- 签名：Apple Development
- Release 构建：成功
- 安装：成功
- 启动：成功
- 安装包：
  `/tmp/SwingArc-PPoint-Release/Build/Products/Release-iphoneos/SwingArcProject.app`

安装后的前两次自动启动被 iOS 以设备锁屏拒绝。用户解锁后重新启动成功，
并确认 Release 进程正在运行。

通过 Device Hub 对物理 iPhone 16 Pro 完成界面核对：

- 主页、历史项目库和 7 月 23 日 16:06 的 45 秒视频均能打开；
- 分析页右上角显示“修正 P 点”；
- 底部绘图按钮显示“画线”；
- P 点修正页的视频占据主要屏幕空间；
- P1–P8 使用顶部浮层；
- `−5 / −1 / +1 / +5` 和“设为 P1”使用无底板的透明底部浮层；
- 旧活动草稿中的 P1 已恢复为 `帧 636 / 1364`，并显示“人工修正”，
  与原草稿的零基源帧 635 一致；
- 页面没有 A/B、复核者、分歧裁定或关键点训练控件。

真机截图：

- `/tmp/swingarc-ppoint-device-launch.png`
- `/tmp/swingarc-ppoint-device-verified.png`

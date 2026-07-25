# P1–P8 开发精度评估

此流程把手机上的人工 P 点修正作为当前视频的单次开发参考，并在
Mac 上与自动分析结果逐帧比较。DTL 与 Face-on 始终分开统计。

## 手机导出

1. 打开视频并选择正确拍摄视角。
2. 在“修正 P 点”中逐一确认 P1–P8。
3. 点击右上角导出按钮。
4. 选择“分享 P 点标准答案”，通过隔空投送保存 JSON 到 Mac。

导出的 JSON 不包含原视频。只有八个 P 点全部人工确认、都有精确源帧且
帧序正确时才允许导出。该文件标记为 `single-pass-development`，不能作为
发布精度证明或训练集最终真值。

## Mac 批量评估

编译运行器：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  -framework AVFoundation -framework Vision -framework ImageIO \
  -framework SwiftUI -framework CoreVideo -framework CoreML \
  -framework Accelerate -framework CryptoKit \
  $(find SwingArc/Models SwingArc/Services -name '*.swift' -print | sort) \
  Tools/PrecisionDataset/PPointDevelopmentEvaluation.swift \
  Tools/PrecisionDataset/PPointDevelopmentRunnerSupport.swift \
  Tools/PrecisionDataset/RunPPointDevelopmentEvaluation.swift \
  -o /tmp/run-p-point-development-evaluation
```

生成报告：

```bash
/tmp/run-p-point-development-evaluation \
  --exports /path/to/p-point-json \
  --videos /path/to/videos \
  --output /path/to/report
```

运行器优先按原视频 SHA-256 配对；容器或文件名变化时，使用精确时间线哈希
与帧数配对。报告同时生成 Markdown 与 JSON，包含：

- DTL/Face-on 各自的 P1–P8 两帧内命中率；
- 未识别率与超差率；
- 中位绝对帧误差；
- 每段视频的人工帧、自动帧以及偏早/偏晚帧数；
- 自动分析耗时。

当前开发报告不能替代正式验收。正式基线仍要求独立双人标注、分歧裁决和
锁定的保留测试集。

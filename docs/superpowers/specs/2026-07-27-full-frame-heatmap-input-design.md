# SwingArc 五点热图全画幅等比输入补充设计

日期：2026-07-27
状态：方案 A 已确认，作为五点热图实现计划 Task 1 的输入合同

## 1. 决策摘要

五点热图模型不再把现有 `roi-v1` 人体裁剪当作训练或推理输入。

新的唯一输入合同是 `full-frame-aspect-fit-v1`：

- 解码方向修正后的完整源帧；
- 等比缩放到 `512 × 512` 黑色画布；
- 不裁掉源帧内容，不拉伸画面；
- 把永久保存的原片标准化标注确定性映射到画布坐标；
- 生成五张 `128 × 128` 热图和三分类可见性目标；
- 保存可逆的输入变换 metadata；
- iOS 后续推理使用完全相同的预处理和逆变换。

现有 Prediction Run、人工 revision 和其中的 `roi-v1` 变换保持不可变。
`roi-v1` 继续作为当时主体跟踪和标注上下文的审计字段，但不得被训练读取器
解释为五点模型输入变换。

## 2. 变更原因与真实证据

2026-07-27 对冻结的 8 段、64 个 P1–P8 标注帧进行了逐点审计。数据共有
250 个 `visible` 关键点。把这些原片坐标通过对应 Prediction Run 的
`roi-v1` 变换映射后，有 71 个 `visible` 点落在 `[0, 1] × [0, 1]` 之外。

越界不是单纯的浮点边界误差：

- DTL 上杆帧出现 `shaftEnd roiY = -0.285`；
- DTL 上杆帧出现 `clubhead roiY = -0.343`；
- Face-on 下方球位出现 `ball roiY = 1.13`；
- 另有少量杆头或球位在边界外约 `0.002–0.012`。

这证明当前 `roi-v1` 实际覆盖的是主体人体区域，不能保证覆盖挥杆全过程中的
杆身、杆头和球。若继续使用它，训练读取器只能在以下三种错误行为中选择：
丢弃真实可见点、把点夹到边界，或用画布外目标训练。三者都会污染标签语义。

因此本设计修正的是模型输入合同，不修改已完成的人工标注，也不把旧
Prediction Run 伪装成另一种 ROI 算法的结果。

## 3. 数据不变量

以下源数据保持原样：

- `GolfPredictionRun` 的 ID、provenance hash、逐帧 `roi-v1` 变换和时间线；
- `GolfAnnotationRevision` 的 ID、父 Prediction Run、人工 decision 和完成时间；
- 所有人工点的权威坐标空间：方向修正后的原片标准化坐标；
- golfer 级 training/validation split；
- 媒体 SHA-256、时间线 SHA-256、帧数、方向修正后宽高和授权状态；
- P1–P8 源帧真值。

冻结导出仍是源数据的确定性解析结果。训练代码只读取冻结导出和调用者显式
提供的媒体目录，不读取 App Support 中正在编辑的 prediction 或 revision
sidecar。

## 4. `full-frame-aspect-fit-v1` 精确定义

### 4.1 坐标约定

- 源坐标原点位于方向修正后完整画面的左上角；
- x 向右，y 向下；
- 源点 `(x, y)` 使用连续标准化边界坐标，合法范围为 `[0, 1]`；
- 目标画布为 `512 × 512`，黑色为 RGB `(0, 0, 0)`；
- 缩放使用双线性插值；
- 画面在两个方向都居中，多出的奇数像素放在右侧或下侧。

### 4.2 整数内容矩形

设方向修正后的源尺寸为正整数 `W × H`，画布边长 `C = 512`。内容尺寸使用
整数除法定义，避免 Swift、Python 和 iOS 的浮点舍入差异：

```text
if W >= H:
    contentWidth = C
    contentHeight = (2 * C * H + W) // (2 * W)
else:
    contentWidth = (2 * C * W + H) // (2 * H)
    contentHeight = C

offsetX = floor((C - contentWidth) / 2)
offsetY = floor((C - contentHeight) / 2)
```

这里 `//` 是非负整数向下除法，等价于对理想等比尺寸执行 half-up 取整。
`contentWidth` 和 `contentHeight` 至少为 1，且都不大于 512。源图先一次性缩放
到这个整数尺寸，再粘贴到黑色画布的
`(offsetX, offsetY, contentWidth, contentHeight)` 内容矩形。禁止先裁剪源图。

对当前 `1080 × 1920` 竖屏视频，结果固定为：

```text
contentWidth = 288
contentHeight = 512
offsetX = 112
offsetY = 0
```

### 4.3 标签正向变换

原片标准化点 `(x, y)` 映射到画布标准化点 `(canvasX, canvasY)`：

```text
canvasX = (offsetX + x * contentWidth) / 512
canvasY = (offsetY + y * contentHeight) / 512
```

合法的源点必然落在内容矩形的闭边界内，也必然落在画布 `[0, 1]` 范围内。
读取器不得 clamp。非有限值、源坐标越界或正向变换后越界都使该冻结导出
不可用于训练。

### 4.4 预测逆变换

模型解码后的画布标准化点使用同一 metadata 逆变换回原片：

```text
x = (canvasX * 512 - offsetX) / contentWidth
y = (canvasY * 512 - offsetY) / contentHeight
```

只有落在内容矩形内的预测点可以成为原片可见坐标。落在黑边中的峰值必须标记
为输入 padding 异常，不得 clamp 后送入跟踪或 P1–P8 求解。

正向再逆向的数值往返误差门为每轴 `1e-9`。这个门验证 metadata 和公式一致，
不代表模型定位精度。

## 5. 冻结导出 schema v2

`manifest.json` 和 `resolved-labels.json` 的 `schemaVersion` 升为 `2`。
两份文件都明确记录：

```json
{
  "inputTransformVersion": "full-frame-aspect-fit-v1",
  "inputWidth": 512,
  "inputHeight": 512
}
```

每个 resolved clip 固化以下训练输入 metadata：

```json
{
  "trainingInputTransform": {
    "version": "full-frame-aspect-fit-v1",
    "sourceOrientedWidth": 1080,
    "sourceOrientedHeight": 1920,
    "canvasWidth": 512,
    "canvasHeight": 512,
    "contentWidth": 288,
    "contentHeight": 512,
    "offsetX": 112,
    "offsetY": 0,
    "forward": {
      "scaleX": 0.5625,
      "scaleY": 1.0,
      "translateX": 0.21875,
      "translateY": 0.0
    },
    "inverse": {
      "scaleX": 1.7777777777777777,
      "scaleY": 1.0,
      "translateX": -0.3888888888888889,
      "translateY": 0.0
    }
  }
}
```

`forward` 和 `inverse` 是由同一整数内容矩形导出的审计副本。导出器和读取器
都必须按下式重新计算并逐字段核对；不接受文件中任意声明的变换：

```text
forward.scaleX = contentWidth / 512
forward.scaleY = contentHeight / 512
forward.translateX = offsetX / 512
forward.translateY = offsetY / 512

inverse.scaleX = 512 / contentWidth
inverse.scaleY = 512 / contentHeight
inverse.translateX = -offsetX / contentWidth
inverse.translateY = -offsetY / contentHeight
```

每个 resolved frame 仍保存创建父 Prediction Run 时的原片到 `roi-v1` 变换，
字段名为 `annotationROITransform`。该字段的合同用途只有：

- 复核 prediction provenance；
- 重建当时的主体 ROI 画面；
- 诊断旧 ROI 的覆盖和触边行为。

训练读取器不得用 `annotationROITransform` 裁图或变换训练标签。采用明确字段名
而不是通用的 `roiTransform`，用于阻止两个坐标空间再次混淆。

manifest clip 继续固化并与 resolved clip 交叉核对：

- clip、golfer、prediction run 和 completed revision 身份；
- authorization；
- file name、media SHA-256、timeline SHA-256；
- frame count、oriented width、oriented height、source timescale；
- P1–P8 truth SHA-256；
- resolved frame count；
- training input transform metadata 的规范哈希。

manifest 字节和 resolved-labels 字节分别计算 SHA-256。训练入口必须接收预期
manifest SHA-256，且必须验证 manifest 指向的 resolved-labels SHA-256。

## 6. 热图和可见性语义

关键点顺序固定为：

1. `grip`
2. `shaftStart`
3. `shaftEnd`
4. `clubhead`
5. `ball`

目标语义不因输入合同改变：

- `visible`：先用 `full-frame-aspect-fit-v1` 映射坐标，再生成对应
  `128 × 128` 高斯热图，同时监督 visibility class 0；
- `occluded`：热图全零、coordinate mask 为 false，监督 class 1；
- `out-of-frame`：热图全零、coordinate mask 为 false，监督 class 2；
- resolved export 中缺少该 landmark：视为 unresolved，热图全零、
  coordinate mask 为 false、visibility target 为 ignore index `-100`。

不得从旧 prediction 峰值补齐 unresolved，也不得为隐藏点制造坐标。

## 7. iOS 同合同要求

Core ML 候选接入 iOS 前，iOS 预处理器必须实现同一个
`full-frame-aspect-fit-v1`：

- 使用方向修正后的完整帧；
- 使用完全相同的内容尺寸取整、偏移、黑边和双线性缩放规则；
- 模型输入仍为 `512 × 512`；
- 热图点先在画布空间解码，再用 metadata 逆变换回原片；
- 黑边峰值作为异常拒绝，不 clamp；
- 输出的原片点再进入可见性门、连续跟踪和 P1–P8 求解。

PyTorch 和 iOS 必须共享一组 portrait、landscape、square 和奇数尺寸 golden
fixtures。每个 fixture 核对内容矩形、关键像素位置、正逆变换和黑边行为。
只有预处理逐像素/允许的插值容差一致，模型转换验收才可通过。

## 8. 拒绝的替代方案

### 8.1 不按标签扩大 ROI

禁止用本帧人工点的最小外接框扩大 `roi-v1`。这样会把真值泄漏进模型输入：
训练时知道杆头和球在哪里，推理时却不知道，训练与生产分布不一致。标签变化
还会改变输入像素，使同一源帧无法独立重现。

### 8.2 不按旧预测扩大 ROI

旧 manual-bootstrap Prediction Run 没有可靠的五点模型结果。按人体或不稳定
球杆预测动态扩大 ROI 会让输入变换依赖待训练模型的错误，并使 Prediction Run
provenance 与实际训练像素不一致。若未来重新设计动态五点 ROI，必须使用新的
ROI 版本、新 Prediction Run 和独立验收，不能改写本批冻结数据。

### 8.3 不给 `roi-v1` 增加固定大边距

真实越界同时出现在画面上方、下方和横向边缘。能保证覆盖全部挥杆杆头与球的
固定边距最终接近完整画幅，却仍保留裁剪失败边界和额外版本复杂度。完整画幅
等比输入更简单、可证明覆盖且可直接在 iOS 重现。

### 8.4 不把完整画面直接拉伸成正方形

非等比拉伸会改变人体比例、杆身角度、杆头轨迹和距离关系。训练、评估和 iOS
反馈都依赖这些几何量，因此拉伸不是可接受的提速手段。黑边的代价可见且稳定，
比不可逆的几何畸变更容易由模型和验收处理。

### 8.5 不 clamp 画布外坐标

clamp 会把不同的真实位置压到同一边界像素，制造虚假的边缘热图峰值，并掩盖
输入合同错误。任何按本设计仍出现的画布越界都属于数据或实现失败，必须阻断
训练。

## 9. 错误处理

以下任一情况使数据集构建失败，不跳过样本：

- manifest 或 resolved-labels SHA-256 不匹配；
- schema 不是 v2，或 input transform version 不是
  `full-frame-aspect-fit-v1`；
- clip 未获 `training-allowed`、revision 未完成或 golfer split 不一致；
- 媒体/时间线身份、方向修正尺寸或帧范围不一致；
- 导出的输入 metadata 与按源尺寸重新计算的结果不一致；
- `annotationROITransform` 缺失、非有限或不可逆；
- visible 原片坐标无效，或 full-frame aspect-fit 映射越界；
- 隐藏点带坐标；
- 视频解码尺寸不等于导出的方向修正尺寸；
- 解码点落在黑边中。

错误必须包含 clipID、sourceFrameIndex 和 landmark（适用时），以便追溯，且不得
用自动降级到 `roi-v1`、拉伸或 clamp 的方式继续。

## 10. 验证门

### 10.1 单元合同

测试至少覆盖：

- `320 × 180` landscape、`180 × 320` portrait、square 和奇数尺寸源图；
- portrait fixture 的左右黑边、内容矩形和一个已知热图峰值；
- 四角、中心和边界点的正向/逆向坐标；
- visible、occluded、out-of-frame、unresolved 的 target/mask；
- 篡改 manifest、resolved labels、input metadata 或媒体身份时失败；
- 把 `annotationROITransform` 误当训练输入时由预期峰值测试发现；
- 黑边预测的逆解码失败；
- 同一导出重复生成时字节和哈希完全一致。

### 10.2 真实 64 帧覆盖

冻结的 8 段 P1–P8 数据必须同时满足：

- training 为 48 帧，validation 为 16 帧；
- 共 64 帧全部成功解码并生成 `512 × 512` 输入；
- 250 个 visible 点全部落在各自内容矩形和画布范围内；
- 44 个 occluded 和 26 个 out-of-frame 点都不生成热图；
- unresolved 数为 0；
- 每个 visible 点正向再逆向误差每轴不超过 `1e-9`；
- 每个样本输出五张 `128 × 128` 热图、五个 visibility targets 和五个
  coordinate masks；
- 不读取 App Support prediction/revision sidecar；
- 不改动任何 Prediction Run 或 revision 文件；
- 第二次导出得到相同 manifest 和 resolved-labels SHA-256。

通过这些门只证明开发数据输入管线完整，不证明模型准确，也不解除“当前只有
两位球员、没有 locked held-out golfer”的发布限制。

## 11. 实施边界

本补充设计只替换五点热图 Task 1 的输入变换与 frozen export v2 合同。后续
实现按顺序完成：

1. frozen export v2 和确定性 input metadata；
2. Python strict decoder、aspect-fit renderer、heatmap targets；
3. 真实 64 帧覆盖验收；
4. 热图网络、masked losses、开发训练和 validation；
5. Core ML 转换；
6. iOS 同合同预处理和真实设备验收。

本阶段不重建旧 Prediction Run、不修改人工 revision、不训练模型、不改变
P1–P8 求解门，也不宣称当前 64 帧足以产生发布模型。

# SwingArc App 内正式标注验证记录 — 2026-07-23

状态：**模拟器真实原片标注闭环已通过；真机闭环尚未验证**

本记录覆盖实现提交 `4f50b3e5c0d052cac5dddbbd4f3249ee56497046`
及此前六个标注基础设施提交。所有结论只来自本次实际测试，不把编译
成功等同于标注精度或真机可用性。

## 已验证

### 原片身份与逐帧读取

- 原片：`/Users/liangbo/Desktop/test/original-240fps/IMG_4692.MOV`
- 解码源帧数：`1526`
- 时间线 SHA-256：
  `cef1d9f2cd03ecbb61d52f080f3f1722c5326f6f95b87cd23024e36435c13f64`
- 同一原片连续运行两次，帧数和时间线指纹完全一致。
- 首帧和末帧均按真实 presentation timestamp 解码；测试未出现
  `decodedNeighborFrame`。

### 规则、隔离和导出

以下独立 smoke tests 全部通过：

- 标注数据契约、P1–P8 顺序和双人规则；
- 可变帧率源时间线和精确帧读取；
- 独立标注包保存/恢复和媒体身份不匹配拒绝；
- A/B 标注隔离、修订归档、人工锁定、裁决队列；
- 训练授权、人工复核和冻结导出门；
- iPhone/iPad 布局策略、画面坐标映射和逐帧步进策略；
- 现有分析结果到“建议标注”的映射；
- 标注存储不修改普通项目 UserDefaults；
- 现有输入质量回归测试。

验证用冻结导出：

- 文件：`fixture-clip-annotation-v1.json`
- SHA-256：
  `9e3bee43f7d03ddb03e03eb3d6fa4b5856244752db78ec5cb1511599a6b514d4`
- Mac 校验器输出：`VALID fixture-clip 400 frames 2 passes`
- 导出仅包含 JSON，`includesRawVideo = false`，不包含原始视频字节。

### 构建和签名

- iOS Simulator Debug：`BUILD SUCCEEDED`
- generic iOS Release：`BUILD SUCCEEDED`
- Release App 路径：
  `/tmp/SwingArcAnnotationDevice/Build/Products/Release-iphoneos/SwingArcProject.app`
- 签名验证：`valid on disk` 且
  `satisfies its Designated Requirement`
- Bundle ID：`com.liangbo.swingarc`
- Team ID：`RCP42Y96T8`

模拟器已安装该 App，并用 `IMG_4692.MOV` 的模拟器沙盒副本启动。
日志证明原片被读取和解码。iOS 27 beta 模拟器缺少
`cnn_human_pose.espresso.weights`，因此模拟器内 Apple Vision 人体姿态
请求不可作为本次算法精度证据；这不是 App 内精确帧读取器的失败。

### 模拟器真实界面闭环

在 iPhone 17、iOS 27.0 模拟器中实际点按完成了以下流程：

- 原片标注页显示 `帧 1 / 1526` 和 `IMG_4692.MOV`；
- `+1` 将帧 1 移到帧 2，`+5` 将帧 2 移到帧 7，`−5` 返回帧 2，
  `−1` 返回帧 1；界面没有跳到邻近解码帧；
- 使用标注者 A 建立并提交了一组仅用于流程验证的 P1–P8 测试标记；
- 在真实视频画面上放置 grip、shaftStart、shaftEnd、clubhead、ball
  五类人工关键点，并实际拖动了杆头点；
- 当前帧加入队列并由 `reviewer` 完成人工复核，提交后任务资料页显示
  “标注者 A · 修订 1”；
- 切换到标注者 B 并开始独立标注后，P1–P8 全部显示“尚未人工确定”，
  没有显示 A 的答案；
- 强制终止并重启 App，再次进入标注页后恢复到界面第 8 帧，B 仍为
  活动草稿且 A 仍保持已提交；
- B 提交后，系统正确生成 P8 分歧：A 为界面第 8 帧、B 为第 12 帧，
  两者相差 4 个源帧；选择 A 候选并完成裁决；
- 冻结导出成功生成 `dac4a72674a0883e-annotation-v1.json`，Mac 校验器
  输出 `VALID dac4a72674a0883e 1526 frames 2 passes`；
- 本轮真实界面导出 SHA-256：
  `38faa8e235e345022bb518811bf81aeb1d8c63b31fe5a1cf30bed72498c8bc40`。

本轮强制终止 App 后，沙盒标注包仍保存：

- A 的 8 个阶段、1 个已复核关键点帧和提交时间；
- B 的独立活动草稿，8 个阶段均为 `unresolved`；
- 当前源帧索引 `7`（界面帧号 8）和帧队列 `[7]`。

这些测试标记只证明交互、隔离与持久化流程，不是
`IMG_4692.MOV` 的真实 P1–P8 或杆球真值。

## 尚未验证

以下项目没有完成，不能标记为通过：

1. 无线 iPhone 16 Pro
   `ECE6D973-A2C0-50A1-B4F1-AFD6ACA2ACF3` 在 `devicectl` 中为
   `unavailable`，因此本次未能安装 Release App、启动进程或完成真机
   标注闭环。
2. 尚未在常规宽度 iPad 上实际点按完整标注闭环。
3. 尚无两位真人标注者对 `IMG_4692.MOV` 完成独立 P1–P8 和关键点标注；
   因此没有真实两人分歧、裁决结果或人体/球杆坐标误差统计。
4. 当前工程不包含训练完成的 `GolfKeypoints` Core ML 模型。该功能建立
   真值生产工具，但不会自动提高杆头、杆身或 P1–P8 精度。

## 真机复验清单

手机重新显示为 `available` 且 Mac 解锁后，需要完整执行：

1. 安装并启动签名 Release App；
2. 导入原始 `IMG_4692.MOV`，进入“标注”，确认显示 `1/1526`；
3. 验证 `−5/−1/+1/+5` 严格按源帧序号移动；
4. 使用两位真人标注者独立完成 P1–P8，提交前不可见对方答案；
5. 对真实分歧逐项裁决；
6. 放大并移动 grip、shaftStart、shaftEnd、clubhead、ball，设置可见性和
   人工复核；
7. 活跃修订期间强制退出，重启后核对当前帧、队列、复核状态和
   人工锁定；
8. 在常规宽度 iPad 布局再走一遍；
9. 使用具备训练授权和训练/验证分区的正式任务导出 JSON，并用 Mac
   校验器确认 `VALID`；
10. 关闭标注页后确认普通分析项目未改变。

## 能力边界与下一项目

现阶段已具备“Apple Vision/现有算法给建议值 → 人工双人标注 →
分歧裁决 → 人工锁定 → 标准 JSON”的真值基础设施。建议值不会被当作
训练真值，人工锁定不会被重新分析覆盖。

仍不能宣称：

- P1–P8 已达到准确或教练级；
- 手、胳膊、头、脊椎、身体、杆身和杆头轨迹已达到量化精度；
- 杆头/杆身在所有可见帧中都能稳定检测。

下一项目应使用本工具收集经过授权且双人复核的原片标注，训练
高分辨率 golf-object/GolfKeypoints 模型，并加入连续双向轨迹跟踪。
只有在按球手隔离的 held-out 集上得到 P1–P8 帧误差、关键点像素误差、
可见帧命中率和轨迹断点指标后，才能更新发布精度结论。

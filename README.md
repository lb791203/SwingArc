# SwingArc - 高尔夫视频画线与挥杆分析 iOS App

SwingArc 是一款专为 iOS 设备开发的**原生高尔夫挥杆分析与画线 App**。它结合了苹果高性能多媒体引擎 (AVFoundation) 与人工智能视觉分析框架 (Vision)，能为教练和高尔夫爱好者提供极佳的慢动作回放、姿态追踪和专业的画线对齐工具。

---

## ✨ 核心功能亮点
1. **高性能 120/240 FPS 慢动作录像**：内置高帧率录制引擎，自动检测并锁定摄像头的高速硬件快门模式，并支持 3 秒起杆倒计时和防起伏站姿引导框。
2. **Apple Vision AI 姿态追踪**：基于 iOS 系统硬件加速的 `VNDetectHumanBodyPoseRequest`。在视频正常播放、慢放 (0.1x-1.0x)、或拖动时间轴时，进行 2-5ms 的实时骨架识别。
3. **身体倾斜与脊椎角度自动测算**：动态识别肩膀与髋部中轴，实时在 Canvas 上投影脊椎倾斜线并显示与绝对垂直线的度数夹角。
4. **头部稳定圈与轨迹追踪**：以鼻尖/耳部为核心绘制“防起伏定位圆”，引导球员分析起杆、下杆和击球瞬间头部的升降和偏摆。
5. **精准画线微调放大镜 (Magnifying Loupe)**：触屏绘制直线、圆圈、3 点量角器时，自动在手指上方弹出 2x 矢量局部放大镜，防止手指遮挡关节，实现像素级对齐。
6. **挥杆阶段标记 (Keyframe Timeline Flags)**：可在时间轴上为准备 (Address)、顶点 (Top)、击球 (Impact)、收杆 (Finish) 进行一键书签标记和快速定位。

---

## 🛠️ 当前 Xcode 项目与验收状态

请直接打开现有工程 [SwingArcProject.xcodeproj](/Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj)，它引用本仓库内的 `SwingArc` 源码目录；无需新建工程或删除默认文件。

截至 2026-07-20，已在 iPhone 17 模拟器以实际 SwiftUI 程序完成并确认：专业巡回赛风格首页、DTL 相机对齐、站姿锁定 READY 画面。模拟器的相机预览为黑色属正常现象，尚未进行真机安装或声学击球触发测试。

完整范围、已验证项目与真机前待测项见 [Pro Tour 模拟器验收记录](docs/validation/pro-tour-simulator-review.md)。

### 编译运行

1. 在 Xcode 27 beta 打开上述工程，选择 `iPhone 17` 模拟器。
2. 点击 Run (▶) 编译并启动。
3. 真机阶段仅在模拟器 UI 验收完成、且另行确认后执行；届时需启用 Developer Mode，并授予相机、麦克风和相册权限。

开发构建仅提供模拟器画面检查参数：`-swingarc-preview-dtl`、`-swingarc-preview-ready`、`-swingarc-preview-face-on`、`-swingarc-preview-face-on-ready`、`-swingarc-preview-waiting`、`-swingarc-preview-paused`、`-swingarc-preview-manual-capture`、`-swingarc-preview-library`、`-swingarc-preview-new-project`，以及配合本地测试影片的 `-swingarc-preview-import` / `-swingarc-preview-analysis`。它们被 `#if DEBUG` 隔离，不会进入发布构建或改变真机正常流程。

---

## 历史说明：从零导入源码（当前无需执行）

本工作区已为您生成了完整的 Swift 与 SwiftUI 核心源代码文件。请按照以下步骤在您的 Mac 电脑上编译运行：

### 第一步：新建 Xcode 项目
1. 打开您的 Mac **Xcode**，选择 **"Create a new Xcode project"**。
2. 选择 **iOS -> App** 模板，点击 Next。
3. 填入项目基本信息：
   - **Product Name**: `SwingArc`
   - **Organization Identifier**: `com.swingarc`
   - **Interface**: `SwiftUI`
   - **Language**: `Swift`
4. 选择保存位置并创建。

### 第二步：导入源文件
1. 在 Finder 中打开您的本地目录：`/Users/liangbo/Documents/SwingArc`。
2. 将该目录下的 **`SwingArc`** 文件夹（包含 `Models`、`Services`、`Views` 以及 `SwingArcApp.swift`）整体拖拽入 Xcode 左侧的项目导航器 (Project Navigator) 中。
3. 在弹出的对话框中：
   - 勾选 **"Copy items if needed"**。
   - 选择 **"Create groups"**。
   - 在 **"Add to targets"** 列表中勾选 **`SwingArc`**。
   - 点击 **Finish**。
4. 此时，您可以安全地删除 Xcode 默认生成的 `ContentView.swift` 和 `SwingArcApp.swift`（因为导入的文件夹中已经包含这两个同名文件）。

### 第三步：配置权限隐私描述 (Privacy Permissions)
本 App 需要调用手机摄像头录制和读取系统相册，需在项目设置中声明权限用途：
1. 在 Xcode 导航器中点击最顶部的项目根节点 **`SwingArc`**，然后选择 **Info** 标签页。
2. 在 **Custom iOS Target Properties** 列表中，悬浮并点击 `+` 号添加以下两项隐私声明：
   - **`Privacy - Camera Usage Description`** : `需要访问您的相机以录制高尔夫挥杆视频进行慢动作分析。`
   - **`Privacy - Photo Library Usage Description`** : `需要访问您的相册以导入高尔夫挥杆视频进行分析。`

### 第四步：编译并运行
1. 将您的 iPhone 或 iPad 通过数据线连接至 Mac 电脑（或者在 Xcode 顶部选择 iOS Simulator 模拟器）。
2. 在真机上，请确保已开启 **开发者模式 (Developer Mode)**（iOS 设置 -> 隐私与安全 -> 开发者模式 -> 开启并重启）。
3. 点击 Xcode 左上角的 **Run (▶)** 按钮进行编译安装。

---

## 📂 项目模块结构解析

* **`Models/DrawingModels.swift`**：
  定义了画笔工具类别（直线、圆形、3点夹角、手绘）、挥杆 P-阶段节点（P1 准备、P4 顶点、P6 下杆杆身平行、P7 击球、P8 击球后杆身平行）和自适应比例绘图元素数据结构；收杆仅保留为历史项目兼容标记。
* **`Services/VisionPoseDetector.swift`**：
  基于 Vision 框架，获取 CVPixelBuffer 并对 14+ 人体关节执行提取，转换为屏幕绘图坐标，完成脊椎角度和头部半径的数学计算。
* **`Views/CustomVideoPlayer.swift`**：
  桥接 AVPlayerLayer 与 SwiftUI。通过 `CADisplayLink` 定时器提取高帧率播放下的每一帧，提供 0.1x / 0.25x / 0.5x 慢动作切换和微秒级步进控制。
* **`Views/DrawingOverlay.swift`**：
  核心画板。监听 Touch 触控，处理三点量角器、直线和圆的触碰拉伸，包含磁贴关节吸附 (Snap) 和 2x 手写防遮挡放大镜算法。
* **`Views/CameraView.swift`**：
  120 FPS 慢动作相机。内含高帧率相机格式锁定逻辑、3秒起杆倒计时和对齐辅助网格。
* **`Views/ContentView.swift`**：
  主控制板。包含横屏（专业教练分析视图，带左右侧边控制面板）与竖屏（手持查看视图）的自适应布局。

---

## P1–P8 多关节定位验收

当前首版面向 30–120 FPS、正面或近正面固定机位。生产流程为：8 FPS 姿态粗扫分离并排序多个动作候选 → 逐个候选按源视频真实帧率精扫验证 → 向前/向后自适应扩展边界 → 提取未缓存帧 → 在候选邻域稀疏提取杆身与球位证据 → 以冲击走廊为锚点双向生成 P1–P8 候选 → 通过方向、关节、手相对髋部位置与证据质量联合求解。粗扫不再直接决定最终挥杆片段；只有通过完整时序约束的候选才会成为分析结果，避免把走路、弯腰或捡球动作误认为挥杆。整个自适应窗口严格不超过 8 秒；达到上限后以固定宽度朝缺失边界单向移动，并淘汰离开窗口的细扫缓存。8 FPS 粗扫与自适应细扫是两个独立流程，可能读取同一源帧；细扫窗口在单向演进期间每个源帧最多解码一次，杆球证据直接复用细扫图像，不增加视频解码。

所有自动阶段必须对应实际提取到的源视频帧。分析不插帧、不按视频百分比补点，也不把固定时间偏移当作阶段。缺少地址、顶点、冲击走廊或击球后动作边界时会返回对应失败；剪掉挥杆首尾的素材返回不完整挥杆错误。P6 没有可靠的杆身平行证据时保持未确定，P7 才使用杆身与球位变化证据。

在真实 iPhone 上重新构建后，使用正面或近正面挥杆视频逐项验证：正常稳定挥杆、上杆顶点短暂停顿、单侧手腕遮挡、快挥、慢挥、无人体视频、包含两次挥杆的视频，以及手动校正 P4 后重新分析并保存/重开项目。

对每个视频记录 P1–P8 的人工帧、自动帧、帧误差、`已确认 / 低置信度 / 未确定`、杆身证据和球位证据。当前验收标准为：DTL 与 Face-on 分别统计，每个 P 位至少 90% 的结果落在双人裁定真值的正负 2 个源视频帧内；未解析和错误确认均计为未通过。无充分杆身平行证据时 P6 不得显示为已确认；P7 的确认另需击球时刻的杆身与球位变化证据。手动设置的阶段必须在重新分析、保存和恢复后保持不变。最终保留集至少包含 10 位未参与训练或调参的球员，并按球员隔离训练、验证和验收数据。

### P1–P8 accuracy contract

Automatic stages always reference observed source frames. For DTL and Face-on separately, every P stage must reach at least a 90% hit rate within ±2 source frames of a frozen two-pass manual annotation. Unresolved and false confirmations count as misses. Missing required evidence is reported as low confidence, unresolved, or a specific clip failure; the app never fills a stage from a fixed timestamp or video percentage.

`/Users/liangbo/Desktop/IMG_4500.mov` 现保留为历史命名关键帧兼容性报告（`legacy-named-keyframes-v1`）：它不能作为 P1–P8 验收，尤其不能替代带杆身证据的 P6 与 P8 标注。其自适应窗口曾为 `12.2667–20.2667` 秒（严格 8.0 秒）；可重复运行：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library \
  -framework AVFoundation -framework Vision -framework ImageIO \
  -framework SwiftUI -framework CoreVideo \
  SwingArc/Models/DrawingModels.swift \
  SwingArc/Models/WorkspaceModels.swift \
  SwingArc/Models/FrameExtractionTolerancePolicy.swift \
  SwingArc/Services/StageCalibration.swift \
  SwingArc/Services/VisionPoseDetector.swift \
  SwingArc/Services/SwingStageDetector.swift \
  Tests/P1P8AcceptanceSupport.swift \
  Tests/RealVideoP1P8Acceptance.swift \
  -o /tmp/real-video-p1p8

/tmp/real-video-p1p8 \
  /Users/liangbo/Desktop/IMG_4500.mov \
  Tests/Fixtures/IMG_4500-ground-truth.json
```

当前 `/Users/liangbo/Desktop/test` 的 8 段 MOV 只用于建立标注流程、冻结算法基线和开发调试；一旦参与调参便不再具备独立验收资格。最终准确度结论必须来自至少 10 位未参与训练或调参的球员，DTL 与 Face-on 分开报告，并另用缺少准备段、球位遮挡、杆头出画和机位不合格素材验证明确降级。

## Studio Focus 通用界面

- iPhone 与 iPad 共用一套 SwiftUI 代码，并按水平 size class 自适应，不按设备型号分支。
- 项目库使用浅色本地项目卡；分析工作台使用深色固定区域，视频始终优先获得空间。
- iPhone 与 iPad 的 P1–P8 都使用一行八列紧凑阶段轴。
- 画线工具仅在画线模式出现；退出工具后全视频标注仍持续显示。
- AI 分析显示真实的定位挥杆段、逐帧提取和阶段求解进度，可取消，结果按已确认、待核对和未确定展示。
- 旧版本保存的“上次视频”会在首次打开新项目库时迁移为项目卡，不删除原视频或标注。

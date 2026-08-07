# YouTube 挥杆候选素材登记表（2026-07-22）

## 状态与边界

这是一次**候选检索**，不是训练数据集。检索只读取了公开视频的链接与元数据；没有下载视频、音频、缩略图或字幕，也没有把任何视频帧放入 SwingArc。

YouTube 的公开可观看状态不代表可复用、可抽帧或可训练。本表中每一条的 `license` 元数据均未返回明确许可，因此当前统一状态为：`blocked — 未获书面许可，不可入库`。

只有同时满足下列条件的素材才能从本表迁入受控本地评测集：

1. 权利人明确授权抽帧、双人标注、离线训练/评测、衍生处理及产品商业使用；或经人工核验的 CC BY 权利链；
2. 优先由权利人直接提供原始文件，而不是从 YouTube 抓取；
3. 已记录拍摄者、出镜者/场地许可、许可文本、来源 URL、取得日期和撤销联系渠道；
4. 视觉复核通过：单一完整挥杆、固定机位、全身/球/杆可见，无拼接、广播图层或速度插值；
5. 之后才做 P1–P8 两轮独立逐帧标注，并按**球手**而非帧随机拆分开发、验证和保留测试集。

`个人原始拍摄线索` 仅表示标题或说明看起来像上传者自录，适合后续寻求授权；它**不是**权属证明。

## DTL（后方/目标线）候选

| 候选 | 链接 | 上传者 | 时长 | 个人原始拍摄线索/画面线索 | 当前入库状态 |
| --- | --- | --- | ---: | --- | --- |
| DTL-01 | [Slow motion golf swing 120fps iPhone 5s](https://www.youtube.com/watch?v=6S2vqUnwH3g) | Tyler presto | 0:17 | 说明为测试自己的 iPhone 5s；120 fps；短单次挥杆候选 | blocked — 联系上传者并取得原文件/许可 |
| DTL-02 | [GoPro Hero 3 Slow Motion at 120fps of a Golf Swing](https://www.youtube.com/watch?v=2IW80rS4sD4) | Five on a Bike | 1:19 | 说明为 GoPro 3 120 fps，自录线索强；可能含变速或多个片段 | blocked — 需原始未变速片段 |
| DTL-03 | [My Golfswing Slowmotion](https://www.youtube.com/watch?v=GGK0LKHBm3A) | myaddiction2golf | 0:38 | 自我挥杆说明，但描述出现背景音乐 | blocked — 权利、音乐与原始无声文件均需确认 |
| DTL-04 | [My 7 Iron Golf Swing taken with my iPhone](https://www.youtube.com/watch?v=icZ4LT9pbNI) | 呂艾帥 | 0:23 | 自我 iPhone 拍摄说明；适合手机域候选 | blocked — 联系上传者 |
| DTL-05 | [Kethan Reddy slow motion golf swing jan 2014 face on down the line](https://www.youtube.com/watch?v=ULaF9RC3hI4) | kethan reddy | 0:29 | 说明为 iPhone 5s 拍摄，含 DTL 与 face-on；描述有配乐 | blocked — 需拆分原始单视角无音乐片段 |
| DTL-06 | [critique my golf swing (back view)](https://www.youtube.com/watch?v=8WWxrERXZ2c) | robisonhd | 0:49 | 自我挥杆、iPhone 4 慢动作；后方机位但 DTL 精确度待视觉核验 | blocked — 联系上传者，后续仅作 DTL 候选 |
| DTL-07 | [Driver swing down the line](https://www.youtube.com/watch?v=hs9fuDICchg) | Casen Davis | 0:15 | 标题明确 DTL，短片、单挥杆候选 | blocked — 联系上传者 |
| DTL-08 | [Full Swing down the line](https://www.youtube.com/watch?v=PXhEU-DHl0Q) | TheCoxFamily14 | 0:30 | 描述明确三脚架拍摄的 6 铁全挥杆 | blocked — 联系上传者；优先获取原始文件 |
| DTL-09 | [Hogan 4 wood Down the Line](https://www.youtube.com/watch?v=PmhXrVW5kb8) | Addam Smith | 0:17 | 标题明确 DTL，短片 | blocked — 旧第三方素材，权利链未明 |
| DTL-10 | [Ernie Els golf swing — long-iron (down-the-line view)](https://www.youtube.com/watch?v=qv1RWUfhPck) | Michael John Field | 0:17 | 描述称练习场、240 fps、DTL；适合作为专业固定机位质量参考 | blocked — 赛事/肖像/拍摄权均需权利人许可 |
| DTL-11 | [Martin Kaymer Golf Swing in High Speed (Down the Line)](https://www.youtube.com/watch?v=Fswo-1LH8G8) | Matthew Parry GOLF | 0:14 | 标题明确高帧率 DTL | blocked — 第三方专业素材 |
| DTL-12 | [Richard Green Golf Swing Down the Line in Slow Motion (Left Handed)](https://www.youtube.com/watch?v=4KtONOxhl0w) | Matthew Parry GOLF | 0:20 | 明确左手、DTL；可补充左右手覆盖 | blocked — 第三方专业素材 |
| DTL-13 | [BILLY HORSCHEL SLO-MO IRON SWING DTL](https://www.youtube.com/watch?v=Jm-wUQM7Bb4) | EK Golf | 0:14 | 明确 DTL、短片 | blocked — 赛事/转载风险 |
| DTL-14 | [David Duval Driver Golf Swing Slow Motion Down the Line](https://www.youtube.com/watch?v=rQyGT7Z_hDo) | ratetheswing | 0:10 | 明确 DTL，极短 | blocked — 第三方素材；也可能缺 P1/P8 上下文 |
| DTL-15 | [Driver HS 240 fps DTL](https://www.youtube.com/watch?v=i7LLPqxuirg) | Michael Yoder | 0:32 | 明确 240 fps、DTL；可能是自录高帧率候选 | blocked — 联系上传者并确认原片/机位 |

## FACE-ON（正面）候选

| 候选 | 链接 | 上传者 | 时长 | 个人原始拍摄线索/画面线索 | 当前入库状态 |
| --- | --- | --- | ---: | --- | --- |
| FO-01 | [My 5 iron golf swing face on taken with my iphone](https://www.youtube.com/watch?v=m6GYr5xxTQg) | 呂艾帥 | 0:08 | 自我 iPhone 正面拍摄；很短，须确认 P1/P8 是否完整 | blocked — 联系上传者 |
| FO-02 | [critique my golf swing (front view)](https://www.youtube.com/watch?v=O3dghohO-3U) | robisonhd | 0:39 | 自我挥杆、iPhone 4 慢动作；正面手机域候选 | blocked — 联系上传者 |
| FO-03 | [Golf Swing [iPhone 5s Slo-Mo]](https://www.youtube.com/watch?v=pPxSkbkvDMc) | instafication | 0:10 | iPhone 5s 慢动作，机位需视觉判定 | blocked — 联系上传者；确认是否完整正面挥杆 |
| FO-04 | [slow motion golf swing](https://www.youtube.com/watch?v=edIyFbdWMj4) | Daniel Cole | 0:22 | 说明为 iPhone 6 慢动作，机位需视觉判定 | blocked — 联系上传者 |
| FO-05 | [[Golf] Swing Check Slowmo by NEX-FS700](https://www.youtube.com/watch?v=E98K24YmsOc) | Pineappleholic | 1:29 | 说明为 240 fps，适合寻找未插帧的高帧率原片 | blocked — 联系上传者；分离单次完整挥杆 |
| FO-06 | [MP Face on Swing](https://www.youtube.com/watch?v=48niICKsJkM) | Matt Lindberg Golf | 1:26 | 标题明确正面；说明称 Sony RX10 II 1000 fps | blocked — 联系上传者；需原始采样率与是否重放确认 |
| FO-07 | [Tiger Woods Slow Mo Driver Swing](https://www.youtube.com/watch?v=Jlp8G9paliw) | TaylorMade Golf | 0:32 | 官方频道、短慢动作；专业正面构图参考 | blocked — 官方版权/肖像授权未取得 |
| FO-08 | [Dustin Johnson Mid-Iron Swing in SUPER Slow Motion](https://www.youtube.com/watch?v=v8lh6Ct-32U) | TaylorMade Golf | 0:34 | 官方频道，正面铁杆构图候选 | blocked — 官方版权/肖像授权未取得 |
| FO-09 | [Collin Morikawa's PURE Iron Swing](https://www.youtube.com/watch?v=02imCuJAZCw) | TaylorMade Golf | 0:35 | 官方频道，固定正面铁杆候选 | blocked — 官方版权/肖像授权未取得 |
| FO-10 | [Tiger Woods Face On Iron Swing At The Presidents Cup](https://www.youtube.com/watch?v=DXAG9p9h6G0) | TigerWoodsTV | 0:05 | 官方球员频道；极短，故更适合作为截断负例 | blocked — 版权/肖像授权未取得；不可作完整序列 |
| FO-11 | [Tommy Fleetwood's slo-mo swing is analyzed at Honda](https://www.youtube.com/watch?v=QjTxg3q8eIk) | EK Golf | 0:22 | 标题明确正面慢动作 | blocked — 分析图层/转载风险 |
| FO-12 | [BRYSON DECHAMBEAU SLOW MOTION DRIVER SWING (FACE ON)](https://www.youtube.com/watch?v=1d0MhjE1Jzs) | EK Golf | 0:19 | 标题明确正面、短单次候选 | blocked — 第三方赛事素材 |
| FO-13 | [Rory Mcilroy Pure Swing Sequence in Slow Motion (Face On)](https://www.youtube.com/watch?v=keRF_5VgtYI) | Visual Golf | 1:59 | 明确正面，但可能有重放或剪辑 | blocked — 第三方素材；先核验单次无剪辑段 |
| FO-14 | [HYO JOO KIM 120fps SLOW MOTION FACE ON DRIVER GOLF SWING](https://www.youtube.com/watch?v=iW323nsTGtU) | GolfswingHD | 2:01 | 明确 120 fps、正面；可补充女性职业球手 | blocked — 赛事/转载风险 |
| FO-15 | [Jason Day Driver Swing in Super Slow Motion, face on](https://www.youtube.com/watch?v=Eaw70tWpRLQ) | GOLFFY | 0:57 | 明确正面，时长较短 | blocked — 第三方素材/重放风险 |

## 明确保留的负例/拒收样本候选

这些视频也不能下载或入库；它们只说明日后应有哪类**授权负例**，用于验证算法是否正确返回低置信度或未解析，而不是臆造 P 点。

| 负例 | 链接 | 格式问题 | 建议拒收标签 |
| --- | --- | --- | --- |
| NEG-01 | [5 seconds of Adam Scott](https://www.youtube.com/watch?v=ZYJOrpdM0oU) | 6 秒，缺上下文 | `truncated_swing`, `insufficient_context`, `too_short` |
| NEG-02 | [Four! Kafka golf swing with camera mounted on club](https://www.youtube.com/watch?v=cRcmtOL1Cls) | 相机随杆移动 | `moving_camera`, `nonstandard_viewpoint`, `club_mounted_camera` |
| NEG-03 | [2024 Masters Tournament Final Round Broadcast](https://www.youtube.com/watch?v=Jn9auU-6JtQ) | 广播、多球手、切镜、图层 | `broadcast_graphics`, `multiple_golfers`, `scene_cuts` |
| NEG-04 | [Every shot from Rory McIlroy's win](https://www.youtube.com/watch?v=EVdj0aWbSo8) | 集锦和反复切换 | `broadcast_graphics`, `moving_camera`, `highlight_edit` |
| NEG-05 | [Golf swings in ULTRA slow motion](https://www.youtube.com/watch?v=b8LEAMlqE0E) | 多球手拼接 | `multiple_golfers`, `compilation`, `scene_cuts` |
| NEG-06 | [Ernie Els' sweet swing in slow motion (all angles)](https://www.youtube.com/watch?v=ebJmX66wqBo) | 多机位/多视角 | `multi_angle_edits`, `viewpoint_switching` |
| NEG-07 | [Tiger Woods' side-by-side swing analysis](https://www.youtube.com/watch?v=aO3-fqitzkw) | 分屏、分析叠层 | `split_screen`, `analysis_overlay`, `multi_angle_edits` |
| NEG-08 | [Tracing some of golf's best swings](https://www.youtube.com/watch?v=_tyKvfRO9Ok) | 路径图层与多个球手 | `graphics_overlay`, `analysis_overlay`, `multiple_golfers` |
| NEG-09 | [I Started My Golf Journey](https://www.youtube.com/watch?v=RcV6VB6PbVA) | Vlog，机位与内容混杂 | `moving_camera`, `vlog_format`, `mixed_content` |
| NEG-10 | [Driving Range Session — including shots off an iPhone](https://www.youtube.com/watch?v=UeBwT-QvbQ0) | 多种拍摄方式，机位不稳定 | `moving_camera`, `mixed_capture`, `inconsistent_framing` |
| NEG-11 | [RAPSODO Mobile Launch Monitor Indoor Review — NET MODE](https://www.youtube.com/watch?v=lT-AN1o6Fzo) | 室内球网遮挡球/杆 | `occluded_ball_flight`, `indoor_net`, `equipment_occlusion` |
| NEG-12 | [Golf Swing Systems Home Practice Golf Net with SkyTrak](https://www.youtube.com/watch?v=kKtg50oB8IU) | 室内球网、设备遮挡 | `occluded_ball_flight`, `indoor_net`, `equipment_occlusion` |

## 接下来的收集与验证顺序

1. **授权优先：** 先联系 DTL-01/02/04/05/06/07/08/15 与 FO-01/02/03/04/05/06 的上传者，索取原始文件和明确书面许可；本轮不联系、不下载。
2. **先建小而干净的基准：** 目标是 20 个 DTL、20 个 FACE-ON、8 个授权负例；每条都需要完整挥杆、固定机位和双人 P1–P8 标注。
3. **先测再调：** 在锁定当前算法基线后，逐段输出 P1–P8 帧误差、未解析率、误确认率、杆/球证据。不得用测试集调阈值。
4. **手机域保留：** 自录 iPhone 素材和获授权的手机原片必须占基准集主体；职业慢动作片可作为压力测试，不可替代真实产品拍摄条件。


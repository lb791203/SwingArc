import SwiftUI
import AVFoundation
import Combine

/// 视频播放核心管理器，负责控制回放、慢动作、逐帧步进和实时 Vision 姿态计算
class VideoPlaybackManager: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var playbackSpeed: Double = 1.0
    @Published var currentPose: PoseEstimationResult? = nil
    @Published var videoSize: CGSize = .zero
    @Published var videoRect: CGRect = .zero // 视频在屏幕上的实际渲染矩形（去除黑边）
    @Published var isProcessing = false
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    
    var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var timeObserver: Any?
    
    private let poseDetector = VisionPoseDetector()
    private var videoOrientation: CGImagePropertyOrientation = .up
    
    init() {}
    
    deinit {
        stopDisplayLink()
        removeObservers()
    }
    
    /// 加载本地或沙盒视频文件
    func loadVideo(url: URL) {
        isPlaying = false
        stopDisplayLink()
        removeObservers()
        
        let asset = AVAsset(url: url)
        
        // 获取视频原始分辨率和方向
        if let track = asset.tracks(withMediaType: .video).first {
            let transform = track.preferredTransform
            let size = track.naturalSize
            
            // 计算 Vision 识别所需的方向
            let angle = atan2(transform.b, transform.a)
            let degrees = angle * 180 / .pi
            switch Int(degrees) {
            case 90, -270:
                self.videoOrientation = .right
            case 180, -180:
                self.videoOrientation = .down
            case 270, -90:
                self.videoOrientation = .left
            default:
                self.videoOrientation = .up
            }
            
            if (transform.b == 1 && transform.c == -1) || (transform.b == -1 && transform.c == 1) {
                self.videoSize = CGSize(width: size.height, height: size.width)
            } else {
                self.videoSize = size
            }
        }
        
        // 创建带有像素缓冲输出的 AVPlayerItem
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]
        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        self.videoOutput = videoOutput
        
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.add(videoOutput)
        
        let player = AVPlayer(playerItem: playerItem)
        self.player = player
        
        // 观察总时长
        let durationSeconds = asset.duration.seconds
        self.duration = durationSeconds.isNaN ? 0 : durationSeconds
        
        // 播放进度观察器
        let interval = CMTime(value: 1, timescale: 120) // 每秒观察120次以实现超平滑拖动与慢放
        self.timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            // 只有当非手动拖动时，才由 player 更新当前播放时间
            if !self.isProcessing {
                self.currentTime = time.seconds
            }
        }
        
        // 播放结束监听
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        
        // 启动显示定时器，用于实时抓取像素缓冲区执行 Vision 检测
        startDisplayLink()
        
        // 运行首帧的姿态估计
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.processCurrentFramePose()
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        pause()
        seek(to: 0)
    }
    
    /// 播放
    func play() {
        guard let player = player else { return }
        player.rate = Float(playbackSpeed)
        isPlaying = true
    }
    
    /// 暂停
    func pause() {
        guard let player = player else { return }
        player.pause()
        isPlaying = false
    }
    
    /// 设置回放速度
    func setSpeed(_ speed: Double) {
        self.playbackSpeed = speed
        if isPlaying {
            player?.rate = Float(speed)
        }
    }
    
    /// 拖动到指定时间（秒）
    func seek(to time: Double) {
        guard let player = player else { return }
        isProcessing = true
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        
        // 使用精确 seek，对于高尔夫单帧分析至关重要
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            if finished {
                DispatchQueue.main.async {
                    self?.currentTime = time
                    if self?.isPlaying == true {
                        self?.processCurrentFramePose()
                    } else {
                        self?.extractPoseAtCurrentTime()
                    }
                    self?.isProcessing = false
                }
            }
        }
    }
    
    /// 暂停或拖拽进度条时，强制解帧获取实时骨骼数据
    private func extractPoseAtCurrentTime() {
        guard let player = player, let currentItem = player.currentItem else { return }
        let time = currentItem.currentTime()
        let asset = currentItem.asset
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                if let pose = self.poseDetector.detectPose(in: cgImage, orientation: .up) {
                    DispatchQueue.main.async {
                        self.currentPose = pose
                    }
                }
            } catch {
                print("提取帧用于骨骼分析失败: \(error)")
            }
        }
    }
    
    /// 逐帧步进：向前或向后移动一帧
    /// 假定 60fps 视频一帧约 16.7ms，30fps 约 33.3ms。高尔夫分析中我们按 240fps (约 4.1ms) 或普通帧 16ms 步进。
    func stepFrame(forward: Bool) {
        guard let player = player else { return }
        pause()
        
        // 采用 1/60 秒（约16.6毫秒）作为通用单帧步进单位，若是高速摄像则使用更小单位
        let frameDuration = 0.0166 
        let targetTime = forward ? (currentTime + frameDuration) : (currentTime - frameDuration)
        let clampedTime = max(0, min(targetTime, duration))
        
        seek(to: clampedTime)
    }
    
    // MARK: - Display Link & Vision Analysis
    
    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidFire))
        // 适配屏幕刷新率运行 (如 ProMotion 120Hz)
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func displayLinkDidFire() {
        // 只有在视频播放期间才实时刷新姿态估计
        if isPlaying {
            processCurrentFramePose()
        }
    }
    
    /// 抓取当前视频播放时刻的帧像素并交给 Vision 检测
    func processCurrentFramePose() {
        guard let player = player,
              let currentItem = player.currentItem,
              let videoOutput = videoOutput else { return }
        
        let itemTime = currentItem.currentTime()
        
        // 检查在此时间点是否有新的可用视频帧
        if videoOutput.hasNewPixelBuffer(forItemTime: itemTime) {
            var presentationItemTimeForDisplay = CMTime.zero
            if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &presentationItemTimeForDisplay) {
                // 运行姿态检测 (在后台线程执行，避免阻塞主线程渲染)
                DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                    guard let self = self else { return }
                    
                    if let result = self.poseDetector.detectPose(in: pixelBuffer, orientation: self.videoOrientation) {
                        DispatchQueue.main.async {
                            self.currentPose = result
                        }
                    }
                }
            }
        }
    }
    
    private func removeObservers() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        videoOutput = nil
        player = nil
    }
    
    /// 自动分析高尔夫球挥杆并识别关键阶段（P1 准备、P2 起杆、P4 顶点、P6 击球、P7 送杆、P8 收杆）
    func autoDetectSwingStages(completion: @escaping ([KeyframeMarker]) -> Void) {
        guard let player = player,
              let currentItem = player.currentItem else {
            completion([])
            return
        }
        
        let asset = currentItem.asset
        let durationSeconds = asset.duration.seconds
        guard durationSeconds > 0 && !durationSeconds.isNaN else {
            completion([])
            return
        }
        
        self.isScanning = true
        self.scanProgress = 0.0
        
        // 1. 进行后台像素帧抽取与 AI 姿态检测
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            
            // 我们在视频中抽取 60 个时间样本（提升密集度，解决捕捉不到 P4 和 P6 的问题）
            let sampleCount = 60
            var times: [CMTime] = []
            for i in 0..<sampleCount {
                let timeVal = Double(i) * durationSeconds / Double(sampleCount - 1)
                times.append(CMTime(seconds: timeVal, preferredTimescale: 600))
            }
            
            var detectedPoses: [(time: Double, pose: PoseEstimationResult)] = []
            let group = DispatchGroup()
            
            for time in times {
                group.enter()
                generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] _, cgImage, _, result, _ in
                    defer { group.leave() }
                    guard let self = self, result == .succeeded, let cgImage = cgImage else { return }
                    
                    // 用 VisionPoseDetector 运算姿态
                    if let pose = self.poseDetector.detectPose(in: cgImage, orientation: .up) {
                        detectedPoses.append((time: time.seconds, pose: pose))
                    }
                    
                    // 更新进度
                    DispatchQueue.main.async {
                        self.scanProgress = Double(detectedPoses.count) / Double(sampleCount)
                    }
                }
            }
            
            group.wait()
            
            // 2. 核心分析识别算法：结合人体运动学特征
            // 按时间排序
            detectedPoses.sort(by: { $0.time < $1.time })
            
            // 如果成功抓取到了关节点，则使用骨骼跟踪拟合；否则使用基于时间段的拟合算法作为坚实的兜底
            var markers: [KeyframeMarker] = []
            
            if detectedPoses.count >= 8 {
                // 找到双手/手腕 (wrist) 相对身体中轴线的位置
                // 1. P1 准备姿势 (Address): 前 25% 时间内手部最低点 (y 轴坐标最大值，由于 y=0.0 为顶部，y=1.0 为底部)
                let p1Range = detectedPoses.filter { $0.time <= durationSeconds * 0.25 }
                let p1Best = p1Range.max(by: { a, b in
                    let ay = a.pose.point(for: "rightWrist")?.y ?? 1.0
                    let by = b.pose.point(for: "rightWrist")?.y ?? 1.0
                    return ay < by
                })
                let p1Time = p1Best?.time ?? (durationSeconds * 0.08)
                
                // 2. P4 挥杆顶点 (Top of backswing): 在 P1 之后，20% - 60% 范围内，手部最高点 (y 轴坐标最小值)
                let p4Range = detectedPoses.filter { $0.time > p1Time && $0.time <= durationSeconds * 0.6 }
                let p4Best = p4Range.min(by: { a, b in
                    let ay = a.pose.point(for: "rightWrist")?.y ?? 1.0
                    let by = b.pose.point(for: "rightWrist")?.y ?? 1.0
                    return ay < by
                })
                let p4Time = p4Best?.time ?? (durationSeconds * 0.42)
                
                // 3. P2 起杆上拉 (Takeaway): P1 和 P4 的中点
                let p2Time = (p1Time + p4Time) / 2.0
                
                // 4. P6 击球刹那 (Impact): 在 P4 之后，手部最低点且速度最大（在此处手部 y 再次达到局部极大值）
                let p6Range = detectedPoses.filter { $0.time > p4Time && $0.time <= durationSeconds * 0.85 }
                let p6Best = p6Range.max(by: { a, b in
                    let ay = a.pose.point(for: "rightWrist")?.y ?? 1.0
                    let by = b.pose.point(for: "rightWrist")?.y ?? 1.0
                    return ay < by
                })
                let p6Time = p6Best?.time ?? (p4Time + (durationSeconds - p4Time) * 0.4)
                
                // 5. P7 送杆 (Follow-Through): 在 P6 之后，最后 80% - 90% 时间段内，当手腕再次高举并相对静止时
                let p7Range = detectedPoses.filter { $0.time > p6Time && $0.time <= durationSeconds * 0.92 }
                let p7Best = p7Range.min(by: { a, b in
                    let ay = a.pose.point(for: "rightWrist")?.y ?? 1.0
                    let by = b.pose.point(for: "rightWrist")?.y ?? 1.0
                    return ay < by
                })
                let p7Time = p7Best?.time ?? (durationSeconds * 0.85)
                
                // 6. P8 收杆 (Finish): 最后的稳定阶段
                let p8Time = durationSeconds * 0.95
                
                markers = [
                    KeyframeMarker(time: p1Time, stage: .address),
                    KeyframeMarker(time: p2Time, stage: .takeaway),
                    KeyframeMarker(time: p4Time, stage: .top),
                    KeyframeMarker(time: p4Time + (p6Time - p4Time) * 0.5, stage: .downswing),
                    KeyframeMarker(time: p6Time, stage: .impact),
                    KeyframeMarker(time: p7Time, stage: .followThrough),
                    KeyframeMarker(time: p8Time, stage: .finish)
                ]
            } else {
                // 兜底拟合算法 (依据标准挥杆时间比率分配)
                markers = [
                    KeyframeMarker(time: durationSeconds * 0.08, stage: .address),
                    KeyframeMarker(time: durationSeconds * 0.22, stage: .takeaway),
                    KeyframeMarker(time: durationSeconds * 0.45, stage: .top),
                    KeyframeMarker(time: durationSeconds * 0.58, stage: .downswing),
                    KeyframeMarker(time: durationSeconds * 0.70, stage: .impact),
                    KeyframeMarker(time: durationSeconds * 0.85, stage: .followThrough),
                    KeyframeMarker(time: durationSeconds * 0.95, stage: .finish)
                ]
            }
            
            // 3. 返回结果给主线程
            DispatchQueue.main.async {
                self.isScanning = false
                completion(markers)
            }
        }
    }
}

// MARK: - UIKit AVPlayerLayer 桥接视图

struct PlayerViewRepresentable: UIViewRepresentable {
    let player: AVPlayer
    let onVideoRectChanged: (CGRect) -> Void
    
    func makeUIView(context: Context) -> PlayerUIView {
        return PlayerUIView(player: player, onVideoRectChanged: onVideoRectChanged)
    }
    
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.updatePlayer(player)
    }
}

class PlayerUIView: UIView {
    private let playerLayer = AVPlayerLayer()
    var onVideoRectChanged: (CGRect) -> Void
    
    init(player: AVPlayer, onVideoRectChanged: @escaping (CGRect) -> Void) {
        self.onVideoRectChanged = onVideoRectChanged
        super.init(frame: .zero)
        
        backgroundColor = .black
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect // 维持宽高比，在界面中心显示视频，黑边填充
        layer.addSublayer(playerLayer)
        
        isUserInteractionEnabled = false // 禁用交互，防止 UIKit 拦截 SwiftUI Overlay 的手势
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        
        // 延时一下以确保 videoRect 已经完成计算并就绪
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let rect = self.playerLayer.videoRect
            if rect != .zero && rect.width > 0 && rect.height > 0 {
                self.onVideoRectChanged(rect)
            }
        }
    }
    
    func updatePlayer(_ player: AVPlayer) {
        if playerLayer.player !== player {
            playerLayer.player = player
            // 当更换视频时，重新发送视频渲染范围
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                let rect = self.playerLayer.videoRect
                if rect != .zero {
                    self.onVideoRectChanged(rect)
                }
            }
        }
    }
}

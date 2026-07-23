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
    @Published var analysisProgressPhase: AnalysisProgressPhase = .preparing
    @Published var sourceFrameRate: Double = 60
    @Published private(set) var mediaLoadState: MediaLoadState = .idle
    @Published private(set) var analysisState: SwingAnalysisState = .idle
    @Published private(set) var analysisResult: SwingAnalysisResult? = nil
    @Published private(set) var analysisOutput: SwingVideoAnalysisOutput? = nil
    @Published private(set) var analysisFailure: AnalysisFailure? = nil
    
    var player: AVPlayer?
    var currentAsset: AVAsset? { player?.currentItem?.asset }
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var timeObserver: Any?
    
    private let poseDetector = VisionPoseDetector()
    private let poseQueue = DispatchQueue(label: "com.liangbo.swingarc.pose", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "com.liangbo.swingarc.analysis", qos: .userInitiated)
    private var videoOrientation: CGImagePropertyOrientation = .up
    private var isPoseDetectionInFlight = false
    private let analysisRunGate = AnalysisRunGate()
    private var analysisRunID: UUID?
    
    init() {}
    
    deinit {
        stopDisplayLink()
        removeObservers()
    }
    
    /// 加载本地或沙盒视频文件
    @discardableResult
    func loadVideo(url: URL, fileManager: FileManager = .default) -> Bool {
        guard !url.isFileURL || fileManager.fileExists(atPath: url.path) else {
            unloadVideo()
            mediaLoadState = .missing
            return false
        }

        cancelAnalysis()
        isPlaying = false
        stopDisplayLink()
        removeObservers()
        analysisState = .idle
        analysisResult = nil
        analysisOutput = nil
        analysisFailure = nil
        scanProgress = 0
        analysisProgressPhase = .preparing
        currentPose = nil
        isPoseDetectionInFlight = false
        mediaLoadState = .ready
        
        let asset = AVAsset(url: url)
        
        // 获取视频原始分辨率和方向
        if let track = asset.tracks(withMediaType: .video).first {
            sourceFrameRate = track.nominalFrameRate > 0 ? Double(track.nominalFrameRate) : 60
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
        return true
    }

    func unloadVideo() {
        cancelAnalysis()
        pause()
        stopDisplayLink()
        removeObservers()
        currentTime = 0
        duration = 0
        currentPose = nil
        videoSize = .zero
        videoRect = .zero
        sourceFrameRate = 60
        analysisResult = nil
        analysisOutput = nil
        analysisFailure = nil
        analysisState = .idle
        mediaLoadState = .idle
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
        
        poseQueue.async { [weak self] in
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
        guard player != nil else { return }
        pause()
        
        let frameDuration = VideoFramePolicy.frameDuration(sourceFrameRate: sourceFrameRate)
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
        if isPlaying && !isScanning {
            processCurrentFramePose()
        }
    }
    
    /// 抓取当前视频播放时刻的帧像素并交给 Vision 检测
    func processCurrentFramePose() {
        guard let player = player,
              let currentItem = player.currentItem,
              let videoOutput = videoOutput,
              !isScanning else { return }
        
        let itemTime = currentItem.currentTime()
        
        // 检查在此时间点是否有新的可用视频帧
        if videoOutput.hasNewPixelBuffer(forItemTime: itemTime) {
            var presentationItemTimeForDisplay = CMTime.zero
            if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &presentationItemTimeForDisplay) {
                enqueuePoseDetection(pixelBuffer, orientation: videoOrientation)
            }
        }
    }

    /// Vision runs on a serial queue.  Keeping at most one request in flight
    /// prevents display-link ticks from building a stale frame backlog, which
    /// otherwise makes the overlay jump or disappear behind the video.
    private func enqueuePoseDetection(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        guard !isPoseDetectionInFlight else { return }
        isPoseDetectionInFlight = true
        poseQueue.async { [weak self] in
            guard let self = self else { return }
            let result = self.poseDetector.detectPose(in: pixelBuffer, orientation: orientation)
            DispatchQueue.main.async {
                // Keep the last valid pose through a single missed Vision frame.
                // This removes transient flashing without inventing pose data.
                if let result {
                    self.currentPose = result
                }
                self.isPoseDetectionInFlight = false
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
    
    /// Runs the shared adaptive engine and publishes only the active run.
    func analyzeSwing(completion: @escaping (SwingAnalysisResult) -> Void) {
        // Beginning a replacement atomically invalidates the old run without
        // publishing an explicit-cancel failure.
        let runID = AnalysisRunPublicationPolicy.beginReplacement(gate: analysisRunGate)
        analysisRunID = runID
        guard let player = player,
              let currentItem = player.currentItem,
              let asset = currentItem.asset as? AVURLAsset else {
            AnalysisRunPublicationPolicy.complete(runID: runID, gate: analysisRunGate) {
                self.analysisRunID = nil
                self.finishAnalysis(with: .noVideo, completion: completion)
            }
            return
        }

        isScanning = true
        scanProgress = 0.0
        analysisProgressPhase = .preparing
        analysisResult = nil
        analysisOutput = nil
        analysisFailure = nil
        analysisState = .scanning(progress: 0)
        analysisQueue.async { [weak self] in
            guard let self, self.analysisRunGate.isActive(runID) else { return }
            let outcome = SwingVideoAnalysisEngine().analyze(
                url: asset.url,
                runID: runID,
                gate: self.analysisRunGate
            ) { [weak self] update in
                DispatchQueue.main.async {
                    guard let self else { return }
                    AnalysisRunPublicationPolicy.publish(runID: runID, gate: self.analysisRunGate) {
                        self.analysisProgressPhase = update.phase
                        self.scanProgress = update.progress
                        self.analysisState = .scanning(progress: update.progress)
                    }
                }
            }
            DispatchQueue.main.async {
                switch outcome {
                case .cancelled:
                    return
                case let .completed(output):
                    let didPublish = AnalysisRunPublicationPolicy.complete(
                        runID: runID,
                        gate: self.analysisRunGate
                    ) {
                        self.analysisRunID = nil
                        self.isScanning = false
                        self.scanProgress = 1
                        self.sourceFrameRate = output.sourceFrameRate
                        self.analysisResult = output.result
                        self.analysisOutput = output
                        self.analysisFailure = nil
                        self.analysisState = .completed(output.result)
                    }
                    if didPublish {
                        completion(output.result)
                    }
                case let .failed(reason):
                    AnalysisRunPublicationPolicy.complete(runID: runID, gate: self.analysisRunGate) {
                        self.analysisRunID = nil
                        self.isScanning = false
                        self.scanProgress = 0
                        self.analysisResult = nil
                        self.analysisOutput = nil
                        self.analysisFailure = reason
                        self.analysisState = .failed(reason)
                    }
                }
            }
        }
    }

    func cancelAnalysis() {
        let wasScanning = isScanning
        if wasScanning, let runID = analysisRunID {
            AnalysisRunPublicationPolicy.cancel(runID: runID, gate: analysisRunGate) {
                self.analysisFailure = .analysisCancelled
                self.analysisState = .failed(.analysisCancelled)
                self.analysisResult = nil
                self.analysisOutput = nil
            }
        }
        analysisRunID = nil
        isScanning = false
        scanProgress = 0
        analysisProgressPhase = .preparing
        if !wasScanning {
            analysisState = .idle
            analysisResult = nil
            analysisOutput = nil
            analysisFailure = nil
        }
    }

    /// 兼容旧界面调用；新界面应使用 analyzeSwing 读取完整状态。
    func autoDetectSwingStages(completion: @escaping ([KeyframeMarker]) -> Void) {
        analyzeSwing { completion($0.detectedMarkers) }
    }

    private func finishAnalysis(with failure: AnalysisFailure, completion: @escaping (SwingAnalysisResult) -> Void) {
        let result = SwingAnalysisResult(detectedMarkers: [], unresolvedStages: Set(SwingStage.allCases))
        isScanning = false
        scanProgress = 0
        analysisProgressPhase = .preparing
        analysisResult = result
        analysisOutput = nil
        analysisFailure = failure
        analysisState = .failed(failure)
        completion(result)
    }

    func priorityFeedback(
        view: PracticeCameraView?,
        manualMarkers: [KeyframeMarker]
    ) -> PriorityFeedback? {
        guard let output = analysisOutput else { return nil }
        // Imported legacy videos may not carry a declared camera angle. Do
        // not turn that missing context into a false technique diagnosis.
        guard let view else { return nil }
        let detections = ManualStageDetectionPolicy.applying(
            manualMarkers: manualMarkers,
            sourceFrameRate: output.sourceFrameRate,
            automatic: output.result.detections,
            availablePoseSamples: output.poseSamples
        )
        return .select(from: SwingTechniqueEvaluator.evaluate(
            samples: output.poseSamples,
            stages: detections,
            view: view,
            leadArm: output.leadArm
        ))
    }

    func correctedDetections(
        manualMarkers: [KeyframeMarker]
    ) -> [SwingStageDetection] {
        guard let output = analysisOutput else { return [] }
        return ManualStageDetectionPolicy.applying(
            manualMarkers: manualMarkers,
            sourceFrameRate: output.sourceFrameRate,
            automatic: output.result.detections,
            availablePoseSamples: output.poseSamples
        )
    }

    func analysisArtifact(
        view: PracticeCameraView?,
        manualMarkers: [KeyframeMarker]
    ) -> SwingAnalysisArtifact? {
        feedbackPipeline(
            view: view,
            manualMarkers: manualMarkers
        )?.artifact
    }

    func simplifiedFeedback(
        view: PracticeCameraView?,
        manualMarkers: [KeyframeMarker]
    ) -> SimplifiedSwingFeedback? {
        feedbackPipeline(
            view: view,
            manualMarkers: manualMarkers
        )?.feedback
    }

    private func feedbackPipeline(
        view: PracticeCameraView?,
        manualMarkers: [KeyframeMarker]
    ) -> SwingFeedbackPipelineResult? {
        guard let output = analysisOutput else { return nil }
        return SwingFeedbackPipeline.make(
            output: output,
            view: view,
            manualMarkers: manualMarkers
        )
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

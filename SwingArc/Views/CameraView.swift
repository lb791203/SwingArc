import SwiftUI
import AVFoundation
import Combine

/// 摄像头录制回调
struct CameraView: View {
    @Environment(\.presentationMode) var presentationMode
    let onRecordCompleted: (URL) -> Void

    @State private var isRecording = false
    @State private var countdownValue = 0
    @State private var isCountingDown = false
    @State private var useFrontCamera = false
    @State private var timer: Timer? = nil

    @StateObject private var cameraState = CameraStateModel()

    var body: some View {
        ZStack {
            CameraPreviewRepresentable(cameraState: cameraState, useFrontCamera: useFrontCamera)
                .ignoresSafeArea()

            Color.black.opacity(0.26).ignoresSafeArea().allowsHitTesting(false)
            LinearGradient(
                colors: [
                    AnalysisTheme.proTourBackground.opacity(0.94),
                    .clear,
                    AnalysisTheme.proTourBackground.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            captureGuide

            VStack(spacing: 0) {
                header
                Spacer(minLength: 24)
                captureStatus
                Spacer(minLength: 24)
                captureControl
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            cameraState.setupSession()
        }
        .onDisappear {
            cameraState.stopSession()
            timer?.invalidate()
        }
        .onChange(of: cameraState.recordedVideoURL) { newURL in
            if let url = newURL {
                onRecordCompleted(url)
                presentationMode.wrappedValue.dismiss()
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(AnalysisTheme.proTourSurface.opacity(0.9), in: Circle())
                    .overlay(Circle().stroke(AnalysisTheme.proTourRaisedSurface))
            }
            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
            .accessibilityLabel("关闭录制")

            Spacer()

            VStack(spacing: 3) {
                Text("MANUAL CAPTURE")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.2)
                Text("120 FPS · LOCAL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            }
            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(AnalysisTheme.proTourSurface.opacity(0.9), in: Capsule())
            .overlay(Capsule().stroke(AnalysisTheme.proTourRaisedSurface))

            Spacer()

            Button {
                useFrontCamera.toggle()
                cameraState.toggleCamera(useFront: useFrontCamera)
            } label: {
                Image(systemName: "camera.rotate")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(AnalysisTheme.proTourSurface.opacity(0.9), in: Circle())
                    .overlay(Circle().stroke(AnalysisTheme.proTourRaisedSurface))
            }
            .foregroundStyle(AnalysisTheme.proTourPrimaryText)
            .accessibilityLabel("切换前后镜头")
        }
    }

    private var captureGuide: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(
                        AnalysisTheme.proTourSignal.opacity(isRecording ? 0.2 : 0.94),
                        style: StrokeStyle(lineWidth: 3, dash: [12, 10])
                    )
                    .frame(width: geometry.size.width * 0.62, height: geometry.size.height * 0.52)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.48)

                if !isRecording && !isCountingDown {
                    Text("FULL BODY + BALL IN FRAME")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(AnalysisTheme.proTourBackground.opacity(0.9), in: Capsule())
                        .overlay(Capsule().stroke(AnalysisTheme.proTourRaisedSurface))
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.76)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var captureStatus: some View {
        if isCountingDown {
            Text("\(countdownValue)")
                .font(.system(size: 132, weight: .black, design: .rounded))
                .foregroundStyle(AnalysisTheme.proTourSignal)
                .shadow(color: .black.opacity(0.7), radius: 16)
                .accessibilityLabel("倒计时 \(countdownValue)")
        } else {
            VStack(spacing: 11) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(isRecording ? AnalysisTheme.proTourPaused : AnalysisTheme.proTourSignal)
                        .frame(width: 10, height: 10)
                    Text(isRecording ? "RECORDING" : "READY TO CAPTURE")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(isRecording ? AnalysisTheme.proTourPaused : AnalysisTheme.proTourSignal)
                }
                Text(isRecording ? "RECORDING" : "READY")
                    .font(.system(size: 42, weight: .heavy, design: .monospaced))
                    .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                Text(isRecording ? "录制将在 6 秒后自动停止" : "架好手机后开始 3 秒倒计时")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(AnalysisTheme.proTourBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AnalysisTheme.proTourRaisedSurface))
        }
    }

    private var captureControl: some View {
        Button {
            if isRecording {
                stopRecording()
            } else if !isCountingDown {
                startCountdown()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 20, weight: .bold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isRecording ? "结束录制" : "开始倒计时")
                        .font(.system(size: 20, weight: .black))
                    Text(isRecording ? "保存当前挥杆影片" : "3 秒后自动录制")
                        .font(.system(size: 13, weight: .bold))
                        .opacity(0.68)
                }
                Spacer()
            }
            .foregroundStyle(isRecording ? AnalysisTheme.proTourPrimaryText : AnalysisTheme.proTourBackground)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(
                isRecording ? AnalysisTheme.proTourPaused : AnalysisTheme.proTourSignal,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isCountingDown)
        .opacity(isCountingDown ? 0.55 : 1)
    }

    private func startCountdown() {
        isCountingDown = true
        countdownValue = 3

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            if countdownValue > 1 {
                countdownValue -= 1
            } else {
                t.invalidate()
                isCountingDown = false
                startRecording()
            }
        }
    }
    
    private func startRecording() {
        isRecording = true
        cameraState.startRecording()

        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            if self.isRecording {
                self.stopRecording()
            }
        }
    }
    
    private func stopRecording() {
        isRecording = false
        cameraState.stopRecording()
    }
}

// MARK: - 相机状态模型类

class CameraStateModel: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    @Published var session = AVCaptureSession()
    @Published var recordedVideoURL: URL? = nil
    @Published private(set) var lastImpactTime: TimeInterval? = nil
    
    private var movieOutput = AVCaptureMovieFileOutput()
    private var activeVideoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let audioOutput = AVCaptureAudioDataOutput()
    private let audioQueue = DispatchQueue(label: "com.liangbo.swingarc.impact-audio", qos: .userInitiated)
    private var impactTrigger = ImpactTriggerPolicy()
    private var audioTimeOrigin: CMTime?
    private var isImpactMonitoring = false
    var onImpactDetected: ((TimeInterval) -> Void)?
    private var practiceWindow: PracticeClipWindow?
    private var practiceRecordingStartedAt: Date?
    private var practiceImpactDetectedAt: Date?
    private var practiceClipCompletion: ((Result<URL, PracticeSessionError>) -> Void)?
    private var discardsNextRecording = false
    
    func setupSession() {
        guard session.inputs.isEmpty else { return }
        
        session.beginConfiguration()
        
        // 预设高分辨率视频输入
        session.sessionPreset = .high
        
        // 默认获取后置广角镜头
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get back camera")
            session.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                activeVideoInput = input
            }
            
            // 尝试配置 120 FPS 高帧率
            configureHighFrameRate(for: camera)
            
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }

            configureImpactAudio()
            
            session.commitConfiguration()
            
            // 后台启动 Session
            DispatchQueue.global(qos: .background).async {
                self.session.startRunning()
            }
        } catch {
            print("Camera session setup error: \(error)")
            session.commitConfiguration()
        }
    }
    
    func stopSession() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    /// The caller arms this only after the user has explicitly started an
    /// automatic practice session. Preview audio alone must never create clips.
    func startImpactMonitoring(onImpactDetected: @escaping (TimeInterval) -> Void) {
        impactTrigger = ImpactTriggerPolicy()
        audioTimeOrigin = nil
        self.onImpactDetected = onImpactDetected
        isImpactMonitoring = true
    }

    func stopImpactMonitoring() {
        isImpactMonitoring = false
        onImpactDetected = nil
        audioTimeOrigin = nil
    }

    /// Starts one continuous source recording. The microphone detector arms
    /// only after the file output confirms recording has begun; the resulting
    /// callback receives a trimmed 2-second-before / 1-second-after clip.
    func startAutomaticPracticeRecording(
        window: PracticeClipWindow = .standard,
        completion: @escaping (Result<URL, PracticeSessionError>) -> Void
    ) {
        guard !movieOutput.isRecording else {
            DispatchQueue.main.async { completion(.failure(.recordingFailed)) }
            return
        }
        practiceWindow = window
        practiceRecordingStartedAt = nil
        practiceImpactDetectedAt = nil
        practiceClipCompletion = completion
        startRecording()
    }

    func cancelAutomaticPracticeRecording() {
        guard practiceWindow != nil || practiceClipCompletion != nil else { return }
        practiceWindow = nil
        practiceClipCompletion = nil
        practiceRecordingStartedAt = nil
        practiceImpactDetectedAt = nil
        discardsNextRecording = movieOutput.isRecording
        stopImpactMonitoring()
        stopRecording()
    }
    
    /// 切换前后摄像头
    func toggleCamera(useFront: Bool) {
        session.beginConfiguration()
        
        guard let currentInput = activeVideoInput else {
            session.commitConfiguration()
            return
        }
        
        session.removeInput(currentInput)
        
        let position: AVCaptureDevice.Position = useFront ? .front : .back
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            session.addInput(currentInput) // 失败则还原
            session.commitConfiguration()
            return
        }
        
        do {
            let newInput = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                activeVideoInput = newInput
                // 再次尝试高帧率配置
                configureHighFrameRate(for: camera)
            } else {
                session.addInput(currentInput)
            }
        } catch {
            session.addInput(currentInput)
        }
        
        session.commitConfiguration()
    }
    
    /// 锁定相机硬件配置 120 FPS / 240 FPS
    private func configureHighFrameRate(for device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            var selectedFormat: AVCaptureDevice.Format? = nil
            var maxRate: Float64 = 30.0
            
            // 遍历相机支持的视频格式
            for format in device.formats {
                for range in format.videoSupportedFrameRateRanges {
                    if range.maxFrameRate >= 120.0 {
                        // 寻找能够支持 120fps 及以上且分辨率理想的格式
                        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                        if dimensions.width >= 1280 { // 保证至少有 720p HD 高清
                            if range.maxFrameRate > maxRate {
                                maxRate = range.maxFrameRate
                                selectedFormat = format
                            }
                        }
                    }
                }
            }
            
            // 应用最高帧率格式
            if let format = selectedFormat {
                device.activeFormat = format
                let targetDuration = CMTime(value: 1, timescale: CMTimeScale(maxRate))
                device.activeVideoMinFrameDuration = targetDuration
                device.activeVideoMaxFrameDuration = targetDuration
                print("Successfully locked camera in \(maxRate) FPS high speed mode.")
            } else {
                print("This camera hardware does not support >=120 FPS slow motion recording.")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to lock device configuration: \(error)")
        }
    }
    
    // MARK: - 录制控制
    
    func startRecording() {
        guard !movieOutput.isRecording else { return }
        
        let tempDir = NSTemporaryDirectory()
        let fileName = "swing_record_\(UUID().uuidString).mp4"
        let outputURL = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
        
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }
    
    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    private func configureImpactAudio() {
        guard audioInput == nil,
              let microphone = AVCaptureDevice.default(for: .audio) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: microphone)
            if session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            }
            audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
            }
        } catch {
            print("Impact audio setup error: \(error)")
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output === audioOutput, isImpactMonitoring,
              let rms = audioRMS(from: sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid else { return }
        if audioTimeOrigin == nil { audioTimeOrigin = timestamp }
        let elapsed = CMTimeGetSeconds(CMTimeSubtract(timestamp, audioTimeOrigin ?? timestamp))
        guard elapsed.isFinite else { return }
        if impactTrigger.ingest(rms: rms, at: elapsed) {
            DispatchQueue.main.async {
                self.lastImpactTime = elapsed
                self.onImpactDetected?(elapsed)
            }
        }
    }

    private func audioRMS(from sampleBuffer: CMSampleBuffer) -> Double? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        let byteCount = CMBlockBufferGetDataLength(blockBuffer)
        guard byteCount >= MemoryLayout<Int16>.size else { return nil }
        var samples = [Int16](repeating: 0, count: byteCount / MemoryLayout<Int16>.size)
        let copyStatus = samples.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: byteCount, destination: $0.baseAddress!)
        }
        guard copyStatus == kCMBlockBufferNoErr else { return nil }
        let meanSquare = samples.reduce(0.0) { partial, sample in
            let normalized = Double(sample) / Double(Int16.max)
            return partial + normalized * normalized
        } / Double(samples.count)
        return sqrt(meanSquare)
    }
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("Camera recording started: \(fileURL)")
        guard let window = practiceWindow else { return }
        practiceRecordingStartedAt = Date()
        startImpactMonitoring { [weak self] elapsed in
            guard let self,
                  self.practiceImpactDetectedAt == nil,
                  elapsed >= window.preImpact else { return }
            self.practiceImpactDetectedAt = Date()
            self.stopImpactMonitoring()
            DispatchQueue.main.asyncAfter(deadline: .now() + window.postImpact + 0.12) {
                self.stopRecording()
            }
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Camera recording error: \(error.localizedDescription)")
        }

        if let window = practiceWindow {
            stopImpactMonitoring()
            let completion = practiceClipCompletion
            let recordingStartedAt = practiceRecordingStartedAt
            let impactDetectedAt = practiceImpactDetectedAt
            practiceWindow = nil
            practiceClipCompletion = nil
            practiceRecordingStartedAt = nil
            practiceImpactDetectedAt = nil
            guard error == nil,
                  let completion,
                  let recordingStartedAt,
                  let impactDetectedAt else {
                DispatchQueue.main.async {
                    completion?(.failure(.recordingFailed))
                }
                return
            }
            exportPracticeClip(
                sourceURL: outputFileURL,
                impactTime: impactDetectedAt.timeIntervalSince(recordingStartedAt),
                window: window,
                completion: completion
            )
            return
        }

        if discardsNextRecording {
            discardsNextRecording = false
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }
        
        // 传递录制结果
        DispatchQueue.main.async {
            self.recordedVideoURL = outputFileURL
        }
    }

    private func exportPracticeClip(
        sourceURL: URL,
        impactTime: TimeInterval,
        window: PracticeClipWindow,
        completion: @escaping (Result<URL, PracticeSessionError>) -> Void
    ) {
        let asset = AVURLAsset(url: sourceURL)
        let duration = CMTimeGetSeconds(asset.duration)
        guard let range = PracticeClipRangePolicy.resolve(
            impactTime: impactTime,
            sourceDuration: duration,
            window: window
        ) else {
            DispatchQueue.main.async { completion(.failure(.recordingFailed)) }
            return
        }
        guard let export = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            DispatchQueue.main.async { completion(.failure(.recordingFailed)) }
            return
        }
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("practice_clip_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: destination)
        export.outputURL = destination
        export.outputFileType = .mp4
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: range.start, preferredTimescale: 600),
            duration: CMTime(seconds: range.duration, preferredTimescale: 600)
        )
        export.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard export.status == .completed else {
                    completion(.failure(.recordingFailed))
                    return
                }
                try? FileManager.default.removeItem(at: sourceURL)
                self?.lastImpactTime = nil
                completion(.success(destination))
            }
        }
    }
}

extension CameraStateModel: PracticeClipRecording {
    func requestClip(
        window: PracticeClipWindow,
        completion: @escaping (Result<URL, PracticeSessionError>) -> Void
    ) {
        startAutomaticPracticeRecording(window: window, completion: completion)
    }

    func cancelPendingClip() {
        cancelAutomaticPracticeRecording()
    }
}

// MARK: - UIViewControllerRepresentable 预览视图

struct CameraPreviewRepresentable: UIViewRepresentable {
    @ObservedObject var cameraState: CameraStateModel
    var useFrontCamera: Bool
    
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = cameraState.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        // 更新画面拉伸属性
        uiView.previewLayer.connection?.videoOrientation = .portrait
        if useFrontCamera {
            uiView.previewLayer.connection?.isVideoMirrored = true // 前置需要镜像
        } else {
            uiView.previewLayer.connection?.isVideoMirrored = false
        }
    }
}

class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

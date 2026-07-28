import SwiftUI
import AVFoundation
import Combine
import UIKit

/// 摄像头录制回调
struct CameraView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    let onRecordCompleted: (URL) -> Void

    @State private var captureLifecycle = ManualCaptureLifecycle()
    @State private var useFrontCamera = false
    @State private var pendingAutomaticStop: DispatchWorkItem?
    @State private var recordingAlertMessage: String?

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

            if cameraState.accessState != .ready {
                Color.black.opacity(0.72).ignoresSafeArea()
                VStack(spacing: 16) {
                    if cameraState.accessState == .checking {
                        ProgressView()
                            .tint(AnalysisTheme.proTourSignal)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(AnalysisTheme.proTourSignal)
                    }

                    Text(CameraAccessPresentation.title(for: cameraState.accessState))
                        .font(.title2.bold())
                        .accessibilityLabel(
                            cameraState.accessState == .denied
                                ? "需要相机权限"
                                : CameraAccessPresentation.title(for: cameraState.accessState)
                        )

                    Text(CameraAccessPresentation.detail(for: cameraState.accessState))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AnalysisTheme.proTourSecondaryText)

                    if cameraState.accessState == .denied {
                        Button("打开设置") {
                            guard let url = URL(
                                string: UIApplication.openSettingsURLString
                            ) else { return }
                            openURL(url)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AnalysisTheme.proTourSignal)
                    }
                }
                .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                .padding(28)
                .background(
                    AnalysisTheme.proTourSurface,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .padding(24)
                .zIndex(10)
            }

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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                cameraState.setupSession()
            }
        }
        .onDisappear {
            pendingAutomaticStop?.cancel()
            if isRecording || isStartingRecording {
                captureLifecycle.didFinish()
                cameraState.stopRecording()
            }
            cameraState.stopSession()
        }
        .onChange(of: cameraState.recordedVideoURL) { _, newURL in
            if let url = newURL {
                onRecordCompleted(url)
                presentationMode.wrappedValue.dismiss()
            }
        }
        .onChange(of: cameraState.recordingFailureMessage) { _, message in
            guard let message else { return }
            pendingAutomaticStop?.cancel()
            pendingAutomaticStop = nil
            captureLifecycle.didFail()
            recordingAlertMessage = message
        }
        .alert(
            "录像未完成",
            isPresented: Binding(
                get: { recordingAlertMessage != nil },
                set: { if !$0 { recordingAlertMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(recordingAlertMessage ?? "")
        }
    }

    private var isRecording: Bool {
        captureLifecycle.state == .recording
    }

    private var isStartingRecording: Bool {
        captureLifecycle.state == .starting
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
                Text(ManualCapturePresentation.title)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.2)
                Text(ManualCapturePresentation.detail)
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
            .disabled(
                cameraState.accessState != .ready
                    || isStartingRecording
                    || isRecording
            )
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

                if !isRecording {
                    Text(ManualCapturePresentation.framingPrompt)
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
                Text(isRecording ? "最长 15 秒，可随时停止" : ManualCapturePresentation.readyDetail)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(AnalysisTheme.proTourBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AnalysisTheme.proTourRaisedSurface))
    }

    private var captureControl: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            VStack(spacing: 4) {
                Label(
                    isRecording ? "结束录制" : "开始录像",
                    systemImage: isRecording ? "stop.fill" : "record.circle"
                )
                .font(.system(size: 20, weight: .black, design: .rounded))

                Text(isRecording ? "保存当前挥杆影片" : "点击立即录制")
                    .font(.system(size: 13, weight: .bold))
                    .opacity(0.68)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(isRecording ? AnalysisTheme.proTourPrimaryText : AnalysisTheme.proTourBackground)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(
                isRecording ? AnalysisTheme.proTourPaused : AnalysisTheme.proTourSignal,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(
            !CameraAccessPresentation.canRecord(cameraState.accessState)
                || isStartingRecording
        )
    }
    
    private func startRecording() {
        guard CameraAccessPresentation.canRecord(cameraState.accessState) else {
            return
        }
        guard captureLifecycle.requestStart() else { return }
        cameraState.startRecording { result in
            switch result {
            case .success:
                captureLifecycle.didStart()
                scheduleAutomaticStop()
            case .failure(let error):
                captureLifecycle.didFail()
                recordingAlertMessage = error.localizedDescription
            }
        }
    }

    private func scheduleAutomaticStop() {
        guard captureLifecycle.shouldScheduleAutomaticStop else { return }
        let automaticStop = DispatchWorkItem { stopRecording() }
        pendingAutomaticStop = automaticStop
        DispatchQueue.main.asyncAfter(
            deadline: .now() + ManualCaptureTiming.maximumDuration,
            execute: automaticStop
        )
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        pendingAutomaticStop?.cancel()
        pendingAutomaticStop = nil
        captureLifecycle.didFinish()
        cameraState.stopRecording()
    }
}

// MARK: - 相机状态模型类

class CameraStateModel: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var session = AVCaptureSession()
    @Published var recordedVideoURL: URL? = nil
    @Published private(set) var captureFrameRate: Double = 30
    @Published private(set) var accessState: CameraAccessState = .checking
    @Published private(set) var recordingFailureMessage: String?
    
    private var movieOutput = AVCaptureMovieFileOutput()
    private var activeVideoInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.liangbo.swingarc.capture-session", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "com.liangbo.swingarc.live-vision", qos: .userInitiated)
    private var livePoseSampler = LivePoseSampler()
    private var liveSwingDetector = LiveSwingTriggerDetector(configuration: .standard)
    private var visualOutputAvailable = false
    private var isVisualMonitoring = false
    private var practiceRecordingTimeOrigin: TimeInterval?
    private var pendingBoundary: PracticeCaptureBoundary?
    private var lastPublishedCaptureStatus: PracticeCaptureStatus?
    private var practiceStatus: ((PracticeCaptureStatus) -> Void)?
    private var practiceClipCompletion: ((Result<RecordedPracticeClip, PracticeSessionError>) -> Void)?
    private var discardsNextRecording = false
    private var pendingRecordingStartCompletion: ((
        Result<Void, CameraRecordingStartError>
    ) -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func setupSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            accessState = .checking
            configureSessionIfNeeded()
        case .notDetermined:
            accessState = .checking
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.accessState = .checking
                        self.configureSessionIfNeeded()
                    } else {
                        self.accessState = .denied
                        self.stopSession()
                    }
                }
            }
        case .denied, .restricted:
            accessState = .denied
            stopSession()
        @unknown default:
            accessState = .unavailable
            stopSession()
        }
    }

    private func configureSessionIfNeeded() {
        guard session.inputs.isEmpty else {
            guard activeVideoInput != nil,
                  session.outputs.contains(where: { $0 === movieOutput }) else {
                accessState = .unavailable
                return
            }
            accessState = .checking
            startSessionIfNeeded()
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            session.commitConfiguration()
            accessState = .unavailable
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                accessState = .unavailable
                return
            }
            session.addInput(input)
            activeVideoInput = input
            configureHighFrameRate(for: camera)
            guard session.canAddOutput(movieOutput) else {
                session.removeInput(input)
                activeVideoInput = nil
                session.commitConfiguration()
                accessState = .unavailable
                return
            }
            session.addOutput(movieOutput)
            configureVisualOutput()
            session.commitConfiguration()
            startSessionIfNeeded()
        } catch {
            session.commitConfiguration()
            accessState = .unavailable
        }
    }

    private func startSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            self.publishRecordableReadiness()
        }
    }

    private func publishRecordableReadiness() {
        let videoConnection = movieOutput.connection(with: .video)
        let hasActiveVideoConnection = videoConnection?.isEnabled == true
            && videoConnection?.isActive == true
        let isRecordable = CameraRecordingReadiness.isRecordable(
            sessionIsRunning: session.isRunning,
            hasActiveVideoConnection: hasActiveVideoConnection
        )
        DispatchQueue.main.async { [weak self] in
            self?.accessState = isRecordable ? .ready : .unavailable
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// Starts one continuous source recording. A low-rate Vision stream finds
    /// the golfer and emits a complete or time-bounded swing interval.
    func startAutomaticPracticeRecording(
        status: @escaping (PracticeCaptureStatus) -> Void,
        completion: @escaping (Result<RecordedPracticeClip, PracticeSessionError>) -> Void
    ) {
        guard visualOutputAvailable else {
            status(.visualUnavailable(
                message: "此设备无法启动视觉检测，请返回选择手动录像。"
            ))
            completion(.failure(.recordingFailed))
            return
        }
        practiceStatus = status
        practiceRecordingTimeOrigin = nil
        pendingBoundary = nil
        lastPublishedCaptureStatus = nil
        practiceClipCompletion = completion
        startRecording { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.publishPracticeStatus(
                    .captureFrameRateChanged(self.captureFrameRate)
                )
                self.publishPracticeStatus(.searchingForPerson)
            case .failure:
                guard let completion = self.practiceClipCompletion else { return }
                self.clearAutomaticPracticeState()
                self.practiceClipCompletion = nil
                completion(.failure(.recordingFailed))
            }
        }
    }

    func cancelAutomaticPracticeRecording() {
        guard practiceClipCompletion != nil else { return }
        practiceClipCompletion = nil
        discardsNextRecording = movieOutput.isRecording
        clearAutomaticPracticeState()
        stopRecording()
    }
    
    /// 切换前后摄像头
    func toggleCamera(useFront: Bool) {
        accessState = .checking
        sessionQueue.async { [weak self] in
            self?.toggleCameraOnSessionQueue(useFront: useFront)
        }
    }

    private func toggleCameraOnSessionQueue(useFront: Bool) {
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
            publishRecordableReadiness()
        }
        
        guard let currentInput = activeVideoInput else {
            return
        }
        
        session.removeInput(currentInput)
        
        let position: AVCaptureDevice.Position = useFront ? .front : .back
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            session.addInput(currentInput) // 失败则还原
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
        
    }
    
    /// Prefer 240 FPS, then degrade explicitly to 120 or 60 FPS when the
    /// active camera cannot sustain the faster recording format.
    private func configureHighFrameRate(for device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            let preferredRates: [Float64] = [240, 120, 60]
            var selection: (format: AVCaptureDevice.Format, rate: Float64)?

            for targetRate in preferredRates {
                let candidates = device.formats.filter { format in
                    let dimensions = CMVideoFormatDescriptionGetDimensions(
                        format.formatDescription
                    )
                    guard dimensions.width >= 1280 else { return false }
                    return format.videoSupportedFrameRateRanges.contains { range in
                        range.minFrameRate <= targetRate && range.maxFrameRate >= targetRate
                    }
                }
                if let format = candidates.max(by: { lhs, rhs in
                    formatPreferenceScore(lhs) < formatPreferenceScore(rhs)
                }) {
                    selection = (format, targetRate)
                    break
                }
            }

            if let selection {
                let format = selection.format
                let selectedRate = selection.rate
                device.activeFormat = format
                let targetDuration = CMTime(
                    value: 1,
                    timescale: CMTimeScale(selectedRate)
                )
                device.activeVideoMinFrameDuration = targetDuration
                device.activeVideoMaxFrameDuration = targetDuration
                captureFrameRate = selectedRate
                print("Successfully locked camera in \(selectedRate) FPS high speed mode.")
            } else {
                captureFrameRate = 30
                print("This camera hardware does not support 60 FPS capture.")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to lock device configuration: \(error)")
        }
    }

    private func formatPreferenceScore(_ format: AVCaptureDevice.Format) -> Int64 {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let width = Int64(dimensions.width)
        let height = Int64(dimensions.height)
        let area = width * height
        let fullHD = Int64(1920 * 1080)
        if area <= fullHD {
            return fullHD + area
        }
        return max(0, fullHD - (area - fullHD))
    }
    
    // MARK: - 录制控制
    
    func startRecording(
        completion: @escaping (Result<Void, CameraRecordingStartError>) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.pendingRecordingStartCompletion == nil else {
                DispatchQueue.main.async {
                    completion(.failure(.rejected))
                }
                return
            }
            let videoConnection = self.movieOutput.connection(with: .video)
            let hasActiveVideoConnection = videoConnection?.isEnabled == true &&
                videoConnection?.isActive == true
            guard CameraRecordingReadiness.canStart(
                sessionIsRunning: self.session.isRunning,
                hasActiveVideoConnection: hasActiveVideoConnection,
                isAlreadyRecording: self.movieOutput.isRecording
            ) else {
                DispatchQueue.main.async {
                    completion(.failure(.notReady))
                }
                return
            }

            self.pendingRecordingStartCompletion = completion
            DispatchQueue.main.async {
                self.recordingFailureMessage = nil
            }
            let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("swing_record_\(UUID().uuidString).mp4")
            // Keep capture-session ordering serialized while satisfying the
            // delegate's main-actor isolation under the app target settings.
            DispatchQueue.main.sync {
                self.movieOutput.startRecording(
                    to: outputURL,
                    recordingDelegate: self
                )
            }
        }
    }
    
    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    private func configureVisualOutput() {
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_32BGRA)
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: visionQueue)
        guard session.canAddOutput(videoDataOutput) else {
            visualOutputAvailable = false
            return
        }
        session.addOutput(videoDataOutput)
        visualOutputAvailable = true
        if let connection = videoDataOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output === videoDataOutput,
              isVisualMonitoring,
              pendingBoundary == nil,
              var sample = livePoseSampler.sample(from: sampleBuffer) else {
            return
        }
        if practiceRecordingTimeOrigin == nil {
            practiceRecordingTimeOrigin = sample.time
        }
        guard let origin = practiceRecordingTimeOrigin else { return }
        sample = LivePoseMotionSample(
            time: max(0, sample.time - origin),
            personVisible: sample.personVisible,
            normalizedWristSpeed: sample.normalizedWristSpeed,
            normalizedTorsoSpeed: sample.normalizedTorsoSpeed,
            backswingDirectionScore: sample.backswingDirectionScore,
            followThroughScore: sample.followThroughScore
        )
        let update = liveSwingDetector.ingest(sample)
        guard let boundary = update.boundary else {
            publishDetectorState(update.state)
            return
        }
        pendingBoundary = boundary
        isVisualMonitoring = false
        publishPracticeStatus(.finalizing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.stopRecording()
        }
    }
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("Camera recording started: \(fileURL)")
        completePendingRecordingStart(.success(()))
        guard practiceClipCompletion != nil else { return }
        visionQueue.async { [weak self] in
            guard let self else { return }
            self.livePoseSampler.reset()
            self.liveSwingDetector.reset()
            self.practiceRecordingTimeOrigin = nil
            self.pendingBoundary = nil
            self.isVisualMonitoring = true
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Camera recording error: \(error.localizedDescription)")
            completePendingRecordingStart(.failure(.rejected))
            publishRecordingFailure(
                "录像中断：\(error.localizedDescription)"
            )
        }

        if practiceClipCompletion != nil {
            let completion = practiceClipCompletion
            let boundary = pendingBoundary
            practiceClipCompletion = nil
            clearAutomaticPracticeState()
            guard error == nil,
                  let completion,
                  let boundary else {
                DispatchQueue.main.async {
                    completion?(.failure(.recordingFailed))
                }
                return
            }
            exportPracticeClip(
                sourceURL: outputFileURL,
                boundary: boundary,
                completion: completion
            )
            return
        }

        if discardsNextRecording {
            discardsNextRecording = false
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        guard error == nil else {
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }
        
        // 传递录制结果
        DispatchQueue.main.async {
            self.recordedVideoURL = outputFileURL
        }
    }

    private func completePendingRecordingStart(
        _ result: Result<Void, CameraRecordingStartError>
    ) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let completion = self.pendingRecordingStartCompletion
            self.pendingRecordingStartCompletion = nil
            DispatchQueue.main.async {
                completion?(result)
            }
        }
    }

    private func publishRecordingFailure(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.recordingFailureMessage = message
        }
    }

    private func exportPracticeClip(
        sourceURL: URL,
        boundary: PracticeCaptureBoundary,
        completion: @escaping (Result<RecordedPracticeClip, PracticeSessionError>) -> Void
    ) {
        let asset = AVURLAsset(url: sourceURL)
        let duration = CMTimeGetSeconds(asset.duration)
        let start = max(0, boundary.swingStartTime - 1.0)
        let end = min(duration, boundary.swingEndTime + 0.8)
        guard duration.isFinite, start.isFinite, end.isFinite, end > start else {
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
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
        )
        export.exportAsynchronously {
            DispatchQueue.main.async {
                guard export.status == .completed else {
                    completion(.failure(.recordingFailed))
                    return
                }
                try? FileManager.default.removeItem(at: sourceURL)
                completion(.success(RecordedPracticeClip(
                    url: destination,
                    quality: boundary.quality
                )))
            }
        }
    }

    private func publishDetectorState(_ state: LiveSwingTriggerState) {
        switch state {
        case .searchingForPerson:
            publishPracticeStatus(.searchingForPerson)
        case .ready, .cooldown:
            publishPracticeStatus(.readyForSwing)
        case .swingInProgress, .finishing:
            publishPracticeStatus(.capturingSwing)
        }
    }

    private func publishPracticeStatus(_ status: PracticeCaptureStatus) {
        guard status != lastPublishedCaptureStatus else { return }
        lastPublishedCaptureStatus = status
        DispatchQueue.main.async { [weak self] in
            self?.practiceStatus?(status)
        }
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        handleSessionFailure("相机被系统中断，请稍候后重试。")
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.setupSession()
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
        let detail = error?.localizedDescription ?? "未知相机错误"
        handleSessionFailure("相机运行错误：\(detail)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.setupSession()
        }
    }

    private func handleSessionFailure(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.accessState = .checking
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            self.completePendingRecordingStart(.failure(.interrupted))
            self.publishRecordingFailure(message)
        }
    }

    private func clearAutomaticPracticeState() {
        isVisualMonitoring = false
        practiceRecordingTimeOrigin = nil
        pendingBoundary = nil
        lastPublishedCaptureStatus = nil
        practiceStatus = nil
    }
}

extension CameraStateModel: PracticeClipRecording {
    func requestClip(
        status: @escaping (PracticeCaptureStatus) -> Void,
        completion: @escaping (Result<RecordedPracticeClip, PracticeSessionError>) -> Void
    ) {
        startAutomaticPracticeRecording(status: status, completion: completion)
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
        guard let connection = uiView.previewLayer.connection else { return }
        connection.videoOrientation = .portrait
        if connection.isVideoMirroringSupported {
            // AVCaptureConnection throws an Objective-C exception if manual
            // mirroring is assigned while automatic mirroring remains enabled.
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = useFrontCamera
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

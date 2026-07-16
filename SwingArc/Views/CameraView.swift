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
            // 1. 原生相机画面预览
            CameraPreviewRepresentable(cameraState: cameraState, useFrontCamera: useFrontCamera)
                .ignoresSafeArea()
            
            // 2. 高尔夫站姿引导参考网格 (Golfer Stance Guide Grid)
            GeometryReader { geo in
                ZStack {
                    // 头部定位盒
                    Circle()
                        .stroke(Color.green.opacity(0.6), lineWidth: 2)
                        .frame(width: geo.size.width * 0.2, height: geo.size.width * 0.2)
                        .position(x: geo.size.width * 0.5, y: geo.size.height * 0.25)
                    
                    // 站姿定位线 (矩形和斜线)
                    Path { path in
                        // 地面基准线
                        path.move(to: CGPoint(x: 20, y: geo.size.height * 0.8))
                        path.addLine(to: CGPoint(x: geo.size.width - 20, y: geo.size.height * 0.8))
                        
                        // 身体站位左右限位线
                        path.move(to: CGPoint(x: geo.size.width * 0.35, y: geo.size.height * 0.35))
                        path.addLine(to: CGPoint(x: geo.size.width * 0.35, y: geo.size.height * 0.8))
                        
                        path.move(to: CGPoint(x: geo.size.width * 0.65, y: geo.size.height * 0.35))
                        path.addLine(to: CGPoint(x: geo.size.width * 0.65, y: geo.size.height * 0.8))
                    }
                    .stroke(Color.green.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    
                    // 文字提示
                    Text("请对齐头部与身体框架")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                        .position(
                            x: geo.size.width * 0.5,
                            y: CameraCaptureLayout.instructionVerticalPosition(containerHeight: geo.size.height)
                        )
                }
            }
            .ignoresSafeArea()
            
            // 3. 控制与浮层
            VStack {
                // 顶部关闭与摄像头切换
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("120 FPS 慢动作录像")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(20)
                    
                    Spacer()
                    
                    Button(action: {
                        useFrontCamera.toggle()
                        cameraState.toggleCamera(useFront: useFrontCamera)
                    }) {
                        Image(systemName: "camera.rotate")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 50)
                
                Spacer()
                
                // 巨大的倒计时显示
                if isCountingDown {
                    Text("\(countdownValue)")
                        .font(.system(size: 120, weight: .black, design: .rounded))
                        .foregroundColor(.yellow)
                        .shadow(color: .black, radius: 10)
                        .transition(.scale)
                }
                
                // 录制指示字样
                if isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("录制中 (6秒自动停止)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(15)
                }
                
                Spacer()
                
                // 录像控制大按钮
                HStack {
                    Spacer()
                    
                    Button(action: {
                        if isRecording {
                            stopRecording()
                        } else {
                            startCountdown()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 76, height: 76)
                            
                            if isRecording {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red)
                                    .frame(width: 32, height: 32)
                            } else {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 60, height: 60)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 40)
            }
        }
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
    
    // MARK: - 录制逻辑
    
    private func startCountdown() {
        isCountingDown = true
        countdownValue = 3 // 3 秒倒计时准备挥杆
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            if countdownValue > 1 {
                countdownValue -= 1
                // 播放滴答警告音 (可选)
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
        
        // 自动录制 6 秒停止（捕获完整高尔夫挥杆的最佳时长）
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

class CameraStateModel: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var session = AVCaptureSession()
    @Published var recordedVideoURL: URL? = nil
    
    private var movieOutput = AVCaptureMovieFileOutput()
    private var activeVideoInput: AVCaptureDeviceInput?
    
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
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("Camera recording started: \(fileURL)")
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Camera recording error: \(error.localizedDescription)")
        }
        
        // 传递录制结果
        DispatchQueue.main.async {
            self.recordedVideoURL = outputFileURL
        }
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

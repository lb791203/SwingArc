import Foundation

@main
struct CameraRecordingSerializationSmoke {
    static func main() throws {
        let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)

        guard let startRecording = source.range(of: "func startRecording()") else {
            preconditionFailure("CameraStateModel must expose the shared recording entry point")
        }
        let implementation = source[startRecording.lowerBound...]

        precondition(
            source.contains("private let sessionQueue = DispatchQueue"),
            "Capture session lifecycle and recording must share one serial queue"
        )
        precondition(
            implementation.contains("sessionQueue.async"),
            "Recording must be ordered after capture-session startup"
        )
        precondition(
            implementation.contains("CameraRecordingReadiness.canStart"),
            "Recording must reject an inactive video connection before AVFoundation can throw"
        )

        guard let previewUpdate = source.range(of: "func updateUIView(_ uiView: CameraPreviewView") else {
            preconditionFailure("Camera preview must configure its capture connection")
        }
        let previewImplementation = source[previewUpdate.lowerBound...]
        guard
            let disablesAutomaticMirroring = previewImplementation.range(
                of: "automaticallyAdjustsVideoMirroring = false"
            ),
            let setsManualMirroring = previewImplementation.range(of: "isVideoMirrored = useFrontCamera")
        else {
            preconditionFailure(
                "Preview must disable automatic mirroring before setting isVideoMirrored"
            )
        }
        precondition(
            disablesAutomaticMirroring.lowerBound < setsManualMirroring.lowerBound,
            "Automatic mirroring must be disabled before manual mirroring is assigned"
        )

        precondition(
            source.contains("AVCaptureVideoDataOutput"),
            "Automatic practice must inspect camera frames instead of microphone peaks"
        )
        precondition(
            source.contains("private let visionQueue = DispatchQueue"),
            "Live Vision work must stay off the capture-session and main queues"
        )
        precondition(
            !source.contains("AVCaptureAudioDataOutput") &&
                !source.contains("startImpactMonitoring") &&
                !source.contains("audioRMS"),
            "Automatic practice must not retain the microphone trigger path"
        )
    }
}

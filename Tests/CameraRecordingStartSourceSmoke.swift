import Foundation

@main
struct CameraRecordingStartSourceSmoke {
    static func main() throws {
        let source = try String(
            contentsOfFile: "SwingArc/Views/CameraView.swift",
            encoding: .utf8
        )
        let viewStart = try section(
            of: source,
            from: "private func startRecording()",
            to: "private func stopRecording()"
        )
        precondition(viewStart.contains("captureLifecycle.requestStart()"))
        precondition(viewStart.contains("cameraState.startRecording { result in"))
        precondition(viewStart.contains("case .success"))
        precondition(viewStart.contains("captureLifecycle.didStart()"))
        precondition(viewStart.contains("scheduleAutomaticStop()"))
        precondition(viewStart.contains("case .failure"))
        precondition(viewStart.contains("captureLifecycle.didFail()"))
        precondition(!viewStart.contains("isRecording = true"))

        let modelStart = try section(
            of: source,
            from: "func startRecording(\n        completion:",
            to: "func stopRecording()"
        )
        precondition(modelStart.contains("sessionQueue.async"))
        precondition(modelStart.contains("CameraRecordingReadiness.canStart"))
        precondition(modelStart.contains("pendingRecordingStartCompletion"))

        let didStart = try section(
            of: source,
            from: "didStartRecordingTo",
            to: "didFinishRecordingTo"
        )
        precondition(
            didStart.contains("completePendingRecordingStart(.success(()))")
        )
        let didFinish = try section(
            of: source,
            from: "didFinishRecordingTo",
            to: "private func exportPracticeClip"
        )
        precondition(didFinish.contains("completePendingRecordingStart"))
        precondition(didFinish.contains("recordingFailureMessage"))

        guard let startsSession = source.range(of: "session.startRunning()"),
              let publishesReadiness = source.range(
                  of: "publishRecordableReadiness()",
                  range: startsSession.upperBound..<source.endIndex
              ) else {
            preconditionFailure("Recordable readiness must follow startRunning")
        }
        precondition(startsSession.lowerBound < publishesReadiness.lowerBound)

        for notification in [
            "AVCaptureSessionWasInterrupted",
            "AVCaptureSessionInterruptionEnded",
            "AVCaptureSessionRuntimeError"
        ] {
            precondition(source.contains(notification))
        }
        precondition(source.contains("recordingFailureMessage"))
        precondition(source.contains(".onChange(of: cameraState.recordingFailureMessage)"))

        let viewLifecycle = try section(
            of: source,
            from: ".onDisappear {",
            to: ".onChange(of: cameraState.recordedVideoURL)"
        )
        precondition(viewLifecycle.contains("isStartingRecording"))
        precondition(viewLifecycle.contains("captureLifecycle.didFinish()"))
        precondition(viewLifecycle.contains("cameraState.stopRecording()"))

        let toggle = try section(
            of: source,
            from: "private func toggleCameraOnSessionQueue",
            to: "private func configureHighFrameRate"
        )
        precondition(
            toggle.contains("defer {"),
            "Every camera-switch exit must commit and republish readiness"
        )
        precondition(toggle.contains("session.commitConfiguration()"))
        precondition(toggle.contains("publishRecordableReadiness()"))
    }

    private static func section(
        of source: String,
        from start: String,
        to end: String
    ) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(
                  of: end,
                  range: startRange.upperBound..<source.endIndex
              ) else {
            throw SourceContractError.missing(start)
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
}

private enum SourceContractError: Error {
    case missing(String)
}

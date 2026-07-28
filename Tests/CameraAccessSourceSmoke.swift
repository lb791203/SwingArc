import Foundation

@main
struct CameraAccessSourceSmoke {
    static func main() throws {
        let camera = try String(
            contentsOfFile: "SwingArc/Views/CameraView.swift",
            encoding: .utf8
        )
        let content = try String(
            contentsOfFile: "SwingArc/Views/ContentView.swift",
            encoding: .utf8
        )

        precondition(camera.contains("AVCaptureDevice.authorizationStatus"))
        precondition(camera.contains("AVCaptureDevice.requestAccess"))
        precondition(camera.contains("UIApplication.openSettingsURLString"))
        precondition(camera.contains("CameraAccessPresentation.canRecord"))
        precondition(camera.contains("需要相机权限"))
        precondition(camera.contains("打开设置"))
        precondition(camera.contains("@Environment(\\.scenePhase) private var scenePhase"))

        let viewLifecycle = try section(
            of: camera,
            from: "struct CameraView: View",
            to: "private var header"
        )
        precondition(viewLifecycle.contains(".onAppear"))
        precondition(viewLifecycle.contains(".onChange(of: scenePhase)"))
        precondition(viewLifecycle.contains("phase == .active"))
        precondition(viewLifecycle.contains("cameraState.setupSession()"))

        let setup = try section(
            of: camera,
            from: "func setupSession()",
            to: "private func configureSessionIfNeeded()"
        )
        guard let authorization = setup.range(
            of: "AVCaptureDevice.authorizationStatus(for: .video)"
        ), let configureCall = setup.range(of: "configureSessionIfNeeded()") else {
            preconditionFailure("Authorization and configuration must both be explicit")
        }
        precondition(
            authorization.lowerBound < configureCall.lowerBound,
            "Authorization must be checked before session configuration"
        )

        let configuredSession = try section(
            of: camera,
            from: "private func configureSessionIfNeeded()",
            to: "func stopSession()"
        )
        precondition(configuredSession.contains("guard session.canAddInput(input) else"))
        precondition(configuredSession.contains("guard session.canAddOutput(movieOutput) else"))
        let inputFailure = try branch(
            in: configuredSession,
            from: "guard session.canAddInput(input) else",
            to: "session.addInput(input)"
        )
        precondition(inputFailure.contains("accessState = .unavailable"))
        precondition(inputFailure.contains("session.commitConfiguration()"))
        let outputFailure = try branch(
            in: configuredSession,
            from: "guard session.canAddOutput(movieOutput) else",
            to: "session.addOutput(movieOutput)"
        )
        precondition(outputFailure.contains("accessState = .unavailable"))
        precondition(outputFailure.contains("session.commitConfiguration()"))
        guard let ready = configuredSession.range(of: "accessState = .ready"),
              let startsSession = configuredSession.range(of: "startSessionIfNeeded()") else {
            preconditionFailure("Only a ready recording session may be started")
        }
        precondition(ready.lowerBound < startsSession.lowerBound)

        precondition(content.contains("showsSettingsAction"))
        precondition(content.contains("MediaExportError.photoPermissionDenied"))
        precondition(content.contains("UIApplication.openSettingsURLString"))
        let alert = try section(of: content, from: ".alert(\"SwingArc\"", to: ".overlay")
        guard let settingsCondition = alert.range(of: "if showsSettingsAction"),
              let settingsButton = alert.range(of: "Button(\"打开设置\")") else {
            preconditionFailure("Photos Settings action must be alert-scoped")
        }
        precondition(
            settingsCondition.lowerBound < settingsButton.lowerBound,
            "Photos Settings button must remain conditional"
        )

        let mediaAction = try section(
            of: content,
            from: "private func performMediaAction",
            to: "private func defaultProjectName"
        )
        precondition(mediaAction.contains("if case MediaExportError.photoPermissionDenied = error"))
        precondition(mediaAction.contains("showsSettingsAction = true"))
        precondition(mediaAction.contains("showsSettingsAction = false"))
        precondition(mediaAction.contains("guard let asset = playbackManager.currentAsset else"))
        for unrelatedStatus in [
            "视频导入失败：",
            "无法读取所选视频：",
            "录像已经完成，但保存失败。",
            "已有 P 点修正未能迁移，原数据仍保留。",
            "没有可导出的视频。",
            "当前帧已保存到相册。"
        ] {
            guard let messageRange = content.range(of: unrelatedStatus) else {
                preconditionFailure("Missing unrelated status message: \(unrelatedStatus)")
            }
            let contextStart = content.index(
                messageRange.lowerBound,
                offsetBy: -140,
                limitedBy: content.startIndex
            ) ?? content.startIndex
            let context = content[contextStart..<messageRange.lowerBound]
            precondition(
                context.contains("showsSettingsAction = false"),
                "Unrelated alerts must clear the Photos Settings action"
            )
        }

        precondition(!camera.contains("AVCaptureAudioDataOutput"))
        precondition(!camera.contains("AVCaptureDevice.requestAccess(for: .audio)"))
        precondition(!camera.contains("AVAudioSession"))
        precondition(!camera.contains("requestRecordPermission"))
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
            throw SourceContractError.missingSection(start)
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private static func branch(
        in source: Substring,
        from start: String,
        to end: String
    ) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(
                  of: end,
                  range: startRange.upperBound..<source.endIndex
              ) else {
            throw SourceContractError.missingSection(start)
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
}

private enum SourceContractError: LocalizedError {
    case missingSection(String)

    var errorDescription: String? {
        switch self {
        case .missingSection(let marker):
            return "Missing source section: \(marker)"
        }
    }
}

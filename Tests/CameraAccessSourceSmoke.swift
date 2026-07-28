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
        precondition(content.contains("showsSettingsAction"))
        precondition(content.contains("MediaExportError.photoPermissionDenied"))
        precondition(content.contains("UIApplication.openSettingsURLString"))
        precondition(content.contains("Button(\"打开设置\")"))
    }
}

import Foundation

@main
struct CameraAccessPolicySmoke {
    static func main() {
        precondition(!CameraAccessPresentation.canRecord(.checking))
        precondition(CameraAccessPresentation.canRecord(.ready))
        precondition(!CameraAccessPresentation.canRecord(.denied))
        precondition(!CameraAccessPresentation.canRecord(.unavailable))
        precondition(
            CameraAccessPresentation.title(for: .denied)
                == "需要相机权限"
        )
        precondition(
            CameraAccessPresentation.detail(for: .denied)
                .contains("设置")
        )
        precondition(
            CameraAccessPresentation.title(for: .unavailable)
                == "无法使用相机"
        )
    }
}

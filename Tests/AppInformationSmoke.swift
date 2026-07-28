import Foundation

@main
struct AppInformationSmoke {
    static func main() {
        precondition(AppInformation.privacyURL.scheme == "https")
        precondition(AppInformation.supportURL.scheme == "https")
        precondition(AppInformation.privacyURL.host == "lb791203.github.io")
        precondition(AppInformation.supportURL.host == "lb791203.github.io")
        precondition(
            AppInformation.version(
                marketingVersion: "1.0",
                buildNumber: "1"
            ) == "1.0 (1)"
        )
        precondition(
            AppInformation.version(
                marketingVersion: nil,
                buildNumber: nil
            ) == "版本未知"
        )
        precondition(AppInformation.analysisDisclaimer.contains("运动训练参考"))
        precondition(AppInformation.analysisDisclaimer.contains("可能不完整"))
    }
}

import Foundation

enum AppInformation {
    static let privacyURL = URL(
        string: "https://lb791203.github.io/SwingArc/app-store/privacy/"
    )!

    static let supportURL = URL(
        string: "https://lb791203.github.io/SwingArc/app-store/support/"
    )!

    static let analysisDisclaimer =
        "P1–P8 自动识别仅供运动训练参考，结果可能不完整；请使用逐帧修正核对关键位置。"

    static var currentVersion: String {
        version(
            marketingVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            buildNumber: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String
        )
    }

    static func version(
        marketingVersion: String?,
        buildNumber: String?
    ) -> String {
        guard let marketingVersion,
              !marketingVersion.isEmpty,
              let buildNumber,
              !buildNumber.isEmpty else {
            return "版本未知"
        }
        return "\(marketingVersion) (\(buildNumber))"
    }
}

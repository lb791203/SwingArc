import Foundation

@main
struct AboutPrivacySourceSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let content = try read(root, "SwingArc/Views/ContentView.swift")
        let home = try read(root, "SwingArc/Views/PracticeHomeView.swift")
        let about = try read(root, "SwingArc/Views/AboutPrivacyView.swift")
        let project = try read(root, "SwingArcProject.xcodeproj/project.pbxproj")

        precondition(content.contains("showAboutPrivacy"))
        precondition(content.contains("AboutPrivacyView()"))
        precondition(home.contains("onOpenAbout"))
        precondition(home.contains("关于与隐私"))
        precondition(about.contains("AppInformation.privacyURL"))
        precondition(about.contains("AppInformation.supportURL"))
        precondition(project.contains("AppInformation.swift in Sources"))
        precondition(project.contains("AboutPrivacyView.swift in Sources"))
    }

    private static func read(_ root: URL, _ path: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}

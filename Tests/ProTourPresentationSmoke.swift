import Foundation

@main
struct ProTourPresentationSmoke {
    static func main() {
        precondition(PracticeHomePresentation.modeOrder == [.downTheLine, .faceOn])
        precondition(PracticeHomePresentation.secondaryActions == [.importVideo, .history])
        precondition(
            PracticePresentationPolicy.primaryControl(
                for: .waitingForImpact(view: .downTheLine, swingCount: 0)
            ) == .pause
        )
        precondition(
            PracticePresentationPolicy.remoteStatus(for: .readyToStart(view: .faceOn)) == "READY"
        )
        precondition(
            PracticePresentationPolicy.remoteStatus(for: .processing(view: .downTheLine, swingCount: 3))
                == "ANALYSING · SHOT 03"
        )
        precondition(
            PracticePreviewConfiguration.view(
                for: ["-swingarc-preview-face-on"]
            ) == .faceOn
        )
        precondition(
            PracticePreviewConfiguration.view(
                for: ["-swingarc-preview-face-on-ready"]
            ) == .faceOn
        )
        precondition(
            PracticePreviewConfiguration.startsReady(
                for: ["-swingarc-preview-face-on-ready"]
            )
        )
        precondition(
            PracticePreviewConfiguration.showsLibrary(
                for: ["-swingarc-preview-library"]
            )
        )
        precondition(
            PracticePreviewConfiguration.importPath(
                for: ["-swingarc-preview-import", "/tmp/sample.mp4"]
            ) == "/tmp/sample.mp4"
        )
        precondition(
            PracticePreviewConfiguration.autoAnalyzes(
                for: ["-swingarc-preview-analysis"]
            )
        )
    }
}

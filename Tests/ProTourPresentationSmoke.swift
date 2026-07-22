import Foundation

@main
struct ProTourPresentationSmoke {
    static func main() {
        precondition(
            PracticeHomePresentation.modeOrder == [
                .downTheLine, .faceOn, .manualCapture, .importVideo
            ]
        )
        precondition(PracticeHomePresentation.secondaryActions.isEmpty)
        precondition(
            PracticePresentationPolicy.primaryControl(
                for: .readyForSwing(view: .downTheLine, swingCount: 0)
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
        precondition(
            PracticePreviewConfiguration.sessionPreview(
                for: ["-swingarc-preview-waiting"]
            ) == .waiting
        )
        precondition(
            PracticePreviewConfiguration.sessionPreview(
                for: ["-swingarc-preview-paused"]
            ) == .paused
        )
        precondition(
            PracticePresentationPolicy.remoteStatus(
                for: .paused(view: .downTheLine, swingCount: 0)
            ) == "PAUSED"
        )
        precondition(
            PracticePreviewConfiguration.showsManualCapture(
                for: ["-swingarc-preview-manual-capture"]
            )
        )
        precondition(
            PracticePreviewConfiguration.showsNewProject(
                for: ["-swingarc-preview-new-project"]
            )
        )
    }
}

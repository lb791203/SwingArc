import Foundation

@main
struct AnalysisThemeSmoke {
    static func main() {
        precondition(WorkspaceMode.drawing.showsToolTray)
        precondition(WorkspaceMode.drawing.requiresPausedPlayback)
        precondition(!WorkspaceMode.layers.showsToolTray)
        precondition(PlaybackRate.allCases.map(\.value) == [0.1, 0.25, 0.5, 1.0])
    }
}

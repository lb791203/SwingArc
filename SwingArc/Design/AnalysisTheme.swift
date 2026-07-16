import SwiftUI

enum AnalysisTheme {
    static let libraryBackground = Color(red: 0.95, green: 0.95, blue: 0.94)
    static let canvasBackground = Color(red: 0.08, green: 0.09, blue: 0.09)
    static let chrome = Color(red: 0.16, green: 0.17, blue: 0.17)
    static let active = Color(red: 0.97, green: 0.79, blue: 0.26)
    static let overlay = Color(red: 0.26, green: 0.83, blue: 0.77)
}

enum WorkspaceMode: Equatable {
    case idle
    case layers
    case drawing
    case keyframes

    var showsToolTray: Bool {
        self == .drawing
    }

    var requiresPausedPlayback: Bool {
        self == .drawing
    }
}

enum PlaybackRate: Double, CaseIterable, Identifiable {
    case tenth = 0.1
    case quarter = 0.25
    case half = 0.5
    case normal = 1

    var id: Double {
        rawValue
    }

    var value: Double {
        rawValue
    }

    var label: String {
        rawValue == 1 ? "1×" : "\(rawValue)×"
    }
}

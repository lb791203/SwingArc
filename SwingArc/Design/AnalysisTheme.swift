import SwiftUI

enum AnalysisTheme {
    // Modern professional-tour system. Signal is reserved for an action the
    // golfer can take now, never used as decorative accent colour.
    static let proTourBackground = Color(red: 0.035, green: 0.051, blue: 0.047)
    static let proTourSurface = Color(red: 0.075, green: 0.098, blue: 0.091)
    static let proTourRaisedSurface = Color(red: 0.116, green: 0.145, blue: 0.134)
    static let proTourGreen = Color(red: 0.12, green: 0.37, blue: 0.27)
    static let proTourSignal = Color(red: 0.78, green: 0.94, blue: 0.22)
    static let proTourPaused = Color(red: 0.95, green: 0.49, blue: 0.16)
    static let proTourPrimaryText = Color(red: 0.95, green: 0.96, blue: 0.93)
    static let proTourSecondaryText = Color(red: 0.60, green: 0.65, blue: 0.62)

    static let libraryBackground = Color(red: 0.965, green: 0.957, blue: 0.941)
    static let libraryCard = Color.white
    static let primaryText = Color(red: 0.08, green: 0.09, blue: 0.10)
    static let secondaryText = Color(red: 0.40, green: 0.42, blue: 0.45)
    static let canvasBackground = Color(red: 0.075, green: 0.082, blue: 0.09)
    static let chrome = Color(red: 0.12, green: 0.14, blue: 0.17)
    static let raisedChrome = Color(red: 0.17, green: 0.19, blue: 0.23)
    static let confirmed = Color(red: 0.18, green: 0.79, blue: 0.37)
    static let current = Color(red: 0.98, green: 0.78, blue: 0.20)
    static let pose = Color(red: 0.10, green: 0.75, blue: 0.87)

    // Compatibility aliases used by existing views and smoke tests.
    static let active = current
    static let overlay = pose
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

/// A fixed design size that still follows the system text size (Dynamic
/// Type). Small decorative labels get a floor so they stay readable outdoors.
struct ScaledSystemFont: ViewModifier {
    static let minimumSize: CGFloat = 11

    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: max(size, Self.minimumSize), relativeTo: .body)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }
}

/// Largest text size the fixed-layout screens support before they would
/// overlap; beyond this the system size is capped.
enum DynamicTypeLimit {
    static let maximum: DynamicTypeSize = .accessibility1
}

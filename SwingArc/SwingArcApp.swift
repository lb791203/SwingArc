// xcode: set sdk=iOS

import SwiftUI

@main
struct SwingArcApp: App {
    @State private var showsBrandLaunch = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()

                if showsBrandLaunch {
                    BrandLaunchView()
                }
            }
            .task {
                guard showsBrandLaunch else { return }
                try? await Task.sleep(nanoseconds: 450_000_000)
                showsBrandLaunch = false
            }
        }
    }
}

private struct BrandLaunchView: View {
    var body: some View {
        ZStack {
            AnalysisTheme.proTourBackground
                .ignoresSafeArea()

            BrandMarkView(size: 96, showsWordmark: false)
        }
        .accessibilityHidden(true)
    }
}

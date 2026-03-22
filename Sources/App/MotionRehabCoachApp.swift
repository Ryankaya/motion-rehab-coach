import SwiftUI

@main
struct MotionRehabCoachApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView(container: container)
        }
    }
}

private struct RootTabView: View {
    @ObservedObject var container: AppContainer

    var body: some View {
        TabView {
            DashboardView(container: container)
                .tabItem {
                    Label("Coach", systemImage: "figure.strengthtraining.traditional")
                }

            ProgressDashboardView(container: container)
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
        }
        .tint(Color(red: 0.04, green: 0.42, blue: 0.60))
    }
}

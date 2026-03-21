import SwiftUI

@main
struct MotionRehabCoachApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            DashboardView(container: container)
        }
    }
}

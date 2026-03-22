import SwiftUI

@main
struct MotionRehabCoachTVApp: App {
    @StateObject private var container = TVAppContainer()

    var body: some Scene {
        WindowGroup {
            TVCoachHomeView(viewModel: container.makeCoachViewModel())
        }
    }
}

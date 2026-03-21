import Foundation

@MainActor
final class AppContainer: ObservableObject {
    private let sessionStore: any SessionStore

    init(sessionStore: any SessionStore = FileSessionStore()) {
        self.sessionStore = sessionStore
    }

    func makeLiveSessionViewModel() -> LiveSessionViewModel {
        LiveSessionViewModel(
            sessionStore: sessionStore,
            poseEstimator: VisionPoseEstimator(),
            cameraService: CameraCaptureService()
        )
    }

    func makeSessionHistoryViewModel() -> SessionHistoryViewModel {
        SessionHistoryViewModel(sessionStore: sessionStore)
    }
}

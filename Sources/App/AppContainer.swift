import Foundation

@MainActor
final class AppContainer: ObservableObject {
    private let sessionStore: any SessionStore

    init(sessionStore: any SessionStore = FileSessionStore()) {
        self.sessionStore = sessionStore
    }

    func makeLiveSessionViewModel(exerciseType: ExerciseType) -> LiveSessionViewModel {
        LiveSessionViewModel(
            exerciseType: exerciseType,
            sessionStore: sessionStore,
            poseEstimator: VisionPoseEstimator(),
            cameraService: CameraCaptureService(),
            voiceCoach: SystemVoiceCoach()
        )
    }

    func makeSessionHistoryViewModel() -> SessionHistoryViewModel {
        SessionHistoryViewModel(sessionStore: sessionStore)
    }
}

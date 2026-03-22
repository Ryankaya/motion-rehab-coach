import Foundation

@MainActor
final class TVAppContainer: ObservableObject {
    let coachViewModel: TVCoachViewModel

    init() {
        coachViewModel = TVCoachViewModel(
            cameraService: TVContinuityCameraService(),
            poseEstimator: VisionPoseEstimator(),
            voiceCoach: TVVoiceCoach()
        )
    }
}

import Foundation

@MainActor
final class TVAppContainer: ObservableObject {
    func makeCoachViewModel() -> TVCoachViewModel {
        TVCoachViewModel(
            cameraService: TVContinuityCameraService(),
            poseEstimator: VisionPoseEstimator()
        )
    }
}

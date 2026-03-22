import AVFoundation
import Foundation

final class TVCoachViewModel: ObservableObject {
    enum TrackingState {
        case waitingForCamera
        case searchingPose
        case trackingPose
        case stopped
    }

    @Published private(set) var trackingState: TrackingState = .waitingForCamera
    @Published private(set) var statusMessage = "Connect your iPhone or iPad camera to Apple TV."
    @Published private(set) var feedback = "Waiting for Continuity Camera"
    @Published private(set) var cameraName = "No camera connected"
    @Published private(set) var continuityCameraCount = 0
    @Published private(set) var visibleJointCount = 0
    @Published private(set) var postureScore = 0.0
    @Published private(set) var estimatedFPS = 0.0
    @Published private(set) var latestPoseFrame: PoseFrame?

    @Published var isDevicePickerPresented = false

    var captureSession: AVCaptureSession { cameraService.session }

    private let cameraService: TVContinuityCameraService
    private let poseEstimator: PoseEstimating

    private var missedPoseFrameCount = 0
    private var previousFrameDate: Date?

    init(
        cameraService: TVContinuityCameraService,
        poseEstimator: PoseEstimating
    ) {
        self.cameraService = cameraService
        self.poseEstimator = poseEstimator

        cameraService.onFrame = { [weak self] buffer in
            self?.processFrame(buffer)
        }
    }

    func onAppear() {
        reconnectPreferredCamera()
    }

    func onDisappear() {
        cameraService.stop()
    }

    func openDevicePicker() {
        isDevicePickerPresented = true
    }

    func handlePickerConnected() {
        isDevicePickerPresented = false
        reconnectPreferredCamera()
    }

    func handlePickerCancelled() {
        isDevicePickerPresented = false
        refreshCameraTelemetry()
        if continuityCameraCount == 0 {
            trackingState = .waitingForCamera
            statusMessage = "No camera connected. Open picker and select your iPhone/iPad."
        }
    }

    func reconnectPreferredCamera() {
        refreshCameraTelemetry()

        do {
            try cameraService.startUsingPreferredCamera()
            refreshCameraTelemetry()
            trackingState = .searchingPose
            statusMessage = "Connected to \(cameraName). Stand in view to start posture tracking."
            feedback = "Looking for your lower-body pose"
        } catch TVContinuityCameraService.CameraError.continuityUnavailable {
            trackingState = .waitingForCamera
            statusMessage = "No Continuity Camera found. Open picker to connect your iPhone/iPad."
            feedback = "Waiting for camera"
            latestPoseFrame = nil
            visibleJointCount = 0
            postureScore = 0
        } catch {
            trackingState = .waitingForCamera
            statusMessage = "Unable to start camera feed: \(error.localizedDescription)"
            feedback = "Camera unavailable"
            latestPoseFrame = nil
            visibleJointCount = 0
            postureScore = 0
        }
    }

    func stopTracking() {
        cameraService.stop()
        trackingState = .stopped
        statusMessage = "Camera stopped"
        feedback = "Tracking paused"
        latestPoseFrame = nil
        visibleJointCount = 0
        postureScore = 0
        estimatedFPS = 0
        previousFrameDate = nil
        missedPoseFrameCount = 0
    }

    private func refreshCameraTelemetry() {
        continuityCameraCount = cameraService.continuityCameraCount
        cameraName = cameraService.currentCameraDisplayName
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        updateFPS()

        do {
            guard let pose = try poseEstimator.estimatePose(in: pixelBuffer) else {
                missedPoseFrameCount += 1

                if missedPoseFrameCount % 10 == 0 {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.trackingState = .searchingPose
                        self.visibleJointCount = 0
                        self.postureScore = 0
                        self.latestPoseFrame = nil
                        self.feedback = "No pose detected. Step back so hips, knees, and ankles are visible."
                    }
                }
                return
            }

            missedPoseFrameCount = 0
            let score = postureScore(for: pose)
            let jointCount = pose.joints.count
            let nextFeedback = makeFeedback(for: score, jointCount: jointCount)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.trackingState = .trackingPose
                self.latestPoseFrame = pose
                self.visibleJointCount = jointCount
                self.postureScore = score
                self.feedback = nextFeedback
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.trackingState = .searchingPose
                self?.feedback = "Pose analysis interrupted. Retrying..."
            }
        }
    }

    private func postureScore(for frame: PoseFrame) -> Double {
        guard !frame.joints.isEmpty else { return 0 }

        var checks = 0
        var successfulChecks = 0

        for joint in BodyJoint.allCases {
            guard let point = frame.point(for: joint) else { continue }
            checks += 1
            if point.confidence >= 0.50 {
                successfulChecks += 1
            }
        }

        if
            let leftKnee = frame.point(for: .leftKnee),
            let leftAnkle = frame.point(for: .leftAnkle)
        {
            checks += 1
            if abs(leftKnee.x - leftAnkle.x) < 0.20 {
                successfulChecks += 1
            }
        }

        if
            let rightKnee = frame.point(for: .rightKnee),
            let rightAnkle = frame.point(for: .rightAnkle)
        {
            checks += 1
            if abs(rightKnee.x - rightAnkle.x) < 0.20 {
                successfulChecks += 1
            }
        }

        guard checks > 0 else { return 0 }
        return (Double(successfulChecks) / Double(checks)) * 100
    }

    private func makeFeedback(for score: Double, jointCount: Int) -> String {
        if jointCount < BodyJoint.allCases.count {
            return "Need all lower-body joints visible (\(jointCount)/\(BodyJoint.allCases.count))."
        }
        if score >= 80 {
            return "Great posture. Keep moving with control."
        }
        if score >= 60 {
            return "Good tracking. Keep knees aligned over ankles."
        }
        return "Adjust stance and stay centered in frame for better posture score."
    }

    private func updateFPS() {
        let now = Date()

        if let previousFrameDate {
            let delta = now.timeIntervalSince(previousFrameDate)
            guard delta > 0 else { return }
            let instantFPS = 1 / delta
            let smoothed = estimatedFPS == 0 ? instantFPS : (estimatedFPS * 0.82) + (instantFPS * 0.18)

            DispatchQueue.main.async { [weak self] in
                self?.estimatedFPS = smoothed
            }
        }

        previousFrameDate = now
    }
}

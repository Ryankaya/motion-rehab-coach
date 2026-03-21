import AVFoundation
import Foundation

final class LiveSessionViewModel: ObservableObject {
    enum TrackingState {
        case idle
        case searching
        case tracking
    }

    @Published private(set) var isSessionRunning = false
    @Published private(set) var repetitionCount = 0
    @Published private(set) var qualityScore = 0.0
    @Published private(set) var currentKneeAngle = 0.0
    @Published private(set) var feedback = "Ready"
    @Published private(set) var trackingState: TrackingState = .idle
    @Published private(set) var visibleJointCount = 0
    @Published var errorMessage: String?
    @Published var cameraAccessDenied = false

    var captureSession: AVCaptureSession { cameraService.session }

    private let sessionStore: any SessionStore
    private let poseEstimator: PoseEstimating
    private let cameraService: CameraCaptureService

    private let processingQueue = DispatchQueue(label: "motion.rehab.processing")
    private let analyzer = RepetitionAnalyzer()

    private var startedAt: Date?
    private var kneeAngleSamples: [Double] = []
    private var missedPoseFrameCount = 0

    init(
        sessionStore: any SessionStore,
        poseEstimator: PoseEstimating,
        cameraService: CameraCaptureService
    ) {
        self.sessionStore = sessionStore
        self.poseEstimator = poseEstimator
        self.cameraService = cameraService

        self.cameraService.onFrame = { [weak self] pixelBuffer in
            self?.processingQueue.async {
                self?.processFrame(pixelBuffer)
            }
        }
    }

    func startSession() {
        Task {
            do {
                try await cameraService.start()
                await MainActor.run {
                    startedAt = Date()
                    kneeAngleSamples.removeAll(keepingCapacity: true)
                    missedPoseFrameCount = 0
                    analyzer.reset()
                    isSessionRunning = true
                    repetitionCount = 0
                    qualityScore = 0
                    currentKneeAngle = 0
                    visibleJointCount = 0
                    trackingState = .searching
                    feedback = "Session started. Keep hips, knees, and ankles in frame."
                    errorMessage = nil
                    cameraAccessDenied = false
                }
            } catch CameraCaptureService.CameraError.unauthorized {
                await MainActor.run {
                    cameraAccessDenied = true
                    errorMessage = "Camera permission is required for live motion tracking."
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to start camera: \(error.localizedDescription)"
                }
            }
        }
    }

    func stopSession() {
        cameraService.stop()

        guard let startedAt else {
            isSessionRunning = false
            trackingState = .idle
            return
        }

        let endedAt = Date()
        let averageAngle = kneeAngleSamples.average
        let computedQuality = qualityScore
        let reps = repetitionCount

        isSessionRunning = false
        trackingState = .idle
        visibleJointCount = 0
        feedback = "Session saved"

        let session = ExerciseSession(
            exerciseType: .squat,
            startedAt: startedAt,
            endedAt: endedAt,
            repetitionCount: reps,
            averageKneeAngle: averageAngle,
            qualityScore: computedQuality,
            notes: "Auto-generated from live pose analysis."
        )

        Task {
            do {
                try await sessionStore.append(session)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Unable to save session: \(error.localizedDescription)"
                }
            }
        }
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isSessionRunning else { return }

        do {
            guard let frame = try poseEstimator.estimatePose(in: pixelBuffer) else {
                missedPoseFrameCount += 1
                if missedPoseFrameCount % 8 == 0 {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.trackingState = .searching
                        self.visibleJointCount = 0
                        self.feedback = "No pose detected. Step back so your full lower body is visible."
                    }
                }
                return
            }

            missedPoseFrameCount = 0
            let snapshot = analyzer.process(frame)
            let jointCount = frame.joints.count

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.visibleJointCount = jointCount

                if let snapshot {
                    self.repetitionCount = snapshot.repetitionCount
                    self.qualityScore = snapshot.qualityScore
                    self.feedback = snapshot.feedback
                }

                if let angle = snapshot?.currentKneeAngle {
                    self.trackingState = .tracking
                    self.currentKneeAngle = angle
                    self.kneeAngleSamples.append(angle)
                    if self.kneeAngleSamples.count > 1500 {
                        self.kneeAngleSamples.removeFirst(self.kneeAngleSamples.count - 1500)
                    }
                } else {
                    self.trackingState = .searching
                    self.feedback = "Pose found (\(jointCount)/6 joints). Keep knees and ankles fully visible."
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.trackingState = .searching
                self?.errorMessage = "Pose estimation error: \(error.localizedDescription)"
            }
        }
    }
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

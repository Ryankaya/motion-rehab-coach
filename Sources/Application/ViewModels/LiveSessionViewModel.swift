import AVFoundation
import Foundation

final class LiveSessionViewModel: ObservableObject {
    @Published private(set) var isSessionRunning = false
    @Published private(set) var repetitionCount = 0
    @Published private(set) var qualityScore = 0.0
    @Published private(set) var currentKneeAngle = 0.0
    @Published private(set) var feedback = "Ready"
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
                    analyzer.reset()
                    isSessionRunning = true
                    repetitionCount = 0
                    qualityScore = 0
                    currentKneeAngle = 0
                    feedback = "Session started"
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
            return
        }

        let endedAt = Date()
        let averageAngle = kneeAngleSamples.average
        let computedQuality = qualityScore
        let reps = repetitionCount

        isSessionRunning = false
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
            guard let frame = try poseEstimator.estimatePose(in: pixelBuffer),
                  let snapshot = analyzer.process(frame)
            else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.repetitionCount = snapshot.repetitionCount
                self.qualityScore = snapshot.qualityScore
                self.feedback = snapshot.feedback

                if let angle = snapshot.currentKneeAngle {
                    self.currentKneeAngle = angle
                    self.kneeAngleSamples.append(angle)
                    if self.kneeAngleSamples.count > 1500 {
                        self.kneeAngleSamples.removeFirst(self.kneeAngleSamples.count - 1500)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
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

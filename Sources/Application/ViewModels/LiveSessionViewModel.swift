import AVFoundation
import Foundation

final class LiveSessionViewModel: ObservableObject {
    enum TrackingState {
        case idle
        case searching
        case tracking
    }

    @Published private(set) var selectedExerciseType: ExerciseType
    @Published private(set) var isSessionRunning = false
    @Published private(set) var repetitionCount = 0
    @Published private(set) var qualityScore = 0.0
    @Published private(set) var currentPrimaryMetricValue = 0.0
    @Published private(set) var feedback = "Ready"
    @Published private(set) var trackingState: TrackingState = .idle
    @Published private(set) var visibleJointCount = 0
    @Published var voiceCoachingEnabled = true {
        didSet {
            voiceCoach.isEnabled = voiceCoachingEnabled
            if !voiceCoachingEnabled {
                voiceCoach.reset()
            }
        }
    }
    @Published var errorMessage: String?
    @Published var cameraAccessDenied = false

    var captureSession: AVCaptureSession { cameraService.session }
    var primaryMetricTitle: String { selectedExerciseType.primaryMetricTitle }
    var primaryMetricUnit: String { selectedExerciseType.primaryMetricUnit }

    private let sessionStore: any SessionStore
    private let poseEstimator: PoseEstimating
    private let cameraService: CameraCaptureService
    private let voiceCoach: VoiceCoaching

    private let processingQueue = DispatchQueue(label: "motion.rehab.processing")
    private let analyzer: RepetitionAnalyzer

    private var startedAt: Date?
    private var primaryMetricSamples: [Double] = []
    private var missedPoseFrameCount = 0

    private var lastAnnouncedFeedback = ""
    private var lastAnnouncedRep = 0
    private var hasAnnouncedTrackingActive = false

    init(
        exerciseType: ExerciseType,
        sessionStore: any SessionStore,
        poseEstimator: PoseEstimating,
        cameraService: CameraCaptureService,
        voiceCoach: VoiceCoaching
    ) {
        self.selectedExerciseType = exerciseType
        self.sessionStore = sessionStore
        self.poseEstimator = poseEstimator
        self.cameraService = cameraService
        self.voiceCoach = voiceCoach
        self.analyzer = RepetitionAnalyzer(exerciseType: exerciseType)
        self.voiceCoach.isEnabled = voiceCoachingEnabled

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
                    primaryMetricSamples.removeAll(keepingCapacity: true)
                    missedPoseFrameCount = 0
                    lastAnnouncedFeedback = ""
                    lastAnnouncedRep = 0
                    hasAnnouncedTrackingActive = false

                    analyzer.reset()
                    isSessionRunning = true
                    repetitionCount = 0
                    qualityScore = 0
                    currentPrimaryMetricValue = 0
                    visibleJointCount = 0
                    trackingState = .searching
                    feedback = selectedExerciseType.sessionStartCue
                    errorMessage = nil
                    cameraAccessDenied = false
                    voiceCoach.announce(selectedExerciseType.sessionStartCue, priority: .high)
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
        voiceCoach.reset()

        guard let startedAt else {
            isSessionRunning = false
            trackingState = .idle
            return
        }

        let endedAt = Date()
        let averageMetric = primaryMetricSamples.average
        let computedQuality = qualityScore
        let reps = repetitionCount

        isSessionRunning = false
        trackingState = .idle
        visibleJointCount = 0
        feedback = "Session saved"

        let notes = "Primary metric: \(selectedExerciseType.primaryMetricTitle) (\(selectedExerciseType.primaryMetricUnit))."
        let session = ExerciseSession(
            exerciseType: selectedExerciseType,
            startedAt: startedAt,
            endedAt: endedAt,
            repetitionCount: reps,
            averageKneeAngle: averageMetric,
            qualityScore: computedQuality,
            notes: notes
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
                        let lostTrackingFeedback = "No pose detected. Step back so your full lower body is visible."
                        self.feedback = lostTrackingFeedback
                        self.announceFeedbackIfNeeded(lostTrackingFeedback)
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
                    self.announceFeedbackIfNeeded(snapshot.feedback)
                    self.announceRepetitionIfNeeded(snapshot.repetitionCount)
                }

                if let value = snapshot?.primaryMetricValue {
                    self.trackingState = .tracking
                    self.currentPrimaryMetricValue = value
                    self.primaryMetricSamples.append(value)
                    if self.primaryMetricSamples.count > 1500 {
                        self.primaryMetricSamples.removeFirst(self.primaryMetricSamples.count - 1500)
                    }

                    if !self.hasAnnouncedTrackingActive {
                        self.hasAnnouncedTrackingActive = true
                        self.voiceCoach.announce("Tracking active.", priority: .high)
                    }
                } else {
                    self.trackingState = .searching
                    let needsVisibilityFeedback = "Pose found (\(jointCount)/6 joints). Keep hips, knees, and ankles visible."
                    self.feedback = needsVisibilityFeedback
                    self.announceFeedbackIfNeeded(needsVisibilityFeedback)
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.trackingState = .searching
                self?.errorMessage = "Pose estimation error: \(error.localizedDescription)"
            }
        }
    }

    private func announceFeedbackIfNeeded(_ message: String) {
        guard message != lastAnnouncedFeedback else { return }
        lastAnnouncedFeedback = message
        voiceCoach.announce(message, priority: .normal)
    }

    private func announceRepetitionIfNeeded(_ count: Int) {
        guard count > lastAnnouncedRep else { return }
        lastAnnouncedRep = count
        voiceCoach.announce("Rep \(count) complete.", priority: .high)
    }
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

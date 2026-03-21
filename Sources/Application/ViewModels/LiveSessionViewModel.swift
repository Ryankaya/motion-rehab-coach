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
    @Published private(set) var latestPoseFrame: PoseFrame?
    @Published private(set) var formAlignmentScore = 0.0
    @Published private(set) var metricInTargetRange = false
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
    var targetMetricRange: ClosedRange<Double> {
        switch selectedExerciseType {
        case .squat:
            return 80...110
        case .sitToStand:
            return 90...120
        case .lunge:
            return 85...112
        case .miniSquat:
            return 112...132
        case .calfRaise:
            return 2.2...3.8
        }
    }

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
                    latestPoseFrame = nil
                    formAlignmentScore = 0
                    metricInTargetRange = false
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
        latestPoseFrame = nil
        formAlignmentScore = 0
        metricInTargetRange = false
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
                        self.latestPoseFrame = nil
                        self.formAlignmentScore = 0
                        self.metricInTargetRange = false
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
            let alignmentScore = calculateFormAlignmentScore(for: frame)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.visibleJointCount = jointCount
                self.latestPoseFrame = frame
                self.formAlignmentScore = alignmentScore

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
                    self.metricInTargetRange = self.targetMetricRange.contains(value)
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
                    self.metricInTargetRange = false
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

    private func calculateFormAlignmentScore(for frame: PoseFrame) -> Double {
        let targets = jointTargets(for: selectedExerciseType)
        var totalChecks = 0
        var successfulChecks = 0

        for joint in BodyJoint.allCases {
            guard
                let target = targets[joint],
                let point = frame.point(for: joint)
            else {
                continue
            }

            totalChecks += 1
            let withinX = target.x.contains(point.x)
            let withinY = target.y.contains(point.y)
            if withinX && withinY {
                successfulChecks += 1
            }
        }

        if
            let leftKnee = frame.point(for: .leftKnee),
            let leftAnkle = frame.point(for: .leftAnkle)
        {
            totalChecks += 1
            if abs(leftKnee.x - leftAnkle.x) < horizontalAlignmentTolerance {
                successfulChecks += 1
            }
        }

        if
            let rightKnee = frame.point(for: .rightKnee),
            let rightAnkle = frame.point(for: .rightAnkle)
        {
            totalChecks += 1
            if abs(rightKnee.x - rightAnkle.x) < horizontalAlignmentTolerance {
                successfulChecks += 1
            }
        }

        guard totalChecks > 0 else { return 0 }
        return Double(successfulChecks) / Double(totalChecks)
    }

    private var horizontalAlignmentTolerance: Double {
        switch selectedExerciseType {
        case .lunge:
            return 0.25
        case .squat, .sitToStand, .miniSquat, .calfRaise:
            return 0.20
        }
    }

    private func jointTargets(for exercise: ExerciseType) -> [BodyJoint: JointTarget] {
        let base: [BodyJoint: JointTarget] = [
            .leftHip: .init(x: 0.18...0.47, y: 0.56...0.92),
            .rightHip: .init(x: 0.53...0.82, y: 0.56...0.92),
            .leftKnee: .init(x: 0.16...0.47, y: 0.34...0.74),
            .rightKnee: .init(x: 0.53...0.84, y: 0.34...0.74),
            .leftAnkle: .init(x: 0.13...0.49, y: 0.07...0.48),
            .rightAnkle: .init(x: 0.51...0.87, y: 0.07...0.48)
        ]

        switch exercise {
        case .lunge:
            return [
                .leftHip: .init(x: 0.14...0.56, y: 0.56...0.92),
                .rightHip: .init(x: 0.44...0.86, y: 0.56...0.92),
                .leftKnee: .init(x: 0.10...0.58, y: 0.26...0.76),
                .rightKnee: .init(x: 0.42...0.90, y: 0.26...0.76),
                .leftAnkle: .init(x: 0.08...0.60, y: 0.05...0.50),
                .rightAnkle: .init(x: 0.40...0.92, y: 0.05...0.50)
            ]
        case .sitToStand:
            return [
                .leftHip: .init(x: 0.24...0.50, y: 0.54...0.90),
                .rightHip: .init(x: 0.50...0.76, y: 0.54...0.90),
                .leftKnee: .init(x: 0.24...0.50, y: 0.32...0.74),
                .rightKnee: .init(x: 0.50...0.76, y: 0.32...0.74),
                .leftAnkle: .init(x: 0.24...0.52, y: 0.08...0.46),
                .rightAnkle: .init(x: 0.48...0.76, y: 0.08...0.46)
            ]
        case .squat, .miniSquat, .calfRaise:
            return base
        }
    }
}

private struct JointTarget {
    let x: ClosedRange<Double>
    let y: ClosedRange<Double>
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

import AudioToolbox
import AVFoundation
import Foundation

final class LiveSessionViewModel: ObservableObject {
    enum TrackingState {
        case idle
        case searching
        case tracking
    }

    enum MovementPhase: String {
        case idle
        case eccentric
        case concentric
        case steady

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .eccentric: return "Eccentric"
            case .concentric: return "Concentric"
            case .steady: return "Steady"
            }
        }
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

    @Published private(set) var symmetryScore = 0.0
    @Published private(set) var compensationAlert: String?
    @Published private(set) var compensationAlertsCount = 0
    @Published private(set) var movementPhaseLabel = MovementPhase.idle.label
    @Published private(set) var eccentricTempo = 0.0
    @Published private(set) var concentricTempo = 0.0
    @Published private(set) var tempoScore = 0.0

    @Published private(set) var watchHeartRate: Double?
    @Published private(set) var watchReachable = false

    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var calibrationMessage = "Run calibration before your first session."
    @Published private(set) var isCalibrating = false
    @Published private(set) var isCalibrationReady = false

    @Published var metronomeEnabled: Bool
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

    @Published private(set) var targetProfile: TargetProfile

    let painScore: Int
    let rpeGoal: Int
    let clinicianSharingMode: Bool

    var captureSession: AVCaptureSession { cameraService.session }
    var primaryMetricTitle: String { selectedExerciseType.primaryMetricTitle }
    var primaryMetricUnit: String { selectedExerciseType.primaryMetricUnit }
    var targetMetricRange: ClosedRange<Double> { targetProfile.metricRange }
    var targetProfileSourceLabel: String { targetProfile.source.label }
    var jointTargets: [BodyJoint: JointTarget] { targetProfile.jointTargets }
    var protocolAdjustmentSummary: String { adjustmentSummaryText }

    private let sessionStore: any SessionStore
    private let poseEstimator: PoseEstimating
    private let cameraService: CameraCaptureService
    private let voiceCoach: VoiceCoaching
    private let watchSync: any WatchSessionSyncing

    private let processingQueue = DispatchQueue(label: "motion.rehab.processing")
    private let analyzer: RepetitionAnalyzer

    private var startedAt: Date?
    private var primaryMetricSamples: [Double] = []
    private var symmetrySamples: [Double] = []
    private var eccentricTempoSamples: [Double] = []
    private var concentricTempoSamples: [Double] = []
    private var calibrationFrames: [PoseFrame] = []
    private var highQualitySamples: [AdaptiveSample] = []
    private var calibrationCompletionPending = false
    private var missedPoseFrameCount = 0

    private var previousMetricValue: Double?
    private var previousMetricTimestamp: Date?
    private var currentMovementPhase: MovementPhase = .idle
    private var phaseStartedAt: Date?
    private var lastMetronomeCueAt = Date.distantPast
    private var lastCompensationAnnouncementAt = Date.distantPast
    private var lastWatchSyncAt = Date.distantPast

    private var lastAnnouncedFeedback = ""
    private var lastAnnouncedRep = 0
    private var hasAnnouncedTrackingActive = false

    private let calibrationFrameTargetCount = 60
    private let adaptiveSampleMinimum = 12
    private let adaptiveSampleWindow = 48
    private let adaptiveUpdateInterval = 6
    private let adaptiveMinimumQuality = 90.0
    private let adaptiveBlendAlpha = 0.18
    private let compensationAnnouncementInterval: TimeInterval = 4.5
    private let watchSyncInterval: TimeInterval = 1.2
    private let metronomeCueInterval: TimeInterval = 1.4
    private let tempoTargetSeconds: Double
    private let safetyMetricBounds: ClosedRange<Double>
    private let adjustmentSummaryText: String

    init(
        exerciseType: ExerciseType,
        painScore: Int,
        rpeGoal: Int,
        clinicianSharingMode: Bool,
        metronomeEnabled: Bool,
        sessionStore: any SessionStore,
        poseEstimator: PoseEstimating,
        cameraService: CameraCaptureService,
        voiceCoach: VoiceCoaching,
        watchSync: any WatchSessionSyncing
    ) {
        self.selectedExerciseType = exerciseType
        self.painScore = painScore
        self.rpeGoal = rpeGoal
        self.clinicianSharingMode = clinicianSharingMode
        self.metronomeEnabled = metronomeEnabled
        self.sessionStore = sessionStore
        self.poseEstimator = poseEstimator
        self.cameraService = cameraService
        self.voiceCoach = voiceCoach
        self.watchSync = watchSync
        self.analyzer = RepetitionAnalyzer(exerciseType: exerciseType)
        self.tempoTargetSeconds = Self.defaultTempoTarget(for: exerciseType)

        let defaultMetricRange = Self.defaultMetricRange(for: exerciseType)
        let adjustedRange = Self.adjustMetricRange(
            defaultMetricRange,
            exerciseType: exerciseType,
            painScore: painScore,
            rpeGoal: rpeGoal
        )
        safetyMetricBounds = adjustedRange
        adjustmentSummaryText = Self.makeAdjustmentSummary(
            exerciseType: exerciseType,
            painScore: painScore,
            rpeGoal: rpeGoal
        )

        targetProfile = Self.defaultTargetProfile(for: exerciseType)
        targetProfile.metricRange = adjustedRange
        voiceCoach.isEnabled = voiceCoachingEnabled
        watchReachable = watchSync.isReachable

        if let stored = Self.loadTargetProfile(for: exerciseType) {
            targetProfile = Self.normalizedTargetProfile(stored, bounds: adjustedRange)
            isCalibrationReady = true
            calibrationMessage = "Calibrated \(stored.updatedAt.formatted(date: .abbreviated, time: .shortened))."
        }

        watchSync.onHeartRateUpdate = { [weak self] heartRate in
            guard let self else { return }
            DispatchQueue.main.async {
                self.watchHeartRate = heartRate
            }
        }

        cameraService.onFrame = { [weak self] pixelBuffer in
            self?.processingQueue.async {
                self?.processFrame(pixelBuffer)
            }
        }
    }

    func runCalibration() {
        startCalibration()
    }

    func startSession() {
        guard isCalibrationReady else {
            feedback = "Calibration required before session start."
            calibrationMessage = "Tap Run Calibration and hold your natural standing stance."
            startCalibration()
            return
        }

        Task {
            do {
                try await cameraService.start()
                await MainActor.run {
                    startedAt = Date()
                    primaryMetricSamples.removeAll(keepingCapacity: true)
                    symmetrySamples.removeAll(keepingCapacity: true)
                    eccentricTempoSamples.removeAll(keepingCapacity: true)
                    concentricTempoSamples.removeAll(keepingCapacity: true)
                    highQualitySamples.removeAll(keepingCapacity: true)
                    missedPoseFrameCount = 0
                    previousMetricValue = nil
                    previousMetricTimestamp = nil
                    currentMovementPhase = .idle
                    phaseStartedAt = nil
                    lastAnnouncedFeedback = ""
                    lastAnnouncedRep = 0
                    hasAnnouncedTrackingActive = false
                    compensationAlert = nil
                    compensationAlertsCount = 0
                    lastCompensationAnnouncementAt = .distantPast
                    lastWatchSyncAt = .distantPast
                    lastMetronomeCueAt = .distantPast

                    analyzer.reset()
                    isSessionRunning = true
                    repetitionCount = 0
                    qualityScore = 0
                    currentPrimaryMetricValue = 0
                    symmetryScore = 0
                    tempoScore = 0
                    eccentricTempo = 0
                    concentricTempo = 0
                    movementPhaseLabel = MovementPhase.idle.label
                    visibleJointCount = 0
                    latestPoseFrame = nil
                    formAlignmentScore = 0
                    metricInTargetRange = false
                    trackingState = .searching
                    feedback = "\(selectedExerciseType.sessionStartCue) \(adjustmentSummaryText)"
                    errorMessage = nil
                    cameraAccessDenied = false
                    watchReachable = watchSync.isReachable
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
        let averageSymmetry = symmetrySamples.average
        let avgEccentricTempo = eccentricTempoSamples.average
        let avgConcentricTempo = concentricTempoSamples.average

        isSessionRunning = false
        trackingState = .idle
        visibleJointCount = 0
        latestPoseFrame = nil
        formAlignmentScore = 0
        metricInTargetRange = false
        movementPhaseLabel = MovementPhase.idle.label
        feedback = "Session saved"

        let notes = """
        Metric: \(selectedExerciseType.primaryMetricTitle) (\(selectedExerciseType.primaryMetricUnit)).
        Adjustment: \(adjustmentSummaryText)
        """

        let session = ExerciseSession(
            exerciseType: selectedExerciseType,
            startedAt: startedAt,
            endedAt: endedAt,
            repetitionCount: reps,
            averageKneeAngle: averageMetric,
            qualityScore: computedQuality,
            notes: notes,
            averageSymmetryScore: averageSymmetry,
            averageEccentricTempo: avgEccentricTempo,
            averageConcentricTempo: avgConcentricTempo,
            painScore: painScore,
            rpeGoal: rpeGoal,
            compensationAlertsCount: compensationAlertsCount,
            clinicianSharingMode: clinicianSharingMode
        )

        watchSync.sendSessionSummary(
            WatchSessionSummaryPayload(
                exerciseType: selectedExerciseType.rawValue,
                reps: reps,
                qualityScore: computedQuality,
                durationSeconds: session.durationSeconds
            )
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

    private func startCalibration() {
        guard !isCalibrating else { return }

        if isSessionRunning {
            feedback = "End the active session before calibration."
            return
        }

        Task {
            do {
                try await cameraService.start()
                await MainActor.run {
                    calibrationFrames.removeAll(keepingCapacity: true)
                    calibrationCompletionPending = false
                    missedPoseFrameCount = 0

                    isCalibrating = true
                    isCalibrationReady = false
                    calibrationProgress = 0
                    trackingState = .searching
                    latestPoseFrame = nil
                    feedback = "Calibration started. Hold a neutral stance in frame."
                    calibrationMessage = "Keep hips, knees, and ankles visible for 2-3 seconds."
                    voiceCoach.announce("Calibration started. Hold your natural stance.", priority: .high)
                }
            } catch CameraCaptureService.CameraError.unauthorized {
                await MainActor.run {
                    cameraAccessDenied = true
                    errorMessage = "Camera permission is required for calibration."
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Unable to start calibration camera: \(error.localizedDescription)"
                }
            }
        }
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let calibrating = isCalibrating
        guard isSessionRunning || calibrating else { return }

        do {
            guard let frame = try poseEstimator.estimatePose(in: pixelBuffer) else {
                handleNoPoseDetected(calibrating: calibrating)
                return
            }

            if calibrating {
                handleCalibrationFrame(frame)
                return
            }

            handleSessionFrame(frame)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.trackingState = .searching
                self?.errorMessage = "Pose estimation error: \(error.localizedDescription)"
            }
        }
    }

    private func handleNoPoseDetected(calibrating: Bool) {
        missedPoseFrameCount += 1

        if calibrating {
            if missedPoseFrameCount % 6 == 0 {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.trackingState = .searching
                    self.visibleJointCount = 0
                    self.latestPoseFrame = nil
                    self.feedback = "No full pose detected for calibration. Step back and center your body."
                }
            }
            return
        }

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
    }

    private func handleCalibrationFrame(_ frame: PoseFrame) {
        guard !calibrationCompletionPending else { return }

        let hasAllJoints = BodyJoint.allCases.allSatisfy { frame.point(for: $0) != nil }
        guard hasAllJoints else {
            if missedPoseFrameCount % 6 == 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.feedback = "Calibration needs full lower-body visibility."
                }
            }
            return
        }

        missedPoseFrameCount = 0
        calibrationFrames.append(frame)
        let progress = min(Double(calibrationFrames.count) / Double(calibrationFrameTargetCount), 1.0)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestPoseFrame = frame
            self.visibleJointCount = frame.joints.count
            self.calibrationProgress = progress
            self.feedback = "Calibrating baseline stance... \(Int(progress * 100))%"
        }

        guard calibrationFrames.count >= calibrationFrameTargetCount else { return }

        calibrationCompletionPending = true
        let calibratedProfile = buildCalibratedProfile(from: calibrationFrames)
        calibrationFrames.removeAll(keepingCapacity: true)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.targetProfile = Self.normalizedTargetProfile(calibratedProfile, bounds: self.safetyMetricBounds)
            self.persistTargetProfile()
            self.isCalibrating = false
            self.isCalibrationReady = true
            self.calibrationProgress = 1
            self.calibrationMessage = "Calibrated \(calibratedProfile.updatedAt.formatted(date: .abbreviated, time: .shortened)). Adaptive learning active."
            self.feedback = "Calibration complete. Start your session."
            self.trackingState = .idle
            self.formAlignmentScore = 0
            self.metricInTargetRange = false
            self.latestPoseFrame = nil
            self.calibrationCompletionPending = false
            self.voiceCoach.announce("Calibration complete. Ready to train.", priority: .high)
        }
    }

    private func handleSessionFrame(_ frame: PoseFrame) {
        missedPoseFrameCount = 0
        let snapshot = analyzer.process(frame)
        let jointCount = frame.joints.count
        let activeTargets = targetProfile.jointTargets
        let alignmentScore = calculateFormAlignmentScore(for: frame, targets: activeTargets)

        let symmetry = calculateSymmetry(frame: frame)
        let sessionNow = Date()
        let metricValue = snapshot?.primaryMetricValue
        if let metricValue {
            updateTempo(metric: metricValue, timestamp: sessionNow)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.visibleJointCount = jointCount
            self.latestPoseFrame = frame
            self.formAlignmentScore = alignmentScore
            self.symmetryScore = symmetry.score

            if let alert = symmetry.alert {
                self.compensationAlert = alert
                self.maybeAnnounceCompensation(alert: alert)
            } else {
                self.compensationAlert = nil
            }

            if let snapshot {
                self.repetitionCount = snapshot.repetitionCount
                self.qualityScore = snapshot.qualityScore
                self.feedback = snapshot.feedback
                self.announceFeedbackIfNeeded(snapshot.feedback)
                self.announceRepetitionIfNeeded(snapshot.repetitionCount)
            }

            if let value = metricValue {
                self.trackingState = .tracking
                self.currentPrimaryMetricValue = value
                self.metricInTargetRange = self.targetMetricRange.contains(value)
                self.primaryMetricSamples.append(value)
                if self.primaryMetricSamples.count > 1500 {
                    self.primaryMetricSamples.removeFirst(self.primaryMetricSamples.count - 1500)
                }

                if let snapshot {
                    self.maybeAdaptTargets(frame: frame, metric: value, quality: snapshot.qualityScore)
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

            self.watchReachable = self.watchSync.isReachable
            self.pushWatchUpdateIfNeeded()
        }
    }

    private func pushWatchUpdateIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastWatchSyncAt) >= watchSyncInterval else { return }
        lastWatchSyncAt = now

        watchSync.sendLiveUpdate(
            WatchLivePayload(
                exerciseType: selectedExerciseType.rawValue,
                reps: repetitionCount,
                qualityScore: qualityScore,
                symmetryScore: symmetryScore,
                tempoScore: tempoScore,
                paceLabel: movementPhaseLabel
            )
        )
    }

    private func maybeAnnounceCompensation(alert: String) {
        let now = Date()
        guard now.timeIntervalSince(lastCompensationAnnouncementAt) >= compensationAnnouncementInterval else { return }
        lastCompensationAnnouncementAt = now
        compensationAlertsCount += 1
        voiceCoach.announce(alert, priority: .high)
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

    private func maybeAdaptTargets(frame: PoseFrame, metric: Double, quality: Double) {
        guard quality >= adaptiveMinimumQuality else { return }

        highQualitySamples.append(AdaptiveSample(frame: frame, metric: metric))
        if highQualitySamples.count > adaptiveSampleWindow {
            highQualitySamples.removeFirst(highQualitySamples.count - adaptiveSampleWindow)
        }

        guard highQualitySamples.count >= adaptiveSampleMinimum else { return }
        guard highQualitySamples.count % adaptiveUpdateInterval == 0 else { return }

        var updatedProfile = targetProfile

        for joint in BodyJoint.allCases {
            let points = highQualitySamples.compactMap { $0.frame.point(for: joint) }
            guard !points.isEmpty else { continue }
            let xValues = points.map { $0.x }
            let yValues = points.map { $0.y }
            let padding = adaptivePadding(for: joint)
            let desiredX = (xValues.minimum - padding.x)...(xValues.maximum + padding.x)
            let desiredY = (yValues.minimum - padding.y)...(yValues.maximum + padding.y)

            let desired = JointTarget(
                x: clampedUnitRange(desiredX),
                y: clampedUnitRange(desiredY)
            )

            let existing = updatedProfile.jointTargets[joint] ?? desired
            updatedProfile.jointTargets[joint] = JointTarget(
                x: blend(existing.x, desired.x, alpha: adaptiveBlendAlpha),
                y: blend(existing.y, desired.y, alpha: adaptiveBlendAlpha)
            )
        }

        let metricSamples = highQualitySamples.map(\.metric)
        if let learnedRange = learnedMetricRange(from: metricSamples) {
            updatedProfile.metricRange = blend(updatedProfile.metricRange, learnedRange, alpha: adaptiveBlendAlpha)
        }

        updatedProfile.source = .adaptive
        updatedProfile.updatedAt = Date()
        targetProfile = Self.normalizedTargetProfile(updatedProfile, bounds: safetyMetricBounds)
        calibrationMessage = "Adaptive targets refreshed from recent high-quality reps."
        persistTargetProfile()
    }

    private func buildCalibratedProfile(from frames: [PoseFrame]) -> TargetProfile {
        var jointTargets = Self.defaultJointTargets(for: selectedExerciseType)

        for joint in BodyJoint.allCases {
            let points = frames.compactMap { $0.point(for: joint) }
            guard !points.isEmpty else { continue }
            let xValues = points.map { $0.x }
            let yValues = points.map { $0.y }

            let padding = calibrationPadding(for: joint)
            let calibratedX = (xValues.minimum - padding.x)...(xValues.maximum + padding.x)
            let calibratedY = (yValues.minimum - padding.y)...(yValues.maximum + padding.y)
            jointTargets[joint] = JointTarget(
                x: clampedUnitRange(calibratedX),
                y: clampedUnitRange(calibratedY)
            )
        }

        let metricRange = calibratedMetricRange(from: frames)
        return TargetProfile(
            jointTargets: jointTargets,
            metricLowerBound: metricRange.lowerBound,
            metricUpperBound: metricRange.upperBound,
            source: .calibrated,
            updatedAt: Date()
        )
    }

    private func calibratedMetricRange(from frames: [PoseFrame]) -> ClosedRange<Double> {
        let defaultRange = Self.defaultMetricRange(for: selectedExerciseType)
        guard selectedExerciseType != .calfRaise else { return defaultRange }

        let standingSamples = frames.compactMap { averageKneeAngle(from: $0) }
        guard let standingAverage = standingSamples.averageOrNil else { return defaultRange }

        let baseCenter = (defaultRange.lowerBound + defaultRange.upperBound) / 2
        let halfWidth = (defaultRange.upperBound - defaultRange.lowerBound) / 2
        let shift = (standingAverage - 170) * 0.18
        let shifted = (baseCenter + shift - halfWidth)...(baseCenter + shift + halfWidth)
        return clampedMetricRange(shifted)
    }

    private func learnedMetricRange(from samples: [Double]) -> ClosedRange<Double>? {
        guard !samples.isEmpty else { return nil }

        let average = samples.average
        let variance = samples.map { value -> Double in
            let delta = value - average
            return delta * delta
        }.average

        let standardDeviation = sqrt(variance)
        let defaultRange = Self.defaultMetricRange(for: selectedExerciseType)
        let defaultHalfWidth = (defaultRange.upperBound - defaultRange.lowerBound) / 2
        let adaptiveHalfWidth = max(defaultHalfWidth * 0.60, standardDeviation * 1.7)
        let learned = (average - adaptiveHalfWidth)...(average + adaptiveHalfWidth)
        return clampedMetricRange(learned)
    }

    private func calculateSymmetry(frame: PoseFrame) -> (score: Double, alert: String?) {
        guard
            let leftAngle = kneeAngle(hip: .leftHip, knee: .leftKnee, ankle: .leftAnkle, frame: frame),
            let rightAngle = kneeAngle(hip: .rightHip, knee: .rightKnee, ankle: .rightAnkle, frame: frame)
        else {
            return (score: 0, alert: nil)
        }

        let angleDelta = abs(leftAngle - rightAngle)
        let symmetry = max(0, 100 - (angleDelta * 4.2))
        symmetrySamples.append(symmetry)
        if symmetrySamples.count > 1500 {
            symmetrySamples.removeFirst(symmetrySamples.count - 1500)
        }

        let leftOffset = abs((frame.point(for: .leftKnee)?.x ?? 0) - (frame.point(for: .leftAnkle)?.x ?? 0))
        let rightOffset = abs((frame.point(for: .rightKnee)?.x ?? 0) - (frame.point(for: .rightAnkle)?.x ?? 0))

        if angleDelta > 16 {
            return (symmetry, "Compensation alert: weight shift detected. Balance both legs.")
        }

        if max(leftOffset, rightOffset) > (selectedExerciseType == .lunge ? 0.28 : 0.20) {
            return (symmetry, "Compensation alert: knee track drift. Keep knees over ankles.")
        }

        return (symmetry, nil)
    }

    private func updateTempo(metric: Double, timestamp: Date) {
        defer {
            previousMetricValue = metric
            previousMetricTimestamp = timestamp
        }

        guard let previousMetricValue else { return }
        let delta = metric - previousMetricValue
        let threshold = selectedExerciseType == .calfRaise ? 0.2 : 1.4

        let nextPhase: MovementPhase
        if selectedExerciseType == .calfRaise {
            if delta > threshold {
                nextPhase = .concentric
            } else if delta < -threshold {
                nextPhase = .eccentric
            } else {
                nextPhase = .steady
            }
        } else {
            if delta < -threshold {
                nextPhase = .eccentric
            } else if delta > threshold {
                nextPhase = .concentric
            } else {
                nextPhase = .steady
            }
        }

        if nextPhase == .steady {
            movementPhaseLabel = MovementPhase.steady.label
            return
        }

        if currentMovementPhase != nextPhase {
            if
                let phaseStartedAt,
                currentMovementPhase == .eccentric || currentMovementPhase == .concentric
            {
                let duration = max(0, timestamp.timeIntervalSince(phaseStartedAt))
                if currentMovementPhase == .eccentric {
                    eccentricTempoSamples.append(duration)
                    if eccentricTempoSamples.count > 100 {
                        eccentricTempoSamples.removeFirst(eccentricTempoSamples.count - 100)
                    }
                    eccentricTempo = eccentricTempoSamples.average
                } else if currentMovementPhase == .concentric {
                    concentricTempoSamples.append(duration)
                    if concentricTempoSamples.count > 100 {
                        concentricTempoSamples.removeFirst(concentricTempoSamples.count - 100)
                    }
                    concentricTempo = concentricTempoSamples.average
                }
            }

            currentMovementPhase = nextPhase
            phaseStartedAt = timestamp
            movementPhaseLabel = nextPhase.label
            maybeEmitMetronomeCue(for: nextPhase)
        }

        let eccentricScore = tempoComponentScore(tempo: eccentricTempo)
        let concentricScore = tempoComponentScore(tempo: concentricTempo)

        if eccentricScore > 0 && concentricScore > 0 {
            tempoScore = (eccentricScore + concentricScore) / 2
        } else {
            tempoScore = max(eccentricScore, concentricScore)
        }
    }

    private func tempoComponentScore(tempo: Double) -> Double {
        guard tempo > 0 else { return 0 }
        let delta = abs(tempo - tempoTargetSeconds)
        let score = 100 - (delta / tempoTargetSeconds * 120)
        return max(0, min(100, score))
    }

    private func maybeEmitMetronomeCue(for phase: MovementPhase) {
        guard metronomeEnabled else { return }

        let now = Date()
        guard now.timeIntervalSince(lastMetronomeCueAt) >= metronomeCueInterval else { return }
        lastMetronomeCueAt = now

        AudioServicesPlaySystemSound(1104)

        switch phase {
        case .eccentric:
            voiceCoach.announce("Down on a two count.", priority: .normal)
        case .concentric:
            voiceCoach.announce("Up on a two count.", priority: .normal)
        case .idle, .steady:
            break
        }
    }

    private func clampedMetricRange(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        let lower = max(safetyMetricBounds.lowerBound, range.lowerBound)
        let upper = min(safetyMetricBounds.upperBound, range.upperBound)
        if lower >= upper {
            return safetyMetricBounds
        }
        return lower...upper
    }

    private func calculateFormAlignmentScore(
        for frame: PoseFrame,
        targets: [BodyJoint: JointTarget]
    ) -> Double {
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
            if target.x.contains(point.x) && target.y.contains(point.y) {
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

    private func averageKneeAngle(from frame: PoseFrame) -> Double? {
        let left = kneeAngle(hip: .leftHip, knee: .leftKnee, ankle: .leftAnkle, frame: frame)
        let right = kneeAngle(hip: .rightHip, knee: .rightKnee, ankle: .rightAnkle, frame: frame)
        return [left, right].compactMap { $0 }.averageOrNil
    }

    private func kneeAngle(
        hip: BodyJoint,
        knee: BodyJoint,
        ankle: BodyJoint,
        frame: PoseFrame
    ) -> Double? {
        guard
            let hipPoint = frame.point(for: hip),
            let kneePoint = frame.point(for: knee),
            let anklePoint = frame.point(for: ankle)
        else {
            return nil
        }

        let upper = vector(from: kneePoint, to: hipPoint)
        let lower = vector(from: kneePoint, to: anklePoint)

        let dot = upper.x * lower.x + upper.y * lower.y
        let magnitude = (upper.x * upper.x + upper.y * upper.y).squareRoot() *
            (lower.x * lower.x + lower.y * lower.y).squareRoot()

        guard magnitude > 0 else { return nil }

        let cosine = max(-1, min(1, dot / magnitude))
        return acos(cosine) * 180 / .pi
    }

    private func vector(from p1: PosePoint, to p2: PosePoint) -> (x: Double, y: Double) {
        (x: p2.x - p1.x, y: p2.y - p1.y)
    }

    private func calibrationPadding(for joint: BodyJoint) -> (x: Double, y: Double) {
        switch joint {
        case .leftHip, .rightHip:
            return (0.10, 0.12)
        case .leftKnee, .rightKnee:
            return (0.11, 0.14)
        case .leftAnkle, .rightAnkle:
            return (0.12, 0.15)
        }
    }

    private func adaptivePadding(for joint: BodyJoint) -> (x: Double, y: Double) {
        switch joint {
        case .leftHip, .rightHip:
            return (0.08, 0.10)
        case .leftKnee, .rightKnee:
            return (0.09, 0.11)
        case .leftAnkle, .rightAnkle:
            return (0.10, 0.12)
        }
    }

    private func blend(_ lhs: ClosedRange<Double>, _ rhs: ClosedRange<Double>, alpha: Double) -> ClosedRange<Double> {
        let lower = ((1 - alpha) * lhs.lowerBound) + (alpha * rhs.lowerBound)
        let upper = ((1 - alpha) * lhs.upperBound) + (alpha * rhs.upperBound)
        return clampedMetricRange(lower...upper)
    }

    private func clampedUnitRange(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        max(0.02, range.lowerBound)...min(0.98, range.upperBound)
    }

    private func persistTargetProfile() {
        guard let data = try? JSONEncoder().encode(targetProfile) else { return }
        UserDefaults.standard.set(data, forKey: Self.targetProfileStorageKey(for: selectedExerciseType))
    }

    private static func loadTargetProfile(for exercise: ExerciseType) -> TargetProfile? {
        guard let data = UserDefaults.standard.data(forKey: targetProfileStorageKey(for: exercise)) else {
            return nil
        }
        return try? JSONDecoder().decode(TargetProfile.self, from: data)
    }

    private static func targetProfileStorageKey(for exercise: ExerciseType) -> String {
        "motion.rehab.targetProfile.\(exercise.rawValue)"
    }

    private static func normalizedTargetProfile(_ profile: TargetProfile, bounds: ClosedRange<Double>) -> TargetProfile {
        var normalized = profile
        let lower = max(bounds.lowerBound, profile.metricRange.lowerBound)
        let upper = min(bounds.upperBound, profile.metricRange.upperBound)
        normalized.metricRange = lower < upper ? (lower...upper) : bounds
        return normalized
    }

    private static func defaultTempoTarget(for exercise: ExerciseType) -> Double {
        switch exercise {
        case .squat:
            return 2.2
        case .sitToStand:
            return 2.1
        case .lunge:
            return 2.0
        case .miniSquat:
            return 2.4
        case .calfRaise:
            return 1.8
        }
    }

    private static func adjustMetricRange(
        _ base: ClosedRange<Double>,
        exerciseType: ExerciseType,
        painScore: Int,
        rpeGoal: Int
    ) -> ClosedRange<Double> {
        switch exerciseType {
        case .calfRaise:
            var lower = base.lowerBound
            var upper = base.upperBound
            if painScore >= 7 {
                upper *= 0.80
            } else if painScore >= 4 {
                upper *= 0.90
            }
            if rpeGoal <= 4 {
                upper *= 0.88
            }
            if rpeGoal >= 8 {
                upper *= 1.05
            }
            lower = max(0.3, lower)
            upper = min(8.5, upper)
            return lower...max(lower + 0.4, upper)
        case .squat, .sitToStand, .lunge, .miniSquat:
            let center = (base.lowerBound + base.upperBound) / 2
            let halfWidth = (base.upperBound - base.lowerBound) / 2
            var shift = 0.0
            var widthFactor = 1.0

            if painScore >= 7 {
                shift += 12
                widthFactor *= 0.78
            } else if painScore >= 4 {
                shift += 6
                widthFactor *= 0.88
            }

            if rpeGoal <= 4 {
                shift += 4
                widthFactor *= 0.90
            } else if rpeGoal >= 8 {
                shift -= 2
                widthFactor *= 1.05
            }

            let adjustedHalfWidth = max(8.0, halfWidth * widthFactor)
            let adjustedCenter = center + shift
            let lower = max(45, adjustedCenter - adjustedHalfWidth)
            let upper = min(178, adjustedCenter + adjustedHalfWidth)
            return lower...max(lower + 10, upper)
        }
    }

    private static func makeAdjustmentSummary(
        exerciseType: ExerciseType,
        painScore: Int,
        rpeGoal: Int
    ) -> String {
        let intensity: String
        if painScore >= 7 || rpeGoal <= 4 {
            intensity = "Conservative intensity"
        } else if painScore >= 4 || rpeGoal <= 6 {
            intensity = "Moderate intensity"
        } else {
            intensity = "Standard intensity"
        }

        switch exerciseType {
        case .calfRaise:
            return "\(intensity). Target lift adjusted for pain \(painScore)/10 and RPE \(rpeGoal)/10."
        case .squat, .sitToStand, .lunge, .miniSquat:
            return "\(intensity). Depth target adjusted for pain \(painScore)/10 and RPE \(rpeGoal)/10."
        }
    }

    private static func defaultTargetProfile(for exercise: ExerciseType) -> TargetProfile {
        let metricRange = defaultMetricRange(for: exercise)
        return TargetProfile(
            jointTargets: defaultJointTargets(for: exercise),
            metricLowerBound: metricRange.lowerBound,
            metricUpperBound: metricRange.upperBound,
            source: .baseline,
            updatedAt: Date()
        )
    }

    private static func defaultMetricRange(for exercise: ExerciseType) -> ClosedRange<Double> {
        switch exercise {
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

    private static func defaultJointTargets(for exercise: ExerciseType) -> [BodyJoint: JointTarget] {
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

private struct AdaptiveSample {
    let frame: PoseFrame
    let metric: Double
}

struct JointTarget: Codable, Hashable {
    let x: ClosedRange<Double>
    let y: ClosedRange<Double>
}

struct TargetProfile: Codable {
    var jointTargets: [BodyJoint: JointTarget]
    var metricLowerBound: Double
    var metricUpperBound: Double
    var source: TargetProfileSource
    var updatedAt: Date

    var metricRange: ClosedRange<Double> {
        get { metricLowerBound...metricUpperBound }
        set {
            metricLowerBound = newValue.lowerBound
            metricUpperBound = newValue.upperBound
        }
    }
}

enum TargetProfileSource: String, Codable {
    case baseline
    case calibrated
    case adaptive

    var label: String {
        switch self {
        case .baseline:
            return "Default"
        case .calibrated:
            return "Calibrated"
        case .adaptive:
            return "Adaptive"
        }
    }
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    var averageOrNil: Double? {
        guard !isEmpty else { return nil }
        return average
    }

    var minimum: Double {
        guard let first else { return 0 }
        return dropFirst().reduce(first, Swift.min)
    }

    var maximum: Double {
        guard let first else { return 0 }
        return dropFirst().reduce(first, Swift.max)
    }
}

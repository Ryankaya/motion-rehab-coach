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

    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var calibrationMessage = "Run calibration before your first session."
    @Published private(set) var isCalibrating = false
    @Published private(set) var isCalibrationReady = false

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

    var captureSession: AVCaptureSession { cameraService.session }
    var primaryMetricTitle: String { selectedExerciseType.primaryMetricTitle }
    var primaryMetricUnit: String { selectedExerciseType.primaryMetricUnit }
    var targetMetricRange: ClosedRange<Double> { targetProfile.metricRange }
    var targetProfileSourceLabel: String { targetProfile.source.label }
    var jointTargets: [BodyJoint: JointTarget] { targetProfile.jointTargets }

    private let sessionStore: any SessionStore
    private let poseEstimator: PoseEstimating
    private let cameraService: CameraCaptureService
    private let voiceCoach: VoiceCoaching

    private let processingQueue = DispatchQueue(label: "motion.rehab.processing")
    private let analyzer: RepetitionAnalyzer

    private var startedAt: Date?
    private var primaryMetricSamples: [Double] = []
    private var calibrationFrames: [PoseFrame] = []
    private var highQualitySamples: [AdaptiveSample] = []
    private var calibrationCompletionPending = false
    private var missedPoseFrameCount = 0

    private var lastAnnouncedFeedback = ""
    private var lastAnnouncedRep = 0
    private var hasAnnouncedTrackingActive = false

    private let calibrationFrameTargetCount = 60
    private let adaptiveSampleMinimum = 12
    private let adaptiveSampleWindow = 48
    private let adaptiveUpdateInterval = 6
    private let adaptiveMinimumQuality = 90.0
    private let adaptiveBlendAlpha = 0.18

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
        self.targetProfile = Self.defaultTargetProfile(for: exerciseType)
        self.voiceCoach.isEnabled = voiceCoachingEnabled

        if let stored = Self.loadTargetProfile(for: exerciseType) {
            targetProfile = stored
            isCalibrationReady = true
            calibrationMessage = "Calibrated \(stored.updatedAt.formatted(date: .abbreviated, time: .shortened))."
        }

        self.cameraService.onFrame = { [weak self] pixelBuffer in
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
                    highQualitySamples.removeAll(keepingCapacity: true)
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
            self.targetProfile = calibratedProfile
            self.persistTargetProfile()
            self.isCalibrating = false
            self.isCalibrationReady = true
            self.calibrationProgress = 1
            self.calibrationMessage = "Calibrated \(calibratedProfile.updatedAt.formatted(date: .abbreviated, time: .shortened)). Adaptive learning is active."
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
            let adaptivePadding = adaptivePadding(for: joint)
            let desiredX = (xValues.minimum - adaptivePadding.x)...(xValues.maximum + adaptivePadding.x)
            let desiredY = (yValues.minimum - adaptivePadding.y)...(yValues.maximum + adaptivePadding.y)

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
        targetProfile = updatedProfile
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

    private func clampedMetricRange(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        switch selectedExerciseType {
        case .calfRaise:
            return max(0.3, range.lowerBound)...min(8.5, range.upperBound)
        case .squat, .sitToStand, .lunge, .miniSquat:
            return max(45, range.lowerBound)...min(178, range.upperBound)
        }
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
        return lower...upper
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

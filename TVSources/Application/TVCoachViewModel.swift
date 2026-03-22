import AVFoundation
import CoreGraphics
import Foundation
import QuartzCore

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

    @Published var selectedExercise: TVExerciseProgram = .squat
    @Published var voiceCoachingEnabled = true {
        didSet {
            voiceCoach.isEnabled = voiceCoachingEnabled
        }
    }
    @Published var lowerBodyFocusEnabled = true
    @Published var framingMode: TVFramingMode = .feetToHalfBody
    @Published private(set) var previewOffsetY: CGFloat = -132
    @Published private(set) var previewScale: CGFloat = 1.03

    @Published private(set) var isCalibrationReady = false
    @Published private(set) var isCalibrating = false
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var isSessionRunning = false
    @Published private(set) var sessionDurationSeconds = 0

    @Published var isDevicePickerPresented = false

    var captureSession: AVCaptureSession { cameraService.session }
    var sessionDurationLabel: String {
        let minutes = sessionDurationSeconds / 60
        let seconds = sessionDurationSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    var calibrationActionTitle: String {
        isCalibrationReady ? "Recalibrate" : "Run Calibration"
    }
    var sessionActionTitle: String {
        isSessionRunning ? "End Session" : "Start Session"
    }

    private let cameraService: TVContinuityCameraService
    private let poseEstimator: PoseEstimating
    private let voiceCoach: TVVoiceCoach

    private var missedPoseFrameCount = 0
    private var previousFrameDate: Date?
    private var lastAnalysisTimestamp: CFTimeInterval = 0
    private let analysisInterval: CFTimeInterval = 1.0 / 10.0
    private var pendingCameraID: String?
    private var reconnectRetryCount = 0
    private let maxReconnectRetries = 12
    private var hasInitialized = false
    private var framingBaseOffsetY: CGFloat = -132
    private var framingNudgeY: CGFloat = 0

    private var sessionTimer: Timer?
    private var calibrationTimer: Timer?
    private var guidanceCueIndex = 0

    init(
        cameraService: TVContinuityCameraService,
        poseEstimator: PoseEstimating,
        voiceCoach: TVVoiceCoach
    ) {
        self.cameraService = cameraService
        self.poseEstimator = poseEstimator
        self.voiceCoach = voiceCoach

        voiceCoach.isEnabled = voiceCoachingEnabled

        if cameraService.isFrameProcessingEnabled {
            cameraService.onFrame = { [weak self] buffer in
                self?.processFrame(buffer)
            }
        }

        applyFramingMode(resetNudge: true)
    }

    deinit {
        invalidateTimers()
    }

    func onAppear() {
        refreshCameraTelemetry()

        if !hasInitialized {
            hasInitialized = true
            return
        }

        if continuityCameraCount > 0, trackingState == .waitingForCamera {
            reconnectPreferredCamera(resetRetry: true)
        }
    }

    func onDisappear() {
        if isDevicePickerPresented {
            return
        }

        invalidateTimers()
        if !isSessionRunning && !isCalibrating {
            cameraService.stop()
        }
    }

    func openDevicePicker() {
        isDevicePickerPresented = true
    }

    func handlePickerConnected(_ device: AVContinuityDevice?) {
        pendingCameraID = device?.videoDevices.first?.uniqueID
        isDevicePickerPresented = false
        statusMessage = "Connecting to selected iPhone camera..."
        feedback = "Preparing camera feed"

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.reconnectPreferredCamera(resetRetry: true)
        }
    }

    func handlePickerCancelled() {
        isDevicePickerPresented = false
        refreshCameraTelemetry()
        if continuityCameraCount > 0 {
            reconnectPreferredCamera(resetRetry: true)
        } else {
            trackingState = .waitingForCamera
            statusMessage = "No camera connected. Open picker and select your iPhone/iPad."
        }
    }

    func selectExercise(_ exercise: TVExerciseProgram) {
        guard selectedExercise != exercise else { return }
        selectedExercise = exercise
        isCalibrationReady = false

        if isSessionRunning {
            stopSession()
        }

        feedback = "Selected \(exercise.displayName). Run calibration for best guidance."
        voiceCoach.speak("Selected \(exercise.displayName). \(exercise.calibrationCue)", force: true)
    }

    func toggleLowerBodyFocus() {
        lowerBodyFocusEnabled.toggle()
        if lowerBodyFocusEnabled {
            selectFramingMode(.feetToHalfBody)
        } else {
            selectFramingMode(.fullBody)
        }
        let phrase = lowerBodyFocusEnabled
            ? "Feet to half body framing enabled. Keep ankles, knees, and hips inside the guide zone."
            : "Full body framing enabled."
        feedback = phrase
        voiceCoach.speak(phrase, force: true)
    }

    func showMoreFeet() {
        previewOffsetY = max(previewOffsetY - 18, -340)
        framingNudgeY = previewOffsetY - framingBaseOffsetY
        feedback = "Framing adjusted for more feet visibility."
    }

    func showMoreUpperBody() {
        previewOffsetY = min(previewOffsetY + 18, 180)
        framingNudgeY = previewOffsetY - framingBaseOffsetY
        feedback = "Framing adjusted for more upper body visibility."
    }

    func resetFramingAdjustments() {
        framingNudgeY = 0
        previewOffsetY = framingBaseOffsetY
        feedback = "Framing reset for \(framingMode.displayName)."
    }

    func selectFramingMode(_ mode: TVFramingMode) {
        framingMode = mode
        lowerBodyFocusEnabled = mode != .fullBody
        applyFramingMode(resetNudge: true)
        cameraService.applyFocusPreset(mode)
        feedback = "\(mode.displayName) framing selected."
        voiceCoach.speak("\(mode.displayName) framing selected.", force: true)
    }

    func runCalibration() {
        guard !isCalibrating else { return }

        reconnectPreferredCamera(resetRetry: true)
        guard continuityCameraCount > 0 else {
            trackingState = .waitingForCamera
            statusMessage = "Connect iPhone camera before calibration."
            feedback = "Open camera picker and connect your iPhone."
            return
        }

        if isSessionRunning {
            stopSession()
        }

        invalidateCalibrationTimer()
        isCalibrating = true
        isCalibrationReady = false
        calibrationProgress = 0
        statusMessage = "Calibrating \(selectedExercise.displayName)..."
        feedback = selectedExercise.calibrationCue
        guidanceCueIndex = 0
        voiceCoach.speak("Calibration started. \(selectedExercise.calibrationCue)", force: true)

        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let nextProgress = min(self.calibrationProgress + 0.04, 1.0)
            self.calibrationProgress = nextProgress

            if nextProgress >= 1 {
                timer.invalidate()
                self.calibrationTimer = nil
                self.finishCalibration()
            }
        }
    }

    func toggleSession() {
        isSessionRunning ? stopSession() : startSession()
    }

    func reconnectPreferredCamera(resetRetry: Bool = false) {
        if resetRetry {
            reconnectRetryCount = 0
        }

        refreshCameraTelemetry()

        guard continuityCameraCount > 0 || pendingCameraID != nil else {
            trackingState = .waitingForCamera
            statusMessage = "No Continuity Camera found. Open picker to connect your iPhone/iPad."
            feedback = "Waiting for camera"
            return
        }

        do {
            try cameraService.startUsingPreferredCamera(preferredCameraID: pendingCameraID)
            pendingCameraID = nil
            reconnectRetryCount = 0
            cameraService.applyFocusPreset(framingMode)
            refreshCameraTelemetry()

            trackingState = isSessionRunning ? .trackingPose : .searchingPose

            if isCalibrating {
                statusMessage = "Calibrating \(selectedExercise.displayName)..."
                feedback = selectedExercise.calibrationCue
            } else if isSessionRunning {
                statusMessage = "Session active: \(selectedExercise.displayName)"
                feedback = selectedExercise.liveCueSequence[guidanceCueIndex % selectedExercise.liveCueSequence.count]
            } else {
                statusMessage = "Connected to \(cameraName). Ready for calibration or session."
                feedback = "Camera preview active on Apple TV"
            }

            if cameraService.isFrameProcessingEnabled {
                feedback = "Live pose analysis active"
            }
        } catch TVContinuityCameraService.CameraError.continuityUnavailable,
            TVContinuityCameraService.CameraError.inputCreationFailed,
            TVContinuityCameraService.CameraError.outputCreationFailed
        {
            if reconnectRetryCount < maxReconnectRetries {
                reconnectRetryCount += 1
                trackingState = .waitingForCamera
                statusMessage = "Connecting to iPhone camera (\(reconnectRetryCount)/\(maxReconnectRetries))..."
                feedback = "Preparing camera feed"

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) { [weak self] in
                    self?.reconnectPreferredCamera(resetRetry: false)
                }
                return
            }

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
        stopSession()
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

    private func startSession() {
        reconnectPreferredCamera(resetRetry: true)
        guard continuityCameraCount > 0 else {
            trackingState = .waitingForCamera
            statusMessage = "Connect iPhone camera before starting session."
            feedback = "Open camera picker and connect your iPhone."
            return
        }

        guard isCalibrationReady else {
            feedback = "Calibration required before session."
            voiceCoach.speak("Run calibration before starting session.", force: true)
            runCalibration()
            return
        }

        invalidateSessionTimer()
        isSessionRunning = true
        sessionDurationSeconds = 0
        trackingState = .trackingPose
        statusMessage = "Session active: \(selectedExercise.displayName)"
        guidanceCueIndex = 0
        feedback = selectedExercise.liveCueSequence[guidanceCueIndex]
        voiceCoach.speak(selectedExercise.startCue, force: true)

        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            self.sessionDurationSeconds += 1
            guard self.voiceCoachingEnabled else { return }

            if self.sessionDurationSeconds % 8 == 0 {
                self.guidanceCueIndex = (self.guidanceCueIndex + 1) % self.selectedExercise.liveCueSequence.count
                let nextCue = self.selectedExercise.liveCueSequence[self.guidanceCueIndex]
                self.feedback = nextCue
                self.voiceCoach.speak(nextCue)
            }
        }
    }

    private func stopSession() {
        invalidateSessionTimer()
        if isCalibrating {
            invalidateCalibrationTimer()
            isCalibrating = false
        }

        isSessionRunning = false
        trackingState = continuityCameraCount > 0 ? .searchingPose : .waitingForCamera
        statusMessage = continuityCameraCount > 0
            ? "Session ended. Ready for next session."
            : "Session ended. Reconnect camera to continue."
        feedback = "Session stopped"
        voiceCoach.reset()
    }

    private func finishCalibration() {
        isCalibrating = false
        isCalibrationReady = true
        calibrationProgress = 1
        statusMessage = "Calibration complete for \(selectedExercise.displayName)."
        feedback = "Press Start Session to begin guided training."
        voiceCoach.speak("Calibration complete. You are ready to start.", force: true)
    }

    private func applyFramingMode(resetNudge: Bool) {
        switch framingMode {
        case .fullBody:
            previewScale = 1.0
            framingBaseOffsetY = 0
        case .feetToHalfBody:
            previewScale = 1.03
            framingBaseOffsetY = -132
        case .kneeFocus:
            previewScale = 1.05
            framingBaseOffsetY = -112
        case .heelFocus:
            previewScale = 1.03
            framingBaseOffsetY = -178
        }

        if resetNudge {
            framingNudgeY = 0
        }
        previewOffsetY = framingBaseOffsetY + framingNudgeY
    }

    private func invalidateTimers() {
        invalidateSessionTimer()
        invalidateCalibrationTimer()
    }

    private func invalidateSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    private func invalidateCalibrationTimer() {
        calibrationTimer?.invalidate()
        calibrationTimer = nil
    }

    private func refreshCameraTelemetry() {
        continuityCameraCount = cameraService.continuityCameraCount
        cameraName = cameraService.currentCameraDisplayName
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let nowTick = CACurrentMediaTime()
        guard nowTick - lastAnalysisTimestamp >= analysisInterval else { return }
        lastAnalysisTimestamp = nowTick

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

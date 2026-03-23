@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

final class TVContinuityCameraService: NSObject {
    enum CameraError: Error {
        case continuityUnavailable
        case inputCreationFailed
        case outputCreationFailed
    }

    let session = AVCaptureSession()
    var onFrame: ((CVPixelBuffer) -> Void)?
    var isFrameProcessingEnabled: Bool { true }

    private let sessionQueue = DispatchQueue(label: "motion.rehab.tv.capture")
    private var configuredDeviceID: String?
    private var focusPreset: TVFramingMode = .feetToHalfBody

    var continuityCameraCount: Int {
        continuityCameras().count
    }

    var currentCameraDisplayName: String {
        guard let camera = currentPreferredCamera(preferredCameraID: nil) else {
            return "No camera connected"
        }
        return camera.localizedName
    }

    func startUsingPreferredCamera(preferredCameraID: String? = nil) throws {
        guard let preferredCamera = currentPreferredCamera(preferredCameraID: preferredCameraID) else {
            throw CameraError.continuityUnavailable
        }

        try sessionQueue.sync {
            try configureSession(using: preferredCamera)
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.sync {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func applyFocusPreset(_ mode: TVFramingMode) {
        focusPreset = mode

        sessionQueue.async { [weak self] in
            guard
                let self,
                let camera = self.currentPreferredCamera(preferredCameraID: nil)
            else {
                return
            }
            self.configureLowerBodyFramingIfSupported(camera, mode: mode)
        }
    }

    func enableWideFieldOfView() {
        sessionQueue.async { [weak self] in
            guard
                let self,
                let camera = self.currentPreferredCamera(preferredCameraID: nil)
            else {
                return
            }
            self.applyWideFieldOfViewIfSupported(camera)
        }
    }

    private func continuityCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    private func currentPreferredCamera(preferredCameraID: String?) -> AVCaptureDevice? {
        let cameras = continuityCameras().filter(isUsableCamera)

        if
            let preferredCameraID,
            let selectedCamera = cameras.first(where: { $0.uniqueID == preferredCameraID })
        {
            return selectedCamera
        }

        return cameras.first
    }

    private func isUsableCamera(_ camera: AVCaptureDevice) -> Bool {
        guard camera.isConnected else { return false }

        return camera.formats.contains { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width > 0 && dimensions.height > 0
        }
    }

    private func configureSession(using camera: AVCaptureDevice) throws {
        guard isUsableCamera(camera) else {
            throw CameraError.continuityUnavailable
        }

        if configuredDeviceID == camera.uniqueID {
            return
        }

        if session.isRunning {
            session.stopRunning()
        }

        session.beginConfiguration()
        // Keep continuity configuration conservative; aggressive preset/format mutations can
        // trigger unsupported active format exceptions on some iPhone/tvOS combinations.
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        session.inputs.forEach { input in
            session.removeInput(input)
        }
        session.outputs.forEach { output in
            session.removeOutput(output)
        }

        guard let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.inputCreationFailed
        }
        session.addInput(input)

        let activeDimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        guard activeDimensions.width > 0, activeDimensions.height > 0 else {
            session.commitConfiguration()
            throw CameraError.continuityUnavailable
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraError.outputCreationFailed
        }
        session.addOutput(output)

        session.commitConfiguration()
        configuredDeviceID = camera.uniqueID

        // Apply focus tuning after the session graph is committed to avoid null active-format states.
        configureLowerBodyFramingIfSupported(camera, mode: focusPreset)
    }

    private func configureLowerBodyFramingIfSupported(_ camera: AVCaptureDevice, mode: TVFramingMode) {
        guard camera.isConnected else { return }
        guard !camera.formats.isEmpty else { return }

        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }

            let lowerBodyPoint = pointOfInterest(for: mode)

            if camera.isFocusPointOfInterestSupported {
                camera.focusPointOfInterest = lowerBodyPoint
            }
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }

            if camera.isExposurePointOfInterestSupported {
                camera.exposurePointOfInterest = lowerBodyPoint
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }

            let minimumZoom = max(1.0, camera.minAvailableVideoZoomFactor)
            let clampedMinimumZoom = min(minimumZoom, camera.maxAvailableVideoZoomFactor)
            if abs(camera.videoZoomFactor - clampedMinimumZoom) > 0.001 {
                camera.videoZoomFactor = clampedMinimumZoom
            }
            camera.isSubjectAreaChangeMonitoringEnabled = false
        } catch {
            // Continue with default continuity framing if configuration is restricted.
        }
    }

    private func applyWideFieldOfViewIfSupported(_ camera: AVCaptureDevice) {
        guard camera.isConnected else { return }

        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }

            let minimumZoom = max(1.0, camera.minAvailableVideoZoomFactor)
            let clampedMinimumZoom = min(minimumZoom, camera.maxAvailableVideoZoomFactor)
            if abs(camera.videoZoomFactor - clampedMinimumZoom) > 0.001 {
                camera.videoZoomFactor = clampedMinimumZoom
            }
            camera.isSubjectAreaChangeMonitoringEnabled = false
        } catch {
            // Keep default continuity camera behavior when zoom configuration is locked.
        }
    }

    private func pointOfInterest(for mode: TVFramingMode) -> CGPoint {
        switch mode {
        case .fullBody:
            return CGPoint(x: 0.5, y: 0.56)
        case .upperBody:
            return CGPoint(x: 0.5, y: 0.36)
        case .feetToHalfBody:
            return CGPoint(x: 0.5, y: 0.80)
        case .kneeFocus:
            return CGPoint(x: 0.5, y: 0.72)
        case .heelFocus:
            return CGPoint(x: 0.5, y: 0.88)
        }
    }

}

extension TVContinuityCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buffer)
    }
}

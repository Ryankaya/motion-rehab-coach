@preconcurrency import AVFoundation
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

    private let sessionQueue = DispatchQueue(label: "motion.rehab.tv.capture")
    private var configuredDeviceID: String?

    var continuityCameraCount: Int {
        continuityCameras().count
    }

    var currentCameraDisplayName: String {
        guard let camera = currentPreferredCamera() else {
            return "No camera connected"
        }
        return camera.localizedName
    }

    func startUsingPreferredCamera() throws {
        guard let preferredCamera = currentPreferredCamera() else {
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

    private func continuityCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    private func currentPreferredCamera() -> AVCaptureDevice? {
        if let camera = AVCaptureDevice.systemPreferredCamera, camera.isContinuityCamera {
            return camera
        }

        return continuityCameras().first
    }

    private func configureSession(using camera: AVCaptureDevice) throws {
        if configuredDeviceID == camera.uniqueID {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high

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

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraError.outputCreationFailed
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = true
        }

        session.commitConfiguration()
        configuredDeviceID = camera.uniqueID
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

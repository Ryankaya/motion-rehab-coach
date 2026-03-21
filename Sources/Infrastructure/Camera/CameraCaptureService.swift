@preconcurrency import AVFoundation
import CoreVideo
import Foundation

final class CameraCaptureService: NSObject {
    enum CameraError: Error {
        case unavailable
        case inputCreationFailed
        case outputCreationFailed
        case unauthorized
    }

    let session = AVCaptureSession()
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let outputQueue = DispatchQueue(label: "motion.rehab.camera.output")
    private var isConfigured = false

    static func requestAuthorization() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func start() async throws {
        guard await Self.requestAuthorization() else {
            throw CameraError.unauthorized
        }

        try configureIfNeeded()
        let session = self.session

        if !session.isRunning {
            outputQueue.async {
                session.startRunning()
            }
        }
    }

    func stop() {
        let session = self.session
        if session.isRunning {
            outputQueue.async {
                session.stopRunning()
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraError.unavailable
        }

        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            throw CameraError.inputCreationFailed
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(output) else {
            throw CameraError.outputCreationFailed
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        session.commitConfiguration()
        isConfigured = true
    }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buffer)
    }
}

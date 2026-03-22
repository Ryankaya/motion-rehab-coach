import AVFoundation
import AVKit
import SwiftUI

struct TVContinuityDevicePickerView: UIViewControllerRepresentable {
    let onConnected: (AVContinuityDevice?) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onConnected: onConnected, onCancelled: onCancelled)
    }

    func makeUIViewController(context: Context) -> AVContinuityDevicePickerViewController {
        let picker = AVContinuityDevicePickerViewController()
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: AVContinuityDevicePickerViewController, context: Context) {}
}

extension TVContinuityDevicePickerView {
    final class Coordinator: NSObject, AVContinuityDevicePickerViewControllerDelegate {
        private let onConnected: (AVContinuityDevice?) -> Void
        private let onCancelled: () -> Void
        private var didComplete = false

        init(
            onConnected: @escaping (AVContinuityDevice?) -> Void,
            onCancelled: @escaping () -> Void
        ) {
            self.onConnected = onConnected
            self.onCancelled = onCancelled
        }

        @objc(continuityDevicePicker:didConnectDevice:)
        func continuityDevicePicker(
            _ pickerViewController: AVContinuityDevicePickerViewController,
            didConnect device: AVContinuityDevice
        ) {
            didComplete = true
            DispatchQueue.main.async { [onConnected] in
                onConnected(device)
            }
        }

        @objc(continuityDevicePickerDidCancel:)
        func continuityDevicePickerDidCancel(_ pickerViewController: AVContinuityDevicePickerViewController) {
            didComplete = true
            DispatchQueue.main.async { [onCancelled] in
                onCancelled()
            }
        }

        @objc(continuityDevicePickerDidEndPresenting:)
        func continuityDevicePickerDidEndPresenting(_ pickerViewController: AVContinuityDevicePickerViewController) {
            guard !didComplete else { return }
            didComplete = true
            DispatchQueue.main.async { [onConnected] in
                onConnected(nil)
            }
        }
    }
}
